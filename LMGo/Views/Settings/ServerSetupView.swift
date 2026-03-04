import SwiftUI

struct ServerSetupView: View {
    @ObservedObject var serverVM: ServerViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = "LM Studio"
    @State private var host = ""
    @State private var port = "1234"
    @State private var apiKey = ""
    @State private var useTLS = false
    @State private var isTesting = false
    @State private var testResult: TestResult?
    @State private var revealContent = false

    var editingServer: ServerConfig?
    var isInitialSetup: Bool = false
    var onSkipInitialSetup: (() -> Void)? = nil

    enum TestResult {
        case success
        case failure(String)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: LMTheme.paddingXL) {
                    if isInitialSetup {
                        welcomeHeader
                    }

                    formSection

                    testConnectionButton

                    if isInitialSetup {
                        Button {
                            onSkipInitialSetup?()
                        } label: {
                            Text("Use On-Device Mode")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(LMTheme.textSecondary)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }

                    if let result = testResult {
                        testResultBanner(result)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                }
                .padding(.horizontal, LMTheme.paddingLG)
                .padding(.vertical, LMTheme.paddingLG)
                .opacity(revealContent ? 1 : 0)
                .offset(y: revealContent ? 0 : 8)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background {
                LMTheme.appBackground.ignoresSafeArea()
            }
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: LMTheme.paddingSM)
            }
            .navigationTitle(editingServer != nil ? "Edit Server" : "Add Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !isInitialSetup {
                        Button("Cancel") { dismiss() }
                            .foregroundStyle(LMTheme.textSecondary)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveServer() }
                        .foregroundStyle(LMTheme.accent)
                        .fontWeight(.semibold)
                        .disabled(host.isEmpty)
                }
            }
            .onAppear {
                if let server = editingServer {
                    name = server.name
                    host = server.host
                    port = String(server.port)
                    apiKey = server.apiKey
                    useTLS = server.useTLS
                }

                withAnimation(.easeOut(duration: 0.28)) {
                    revealContent = true
                }
            }
            .onDisappear {
                revealContent = false
            }
        }
    }

    // MARK: - Welcome Header

    private var welcomeHeader: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(LMTheme.meshGlow)
                    .frame(width: 140, height: 140)

                ZStack {
                    Circle()
                        .fill(LMTheme.accentGradient)
                        .frame(width: 56, height: 56)

                    Image(systemName: "server.rack")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.white)
                }
            }

            VStack(spacing: 8) {
                Text("Welcome to LM Go")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(LMTheme.textPrimary)

                Text("Connect to your LM Studio server\nor any OpenAI-compatible endpoint")
                    .font(.subheadline)
                    .foregroundStyle(LMTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.bottom, LMTheme.paddingSM)
    }

    // MARK: - Form

    private var formSection: some View {
        VStack(spacing: 0) {
            formRow(icon: "tag", title: "Name") {
                TextField("My Server", text: $name)
            }

            formDivider

            formRow(icon: "network", title: "Host") {
                TextField("192.168.1.100", text: $host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            }

            formDivider

            formRow(icon: "number", title: "Port") {
                TextField("1234", text: $port)
                    .keyboardType(.numberPad)
            }

            formDivider

            formRow(icon: "key", title: "API Key") {
                SecureField("Optional", text: $apiKey)
                    .textInputAutocapitalization(.never)
            }

            formDivider

            HStack {
                Image(systemName: "lock.shield")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(LMTheme.accent)
                    .frame(width: 24)

                Text("Use HTTPS")
                    .font(.body)
                    .foregroundStyle(LMTheme.textPrimary)

                Spacer()

                Toggle("", isOn: $useTLS)
                    .tint(LMTheme.accent)
                    .labelsHidden()
            }
            .padding(.horizontal, LMTheme.paddingLG)
            .padding(.vertical, LMTheme.paddingMD)
        }
        .glassCard(padding: 0, cornerRadius: 16)
    }

    private func formRow<Content: View>(
        icon: String,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(LMTheme.accent)
                .frame(width: 24)

            Text(title)
                .font(.body)
                .foregroundStyle(LMTheme.textSecondary)
                .frame(width: 60, alignment: .leading)

            content()
                .font(.body)
                .foregroundStyle(LMTheme.textPrimary)
                .tint(LMTheme.accent)
        }
        .padding(.horizontal, LMTheme.paddingLG)
        .padding(.vertical, LMTheme.paddingMD)
    }

    private var formDivider: some View {
        Rectangle()
            .fill(LMTheme.border)
            .frame(height: 1)
            .padding(.leading, 52)
    }

    // MARK: - Test Connection

    private var testConnectionButton: some View {
        Button {
            testConnection()
        } label: {
            HStack(spacing: 8) {
                if isTesting {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 15, weight: .medium))
                }
                Text(isTesting ? "Testing..." : "Test Connection")
                    .font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(LMTheme.accentGradient)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: LMTheme.radiusMD, style: .continuous))
            .shadow(color: Color.black.opacity(0.24), radius: 12, x: 0, y: 8)
        }
        .disabled(host.isEmpty || isTesting)
        .opacity(host.isEmpty ? 0.5 : 1)
    }

    private func testResultBanner(_ result: TestResult) -> some View {
        HStack(spacing: 10) {
            switch result {
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(LMTheme.success)
                Text("Connection successful!")
                    .foregroundStyle(LMTheme.success)
            case .failure(let error):
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(LMTheme.error)
                Text(error)
                    .foregroundStyle(LMTheme.error)
            }

            Spacer()
        }
        .font(.subheadline.weight(.medium))
        .padding(LMTheme.paddingLG)
        .background(
            RoundedRectangle(cornerRadius: LMTheme.radiusMD, style: .continuous)
                .fill((result.isSuccess ? LMTheme.success : LMTheme.error).opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: LMTheme.radiusMD, style: .continuous)
                .stroke((result.isSuccess ? LMTheme.success : LMTheme.error).opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Actions

    private func buildConfig() -> ServerConfig {
        ServerConfig(
            id: editingServer?.id ?? UUID(),
            name: name.isEmpty ? "LM Studio" : name,
            host: host,
            port: Int(port) ?? 1234,
            apiKey: apiKey,
            isActive: true,
            useTLS: useTLS
        )
    }

    private func testConnection() {
        isTesting = true
        testResult = nil

        Task {
            let config = buildConfig()
            let service = APIService()
            let healthy = await service.checkServerHealth(server: config)

            withAnimation(.easeOut(duration: 0.2)) {
                isTesting = false
                testResult = healthy ? .success : .failure("Cannot reach \(config.displayURL)")
            }
        }
    }

    private func saveServer() {
        let config = buildConfig()
        if editingServer != nil {
            serverVM.updateServer(config)
        } else {
            serverVM.addServer(config)
        }
        dismiss()
    }
}

extension ServerSetupView.TestResult {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
