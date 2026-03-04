import Foundation
import SwiftUI

struct SettingsView: View {
    @ObservedObject var serverVM: ServerViewModel
    @Environment(\.dismiss) private var dismiss

    private static let huggingFaceDateParserWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let huggingFaceDateParser: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    @State private var showAddServer = false
    @State private var editingServer: ServerConfig?
    @State private var revealContent = false
    @State private var embeddingInput = ""
    @State private var huggingFaceRepoId = ""
    @State private var huggingFaceSearchQuery = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: LMTheme.paddingXL) {
                    serversSection
                    activeServerSection
                    modelsSection
                    localModelsSection
                    embeddingsSection
                    aboutSection
                }
                .padding(.horizontal, LMTheme.paddingLG)
                .padding(.vertical, LMTheme.paddingLG)
                .opacity(revealContent ? 1 : 0)
                .offset(y: revealContent ? 0 : 10)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background {
                LMTheme.appBackground.ignoresSafeArea()
            }
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: LMTheme.paddingSM)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(LMTheme.accent)
                        .fontWeight(.medium)
                }
            }
            .sheet(isPresented: $showAddServer) {
                ServerSetupView(serverVM: serverVM)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(28)
                    .presentationCompactAdaptation(.sheet)
            }
            .sheet(item: $editingServer) { server in
                ServerSetupView(serverVM: serverVM, editingServer: server)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(28)
                    .presentationCompactAdaptation(.sheet)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.24)) {
                    revealContent = true
                }

                if huggingFaceRepoId.isEmpty {
                    huggingFaceRepoId = "mlx-community/Qwen3.5-4B-MLX-4bit"
                }
                if huggingFaceSearchQuery.isEmpty {
                    huggingFaceSearchQuery = "qwen 3.5 mlx"
                }

                if serverVM.isConnected {
                    Task {
                        await serverVM.refreshServerModels()
                    }
                }
            }
            .onDisappear {
                revealContent = false
            }
        }
    }

    // MARK: - Servers

    private var serversSection: some View {
        VStack(alignment: .leading, spacing: LMTheme.paddingMD) {
            sectionHeader("Servers")

            VStack(spacing: 0) {
                ForEach(Array(serverVM.servers.enumerated()), id: \.element.id) { index, server in
                    if index > 0 {
                        Rectangle()
                            .fill(LMTheme.border)
                            .frame(height: 1)
                            .padding(.leading, 52)
                    }

                    serverRow(server)
                }

                if !serverVM.servers.isEmpty {
                    Rectangle()
                        .fill(LMTheme.border)
                        .frame(height: 1)
                        .padding(.leading, 52)
                }

                Button {
                    showAddServer = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(LMTheme.accent)
                            .frame(width: 28)

                        Text("Add Server")
                            .font(.body)
                            .foregroundStyle(LMTheme.accent)

                        Spacer()
                    }
                    .padding(.horizontal, LMTheme.paddingLG)
                    .padding(.vertical, LMTheme.paddingMD)
                }
            }
            .glassCard(padding: 0, cornerRadius: 16)
        }
    }

    private func serverRow(_ server: ServerConfig) -> some View {
        let isActive = serverVM.activeServer?.id == server.id

        return Button {
            serverVM.setActiveServer(server)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isActive ? LMTheme.accentMuted : LMTheme.surfaceSecondary)
                        .frame(width: 36, height: 36)

                    Image(systemName: "server.rack")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isActive ? LMTheme.accent : LMTheme.textTertiary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(server.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(LMTheme.textPrimary)
                    Text(server.displayURL)
                        .font(.caption)
                        .foregroundStyle(LMTheme.textTertiary)
                }

                Spacer()

                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(LMTheme.accent)
                }
            }
            .padding(.horizontal, LMTheme.paddingLG)
            .padding(.vertical, LMTheme.paddingMD)
            .contentShape(Rectangle())
        }
        .contextMenu {
            Button {
                editingServer = server
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Button(role: .destructive) {
                serverVM.removeServer(server)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Active Server

    private var activeServerSection: some View {
        Group {
            if let server = serverVM.activeServer {
                VStack(alignment: .leading, spacing: LMTheme.paddingMD) {
                    sectionHeader("Connection")

                    VStack(spacing: 0) {
                        infoRow(icon: "globe", title: "Host", value: server.host)
                        infoDivider
                        infoRow(icon: "number", title: "Port", value: String(server.port))
                        infoDivider
                        infoRow(icon: "lock.shield", title: "TLS", value: server.useTLS ? "Enabled" : "Disabled")
                        infoDivider
                        infoRow(icon: "key", title: "API Key", value: server.apiKey.isEmpty ? "None" : "Set")
                        infoDivider

                        HStack(spacing: 12) {
                            Image(systemName: "wifi")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(LMTheme.accent)
                                .frame(width: 24)

                            Text("Status")
                                .font(.body)
                                .foregroundStyle(LMTheme.textSecondary)

                            Spacer()

                            HStack(spacing: 6) {
                                Circle()
                                    .fill(serverVM.isConnected ? LMTheme.success : LMTheme.error)
                                    .frame(width: 7, height: 7)
                                Text(serverVM.isConnected ? "Connected" : "Disconnected")
                                    .font(.body)
                                    .foregroundStyle(serverVM.isConnected ? LMTheme.success : LMTheme.error)
                            }
                        }
                        .padding(.horizontal, LMTheme.paddingLG)
                        .padding(.vertical, LMTheme.paddingMD)

                        infoDivider

                        Button {
                            Task { await serverVM.connectToActiveServer() }
                        } label: {
                            HStack {
                                Spacer()
                                if serverVM.isCheckingConnection {
                                    ProgressView()
                                        .tint(LMTheme.accent)
                                        .scaleEffect(0.8)
                                } else {
                                    HStack(spacing: 6) {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.system(size: 13, weight: .semibold))
                                        Text("Reconnect")
                                            .font(.body.weight(.medium))
                                    }
                                }
                                Spacer()
                            }
                            .foregroundStyle(LMTheme.accent)
                            .padding(.vertical, LMTheme.paddingMD)
                        }
                    }
                    .glassCard(padding: 0, cornerRadius: 16)
                }
            }
        }
    }

    // MARK: - Models

    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: LMTheme.paddingMD) {
            HStack {
                sectionHeader("Models")
                Spacer()
                if serverVM.isLoadingServerModels {
                    ProgressView()
                        .tint(LMTheme.accent)
                        .scaleEffect(0.8)
                } else {
                    Button {
                        Task { await serverVM.refreshServerModels() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(LMTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(serverVM.activeServer == nil)
                }
            }

            VStack(spacing: 0) {
                if !serverVM.serverModels.isEmpty {
                    ForEach(Array(serverVM.serverModels.enumerated()), id: \.element.id) { index, model in
                        if index > 0 {
                            Rectangle()
                                .fill(LMTheme.border)
                                .frame(height: 1)
                                .padding(.leading, 52)
                        }

                        unifiedModelRow(model)
                    }
                } else if !serverVM.availableModels.isEmpty {
                    ForEach(Array(serverVM.availableModels.enumerated()), id: \.element.id) { index, model in
                        if index > 0 {
                            Rectangle()
                                .fill(LMTheme.border)
                                .frame(height: 1)
                                .padding(.leading, 52)
                        }

                        fallbackModelRow(model)
                    }
                } else {
                    emptyModelsRow
                }
            }
            .glassCard(padding: 0, cornerRadius: 16)

            if let error = serverVM.modelManagementError {
                sectionErrorBanner(message: error) {
                    serverVM.clearModelManagementError()
                }
            }
        }
    }

    private var emptyModelsRow: some View {
        let title = serverVM.isConnected ? "No runtime models found" : "Server disconnected"
        let subtitle = serverVM.isConnected
            ? "Open LM Studio and download or discover models there."
            : "Reconnect to inspect model runtime state."

        return HStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(LMTheme.textTertiary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(LMTheme.textPrimary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(LMTheme.textTertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, LMTheme.paddingLG)
        .padding(.vertical, LMTheme.paddingMD)
    }

    private func unifiedModelRow(_ model: ServerModel) -> some View {
        let isBusy = serverVM.isModelOperationInProgress(for: model.key)
        let isLoaded = model.isLoaded
        let selectedRuntimeKey = selectedRuntimeModelKey()
        let isSelected = isLoaded && selectedRuntimeKey == model.key
        let linkedModel = matchedAvailableModel(for: model)

        return HStack(spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? LMTheme.accentMuted : LMTheme.surfaceSecondary)
                        .frame(width: 36, height: 36)

                    Image(systemName: model.type.lowercased().contains("embedding") ? "waveform.path.ecg" : "cpu")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isSelected ? LMTheme.accent : LMTheme.textTertiary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(LMTheme.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(model.normalizedType)
                            .font(.caption)
                            .foregroundStyle(LMTheme.textTertiary)
                        Text(isLoaded ? "Loaded \(model.loadedInstanceCount)x" : "Not loaded")
                            .font(.caption)
                            .foregroundStyle(isLoaded ? LMTheme.success : LMTheme.warning)
                    }
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard isLoaded, let linkedModel else { return }
                serverVM.selectModel(linkedModel)
            }

            Button {
                Task {
                    if isLoaded {
                        await serverVM.unloadModel(model)
                    } else {
                        await serverVM.loadModel(model)
                    }
                }
            } label: {
                Group {
                    if isBusy {
                        ProgressView()
                            .tint(LMTheme.accent)
                            .scaleEffect(0.8)
                    } else {
                        Text(isLoaded ? "Unload" : "Load")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isLoaded ? LMTheme.warning : LMTheme.accent)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background((isLoaded ? LMTheme.warning : LMTheme.accent).opacity(0.16))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isBusy || serverVM.activeServer == nil || !serverVM.isConnected)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(LMTheme.accent)
            }
        }
        .padding(.horizontal, LMTheme.paddingLG)
        .padding(.vertical, LMTheme.paddingMD)
    }

    private func fallbackModelRow(_ model: LMModel) -> some View {
        let isSelected = serverVM.selectedModel?.id == model.id
        return Button {
            serverVM.selectModel(model)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? LMTheme.accentMuted : LMTheme.surfaceSecondary)
                        .frame(width: 36, height: 36)

                    Image(systemName: "cpu")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isSelected ? LMTheme.accent : LMTheme.textTertiary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(LMTheme.textPrimary)
                    if let owner = model.ownedBy {
                        Text(owner)
                            .font(.caption)
                            .foregroundStyle(LMTheme.textTertiary)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(LMTheme.accent)
                }
            }
            .padding(.horizontal, LMTheme.paddingLG)
            .padding(.vertical, LMTheme.paddingMD)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func matchedAvailableModel(for model: ServerModel) -> LMModel? {
        serverVM.availableModels.first { modelKeysOverlap($0.id, model.key) }
    }

    private func selectedRuntimeModelKey() -> String? {
        guard let selected = serverVM.selectedModel else { return nil }

        if let exact = serverVM.serverModels.first(where: { normalizedModelKey($0.key) == normalizedModelKey(selected.id) }) {
            return exact.key
        }

        let overlapping = serverVM.serverModels.filter { modelKeysOverlap(selected.id, $0.key) }

        if overlapping.count == 1 {
            return overlapping[0].key
        }
        if let loaded = overlapping.first(where: { $0.isLoaded }) {
            return loaded.key
        }

        return overlapping.first?.key
    }

    private func modelKeysOverlap(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalizedModelKey(lhs)
        let right = normalizedModelKey(rhs)

        if left == right {
            return true
        }

        if left.count >= 6 && right.count >= 6 && (left.contains(right) || right.contains(left)) {
            return true
        }

        return !modelKeyTokens(lhs).isDisjoint(with: modelKeyTokens(rhs))
    }

    private func normalizedModelKey(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
    }

    private func modelKeyTokens(_ raw: String) -> Set<String> {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")

        guard !normalized.isEmpty else { return [] }

        var tokens: Set<String> = [normalized]

        if normalized.contains("/") {
            let tail = normalized.split(separator: "/").last.map(String.init) ?? normalized
            tokens.insert(tail)
        }

        return tokens
    }

    // MARK: - On-Device Models

    private var localModelsSection: some View {
        VStack(alignment: .leading, spacing: LMTheme.paddingMD) {
            sectionHeader("On-Device LLMs")

            VStack(alignment: .leading, spacing: LMTheme.paddingMD) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Search Hugging Face")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(LMTheme.textTertiary)

                    TextField("qwen 3.5 mlx", text: $huggingFaceSearchQuery)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(LMTheme.surfaceSecondary.opacity(0.82))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(LMTheme.borderLight, lineWidth: 1)
                        )
                        .onSubmit {
                            Task {
                                await serverVM.searchHuggingFaceRepositories(query: huggingFaceSearchQuery)
                            }
                        }
                }

                HStack(spacing: 10) {
                    Button {
                        Task {
                            await serverVM.searchHuggingFaceRepositories(query: huggingFaceSearchQuery)
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if serverVM.isSearchingHuggingFaceRepos {
                                ProgressView()
                                    .tint(LMTheme.accent)
                                    .scaleEffect(0.8)
                            } else {
                                Label("Search Repositories", systemImage: "magnifyingglass")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(LMTheme.accent)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        .background(LMTheme.accentMuted)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(
                        huggingFaceSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || serverVM.isSearchingHuggingFaceRepos
                    )

                    if !serverVM.huggingFaceSearchResults.isEmpty {
                        Button {
                            serverVM.clearHuggingFaceSearchResults()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(LMTheme.textSecondary)
                                .frame(width: 34, height: 34)
                                .background(LMTheme.surfaceSecondary.opacity(0.84))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(LMTheme.border, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !serverVM.huggingFaceSearchResults.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Repository Results")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(LMTheme.textTertiary)

                        ForEach(serverVM.huggingFaceSearchResults) { result in
                            huggingFaceRepoSearchRow(result)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Selected MLX Model ID")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(LMTheme.textTertiary)

                    TextField("owner/repo", text: $huggingFaceRepoId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(LMTheme.surfaceSecondary.opacity(0.82))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(LMTheme.borderLight, lineWidth: 1)
                        )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Hugging Face Token (optional)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(LMTheme.textTertiary)

                    SecureField(
                        "hf_...",
                        text: Binding(
                            get: { serverVM.huggingFaceToken },
                            set: { serverVM.updateHuggingFaceToken($0) }
                        )
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(LMTheme.surfaceSecondary.opacity(0.82))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(LMTheme.borderLight, lineWidth: 1)
                    )
                }

                Button {
                    serverVM.addLocalMLXModel(repoId: huggingFaceRepoId)
                } label: {
                    HStack {
                        Spacer()
                        Label("Add MLX Model", systemImage: "plus")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(LMTheme.accent)
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .background(LMTheme.accentMuted)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(huggingFaceRepoId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if !serverVM.localModels.isEmpty {
                    Rectangle()
                        .fill(LMTheme.border)
                        .frame(height: 1)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Configured On Device")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(LMTheme.textTertiary)

                        ForEach(serverVM.localModels) { model in
                            localDownloadedModelRow(model)
                        }
                    }
                } else {
                    Text("No local models configured yet.")
                        .font(.subheadline)
                        .foregroundStyle(LMTheme.textSecondary)
                }
            }
            .padding(LMTheme.paddingLG)
            .glassCard(padding: 0, cornerRadius: 16)

            if let error = serverVM.localModelsError {
                sectionErrorBanner(message: error) {
                    serverVM.clearLocalModelsError()
                }
            }
        }
    }

    private func huggingFaceRepoSearchRow(_ result: HuggingFaceRepoSearchResult) -> some View {
        let selectedRepoId = huggingFaceRepoId.trimmingCharacters(in: .whitespacesAndNewlines)
        let isSelectedRepo = selectedRepoId.caseInsensitiveCompare(result.repoId) == .orderedSame

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(result.repoId)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LMTheme.textPrimary)
                    .lineLimit(1)

                let metadata = huggingFaceRepoMetadata(result)
                if !metadata.isEmpty {
                    Text(metadata)
                        .font(.caption)
                        .foregroundStyle(LMTheme.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Button {
                huggingFaceRepoId = result.repoId
            } label: {
                Text(isSelectedRepo ? "Selected" : "Use")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LMTheme.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(LMTheme.accentMuted)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(LMTheme.surfaceSecondary.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelectedRepo ? LMTheme.accent.opacity(0.45) : LMTheme.borderLight, lineWidth: 1)
        )
    }

    private func huggingFaceRepoMetadata(_ result: HuggingFaceRepoSearchResult) -> String {
        var parts: [String] = []

        if let count = result.matchingArtifactCount {
            parts.append("\(count) files")
        }
        if result.isLikelyMLX {
            parts.append("MLX")
        }
        if let downloads = result.downloads {
            parts.append("\(downloads.formatted(.number.notation(.compactName))) downloads")
        }
        if let likes = result.likes {
            parts.append("\(likes.formatted(.number.notation(.compactName))) likes")
        }
        if let lastModified = huggingFaceLastModifiedLabel(result.lastModified) {
            parts.append("updated \(lastModified)")
        }

        return parts.joined(separator: " • ")
    }

    private func huggingFaceLastModifiedLabel(_ rawValue: String?) -> String? {
        guard let rawValue, !rawValue.isEmpty else { return nil }
        if let date = SettingsView.huggingFaceDateParserWithFractionalSeconds.date(from: rawValue)
            ?? SettingsView.huggingFaceDateParser.date(from: rawValue) {
            return date.formatted(.dateTime.year().month(.abbreviated).day())
        }
        return String(rawValue.prefix(10))
    }

    private func localDownloadedModelRow(_ model: LocalModelRecord) -> some View {
        let lmModel = LMModel(id: model.modelIdentifier, object: "model", ownedBy: "On Device")
        let isSelected = serverVM.selectedModel?.id == lmModel.id
        let isBusy = serverVM.isLoadingLocalModel

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LMTheme.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(model.repoId)
                        .font(.caption)
                        .foregroundStyle(LMTheme.textTertiary)
                        .lineLimit(1)

                    Text("• \(model.backend.displayName)")
                        .font(.caption)
                        .foregroundStyle(LMTheme.textTertiary)

                    if let size = model.fileSizeBytes {
                        Text("• \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))")
                            .font(.caption)
                            .foregroundStyle(LMTheme.textTertiary)
                    }
                }
            }

            Spacer(minLength: 0)

            if model.isLoaded {
                Text("Loaded")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LMTheme.success)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(LMTheme.success.opacity(0.15))
                    .clipShape(Capsule())
            }

            Button {
                Task {
                    if model.isLoaded {
                        await serverVM.unloadLocalModel()
                    } else {
                        await serverVM.loadLocalModel(model)
                    }
                }
            } label: {
                Group {
                    if isBusy {
                        ProgressView()
                            .tint(LMTheme.accent)
                            .scaleEffect(0.8)
                    } else {
                        Text(model.isLoaded ? "Unload" : "Load")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(model.isLoaded ? LMTheme.warning : LMTheme.accent)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background((model.isLoaded ? LMTheme.warning : LMTheme.accent).opacity(0.16))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isBusy)

            Button {
                serverVM.selectModel(lmModel)
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? LMTheme.accent : LMTheme.textTertiary)
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                serverVM.deleteLocalModel(model)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LMTheme.error)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(LMTheme.surfaceSecondary.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(LMTheme.borderLight, lineWidth: 1)
        )
    }

    // MARK: - Embeddings

    private var embeddingsSection: some View {
        VStack(alignment: .leading, spacing: LMTheme.paddingMD) {
            sectionHeader("Embeddings")

            VStack(alignment: .leading, spacing: LMTheme.paddingMD) {
                if serverVM.embeddingModels.isEmpty {
                    Text("No embedding models available on this server.")
                        .font(.subheadline)
                        .foregroundStyle(LMTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Model")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(LMTheme.textTertiary)

                        Picker("Embedding Model", selection: embeddingModelSelection) {
                            ForEach(serverVM.embeddingModels) { model in
                                Text(model.displayName).tag(model.key)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(LMTheme.accent)
                    }

                    if let selected = serverVM.selectedEmbeddingModel {
                        HStack(spacing: 8) {
                            Text(selected.isLoaded ? "Loaded \(selected.loadedInstanceCount)x" : "Not loaded")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(selected.isLoaded ? LMTheme.success : LMTheme.warning)

                            Spacer(minLength: 0)

                            if !selected.isLoaded {
                                Button {
                                    Task { await serverVM.loadModel(selected) }
                                } label: {
                                    Text("Load Model")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(LMTheme.accent)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(LMTheme.accentMuted)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .disabled(serverVM.isModelOperationInProgress(for: selected.key))
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Input Text")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(LMTheme.textTertiary)

                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(LMTheme.surfaceSecondary.opacity(0.84))

                            TextEditor(text: $embeddingInput)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .scrollContentBackground(.hidden)
                                .foregroundStyle(LMTheme.textPrimary)
                                .font(.subheadline)
                                .frame(minHeight: 92)

                            if embeddingInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("Paste or type text to generate an embedding vector")
                                    .font(.subheadline)
                                    .foregroundStyle(LMTheme.textTertiary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 14)
                                    .allowsHitTesting(false)
                            }
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(LMTheme.borderLight, lineWidth: 1)
                        )
                    }

                    Button {
                        Task { await serverVM.generateEmbedding(for: embeddingInput) }
                    } label: {
                        HStack {
                            Spacer()
                            if serverVM.isGeneratingEmbedding {
                                ProgressView()
                                    .tint(LMTheme.accent)
                            } else {
                                Text("Generate Embedding")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(LMTheme.accent)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        .background(LMTheme.accentMuted)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(
                        serverVM.isGeneratingEmbedding
                            || embeddingInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || serverVM.selectedEmbeddingModelKey == nil
                    )

                    if let dimension = serverVM.lastEmbeddingDimension {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Vector Dimension: \(dimension)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(LMTheme.textPrimary)

                            if let tokenUsage = serverVM.lastEmbeddingTokenUsage {
                                Text("Token Usage: \(tokenUsage)")
                                    .font(.caption)
                                    .foregroundStyle(LMTheme.textTertiary)
                            }

                            if !serverVM.lastEmbeddingPreviewValues.isEmpty {
                                Text(
                                    serverVM.lastEmbeddingPreviewValues
                                        .map { String(format: "%.4f", $0) }
                                        .joined(separator: ", ")
                                )
                                .font(.caption.monospaced())
                                .foregroundStyle(LMTheme.textSecondary)
                                .lineLimit(3)
                            }
                        }
                        .padding(LMTheme.paddingMD)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(LMTheme.surfaceSecondary.opacity(0.78))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(LMTheme.border, lineWidth: 1)
                        )
                    }
                }
            }
            .padding(LMTheme.paddingLG)
            .glassCard(padding: 0, cornerRadius: 16)

            if let error = serverVM.embeddingError {
                sectionErrorBanner(message: error) {
                    serverVM.clearEmbeddingError()
                }
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: LMTheme.paddingMD) {
            sectionHeader("About")

            VStack(spacing: 0) {
                infoRow(icon: "info.circle", title: "Version", value: "1.0.0")
                infoDivider
                infoRow(icon: "arrow.left.arrow.right", title: "Protocol", value: "OpenAI + LM Studio + Local MLX/GGUF")
            }
            .glassCard(padding: 0, cornerRadius: 16)
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(LMTheme.textTertiary)
            .padding(.leading, 4)
    }

    private var embeddingModelSelection: Binding<String> {
        Binding(
            get: {
                serverVM.selectedEmbeddingModelKey
                    ?? serverVM.embeddingModels.first?.key
                    ?? ""
            },
            set: { newValue in
                serverVM.selectedEmbeddingModelKey = newValue
            }
        )
    }

    private func sectionErrorBanner(
        message: String,
        dismiss: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(LMTheme.error)

            Text(message)
                .font(.caption)
                .foregroundStyle(LMTheme.textPrimary)
                .lineLimit(2)

            Spacer(minLength: 0)

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(LMTheme.textTertiary)
                    .frame(width: 22, height: 22)
                    .background(LMTheme.surfaceSecondary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, LMTheme.paddingMD)
        .padding(.vertical, LMTheme.paddingSM)
        .background(LMTheme.error.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(LMTheme.error.opacity(0.42), lineWidth: 1)
        )
    }

    private func infoRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(LMTheme.accent)
                .frame(width: 24)

            Text(title)
                .font(.body)
                .foregroundStyle(LMTheme.textSecondary)

            Spacer()

            Text(value)
                .font(.body)
                .foregroundStyle(LMTheme.textPrimary)
        }
        .padding(.horizontal, LMTheme.paddingLG)
        .padding(.vertical, LMTheme.paddingMD)
    }

    private var infoDivider: some View {
        Rectangle()
            .fill(LMTheme.border)
            .frame(height: 1)
            .padding(.leading, 52)
    }
}
