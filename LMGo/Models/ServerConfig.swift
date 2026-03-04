import Foundation

struct ServerConfig: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var host: String
    var port: Int
    var apiKey: String
    var isActive: Bool
    var useTLS: Bool

    init(
        id: UUID = UUID(),
        name: String = "LM Studio",
        host: String = "localhost",
        port: Int = 1234,
        apiKey: String = "",
        isActive: Bool = true,
        useTLS: Bool = false
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.apiKey = apiKey
        self.isActive = isActive
        self.useTLS = useTLS
    }

    var baseURL: String {
        let scheme = useTLS ? "https" : "http"
        return "\(scheme)://\(host):\(port)"
    }

    var displayURL: String {
        "\(host):\(port)"
    }
}
