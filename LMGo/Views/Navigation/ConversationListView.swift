import SwiftUI

// MARK: - Swipe-to-Delete Wrapper

private struct SwipeToDeleteCard<Content: View>: View {
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var showDelete = false
    @GestureState private var dragOffset: CGFloat = 0

    private let deleteThreshold: CGFloat = -70
    private let snapWidth: CGFloat = 80

    var body: some View {
        ZStack(alignment: .trailing) {
            // Delete background
            HStack(spacing: 0) {
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        onDelete()
                    }
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: snapWidth, height: .infinity)
                        .frame(maxHeight: .infinity)
                }
                .background(LMTheme.error)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 16,
                        topTrailingRadius: 16,
                        style: .continuous
                    )
                )
            }
            .opacity(effectiveOffset < 0 ? 1 : 0)

            // Main content
            content()
                .offset(x: effectiveOffset)
                .gesture(
                    DragGesture(minimumDistance: 16)
                        .updating($dragOffset) { value, state, _ in
                            // Only allow left swipe
                            if value.translation.width < 0 || offset < 0 {
                                state = value.translation.width
                            }
                        }
                        .onEnded { value in
                            let projected = value.predictedEndTranslation.width
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                if projected < -120 {
                                    // Fast swipe — full delete
                                    onDelete()
                                } else if (offset + value.translation.width) < deleteThreshold {
                                    // Snap open
                                    offset = -snapWidth
                                    showDelete = true
                                } else {
                                    // Snap closed
                                    offset = 0
                                    showDelete = false
                                }
                            }
                        }
                )
        }
        .clipped()
    }

    private var effectiveOffset: CGFloat {
        let raw = offset + dragOffset
        // Don't allow positive (right) swipe
        return min(0, raw)
    }
}

struct ConversationListView: View {
    @ObservedObject var conversationsVM: ConversationsViewModel
    @ObservedObject var chatVM: ChatViewModel
    @ObservedObject var serverVM: ServerViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showSettings = false
    @State private var revealContent = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: LMTheme.paddingLG) {
                    serverCard

                    if conversationsVM.conversations.isEmpty {
                        emptyView
                    } else {
                        conversationCards
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
            .background {
                LMTheme.appBackground.ignoresSafeArea()
            }
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: LMTheme.paddingSM)
            }
            .navigationTitle("Chats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(LMTheme.textSecondary)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        chatVM.newConversation()
                        dismiss()
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(LMTheme.accent)
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(serverVM: serverVM)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(30)
                    .presentationCompactAdaptation(.sheet)
            }
            .onAppear {
                conversationsVM.refresh()
                withAnimation(.easeOut(duration: 0.28)) {
                    revealContent = true
                }
            }
            .onDisappear {
                revealContent = false
            }
        }
    }

    // MARK: - Server Card

    private var serverCard: some View {
        HStack(spacing: LMTheme.paddingMD) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LMTheme.accentGradient)
                    .frame(width: 40, height: 40)

                Image(systemName: "server.rack")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(serverVM.isSelectedModelLocal ? "On Device" : (serverVM.activeServer?.name ?? "No Server"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LMTheme.textPrimary)

                HStack(spacing: 6) {
                    Circle()
                        .fill(
                            serverVM.isSelectedModelLocal
                                ? (serverVM.isSelectedLocalModelLoaded ? LMTheme.success : LMTheme.warning)
                                : (serverVM.isConnected ? LMTheme.success : LMTheme.error)
                        )
                        .frame(width: 7, height: 7)

                    Text(
                        serverVM.isSelectedModelLocal
                            ? "On-device local model"
                            : (serverVM.isConnected ? (serverVM.activeServer?.displayURL ?? "") : "Disconnected")
                    )
                        .font(.caption)
                        .foregroundStyle(LMTheme.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if let model = serverVM.selectedModel {
                Text(model.displayName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(LMTheme.accentLight)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(LMTheme.surfaceSecondary.opacity(0.85))
                    .clipShape(Capsule())
            }
        }
        .glassCard(cornerRadius: 18)
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: LMTheme.paddingLG) {
            Spacer().frame(height: 60)

            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 38))
                .foregroundStyle(LMTheme.textTertiary)

            Text("No Conversations Yet")
                .font(.headline.weight(.semibold))
                .foregroundStyle(LMTheme.textPrimary)

            Text("Start a new chat from the top-right button.")
                .font(.subheadline)
                .foregroundStyle(LMTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    // MARK: - Conversation Cards

    private var conversationCards: some View {
        LazyVStack(spacing: 10) {
            ForEach(conversationsVM.conversations) { conversation in
                let isSelected = chatVM.currentConversation?.id == conversation.id
                SwipeToDeleteCard {
                    deleteConversation(conversation)
                } content: {
                    Button {
                        chatVM.loadConversation(conversation)
                        dismiss()
                    } label: {
                        conversationRow(conversation, isSelected: isSelected)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            deleteConversation(conversation)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity.combined(with: .move(edge: .trailing))
                ))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: conversationsVM.conversations.map(\.id))
    }

    // MARK: - Delete

    private func deleteConversation(_ conversation: Conversation) {
        // If the deleted conversation is the currently active chat, clear it
        if chatVM.currentConversation?.id == conversation.id {
            chatVM.clearConversation()
        }

        withAnimation(.easeInOut(duration: 0.25)) {
            conversationsVM.deleteConversation(conversation)
        }
    }

    private func conversationRow(_ conversation: Conversation, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text(conversation.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(LMTheme.textPrimary)
                    .lineLimit(1)

                Spacer()

                Text(conversation.updatedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(LMTheme.textTertiary)
            }

            Text(conversation.preview)
                .font(.subheadline)
                .foregroundStyle(LMTheme.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            HStack(spacing: 8) {
                if let modelId = conversation.modelId {
                    Text(modelId.split(separator: "/").last.map(String.init) ?? modelId)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(LMTheme.accentLight)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(LMTheme.surfaceSecondary.opacity(0.85))
                        .clipShape(Capsule())
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isSelected ? LMTheme.accent : LMTheme.textTertiary)
            }
        }
        .padding(LMTheme.paddingMD)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected ? LMTheme.accentMuted.opacity(0.9) : LMTheme.surfacePrimary.opacity(0.84))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSelected ? LMTheme.accent.opacity(0.45) : LMTheme.borderLight, lineWidth: 1)
        )
    }
}
