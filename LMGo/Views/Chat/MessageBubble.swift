import Foundation
import SwiftUI

struct MessageBubble: View {
    let message: Message
    var isStreaming: Bool = false

    private var isUser: Bool {
        message.role == .user
    }

    private var parsedContent: ParsedMessageContent {
        if isUser {
            return ParsedMessageContent(
                responseText: message.content.trimmingCharacters(in: .whitespacesAndNewlines),
                thoughtText: nil,
                hasOpenThoughtTag: false
            )
        }

        return message.parsedContent
    }

    private var thoughtInProgress: Bool {
        !isUser && (parsedContent.hasOpenThoughtTag || (isStreaming && parsedContent.hasThought && parsedContent.responseText.isEmpty))
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if isUser {
                Spacer(minLength: 52)
            } else {
                avatar
                    .padding(.bottom, 2)
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
                if !isUser, let thoughtText = parsedContent.thoughtText {
                    ReasoningBanner(
                        thoughtText: thoughtText,
                        duration: message.thoughtDuration,
                        isInProgress: thoughtInProgress
                    )
                }

                if !parsedContent.responseText.isEmpty {
                    Text(parsedContent.responseText)
                        .font(.body)
                        .foregroundStyle(isUser ? .white : LMTheme.textPrimary)
                        .textSelection(.enabled)
                        .lineSpacing(2)
                        .multilineTextAlignment(.leading)
                } else if thoughtInProgress && parsedContent.thoughtText == nil {
                    Text("Thinking…")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(LMTheme.textTertiary)
                }

                if isStreaming && !parsedContent.hasThought {
                    streamingCursor
                }

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(isUser ? .white.opacity(0.58) : LMTheme.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
            .background(bubbleBackground)
            .clipShape(bubbleShape)
            .overlay {
                bubbleShape
                    .stroke(
                        isUser ? LMTheme.accent.opacity(0.36) : LMTheme.glassEdge.opacity(0.72),
                        lineWidth: 1
                    )
            }
            .shadow(color: isUser ? Color.black.opacity(0.26) : .clear, radius: 10, x: 0, y: 5)

            if !isUser {
                Spacer(minLength: 52)
            }
        }
        .padding(.horizontal, LMTheme.paddingLG)
        .padding(.vertical, 2)
    }

    private var bubbleBackground: some ShapeStyle {
        if isUser {
            return AnyShapeStyle(LMTheme.accentGradient)
        }

        return AnyShapeStyle(LMTheme.assistantBubble)
    }

    private var bubbleShape: some Shape {
        UnevenRoundedRectangle(
            topLeadingRadius: isUser ? 18 : 8,
            bottomLeadingRadius: 18,
            bottomTrailingRadius: isUser ? 8 : 18,
            topTrailingRadius: 18,
            style: .continuous
        )
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(LMTheme.accentGradient)
                .frame(width: 30, height: 30)

            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private var streamingCursor: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(LMTheme.accent.opacity(0.82))
                    .frame(width: 5, height: 5)
                    .scaleEffect(isStreaming ? 1 : 0.65)
                    .animation(
                        .easeInOut(duration: 0.45)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.12),
                        value: isStreaming
                    )
            }
        }
    }
}

struct ReasoningBanner: View {
    let thoughtText: String
    let duration: TimeInterval?
    let isInProgress: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LMTheme.textTertiary.opacity(0.9))

                Text(titleText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LMTheme.textSecondary)

                Spacer()
            }

            if showsPreview {
                Text(slidingPreviewText)
                    .font(.caption)
                    .foregroundStyle(LMTheme.textTertiary)
                    .lineSpacing(2)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(LMTheme.surfaceSecondary.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(LMTheme.borderLight, lineWidth: 1)
        )
    }

    private var titleText: String {
        if isInProgress {
            return "Thinking..."
        }

        guard let duration else {
            return "Thought"
        }

        if duration < 60 {
            return String(format: "Thought for %.2f seconds", duration)
        }

        let totalSeconds = Int(duration.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "Thought for \(minutes) minutes \(seconds) seconds"
    }

    private var showsPreview: Bool {
        isInProgress && !normalizedThoughtText.isEmpty
    }

    private var slidingPreviewText: String {
        let text = normalizedThoughtText
        let maxChars = 220

        guard text.count > maxChars else { return text }

        let rawStart = text.index(text.endIndex, offsetBy: -maxChars)
        let suffix = text[rawStart...]
        let boundary = suffix.firstIndex(where: { $0 == " " || $0 == "\n" }) ?? rawStart
        let tail = String(text[boundary...]).trimmingCharacters(in: .whitespacesAndNewlines)

        return tail.isEmpty ? text : "…\(tail)"
    }

    private var normalizedThoughtText: String {
        thoughtText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: #"\n{2,}"#, with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
