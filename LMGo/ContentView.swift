import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("lmgo_bypass_server_setup") private var bypassServerSetup = false

    @StateObject private var serverVM = ServerViewModel()
    @StateObject private var chatVM = ChatViewModel()
    @StateObject private var conversationsVM = ConversationsViewModel()

    @State private var showSidebar = false
    @State private var showModelPicker = false

    var body: some View {
        ZStack {
            LMTheme.appBackground.ignoresSafeArea()

            if !serverVM.hasServers && !bypassServerSetup {
                ServerSetupView(
                    serverVM: serverVM,
                    isInitialSetup: true,
                    onSkipInitialSetup: {
                        bypassServerSetup = true
                    }
                )
            } else {
                mainContent
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.xSmall ... .accessibility3)
        .onAppear {
            chatVM.serverViewModel = serverVM
            serverVM.setConnectivityMonitoringActive(scenePhase == .active)
        }
        .onChange(of: scenePhase) { _, newPhase in
            serverVM.setConnectivityMonitoringActive(newPhase == .active)
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ChatView(chatVM: chatVM, serverVM: serverVM)
            .safeAreaInset(edge: .top, spacing: 0) {
                topBar
            }
            .sheet(isPresented: $showSidebar) {
                ConversationListView(
                    conversationsVM: conversationsVM,
                    chatVM: chatVM,
                    serverVM: serverVM
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(30)
                .presentationCompactAdaptation(.sheet)
                .onDisappear {
                    // Sync list in case a conversation was modified while sidebar was open
                    conversationsVM.refresh()
                }
            }
            .sheet(isPresented: $showModelPicker) {
                ModelPickerView(serverVM: serverVM)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(30)
                    .presentationCompactAdaptation(.sheet)
            }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: LMTheme.paddingSM) {
            chromeButton(icon: "sidebar.left") {
                chatVM.saveCurrentConversation()
                showSidebar = true
            }

            Button {
                showModelPicker = true
            } label: {
                let statusColor: Color = {
                    if serverVM.isSelectedModelLocal {
                        return serverVM.isSelectedLocalModelLoaded ? LMTheme.success : LMTheme.warning
                    }
                    return serverVM.isConnected ? LMTheme.success : LMTheme.error
                }()

                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)

                    Text(serverVM.selectedModel?.displayName ?? "Select Model")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(LMTheme.textPrimary)
                        .lineLimit(1)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(LMTheme.textTertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity)
                .background(LMTheme.surfaceTertiary.opacity(0.88))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(LMTheme.borderLight, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .animation(.spring(response: 0.28, dampingFraction: 0.9), value: serverVM.selectedModel?.id)

            chromeButton(icon: "square.and.pencil") {
                chatVM.newConversation()
            }
        }
        .padding(7)
        .glassCard(padding: 0, cornerRadius: 22)
        .padding(.horizontal, LMTheme.paddingMD)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private func chromeButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(LMTheme.textPrimary)
                .frame(width: 44, height: 44)
                .background(LMTheme.surfaceTertiary.opacity(0.88))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(LMTheme.borderLight, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
