import SwiftUI

struct ModelPickerView: View {
    @ObservedObject var serverVM: ServerViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var revealContent = false

    var body: some View {
        NavigationStack {
            Group {
                if isInitialLoading {
                    loadingView
                } else if !serverVM.serverModels.isEmpty {
                    runtimeModelList
                } else if !serverVM.availableModels.isEmpty {
                    loadedModelList
                } else {
                    emptyView
                }
            }
            .background {
                LMTheme.appBackground.ignoresSafeArea()
            }
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: LMTheme.paddingSM)
            }
            .navigationTitle("Models")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await refreshAllModels() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(LMTheme.textSecondary)
                    }
                    .disabled(serverVM.activeServer == nil)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(LMTheme.accent)
                        .fontWeight(.medium)
                }
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.24)) {
                    revealContent = true
                }

                Task {
                    await refreshAllModels()
                }
            }
            .onDisappear {
                revealContent = false
            }
        }
    }

    private var isInitialLoading: Bool {
        (serverVM.isLoadingModels || serverVM.isLoadingServerModels)
            && serverVM.availableModels.isEmpty
            && serverVM.serverModels.isEmpty
    }

    private var loadingView: some View {
        VStack(spacing: LMTheme.paddingLG) {
            ProgressView()
                .tint(LMTheme.accent)
                .scaleEffect(1.1)

            Text("Loading models...")
                .font(.subheadline)
                .foregroundStyle(LMTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(LMTheme.meshGlow)
                    .frame(width: 130, height: 130)

                Image(systemName: "cpu")
                    .font(.system(size: 38))
                    .foregroundStyle(LMTheme.textTertiary)
            }

            Text("No Models Loaded")
                .font(.headline.weight(.semibold))
                .foregroundStyle(LMTheme.textPrimary)

            Text("No models available yet. Load one in LM Studio or use runtime controls, then refresh.")
                .font(.subheadline)
                .foregroundStyle(LMTheme.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                Task { await refreshAllModels() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Refresh")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(LMTheme.accent)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(LMTheme.accentMuted)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            if let error = serverVM.modelManagementError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(LMTheme.error)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, LMTheme.paddingXL)
    }

    private var runtimeModelList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(serverVM.serverModels) { model in
                    runtimeModelRow(model)
                }

                if let error = serverVM.modelManagementError {
                    runtimeSupportBanner(error)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, LMTheme.paddingLG)
            .padding(.top, LMTheme.paddingSM)
            .padding(.bottom, LMTheme.paddingXL)
            .opacity(revealContent ? 1 : 0)
            .offset(y: revealContent ? 0 : 8)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
    }

    private var loadedModelList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(serverVM.availableModels) { model in
                    let isSelected = serverVM.selectedModel?.id == model.id

                    Button {
                        serverVM.selectModel(model)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(isSelected ? LMTheme.accentMuted : LMTheme.surfaceSecondary.opacity(0.86))
                                    .frame(width: 38, height: 38)

                                Image(systemName: "cpu")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(isSelected ? LMTheme.accent : LMTheme.textTertiary)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.displayName)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(LMTheme.textPrimary)
                                    .lineLimit(1)

                                Text("Loaded")
                                    .font(.caption)
                                    .foregroundStyle(LMTheme.success)
                            }

                            Spacer()

                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 21))
                                    .foregroundStyle(LMTheme.accent)
                            }
                        }
                        .padding(LMTheme.paddingMD)
                        .glassCard(padding: 0, cornerRadius: 16)
                    }
                    .buttonStyle(.plain)
                }

                if let error = serverVM.modelManagementError {
                    runtimeSupportBanner("Runtime controls unavailable: \(error)")
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, LMTheme.paddingLG)
            .padding(.top, LMTheme.paddingSM)
            .padding(.bottom, LMTheme.paddingXL)
            .opacity(revealContent ? 1 : 0)
            .offset(y: revealContent ? 0 : 8)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
    }

    private func runtimeModelRow(_ model: ServerModel) -> some View {
        let isBusy = serverVM.isModelOperationInProgress(for: model.key)
        let isLoaded = model.isLoaded
        let selectedRuntimeKey = selectedRuntimeModelKey()
        let isSelected = isLoaded && selectedRuntimeKey == model.key
        let linkedModel = matchedAvailableModel(for: model)

        return HStack(spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? LMTheme.accentMuted : LMTheme.surfaceSecondary.opacity(0.86))
                        .frame(width: 38, height: 38)

                    Image(systemName: model.type.lowercased().contains("embedding") ? "waveform.path.ecg" : "cpu")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSelected ? LMTheme.accent : LMTheme.textTertiary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.displayName)
                        .font(.body.weight(.semibold))
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
                dismiss()
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
                    .font(.system(size: 21))
                    .foregroundStyle(LMTheme.accent)
            }
        }
        .padding(LMTheme.paddingMD)
        .glassCard(padding: 0, cornerRadius: 16)
    }

    private func runtimeSupportBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(LMTheme.warning)
            Text(message)
                .font(.caption)
                .foregroundStyle(LMTheme.textSecondary)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, LMTheme.paddingMD)
        .padding(.vertical, LMTheme.paddingSM)
        .background(LMTheme.warning.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(LMTheme.warning.opacity(0.28), lineWidth: 1)
        )
    }

    private func refreshAllModels() async {
        await serverVM.refreshServerModels()
        await serverVM.fetchModels()
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
        let normalized = normalizedModelKey(raw)
        guard !normalized.isEmpty else { return [] }

        var tokens: Set<String> = [normalized]

        if normalized.contains("/") {
            let tail = normalized.split(separator: "/").last.map(String.init) ?? normalized
            tokens.insert(tail)
        }

        return tokens
    }
}
