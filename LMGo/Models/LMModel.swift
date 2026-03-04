import Foundation

struct LMModel: Identifiable, Codable, Hashable {
    let id: String
    let object: String?
    let ownedBy: String?

    enum CodingKeys: String, CodingKey {
        case id
        case object
        case ownedBy = "owned_by"
    }

    var displayName: String {
        // Clean up model IDs like "lmstudio-community/Meta-Llama-3-8B-Instruct-GGUF"
        let parts = id.split(separator: "/")
        if parts.count > 1 {
            return String(parts.last ?? Substring(id))
        }
        return id
    }
}

struct ModelsResponse: Codable {
    let data: [LMModel]
    let object: String?
}
