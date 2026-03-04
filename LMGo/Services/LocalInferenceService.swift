import Foundation
import SwiftLlama

enum LocalInferenceError: LocalizedError {
    case modelNotLoaded
    case modelFileMissing

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "No local model loaded"
        case .modelFileMissing:
            return "Local model file is missing"
        }
    }
}

actor LocalInferenceService {
    static let shared = LocalInferenceService()

    private var service: LlamaService?
    private var loadedModelPath: String?

    private init() {}

    func loadModel(from modelURL: URL) async throws {
        let path = modelURL.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            throw LocalInferenceError.modelFileMissing
        }

        if loadedModelPath == path, service != nil {
            return
        }

        await unloadModel()

        let config = LlamaConfig(
            batchSize: 512,
            maxTokenCount: 512,
            useGPU: true
        )

        service = LlamaService(modelUrl: modelURL, config: config)
        loadedModelPath = path
    }

    func unloadModel() async {
        if let service {
            await service.stopCompletion()
        }
        service = nil
        loadedModelPath = nil
    }

    func stopCompletion() async {
        if let service {
            await service.stopCompletion()
        }
    }

    func isLoaded(modelURL: URL) -> Bool {
        loadedModelPath == modelURL.path(percentEncoded: false)
    }

    func streamCompletion(
        messages: [Message],
        onToken: @escaping @Sendable (String) async -> Void
    ) async throws {
        guard let service else {
            throw LocalInferenceError.modelNotLoaded
        }

        let llamaMessages = messages
            .filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map {
                LlamaChatMessage(
                    role: role(for: $0.role),
                    content: $0.content
                )
            }

        let sampling = LlamaSamplingConfig(
            temperature: 0.7,
            seed: UInt32.random(in: 1...UInt32.max),
            topP: 0.95,
            topK: 40
        )

        let stream = try await service.streamCompletion(of: llamaMessages, samplingConfig: sampling)

        for try await chunk in stream {
            await onToken(chunk)
        }
    }

    private func role(for role: Message.Role) -> LlamaChatMessage.Role {
        switch role {
        case .system:
            return .system
        case .user:
            return .user
        case .assistant:
            return .assistant
        }
    }
}
