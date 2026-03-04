import Foundation

/// Handles Server-Sent Events (SSE) streaming for chat completions
@MainActor
final class StreamingService: NSObject, URLSessionDataDelegate {
    private nonisolated(unsafe) var session: URLSession!
    private var dataTask: URLSessionDataTask?
    private var buffer = ""
    private var lastFinishReason: String?
    private var didEmitCompletion = false

    private var onToken: ((String) -> Void)?
    private var onComplete: ((StreamCompletion) -> Void)?
    private var onError: ((Error) -> Void)?

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }

    func streamChatCompletion(
        server: ServerConfig,
        model: String,
        messages: [Message],
        onToken: @escaping (String) -> Void,
        onComplete: @escaping (StreamCompletion) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        self.onToken = onToken
        self.onComplete = onComplete
        self.onError = onError
        self.buffer = ""
        self.lastFinishReason = nil
        self.didEmitCompletion = false

        guard let url = URL(string: server.baseURL + "/v1/chat/completions") else {
            onError(APIError.invalidURL)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        if !server.apiKey.isEmpty {
            request.setValue("Bearer \(server.apiKey)", forHTTPHeaderField: "Authorization")
        }

        let body = ChatCompletionRequest(
            model: model,
            messages: messages.map { ChatMessage(role: $0.role.rawValue, content: $0.content) },
            stream: true
        )

        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            onError(error)
            return
        }

        dataTask = session.dataTask(with: request)
        dataTask?.resume()
    }

    func cancel() {
        dataTask?.cancel()
        resetCallbacks()
    }

    // MARK: - URLSessionDataDelegate

    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        MainActor.assumeIsolated {
            buffer += text

            // Process complete SSE lines
            while let lineEnd = buffer.firstIndex(of: "\n") {
                let line = String(buffer[buffer.startIndex..<lineEnd])
                buffer = String(buffer[buffer.index(after: lineEnd)...])
                processSSELine(line)
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        MainActor.assumeIsolated {
            if let error = error {
                if (error as NSError).code == NSURLErrorCancelled { return }
                onError?(error)
                resetCallbacks()
            } else {
                emitCompletionIfNeeded()
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            MainActor.assumeIsolated {
                onError?(APIError.httpError(httpResponse.statusCode, "Stream request failed"))
            }
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    // MARK: - SSE Parsing

    private func processSSELine(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.hasPrefix("data: ") else { return }

        let jsonString = String(trimmed.dropFirst(6))

        if jsonString == "[DONE]" {
            emitCompletionIfNeeded()
            return
        }

        guard let data = jsonString.data(using: .utf8) else { return }

        do {
            let chunk = try JSONDecoder().decode(StreamChunk.self, from: data)
            if let finishReason = chunk.choices.first?.finishReason,
               !finishReason.isEmpty {
                lastFinishReason = finishReason
            }

            if let content = chunk.choices.first?.delta.content {
                onToken?(content)
            }
        } catch {
            // Skip malformed chunks silently
        }
    }

    private func emitCompletionIfNeeded() {
        guard !didEmitCompletion else { return }
        didEmitCompletion = true
        onComplete?(StreamCompletion(finishReason: lastFinishReason))
        resetCallbacks()
    }

    private func resetCallbacks() {
        dataTask = nil
        onToken = nil
        onComplete = nil
        onError = nil
    }
}

// MARK: - Stream Response Types

struct StreamChunk: Codable, Sendable {
    let choices: [StreamChoice]

    struct StreamChoice: Codable, Sendable {
        let delta: Delta
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }

    struct Delta: Codable, Sendable {
        let content: String?
        let role: String?
    }
}

struct StreamCompletion: Sendable {
    let finishReason: String?
}
