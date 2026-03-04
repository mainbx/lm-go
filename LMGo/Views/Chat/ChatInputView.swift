import SwiftUI

struct ChatInputView: View {
    @Binding var text: String
    let isStreaming: Bool
    let canSend: Bool
    let onSend: () -> Void
    let onStop: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message LM Go...", text: $text, axis: .vertical)
                .lineLimit(1...8)
                .font(.body)
                .foregroundStyle(LMTheme.textPrimary)
                .focused($isFocused)
                .tint(LMTheme.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(LMTheme.inputBackground.opacity(0.96))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            isFocused ? LMTheme.accent.opacity(0.45) : LMTheme.border,
                            lineWidth: 1
                        )
                )
                .submitLabel(.send)
                .onSubmit {
                    if canSend { onSend() }
                }

            if isFocused {
                Button {
                    isFocused = false
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(LMTheme.textSecondary)
                        .frame(width: 40, height: 40)
                        .background(LMTheme.surfaceTertiary.opacity(0.88))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(LMTheme.borderLight, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .accessibilityLabel("Dismiss keyboard")
            }

            Button {
                if isStreaming {
                    onStop()
                } else if canSend {
                    onSend()
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(buttonFill)
                        .frame(width: 44, height: 44)

                    Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                        .font(.system(size: isStreaming ? 14 : 17, weight: .bold))
                        .foregroundStyle(buttonIconColor)
                }
                .scaleEffect(isStreaming ? 0.95 : canSend ? 1 : 0.94)
                .animation(.spring(response: 0.24, dampingFraction: 0.8), value: isStreaming)
                .animation(.spring(response: 0.24, dampingFraction: 0.8), value: canSend)
            }
            .buttonStyle(.plain)
            .disabled(!canSend && !isStreaming)
            .accessibilityLabel(isStreaming ? "Stop generating" : "Send message")
        }
        .padding(8)
        .glassCard(padding: 0, cornerRadius: 22)
        .padding(.horizontal, LMTheme.paddingMD)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .animation(.easeOut(duration: 0.16), value: isFocused)
        .onChange(of: isStreaming) { _, isStreamingNow in
            if isStreamingNow {
                isFocused = false
            }
        }
    }

    private var buttonFill: some ShapeStyle {
        if isStreaming {
            return AnyShapeStyle(LMTheme.error)
        } else if canSend {
            return AnyShapeStyle(LMTheme.accentGradient)
        } else {
            return AnyShapeStyle(LMTheme.surfaceTertiary)
        }
    }

    private var buttonIconColor: Color {
        (isStreaming || canSend) ? .white : LMTheme.textTertiary
    }
}
