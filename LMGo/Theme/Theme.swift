import SwiftUI

enum LMTheme {
    // MARK: - Colors — ChatGPT-inspired neutral dark palette

    static let background = Color(hex: "212121")
    static let backgroundElevated = Color(hex: "171717")
    static let surfacePrimary = Color(hex: "2F2F2F")
    static let surfaceSecondary = Color(hex: "383838")
    static let surfaceTertiary = Color(hex: "424242")

    static let accent = Color(hex: "10A37F")
    static let accentLight = Color(hex: "5DD9B3")
    static let accentMuted = Color(hex: "10A37F").opacity(0.18)

    static let textPrimary = Color(hex: "ECECEC")
    static let textSecondary = Color(hex: "B4B4B4")
    static let textTertiary = Color(hex: "707070")

    static let border = Color.white.opacity(0.08)
    static let borderLight = Color.white.opacity(0.14)
    static let glassEdge = Color.white.opacity(0.12)
    static let glassShadow = Color.black.opacity(0.45)
    static let inputBackground = Color(hex: "2F2F2F")

    static let success = Color(hex: "10A37F")
    static let error = Color(hex: "EF4444")
    static let warning = Color(hex: "F59E0B")

    static let userBubble = Color(hex: "10A37F").opacity(0.85)
    static let assistantBubble = Color(hex: "2F2F2F").opacity(0.95)

    // MARK: - Gradients

    static let accentGradient = LinearGradient(
        colors: [Color(hex: "10A37F"), Color(hex: "0EA589")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let subtleGradient = LinearGradient(
        colors: [Color(hex: "10A37F").opacity(0.15), Color(hex: "0EA589").opacity(0.05)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let meshGlow = RadialGradient(
        colors: [Color(hex: "10A37F").opacity(0.18), Color.clear],
        center: .center,
        startRadius: 0,
        endRadius: 260
    )

    static let backgroundGradient = LinearGradient(
        colors: [Color(hex: "1A1A1A"), Color(hex: "212121"), Color(hex: "1E1E1E")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static var appBackground: some View {
        ZStack {
            Color(hex: "212121")

            RadialGradient(
                colors: [Color(hex: "10A37F").opacity(0.04), .clear],
                center: .topTrailing,
                startRadius: 30,
                endRadius: 400
            )
        }
    }

    // MARK: - Spacing

    static let paddingXS: CGFloat = 4
    static let paddingSM: CGFloat = 8
    static let paddingMD: CGFloat = 12
    static let paddingLG: CGFloat = 16
    static let paddingXL: CGFloat = 24
    static let paddingXXL: CGFloat = 32

    // MARK: - Corner Radius

    static let radiusSM: CGFloat = 10
    static let radiusMD: CGFloat = 14
    static let radiusLG: CGFloat = 18
    static let radiusXL: CGFloat = 22
    static let radiusFull: CGFloat = 100
}

// MARK: - Color Extension for Hex

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - View Modifiers

struct GlassCard: ViewModifier {
    var padding: CGFloat = LMTheme.paddingLG
    var cornerRadius: CGFloat = LMTheme.radiusLG

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .padding(padding)
            .background {
                shape
                    .fill(LMTheme.surfacePrimary.opacity(0.86))
                    .background(
                        shape.fill(.ultraThinMaterial.opacity(0.68))
                    )
            }
            .clipShape(shape)
            .overlay(
                shape.stroke(LMTheme.glassEdge, lineWidth: 1)
            )
            .overlay(
                shape
                    .stroke(LMTheme.border.opacity(0.7), lineWidth: 0.5)
            )
            .shadow(color: LMTheme.glassShadow, radius: 22, x: 0, y: 10)
    }
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(LMTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: LMTheme.radiusMD, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: LMTheme.radiusMD, style: .continuous)
                    .stroke(LMTheme.border, lineWidth: 1)
            )
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }

    func glassCard(
        padding: CGFloat = LMTheme.paddingLG,
        cornerRadius: CGFloat = LMTheme.radiusLG
    ) -> some View {
        modifier(GlassCard(padding: padding, cornerRadius: cornerRadius))
    }
}
