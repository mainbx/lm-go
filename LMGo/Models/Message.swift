import Foundation

struct ParsedMessageContent: Sendable {
    let responseText: String
    let thoughtText: String?
    let hasOpenThoughtTag: Bool

    var hasThought: Bool {
        thoughtText != nil
    }
}

struct Message: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let role: Role
    var content: String
    let timestamp: Date
    var thoughtDuration: TimeInterval?

    enum Role: String, Codable, Sendable {
        case system
        case user
        case assistant
    }

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        timestamp: Date = Date(),
        thoughtDuration: TimeInterval? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.thoughtDuration = thoughtDuration
    }
}

extension Message {
    var parsedContent: ParsedMessageContent {
        Self.parseContent(content)
    }

    var displayContent: String {
        let parsed = parsedContent

        if !parsed.responseText.isEmpty {
            return parsed.responseText
        }

        if let thought = parsed.thoughtText, !thought.isEmpty {
            return "Thought: \(thought)"
        }

        return Self.normalize(content)
    }

    static func parseContent(_ raw: String) -> ParsedMessageContent {
        let source = normalizeLineBreaks(raw)
        let fullRange = NSRange(source.startIndex..<source.endIndex, in: source)

        let completeMatches = completeThinkRegex.matches(in: source, range: fullRange)
        var thoughtSections: [String] = []

        for match in completeMatches {
            guard let range = Range(match.range(at: 1), in: source) else { continue }
            let section = normalize(String(source[range]))
            if !section.isEmpty {
                thoughtSections.append(section)
            }
        }

        let responseBuffer = NSMutableString(string: source)
        for match in completeMatches.reversed() {
            responseBuffer.replaceCharacters(in: match.range, with: "")
        }

        var response = String(responseBuffer)
        var hasOpenThoughtTag = false

        let responseRange = NSRange(response.startIndex..<response.endIndex, in: response)
        if let openMatch = openThinkRegex.firstMatch(in: response, range: responseRange),
           let fullTagRange = Range(openMatch.range, in: response) {
            let thoughtTail = normalize(String(response[fullTagRange.upperBound...]))
            if !thoughtTail.isEmpty {
                thoughtSections.append(thoughtTail)
            }

            response = String(response[..<fullTagRange.lowerBound])
            hasOpenThoughtTag = true
        }

        let strippedResponse = NSMutableString(string: response)
        let strippedRange = NSRange(response.startIndex..<response.endIndex, in: response)
        closeThinkRegex.replaceMatches(in: strippedResponse, range: strippedRange, withTemplate: "")

        let finalResponse = normalize(String(strippedResponse))
        let finalThought = normalize(thoughtSections.joined(separator: "\n\n"))

        return ParsedMessageContent(
            responseText: finalResponse,
            thoughtText: finalThought.isEmpty ? nil : finalThought,
            hasOpenThoughtTag: hasOpenThoughtTag
        )
    }

    private static func normalize(_ text: String) -> String {
        normalizeLineBreaks(text)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeLineBreaks(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private static let completeThinkRegex = try! NSRegularExpression(
        pattern: #"(?is)<think\b[^>]*>(.*?)</think>"#
    )

    private static let openThinkRegex = try! NSRegularExpression(
        pattern: #"(?is)<think\b[^>]*>"#
    )

    private static let closeThinkRegex = try! NSRegularExpression(
        pattern: #"(?is)</think>"#
    )
}
