import Foundation
import SwiftUI

@MainActor
final class ServerViewModel: ObservableObject {
    @Published var servers: [ServerConfig] = []
    @Published var activeServer: ServerConfig?
    @Published var availableModels: [LMModel] = []
    @Published var serverModels: [ServerModel] = []
    @Published var selectedModel: LMModel?
    @Published var selectedEmbeddingModelKey: String?
    @Published var isConnected = false
    @Published var isCheckingConnection = false
    @Published var connectionError: String?
    @Published var isLoadingModels = false
    @Published var isLoadingServerModels = false
    @Published var modelManagementError: String?
    @Published var isGeneratingEmbedding = false
    @Published var embeddingError: String?
    @Published var lastEmbeddingDimension: Int?
    @Published var lastEmbeddingPreviewValues: [Double] = []
    @Published var lastEmbeddingTokenUsage: Int?

    @Published private var modelOperationKeys: Set<String> = []

    private let apiService = APIService()
    private let persistence = PersistenceService.shared
    private let healthCheckIntervalNanoseconds: UInt64 = 3_000_000_000
    private let healthCheckTimeoutSeconds: TimeInterval = 2.5
    private var healthMonitorTask: Task<Void, Never>?
    private var isHealthMonitoringActive = true

    init() {
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
                selectedModel = nil
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
            selectedModel = nil
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

            // Restore previously selected model or pick first
            let savedModelId = persistence.loadSelectedModelId()
            if let saved = savedModelId, let match = models.first(where: { $0.id == saved }) {
                selectedModel = match
            } else {
                selectedModel = models.first
            }
        } catch {
            connectionError = error.localizedDescription
            availableModels = []
            selectedModel = nil
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

    // MARK: - Persistence

    private func loadSavedState() {
        servers = persistence.loadServers()

        if let activeId = persistence.loadActiveServerId() {
            activeServer = servers.first { $0.id == activeId }
        } else {
            activeServer = servers.first
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
        !servers.isEmpty
    }
}
