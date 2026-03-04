import Foundation

@MainActor
final class PersistenceService {
    static let shared = PersistenceService()

    private let defaults = UserDefaults.standard

    private init() {}

    private enum Keys {
        static let servers = "lmgo_servers"
        static let conversations = "lmgo_conversations"
        static let activeServerId = "lmgo_active_server_id"
        static let selectedModelId = "lmgo_selected_model_id"
        static let localModels = "lmgo_local_models"
        static let huggingFaceToken = "lmgo_hugging_face_token"
    }

    // MARK: - Servers

    func saveServers(_ servers: [ServerConfig]) {
        if let data = try? JSONEncoder().encode(servers) {
            defaults.set(data, forKey: Keys.servers)
        }
    }

    func loadServers() -> [ServerConfig] {
        guard let data = defaults.data(forKey: Keys.servers),
              let servers = try? JSONDecoder().decode([ServerConfig].self, from: data) else {
            return []
        }
        return servers
    }

    func saveActiveServerId(_ id: UUID?) {
        defaults.set(id?.uuidString, forKey: Keys.activeServerId)
    }

    func loadActiveServerId() -> UUID? {
        guard let string = defaults.string(forKey: Keys.activeServerId) else { return nil }
        return UUID(uuidString: string)
    }

    // MARK: - Conversations

    func saveConversations(_ conversations: [Conversation]) {
        if let data = try? JSONEncoder().encode(conversations) {
            defaults.set(data, forKey: Keys.conversations)
        }
    }

    func loadConversations() -> [Conversation] {
        guard let data = defaults.data(forKey: Keys.conversations),
              let conversations = try? JSONDecoder().decode([Conversation].self, from: data) else {
            return []
        }
        return conversations
    }

    // MARK: - Selected Model

    func saveSelectedModelId(_ id: String?) {
        defaults.set(id, forKey: Keys.selectedModelId)
    }

    func loadSelectedModelId() -> String? {
        defaults.string(forKey: Keys.selectedModelId)
    }

    // MARK: - Local Models

    func saveLocalModels(_ models: [LocalModelRecord]) {
        if let data = try? JSONEncoder().encode(models) {
            defaults.set(data, forKey: Keys.localModels)
        }
    }

    func loadLocalModels() -> [LocalModelRecord] {
        guard let data = defaults.data(forKey: Keys.localModels),
              let models = try? JSONDecoder().decode([LocalModelRecord].self, from: data) else {
            return []
        }
        return models
    }

    // MARK: - Hugging Face

    func saveHuggingFaceToken(_ token: String) {
        defaults.set(token, forKey: Keys.huggingFaceToken)
    }

    func loadHuggingFaceToken() -> String {
        defaults.string(forKey: Keys.huggingFaceToken) ?? ""
    }
}
