import SwiftUI

struct ChatView: View {
    @ObservedObject var chatVM: ChatViewModel
    @ObservedObject var serverVM: ServerViewModel

    @State private var revealEmptyState = false

    var body: some View {
        ZStack {
            LMTheme.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                statusBar

                if chatVM.messages.isEmpty && !chatVM.isStreaming {
                    emptyState
                } else {
                    messagesList
                }

                if let error = chatVM.errorMessage {
                    errorBanner(error)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.horizontal, LMTheme.paddingLG)
                        .padding(.bottom, LMTheme.paddingSM)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ChatInputView(
                text: $chatVM.inputText,
                isStreaming: chatVM.isStreaming,
                canSend: chatVM.canSend,
                onSend: { chatVM.sendMessage() },
                onStop: { chatVM.stopStreaming() }
            )
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.9), value: chatVM.messages.count)
        .animation(.easeOut(duration: 0.2), value: chatVM.errorMessage != nil)
        .onAppear {
            withAnimation(.easeOut(duration: 0.45)) {
                revealEmptyState = true
            }
        }
    }

    // MARK: - Status

    private var statusBar: some View {
        let isLocal = serverVM.isSelectedModelLocal
        let statusColor: Color = {
            if isLocal {
                return serverVM.isSelectedLocalModelLoaded ? LMTheme.success : LMTheme.warning
            }
            return serverVM.isConnected ? LMTheme.success : LMTheme.error
        }()

        return HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(serverVM.selectedModelConnectionLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(LMTheme.textSecondary)

            if isLocal {
                Text(serverVM.selectedLocalModelSourceLabel)
                    .font(.caption2)
                    .foregroundStyle(LMTheme.textTertiary)
                    .lineLimit(1)
            } else if let host = serverVM.activeServer?.displayURL {
                Text(host)
                    .font(.caption2)
                    .foregroundStyle(LMTheme.textTertiary)
                    .lineLimit(1)
            }

            Spacer()

            if let model = serverVM.selectedModel {
                Text(model.displayName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(LMTheme.accentLight)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(LMTheme.surfaceTertiary.opacity(0.88))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, LMTheme.paddingMD)
        .padding(.vertical, 9)
        .glassCard(padding: 0, cornerRadius: 14)
        .padding(.horizontal, LMTheme.paddingLG)
        .padding(.top, LMTheme.paddingSM)
        .padding(.bottom, LMTheme.paddingXS)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: LMTheme.paddingXL) {
                Spacer(minLength: 56)

                ZStack {
                    Circle()
                        .fill(LMTheme.meshGlow)
                        .frame(width: 190, height: 190)

                    ZStack {
                        Circle()
                            .fill(LMTheme.accentGradient)
                            .frame(width: 72, height: 72)

                        Image(systemName: "sparkles")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }

                VStack(spacing: 8) {
                    Text("LM Go")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(LMTheme.textPrimary)

                    Text(serverVM.isSelectedModelLocal
                         ? "Ask anything. Running on-device."
                         : "Ask anything. Your server model is ready.")
                        .font(.subheadline)
                        .foregroundStyle(LMTheme.textSecondary)
                }

                if serverVM.shouldShowReconnectButton {
                    Button {
                        Task { await serverVM.connectToActiveServer() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Reconnect")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(LMTheme.accent)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(LMTheme.accentMuted)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                quickSuggestions
                    .padding(.top, 4)

                Spacer(minLength: 80)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, LMTheme.paddingLG)
            .opacity(revealEmptyState ? 1 : 0)
            .offset(y: revealEmptyState ? 0 : 14)
        }
        .scrollIndicators(.hidden)
    }

    private var quickSuggestions: some View {
        VStack(spacing: 10) {
            ForEach(suggestions, id: \.self) { text in
                Button {
                    chatVM.inputText = text
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(LMTheme.accentLight)

                        Text(text)
                            .font(.subheadline)
                            .foregroundStyle(LMTheme.textSecondary)
                            .lineLimit(1)

                        Spacer()
                    }
                    .padding(.horizontal, LMTheme.paddingMD)
                    .padding(.vertical, 12)
                    .glassCard(padding: 0, cornerRadius: 14)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var suggestions: [String] {
        [
            "Summarize this topic in plain language",
            "Help me draft a clear email",
            "Generate a small Swift utility",
            "Give me a step-by-step plan",
        ]
    }

    // MARK: - Messages List

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: LMTheme.paddingSM) {
                    ForEach(chatVM.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                            .transition(
                                .asymmetric(
                                    insertion: .move(edge: message.role == .user ? .trailing : .leading)
                                        .combined(with: .opacity),
                                    removal: .opacity
                                )
                            )
                    }

                    if chatVM.isStreaming && !chatVM.streamingText.isEmpty {
                        MessageBubble(
                            message: Message(role: .assistant, content: chatVM.streamingText),
                            isStreaming: true
                        )
                        .id("streaming")
                        .transition(.opacity)
                    }

                    Color.clear.frame(height: 6)
                }
                .padding(.top, LMTheme.paddingSM)
                .padding(.bottom, LMTheme.paddingSM)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
            .safeAreaPadding(.horizontal, LMTheme.paddingXS)
            .onChange(of: chatVM.messages.count) {
                scrollToBottom(using: proxy, animated: true)
            }
            .onChange(of: chatVM.streamingText) {
                guard !chatVM.streamingText.isEmpty else { return }
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo("streaming", anchor: .bottom)
                }
            }
        }
    }

    private func scrollToBottom(using proxy: ScrollViewProxy, animated: Bool) {
        guard let lastId = chatVM.messages.last?.id else { return }

        if animated {
            withAnimation(.easeOut(duration: 0.22)) {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(lastId, anchor: .bottom)
        }
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(LMTheme.error)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(LMTheme.textPrimary)
                .lineLimit(2)

            Spacer(minLength: 0)

            Button {
                chatVM.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LMTheme.textTertiary)
                    .frame(width: 24, height: 24)
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
                .stroke(LMTheme.error.opacity(0.4), lineWidth: 1)
        )
    }
}
