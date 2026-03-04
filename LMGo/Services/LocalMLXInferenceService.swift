import Foundation
import MLX
@preconcurrency import MLXLLM
@preconcurrency import MLXLMCommon

enum LocalMLXInferenceError: LocalizedError {
    case modelNotLoaded
    case invalidModelIdentifier

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "No MLX model loaded"
        case .invalidModelIdentifier:
            return "Invalid MLX model identifier"
        }
    }
}

struct LocalMLXMemoryStats: Sendable {
    let activeBytes: Int
    let cacheBytes: Int
    let peakBytes: Int
    let capturedAt: Date
}

actor LocalMLXInferenceService {
    static let shared = LocalMLXInferenceService()

    private var modelContainer: ModelContainer?
    private var loadedModelId: String?
    private var stopRequested = false

    private init() {}

    func loadModel(id rawModelID: String) async throws {
        let modelID = rawModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard modelID.split(separator: "/").count == 2 else {
            throw LocalMLXInferenceError.invalidModelIdentifier
        }

        if loadedModelId == modelID, modelContainer != nil {
            return
        }

        await unloadModel()
        stopRequested = false
        modelContainer = try await loadModelContainer(id: modelID)
        loadedModelId = modelID
    }

    func unloadModel() async {
        stopRequested = true
        modelContainer = nil
        loadedModelId = nil
        Memory.clearCache()
    }

    func memoryStats() -> LocalMLXMemoryStats {
        let snapshot = Memory.snapshot()
        return LocalMLXMemoryStats(
            activeBytes: snapshot.activeMemory,
            cacheBytes: snapshot.cacheMemory,
            peakBytes: snapshot.peakMemory,
            capturedAt: Date()
        )
    }

    func clearMemoryCache() -> LocalMLXMemoryStats {
        Memory.clearCache()
        return memoryStats()
    }

    func stopCompletion() async {
        stopRequested = true
    }

    func isLoaded(modelID: String) -> Bool {
        loadedModelId == modelID
    }

    func streamCompletion(
        messages: [Message],
        onToken: @escaping @Sendable (String) async -> Void
    ) async throws {
        guard let container = modelContainer else {
            throw LocalMLXInferenceError.modelNotLoaded
        }

        stopRequested = false

        let promptItems = messages
            .filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { ($0.role, $0.content) }

        let parameters = GenerateParameters(
            maxTokens: 1024,
            temperature: 0.7,
            topP: 0.95
        )

        let stream = try await container.perform { context in
            let chatMessages = promptItems.map { role, content in
                let mappedRole: Chat.Message.Role
                switch role {
                case .system:
                    mappedRole = .system
                case .user:
                    mappedRole = .user
                case .assistant:
                    mappedRole = .assistant
                }
                return Chat.Message(role: mappedRole, content: content)
            }
            let input = UserInput(chat: chatMessages)
            let lmInput = try await context.processor.prepare(input: input)
            return try MLXLMCommon.generate(
                input: lmInput,
                parameters: parameters,
                context: context
            )
        }

        for await generation in stream {
            if stopRequested || Task.isCancelled {
                break
            }

            guard let chunk = generation.chunk, !chunk.isEmpty else {
                continue
            }

            await onToken(chunk)
        }
    }
}
