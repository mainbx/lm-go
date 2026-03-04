import Foundation
import SwiftUI

@MainActor
final class ServerViewModel: ObservableObject {
    @Published var servers: [ServerConfig] = []
    @Published var activeServer: ServerConfig?
    @Published var availableModels: [LMModel] = []
    @Published var serverModels: [ServerModel] = []
    @Published var localModels: [LocalModelRecord] = []
    @Published var discoveredHuggingFaceFiles: [HuggingFaceGGUFFile] = []
    @Published var huggingFaceSearchResults: [HuggingFaceRepoSearchResult] = []
    @Published var selectedModel: LMModel?
    @Published var selectedEmbeddingModelKey: String?
    @Published var huggingFaceToken: String = ""
    @Published var isConnected = false
    @Published var isCheckingConnection = false
    @Published var connectionError: String?
    @Published var isLoadingModels = false
    @Published var isLoadingServerModels = false
    @Published var isSearchingHuggingFaceRepos = false
    @Published var isFetchingHuggingFaceFiles = false
    @Published var isDownloadingLocalModel = false
    @Published var downloadingHuggingFaceFileID: String?
    @Published var isLoadingLocalModel = false
    @Published var modelManagementError: String?
    @Published var localModelsError: String?
    @Published var isGeneratingEmbedding = false
    @Published var embeddingError: String?
    @Published var lastEmbeddingDimension: Int?
    @Published var lastEmbeddingPreviewValues: [Double] = []
    @Published var lastEmbeddingTokenUsage: Int?

    @Published private var modelOperationKeys: Set<String> = []

    private let apiService = APIService()
    private let huggingFaceService = HuggingFaceService()
    private let localInferenceService = LocalInferenceService.shared
    private let localMLXInferenceService = LocalMLXInferenceService.shared
    private let persistence = PersistenceService.shared
    private let localModelIDPrefix = "local://"
    private let healthCheckIntervalNanoseconds: UInt64 = 3_000_000_000
    private let healthCheckTimeoutSeconds: TimeInterval = 2.5
    private var healthMonitorTask: Task<Void, Never>?
    private var isHealthMonitoringActive = true

    init() {
        loadLocalState()
        loadSavedState()
        startConnectivityMonitoringIfNeeded()
    }

    deinit {
        healthMonitorTask?.cancel()
    }

    // MARK: - Server Management

    func addServer(_ server: ServerConfig) {
        servers.append(server)
        persistence.saveServers(servers)

        if activeServer == nil {
            setActiveServer(server)
        }
    }

    func updateServer(_ server: ServerConfig) {
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = server
            persistence.saveServers(servers)

            if activeServer?.id == server.id {
                activeServer = server
            }
        }
    }

    func removeServer(_ server: ServerConfig) {
        servers.removeAll { $0.id == server.id }
        persistence.saveServers(servers)

        if activeServer?.id == server.id {
            activeServer = servers.first
            persistence.saveActiveServerId(activeServer?.id)
            if activeServer != nil {
                Task { await connectToActiveServer() }
            } else {
                isConnected = false
                connectionError = nil
                availableModels = []
                serverModels = []
                if !isSelectedModelLocal {
                    selectedModel = localModelLMModels.first
                }
                selectedEmbeddingModelKey = nil
                modelOperationKeys.removeAll()
                modelManagementError = nil
                embeddingError = nil
                lastEmbeddingDimension = nil
                lastEmbeddingPreviewValues = []
                lastEmbeddingTokenUsage = nil
            }
        }
    }

    func setActiveServer(_ server: ServerConfig) {
        activeServer = server
        modelOperationKeys.removeAll()
        persistence.saveActiveServerId(server.id)
        Task { await connectToActiveServer() }
    }

    func setConnectivityMonitoringActive(_ isActive: Bool) {
        isHealthMonitoringActive = isActive

        if isActive {
            startConnectivityMonitoringIfNeeded()
            Task { await probeConnectionHealth() }
        } else {
            healthMonitorTask?.cancel()
            healthMonitorTask = nil
        }
    }

    // MARK: - Connection

    func connectToActiveServer() async {
        guard let server = activeServer else {
            isConnected = false
            return
        }

        isCheckingConnection = true
        connectionError = nil

        let healthy = await apiService.checkServerHealth(server: server)

        isCheckingConnection = false
        isConnected = healthy

        if healthy {
            connectionError = nil
            modelManagementError = nil
            await fetchModels()
            await refreshServerModels()
        } else {
            connectionError = "Cannot reach \(server.displayURL)"
            availableModels = []
            serverModels = []
            if !isSelectedModelLocal {
                selectedModel = localModelLMModels.first
            }
            selectedEmbeddingModelKey = nil
            modelOperationKeys.removeAll()
            modelManagementError = nil
            embeddingError = nil
            lastEmbeddingDimension = nil
            lastEmbeddingPreviewValues = []
            lastEmbeddingTokenUsage = nil
        }
    }

    func fetchModels() async {
        guard let server = activeServer else { return }

        isLoadingModels = true
        do {
            let models = try await apiService.fetchModels(server: server)
            availableModels = models

            if !isSelectedModelLocal {
                // Restore previously selected remote model or pick first available
                let savedModelId = persistence.loadSelectedModelId()
                if let saved = savedModelId, let match = models.first(where: { $0.id == saved }) {
                    selectedModel = match
                } else if let current = selectedModel, let match = models.first(where: { $0.id == current.id }) {
                    selectedModel = match
                } else {
                    selectedModel = models.first ?? localModelLMModels.first
                }
            }
        } catch {
            connectionError = error.localizedDescription
            availableModels = []
            if !isSelectedModelLocal {
                selectedModel = localModelLMModels.first
            }
        }
        isLoadingModels = false
    }

    func refreshServerModels() async {
        guard let server = activeServer else { return }

        isLoadingServerModels = true
        modelManagementError = nil
        defer { isLoadingServerModels = false }

        do {
            let models = try await apiService.fetchServerModels(server: server)
            serverModels = models.sorted(by: serverModelSort)
            syncSelectedEmbeddingModel()
        } catch {
            modelManagementError = error.localizedDescription
            serverModels = []
            selectedEmbeddingModelKey = nil
        }
    }

    func selectModel(_ model: LMModel) {
        selectedModel = model
        persistence.saveSelectedModelId(model.id)
    }

    func loadModel(_ model: ServerModel) async {
        guard let server = activeServer else {
            modelManagementError = "No active server configured"
            return
        }
        guard !isModelOperationInProgress(for: model.key) else { return }

        modelOperationKeys.insert(model.key)
        modelManagementError = nil

        defer {
            modelOperationKeys.remove(model.key)
        }

        do {
            _ = try await apiService.loadModel(server: server, modelKey: model.key)
            await refreshAfterModelMutation()
        } catch {
            modelManagementError = error.localizedDescription
        }
    }

    func unloadModel(_ model: ServerModel) async {
        guard let server = activeServer else {
            modelManagementError = "No active server configured"
            return
        }
        guard !isModelOperationInProgress(for: model.key) else { return }

        let instances = model.loadedInstances ?? []
        guard !instances.isEmpty else { return }

        modelOperationKeys.insert(model.key)
        modelManagementError = nil

        defer {
            modelOperationKeys.remove(model.key)
        }

        do {
            for instance in instances {
                try await apiService.unloadModel(server: server, identifier: instance.instanceId)
            }
            await refreshAfterModelMutation()
        } catch {
            modelManagementError = error.localizedDescription
        }
    }

    func isModelOperationInProgress(for modelKey: String) -> Bool {
        modelOperationKeys.contains(modelKey)
    }

    func clearModelManagementError() {
        modelManagementError = nil
    }

    var embeddingModels: [ServerModel] {
        serverModels.filter { $0.type.lowercased().contains("embedding") }
    }

    var selectedEmbeddingModel: ServerModel? {
        guard let key = selectedEmbeddingModelKey else { return nil }
        return embeddingModels.first(where: { $0.key == key })
    }

    func generateEmbedding(for rawInput: String) async {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            embeddingError = "Enter text to embed"
            return
        }
        guard let server = activeServer else {
            embeddingError = "No active server configured"
            return
        }
        guard let modelKey = selectedEmbeddingModelKey else {
            embeddingError = "No embedding model available"
            return
        }

        isGeneratingEmbedding = true
        embeddingError = nil

        defer {
            isGeneratingEmbedding = false
        }

        do {
            let response = try await apiService.createEmbedding(
                server: server,
                model: modelKey,
                input: input
            )

            guard let embedding = response.data.first?.embedding else {
                throw APIError.invalidResponse
            }

            lastEmbeddingDimension = embedding.count
            lastEmbeddingPreviewValues = Array(embedding.prefix(8))
            lastEmbeddingTokenUsage = response.usage?.totalTokens ?? response.usage?.promptTokens
        } catch {
            embeddingError = error.localizedDescription
        }
    }

    func clearEmbeddingError() {
        embeddingError = nil
    }

    // MARK: - Local Models (On-Device)

    var localModelLMModels: [LMModel] {
        localModels.map {
            LMModel(
                id: $0.modelIdentifier,
                object: "model",
                ownedBy: "On Device"
            )
        }
    }

    var allSelectableModels: [LMModel] {
        localModelLMModels + availableModels
    }

    var isSelectedModelLocal: Bool {
        guard let selectedModel else { return false }
        return isLocalModel(selectedModel)
    }

    var isSelectedLocalModelLoaded: Bool {
        guard let selectedModel, isLocalModel(selectedModel),
              let record = localModelRecord(for: selectedModel) else {
            return false
        }
        return record.isLoaded
    }

    var canSendWithSelectedModel: Bool {
        guard let selectedModel else { return false }
        if isLocalModel(selectedModel) {
            return localModelRecord(for: selectedModel) != nil
        }
        return activeServer != nil && isConnected
    }

    var selectedModelConnectionLabel: String {
        if isSelectedModelLocal {
            return isSelectedLocalModelLoaded ? "On Device" : "Local Not Loaded"
        }
        return isConnected ? "Connected" : "Disconnected"
    }

    var selectedLocalModelSourceLabel: String {
        guard let selectedModel,
              isLocalModel(selectedModel),
              let record = localModelRecord(for: selectedModel) else {
            return "On Device"
        }

        switch record.backend {
        case .gguf:
            return "Hugging Face GGUF"
        case .mlx:
            return "Hugging Face MLX"
        }
    }

    var shouldShowReconnectButton: Bool {
        !isSelectedModelLocal && !isConnected
    }

    func isLocalModel(_ model: LMModel) -> Bool {
        model.id.hasPrefix(localModelIDPrefix)
    }

    func updateHuggingFaceToken(_ token: String) {
        huggingFaceToken = token
        persistence.saveHuggingFaceToken(token)
    }

    func searchHuggingFaceRepositories(query rawQuery: String) async {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            localModelsError = "Enter keywords to search Hugging Face repositories"
            huggingFaceSearchResults = []
            return
        }

        isSearchingHuggingFaceRepos = true
        localModelsError = nil
        defer { isSearchingHuggingFaceRepos = false }

        do {
            let results = try await huggingFaceService.searchMLXRepositories(
                query: query,
                token: huggingFaceToken
            )
            huggingFaceSearchResults = results

            if results.isEmpty {
                localModelsError = "No MLX repositories found for \"\(query)\""
            }
        } catch {
            localModelsError = error.localizedDescription
            huggingFaceSearchResults = []
        }
    }

    func fetchHuggingFaceGGUFFiles(repoId rawRepoId: String) async {
        let repoId = rawRepoId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repoId.isEmpty else {
            localModelsError = "Enter a Hugging Face repository ID"
            discoveredHuggingFaceFiles = []
            return
        }

        isFetchingHuggingFaceFiles = true
        localModelsError = nil
        defer { isFetchingHuggingFaceFiles = false }

        do {
            discoveredHuggingFaceFiles = try await huggingFaceService.fetchGGUFFiles(
                repoId: repoId,
                token: huggingFaceToken
            )
        } catch {
            localModelsError = error.localizedDescription
            discoveredHuggingFaceFiles = []
        }
    }

    func clearHuggingFaceSearchResults() {
        huggingFaceSearchResults = []
    }

    func addLocalMLXModel(repoId rawRepoID: String) {
        let repoId = rawRepoID.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = repoId.split(separator: "/")
        guard parts.count == 2 else {
            localModelsError = "Enter a valid model ID (for example: mlx-community/Qwen3.5-4B-MLX-4bit)"
            return
        }

        if let existingIndex = localModels.firstIndex(where: { $0.backend == .mlx && $0.repoId.caseInsensitiveCompare(repoId) == .orderedSame }) {
            localModels[existingIndex].downloadedAt = Date()
        } else {
            localModels.append(
                .mlx(
                    repoId: repoId
                )
            )
        }

        localModelsError = nil
        persistence.saveLocalModels(localModels)

        if selectedModel == nil {
            selectedModel = localModelLMModels.first
            persistence.saveSelectedModelId(selectedModel?.id)
        }
    }

    func downloadLocalModel(file: HuggingFaceGGUFFile) async {
        guard !isDownloadingLocalModel else { return }

        isDownloadingLocalModel = true
        downloadingHuggingFaceFileID = file.id
        localModelsError = nil

        defer {
            isDownloadingLocalModel = false
            downloadingHuggingFaceFileID = nil
        }

        do {
            let destination = localModelURL(repoId: file.repoId, filename: file.filename)
            let contentLength = try await huggingFaceService.downloadGGUF(
                repoId: file.repoId,
                filename: file.filename,
                token: huggingFaceToken,
                to: destination
            )

            upsertLocalModelRecord(
                repoId: file.repoId,
                filename: file.filename,
                storedFilename: destination.lastPathComponent,
                fileSizeBytes: file.sizeBytes ?? contentLength
            )
        } catch {
            localModelsError = error.localizedDescription
        }
    }

    func deleteLocalModel(_ model: LocalModelRecord) {
        if model.isLoaded {
            Task { await unloadLocalModel() }
        }

        if model.requiresLocalFile {
            let url = localModelsDirectory.appendingPathComponent(model.storedFilename)
            if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                try? FileManager.default.removeItem(at: url)
            }
        }

        localModels.removeAll { $0.id == model.id }

        if selectedModel?.id == model.modelIdentifier {
            selectedModel = availableModels.first ?? localModelLMModels.first
            persistence.saveSelectedModelId(selectedModel?.id)
        }

        persistence.saveLocalModels(localModels)
    }

    func loadLocalModel(_ model: LocalModelRecord) async {
        do {
            try await loadLocalModelThrowing(model)
        } catch {
            localModelsError = error.localizedDescription
        }
    }

    func unloadLocalModel() async {
        await localInferenceService.unloadModel()
        await localMLXInferenceService.unloadModel()
        localModels = localModels.map { model in
            var updated = model
            updated.isLoaded = false
            return updated
        }
        persistence.saveLocalModels(localModels)
    }

    func clearLocalModelsError() {
        localModelsError = nil
    }

    func streamLocalCompletion(
        messages: [Message],
        onToken: @escaping @Sendable (String) -> Void
    ) async throws {
        guard let selectedModel, isLocalModel(selectedModel),
              let record = localModelRecord(for: selectedModel) else {
            throw LocalInferenceError.modelNotLoaded
        }

        try await loadLocalModelThrowing(record)
        switch record.backend {
        case .gguf:
            _ = try await localInferenceService.streamCompletion(messages: messages, onToken: onToken)
        case .mlx:
            _ = try await localMLXInferenceService.streamCompletion(messages: messages, onToken: onToken)
        }
    }

    func stopLocalCompletion() async {
        await localInferenceService.stopCompletion()
        await localMLXInferenceService.stopCompletion()
    }

    private func localModelRecord(for model: LMModel) -> LocalModelRecord? {
        localModels.first { $0.modelIdentifier == model.id }
    }

    private func localModelURL(repoId: String, filename: String) -> URL {
        let safeRepo = repoId.replacingOccurrences(of: "/", with: "__")
        let safeFilename = filename.replacingOccurrences(of: "/", with: "__")
        let storageName = "\(safeRepo)__\(safeFilename)"
        return localModelsDirectory.appendingPathComponent(storageName)
    }

    private var localModelsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("LocalModels", isDirectory: true)
    }

    private func upsertLocalModelRecord(
        repoId: String,
        filename: String,
        storedFilename: String,
        fileSizeBytes: Int64?
    ) {
        if let index = localModels.firstIndex(where: { $0.repoId == repoId && $0.filename == filename }) {
            localModels[index].storedFilename = storedFilename
            localModels[index].fileSizeBytes = fileSizeBytes
            localModels[index].downloadedAt = Date()
        } else {
            localModels.append(
                LocalModelRecord(
                    repoId: repoId,
                    filename: filename,
                    storedFilename: storedFilename,
                    fileSizeBytes: fileSizeBytes
                )
            )
        }

        persistence.saveLocalModels(localModels)

        if selectedModel == nil {
            selectedModel = localModelLMModels.first
            persistence.saveSelectedModelId(selectedModel?.id)
        }
    }

    private func loadLocalModelThrowing(_ model: LocalModelRecord) async throws {
        isLoadingLocalModel = true
        defer { isLoadingLocalModel = false }

        switch model.backend {
        case .gguf:
            let url = localModelsDirectory.appendingPathComponent(model.storedFilename)
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
                throw LocalInferenceError.modelFileMissing
            }

            await localMLXInferenceService.unloadModel()
            try await localInferenceService.loadModel(from: url)
        case .mlx:
            await localInferenceService.unloadModel()
            try await localMLXInferenceService.loadModel(id: model.repoId)
        }

        localModels = localModels.map { item in
            var updated = item
            updated.isLoaded = item.id == model.id
            return updated
        }

        selectedModel = LMModel(
            id: model.modelIdentifier,
            object: "model",
            ownedBy: "On Device"
        )

        persistence.saveSelectedModelId(selectedModel?.id)
        persistence.saveLocalModels(localModels)
        localModelsError = nil
    }

    // MARK: - Persistence

    private func loadLocalState() {
        huggingFaceToken = persistence.loadHuggingFaceToken()
        localModels = persistence.loadLocalModels()
        try? FileManager.default.createDirectory(at: localModelsDirectory, withIntermediateDirectories: true)

        // Remove stale file-backed records if files are missing.
        localModels = localModels.filter { model in
            guard model.requiresLocalFile else {
                return true
            }
            let url = localModelsDirectory.appendingPathComponent(model.storedFilename)
            return FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
        }

        localModels = localModels.map { model in
            var updated = model
            updated.isLoaded = false
            return updated
        }

        persistence.saveLocalModels(localModels)
    }

    private func loadSavedState() {
        servers = persistence.loadServers()
        let savedModelId = persistence.loadSelectedModelId()

        if let activeId = persistence.loadActiveServerId() {
            activeServer = servers.first { $0.id == activeId }
        } else {
            activeServer = servers.first
        }

        if let savedModelId,
           let localModel = localModelLMModels.first(where: { $0.id == savedModelId }) {
            selectedModel = localModel
        }

        if activeServer != nil {
            Task { await connectToActiveServer() }
        }
    }

    private func refreshAfterModelMutation() async {
        await fetchModels()
        await refreshServerModels()
    }

    private func startConnectivityMonitoringIfNeeded() {
        guard healthMonitorTask == nil else { return }

        healthMonitorTask = Task { [weak self] in
            await self?.runConnectivityMonitorLoop()
        }
    }

    private func runConnectivityMonitorLoop() async {
        while !Task.isCancelled {
            if isHealthMonitoringActive {
                await probeConnectionHealth()
            }

            try? await Task.sleep(nanoseconds: healthCheckIntervalNanoseconds)
        }
    }

    private func probeConnectionHealth() async {
        guard let server = activeServer else {
            isConnected = false
            connectionError = nil
            return
        }

        if isCheckingConnection {
            return
        }

        let serverID = server.id
        let wasConnected = isConnected
        let healthy = await apiService.checkServerHealth(
            server: server,
            timeout: healthCheckTimeoutSeconds
        )

        guard activeServer?.id == serverID else {
            return
        }

        if healthy {
            if !wasConnected {
                isConnected = true
                connectionError = nil
                await fetchModels()
                await refreshServerModels()
            }
        } else {
            isConnected = false
            connectionError = "Cannot reach \(server.displayURL)"
        }
    }

    private func syncSelectedEmbeddingModel() {
        let keys = Set(embeddingModels.map(\.key))
        if let selected = selectedEmbeddingModelKey, keys.contains(selected) {
            return
        }
        selectedEmbeddingModelKey = embeddingModels.first?.key
    }

    private func serverModelSort(lhs: ServerModel, rhs: ServerModel) -> Bool {
        if lhs.isLoaded != rhs.isLoaded {
            return lhs.isLoaded && !rhs.isLoaded
        }
        if lhs.type != rhs.type {
            return lhs.type.localizedCaseInsensitiveCompare(rhs.type) == .orderedAscending
        }
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }

    var hasServers: Bool {
        !servers.isEmpty || !localModels.isEmpty
    }
}
