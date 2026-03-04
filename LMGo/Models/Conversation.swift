import Foundation

struct Conversation: Identifiable, Codable {
    let id: UUID
    var title: String
    var messages: [Message]
    let createdAt: Date
    var updatedAt: Date
    var modelId: String?

    init(
        id: UUID = UUID(),
        title: String = "New Chat",
        messages: [Message] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        modelId: String? = nil
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.modelId = modelId
    }

    var lastMessage: Message? {
        messages.last
    }

    var preview: String {
        lastMessage?.displayContent.prefix(80).description ?? "No messages yet"
    }
}
