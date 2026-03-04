import Foundation
import SwiftUI

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var currentConversation: Conversation?
    @Published var inputText = ""
    @Published var isStreaming = false
    @Published var streamingText = ""
    @Published var errorMessage: String?
    @Published private(set) var streamStartedAt: Date?

    private var streamingService: StreamingService?
    private var localStreamingTask: Task<Void, Never>?
    private let persistence = PersistenceService.shared
    private let maxAutoContinuationHops = 3
    private var userRequestedStop = false

    var serverViewModel: ServerViewModel?

    var messages: [Message] {
        currentConversation?.messages ?? []
    }

    var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isStreaming
            && (serverViewModel?.canSendWithSelectedModel ?? false)
    }

    // MARK: - Actions

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard let serverVM = serverViewModel,
              let model = serverVM.selectedModel else {
            errorMessage = "No server or model selected"
            return
        }

        let isLocalModel = serverVM.isLocalModel(model)
        if !isLocalModel, serverVM.activeServer == nil {
            errorMessage = "No server selected for remote model"
            return
        }

        let userMessage = Message(role: .user, content: text)
        inputText = ""
        errorMessage = nil

        if currentConversation == nil {
            currentConversation = Conversation(
                title: String(text.prefix(40)),
                modelId: model.id
            )
        }

        currentConversation?.messages.append(userMessage)
        currentConversation?.updatedAt = Date()

        userRequestedStop = false

        let requestMessages = currentConversation?.messages ?? []
        if isLocalModel {
            startLocalStreaming(
                requestMessages: requestMessages,
                resetOutput: true
            )
        } else if let server = serverVM.activeServer {
            startStreaming(
                server: server,
                model: model.id,
                requestMessages: requestMessages,
                resetOutput: true,
                continuationHop: 0
            )
        }
    }

    func stopStreaming() {
        userRequestedStop = true
        streamingService?.cancel()
        streamingService = nil
        localStreamingTask?.cancel()
        localStreamingTask = nil
        Task { await serverViewModel?.stopLocalCompletion() }

        finalizeStreaming(appendAssistantMessage: !streamingText.isEmpty)
    }

    func newConversation() {
        saveCurrentConversation()
        currentConversation = nil
        inputText = ""
        streamingText = ""
        isStreaming = false
        localStreamingTask?.cancel()
        localStreamingTask = nil
        errorMessage = nil
        streamStartedAt = nil
        userRequestedStop = false
    }

    func loadConversation(_ conversation: Conversation) {
        saveCurrentConversation()
        currentConversation = conversation
        inputText = ""
        streamingText = ""
        localStreamingTask?.cancel()
        localStreamingTask = nil
        errorMessage = nil
        streamStartedAt = nil
        userRequestedStop = false
    }

    func deleteMessage(at offsets: IndexSet) {
        currentConversation?.messages.remove(atOffsets: offsets)
        saveCurrentConversation()
    }

    // MARK: - Streaming

    private func startLocalStreaming(
        requestMessages: [Message],
        resetOutput: Bool
    ) {
        guard !requestMessages.isEmpty else {
            isStreaming = false
            streamStartedAt = nil
            return
        }

        isStreaming = true
        if resetOutput {
            streamingText = ""
            streamStartedAt = Date()
        }

        localStreamingTask?.cancel()
        localStreamingTask = Task { [weak self] in
            guard let self else { return }

            do {
                guard let serverViewModel = self.serverViewModel else {
                    throw LocalInferenceError.modelNotLoaded
                }

                try await serverViewModel.streamLocalCompletion(
                    messages: requestMessages,
                    onToken: { [weak self] token in
                        guard let self else { return }
                        Task { @MainActor in
                            self.streamingText += token
                        }
                    }
                )

                if Task.isCancelled || self.userRequestedStop {
                    return
                }

                self.finalizeStreaming(appendAssistantMessage: !self.streamingText.isEmpty)
            } catch {
                if Task.isCancelled || self.userRequestedStop {
                    return
                }
                self.errorMessage = error.localizedDescription
                self.finalizeStreaming(appendAssistantMessage: !self.streamingText.isEmpty)
            }
        }
    }

    private func startStreaming(
        server: ServerConfig,
        model: String,
        requestMessages: [Message],
        resetOutput: Bool,
        continuationHop: Int
    ) {
        isStreaming = true
        if resetOutput {
            streamingText = ""
            streamStartedAt = Date()
        }

        let service = StreamingService()
        self.streamingService = service

        guard !requestMessages.isEmpty else {
            isStreaming = false
            streamStartedAt = nil
            return
        }

        service.streamChatCompletion(
            server: server,
            model: model,
            messages: requestMessages,
            onToken: { [weak self] token in
                self?.streamingText += token
            },
            onComplete: { [weak self] completion in
                self?.handleStreamCompletion(
                    completion,
                    server: server,
                    model: model,
                    continuationHop: continuationHop
                )
            },
            onError: { [weak self] error in
                guard let self else { return }
                self.errorMessage = error.localizedDescription
                self.finalizeStreaming(appendAssistantMessage: !self.streamingText.isEmpty)
            }
        )
    }

    private func handleStreamCompletion(
        _ completion: StreamCompletion,
        server: ServerConfig,
        model: String,
        continuationHop: Int
    ) {
        guard !userRequestedStop else { return }

        if shouldAutoContinue(for: completion.finishReason),
           continuationHop < maxAutoContinuationHops,
           let conversationMessages = currentConversation?.messages,
           !streamingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let continuationMessages = makeContinuationRequestMessages(baseMessages: conversationMessages, partialAssistant: streamingText)
            startStreaming(
                server: server,
                model: model,
                requestMessages: continuationMessages,
                resetOutput: false,
                continuationHop: continuationHop + 1
            )
            return
        }

        finalizeStreaming(appendAssistantMessage: !streamingText.isEmpty)
    }

    private func shouldAutoContinue(for finishReason: String?) -> Bool {
        guard let reason = finishReason?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            !reason.isEmpty else {
            return false
        }

        let exactTruncationReasons: Set<String> = [
            "length",
            "max_tokens",
            "max_token",
            "token_limit",
            "max_output_tokens",
            "context_length_exceeded",
            "model_length",
        ]

        if exactTruncationReasons.contains(reason) {
            return true
        }

        return reason.contains("length")
            || reason.contains("max_token")
            || reason.contains("token_limit")
            || reason.contains("max_output")
    }

    private func makeContinuationRequestMessages(
        baseMessages: [Message],
        partialAssistant: String
    ) -> [Message] {
        var messages = baseMessages
        messages.append(Message(role: .assistant, content: partialAssistant))
        messages.append(
            Message(
                role: .user,
                content: "Continue exactly where you stopped. Do not repeat prior text. Keep the same format and tone."
            )
        )
        return messages
    }

    private func finalizeStreaming(appendAssistantMessage: Bool) {
        if appendAssistantMessage && !streamingText.isEmpty {
            let assistantMessage = makeAssistantMessage(from: streamingText)
            currentConversation?.messages.append(assistantMessage)
        }

        streamingText = ""
        isStreaming = false
        streamStartedAt = nil
        streamingService = nil
        localStreamingTask = nil
        saveCurrentConversation()

        // Auto-generate title from first exchange
        if currentConversation?.messages.count == 2,
           let firstMsg = currentConversation?.messages.first {
            currentConversation?.title = String(firstMsg.content.prefix(40))
        }
    }

    private func makeAssistantMessage(from content: String) -> Message {
        let parsed = Message.parseContent(content)
        let duration: TimeInterval?

        if parsed.hasThought, let startedAt = streamStartedAt {
            duration = max(0, Date().timeIntervalSince(startedAt))
        } else {
            duration = nil
        }

        return Message(
            role: .assistant,
            content: content,
            thoughtDuration: duration
        )
    }

    // MARK: - Persistence

    func saveCurrentConversation() {
        guard let conversation = currentConversation else { return }
        var conversations = persistence.loadConversations()

        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index] = conversation
        } else if !conversation.messages.isEmpty {
            conversations.insert(conversation, at: 0)
        }

        persistence.saveConversations(conversations)
    }
}
