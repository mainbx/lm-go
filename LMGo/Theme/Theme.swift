import SwiftUI

enum LMTheme {
    // MARK: - Colors

    static let background = Color(hex: "0C0E13")
    static let backgroundElevated = Color(hex: "131720")
    static let surfacePrimary = Color(hex: "181C25")
    static let surfaceSecondary = Color(hex: "222836")
    static let surfaceTertiary = Color(hex: "2B3344")

    static let accent = Color(hex: "3B82FF")
    static let accentLight = Color(hex: "75A9FF")
    static let accentMuted = Color(hex: "3B82FF").opacity(0.24)

    static let textPrimary = Color.white
    static let textSecondary = Color(hex: "CDD4E2")
    static let textTertiary = Color(hex: "8E97AB")

    static let border = Color.white.opacity(0.07)
    static let borderLight = Color.white.opacity(0.16)
    static let glassEdge = Color.white.opacity(0.2)
    static let glassShadow = Color.black.opacity(0.42)
    static let inputBackground = Color(hex: "1E2430")

    static let success = Color(hex: "2ED48C")
    static let error = Color(hex: "FF6F73")
    static let warning = Color(hex: "FFC066")

    static let userBubble = Color(hex: "3B82FF").opacity(0.8)
    static let assistantBubble = Color(hex: "1C222F").opacity(0.95)

    // MARK: - Gradients

    static let accentGradient = LinearGradient(
        colors: [Color(hex: "3B82FF"), Color(hex: "5E68FF")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let subtleGradient = LinearGradient(
        colors: [Color(hex: "70A6FF").opacity(0.24), Color(hex: "6E73FF").opacity(0.1)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let meshGlow = RadialGradient(
        colors: [Color(hex: "4A88FF").opacity(0.28), Color.clear],
        center: .center,
        startRadius: 0,
        endRadius: 260
    )

    static let backgroundGradient = LinearGradient(
        colors: [Color(hex: "0A0C11"), Color(hex: "11151E"), Color(hex: "0B0E14")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static var appBackground: some View {
        ZStack {
            backgroundGradient

            RadialGradient(
                colors: [Color(hex: "3B82FF").opacity(0.2), .clear],
                center: .topTrailing,
                startRadius: 30,
                endRadius: 360
            )

            RadialGradient(
                colors: [Color(hex: "5E68FF").opacity(0.14), .clear],
                center: .bottomTrailing,
                startRadius: 20,
                endRadius: 340
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
