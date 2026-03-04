import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int, String)
    case decodingError(Error)
    case networkError(Error)
    case serverUnreachable
    case noActiveServer

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code, let message):
            return "HTTP \(code): \(message)"
        case .decodingError(let error):
            return "Failed to parse response: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .serverUnreachable:
            return "Server is unreachable. Check your connection."
        case .noActiveServer:
            return "No active server configured"
        }
    }
}

actor APIService {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    // MARK: - Models

    func fetchModels(server: ServerConfig) async throws -> [LMModel] {
        let url = try buildURL(server: server, path: "/v1/models")
        var request = URLRequest(url: url)
        applyHeaders(to: &request, server: server)

        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)

        let modelsResponse = try JSONDecoder().decode(ModelsResponse.self, from: data)
        return modelsResponse.data
    }

    func fetchServerModels(server: ServerConfig) async throws -> [ServerModel] {
        let url = try buildURL(server: server, path: "/api/v1/models")
        var request = URLRequest(url: url)
        applyHeaders(to: &request, server: server)

        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)
        let decoder = JSONDecoder()
        var lastError: Error?

        do {
            return try decoder.decode([ServerModel].self, from: data)
        } catch {
            lastError = error
        }

        do {
            return try decoder.decode(ServerModelsResponse.self, from: data).models
        } catch {
            lastError = error
        }

        do {
            return try decoder.decode(ServerModelsDataResponse.self, from: data).data
        } catch {
            lastError = error
        }

        throw APIError.decodingError(lastError ?? APIError.invalidResponse)
    }

    func loadModel(
        server: ServerConfig,
        modelKey: String,
        identifier: String? = nil
    ) async throws -> LoadModelResponse {
        let url = try buildURL(server: server, path: "/api/v1/models/load")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyHeaders(to: &request, server: server)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        request.httpBody = try JSONEncoder().encode(
            LoadModelRequest(model: modelKey, identifier: identifier)
        )

        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)

        if data.isEmpty {
            return LoadModelResponse(status: nil, message: nil, instanceId: nil)
        }

        return (try? JSONDecoder().decode(LoadModelResponse.self, from: data))
            ?? LoadModelResponse(status: nil, message: nil, instanceId: nil)
    }

    func unloadModel(
        server: ServerConfig,
        identifier: String
    ) async throws {
        let url = try buildURL(server: server, path: "/api/v1/models/unload")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyHeaders(to: &request, server: server)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        request.httpBody = try JSONEncoder().encode(
            UnloadModelRequest(instanceId: identifier)
        )

        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)
    }

    // MARK: - Chat Completions (Non-Streaming)

    func chatCompletion(
        server: ServerConfig,
        model: String,
        messages: [Message]
    ) async throws -> String {
        let url = try buildURL(server: server, path: "/v1/chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyHeaders(to: &request, server: server)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ChatCompletionRequest(
            model: model,
            messages: messages.map { ChatMessage(role: $0.role.rawValue, content: $0.content) },
            stream: false
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)

        let completionResponse = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        return completionResponse.choices.first?.message.content ?? ""
    }

    // MARK: - Embeddings

    func createEmbedding(
        server: ServerConfig,
        model: String,
        input: String
    ) async throws -> EmbeddingsResponse {
        let url = try buildURL(server: server, path: "/v1/embeddings")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyHeaders(to: &request, server: server)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = EmbeddingsRequest(model: model, input: input)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)

        return try JSONDecoder().decode(EmbeddingsResponse.self, from: data)
    }

    // MARK: - Server Health Check

    func checkServerHealth(server: ServerConfig, timeout: TimeInterval = 5) async -> Bool {
        do {
            let url = try buildURL(server: server, path: "/v1/models")
            var request = URLRequest(url: url)
            request.timeoutInterval = timeout
            applyHeaders(to: &request, server: server)

            let (_, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                return (200...299).contains(httpResponse.statusCode)
            }
            return false
        } catch {
            return false
        }
    }

    // MARK: - Helpers

    private func buildURL(server: ServerConfig, path: String) throws -> URL {
        guard let url = URL(string: server.baseURL + path) else {
            throw APIError.invalidURL
        }
        return url
    }

    private func applyHeaders(to request: inout URLRequest, server: ServerConfig) {
        if !server.apiKey.isEmpty {
            request.setValue("Bearer \(server.apiKey)", forHTTPHeaderField: "Authorization")
        }
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError where error.code == .cannotConnectToHost ||
            error.code == .timedOut ||
            error.code == .networkConnectionLost {
            throw APIError.serverUnreachable
        } catch {
            throw APIError.networkError(error)
        }
    }

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.httpError(httpResponse.statusCode, message)
        }
    }
}

// MARK: - Request/Response Types

struct ChatCompletionRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool
    var temperature: Double?
    var maxTokens: Int?

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, temperature
        case maxTokens = "max_tokens"
    }
}

struct ServerModelsResponse: Decodable {
    let models: [ServerModel]
}

struct ServerModelsDataResponse: Decodable {
    let data: [ServerModel]
}

struct ServerModel: Identifiable, Decodable, Hashable {
    let type: String
    let publisher: String?
    let displayNameValue: String?
    let modelName: String?
    let key: String
    let path: String?
    let loadedInstances: [LoadedModelInstance]?
    let maxContextLength: Int?

    enum CodingKeys: String, CodingKey {
        case type
        case publisher
        case displayName = "display_name"
        case name
        case modelName = "model_name"
        case key
        case modelKey = "model_key"
        case id
        case path
        case loadedInstances = "loaded_instances"
        case maxContextLength = "max_context_length"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        type = try container.decodeIfPresent(String.self, forKey: .type) ?? "llm"
        publisher = try container.decodeIfPresent(String.self, forKey: .publisher)
        displayNameValue = try container.decodeIfPresent(String.self, forKey: .displayName)
        modelName =
            try container.decodeIfPresent(String.self, forKey: .modelName)
            ?? (try container.decodeIfPresent(String.self, forKey: .name))

        if let keyValue = try container.decodeIfPresent(String.self, forKey: .key)
            ?? (try container.decodeIfPresent(String.self, forKey: .modelKey))
            ?? (try container.decodeIfPresent(String.self, forKey: .id)) {
            key = keyValue
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.key,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Server model payload missing key/model_key"
                )
            )
        }

        path = try container.decodeIfPresent(String.self, forKey: .path)
        loadedInstances = try container.decodeIfPresent([LoadedModelInstance].self, forKey: .loadedInstances)
        maxContextLength = try container.decodeIfPresent(Int.self, forKey: .maxContextLength)
    }

    var id: String { key }

    var displayName: String {
        if let displayNameValue, !displayNameValue.isEmpty {
            return displayNameValue
        }
        if let modelName, !modelName.isEmpty {
            return modelName
        }
        let parts = key.split(separator: "/")
        if parts.count > 1 {
            return String(parts.last ?? Substring(key))
        }
        return key
    }

    var loadedInstanceCount: Int {
        loadedInstances?.count ?? 0
    }

    var isLoaded: Bool {
        loadedInstanceCount > 0
    }

    var normalizedType: String {
        let lowered = type.lowercased()
        if lowered == "llm" {
            return "LLM"
        }
        if lowered == "embedding" {
            return "Embedding"
        }
        return type.capitalized
    }
}

struct LoadedModelInstance: Decodable, Hashable {
    let instanceId: String
    let state: String?
    let maxContextLength: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case identifier
        case instanceId = "instance_id"
        case state
        case maxContextLength = "max_context_length"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try container.decodeIfPresent(String.self, forKey: .instanceId)
            ?? (try container.decodeIfPresent(String.self, forKey: .identifier))
            ?? (try container.decodeIfPresent(String.self, forKey: .id)) {
            instanceId = value
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.instanceId,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Loaded model payload missing id/identifier/instance_id"
                )
            )
        }
        state = try container.decodeIfPresent(String.self, forKey: .state)
        maxContextLength = try container.decodeIfPresent(Int.self, forKey: .maxContextLength)
    }
}

private struct LoadModelRequest: Codable {
    let model: String
    let identifier: String?
}

struct LoadModelResponse: Decodable {
    let status: String?
    let message: String?
    let instanceId: String?

    enum CodingKeys: String, CodingKey {
        case status
        case message
        case instanceId = "instance_id"
    }
}

private struct UnloadModelRequest: Codable {
    let instanceId: String

    enum CodingKeys: String, CodingKey {
        case instanceId = "instance_id"
    }
}

private struct EmbeddingsRequest: Codable {
    let model: String
    let input: String
}

struct EmbeddingsResponse: Decodable {
    let object: String?
    let data: [EmbeddingDataPoint]
    let model: String?
    let usage: EmbeddingsUsage?
}

struct EmbeddingDataPoint: Decodable {
    let object: String?
    let index: Int?
    let embedding: [Double]
}

struct EmbeddingsUsage: Decodable {
    let promptTokens: Int?
    let totalTokens: Int?

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case totalTokens = "total_tokens"
    }
}

struct ChatMessage: Codable {
    let role: String
    let content: String
}

struct ChatCompletionResponse: Codable {
    let choices: [Choice]
    let usage: Usage?

    struct Choice: Codable {
        let message: ChatMessage
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }

    struct Usage: Codable {
        let promptTokens: Int?
        let completionTokens: Int?
        let totalTokens: Int?

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }
}
