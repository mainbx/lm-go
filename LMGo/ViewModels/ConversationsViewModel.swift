import Foundation

@MainActor
final class ConversationsViewModel: ObservableObject {
    @Published var conversations: [Conversation] = []

    private let persistence = PersistenceService.shared

    init() {
        loadConversations()
    }

    func loadConversations() {
        conversations = persistence.loadConversations()
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func deleteConversation(_ conversation: Conversation) {
        conversations.removeAll { $0.id == conversation.id }
        persistence.saveConversations(conversations)
    }

    func deleteConversations(at offsets: IndexSet) {
        conversations.remove(atOffsets: offsets)
        persistence.saveConversations(conversations)
    }

    func refresh() {
        loadConversations()
    }
}
