import SwiftUI

// MARK: - Movete Design System — "Travertino"

enum MV {

    // MARK: - Colors

    enum Colors {
        // Backgrounds
        static let background       = Color(hex: "#0A0A0F")
        static let surface          = Color(hex: "#161620")
        static let surfaceElevated  = Color(hex: "#1E1E2A")
        static let border           = Color.white.opacity(0.06)
        static let borderSubtle     = Color.white.opacity(0.03)

        // Text
        static let textPrimary      = Color(hex: "#F5F5F0")
        static let textSecondary    = Color(hex: "#F5F5F0").opacity(0.55)
        static let textTertiary     = Color(hex: "#F5F5F0").opacity(0.30)

        // Accent — Ambra Romano
        static let accent           = Color(hex: "#E8A838")
        static let accentLight      = Color(hex: "#F0C060")
        static let accentSubtle     = Color(hex: "#E8A838").opacity(0.15)

        // Status
        static let live             = Color(hex: "#34D399")
        static let liveSubtle       = Color(hex: "#34D399").opacity(0.15)
        static let warning          = Color(hex: "#F59E0B")
        static let warningSubtle    = Color(hex: "#F59E0B").opacity(0.15)
        static let error            = Color(hex: "#EF4444")
        static let errorSubtle      = Color(hex: "#EF4444").opacity(0.15)

        // Transit modes
        static let bus              = Color(hex: "#3B82F6")
        static let tram             = Color(hex: "#F97316")
        static let metro            = Color(hex: "#22C55E")
        static let rail             = Color(hex: "#8B5CF6")

        static func transitColor(for type: TransitType) -> Color {
            switch type {
            case .bus:     return bus
            case .tram:    return tram
            case .metro:   return metro
            case .rail:    return rail
            case .ferry:   return Color(hex: "#06B6D4")
            case .unknown: return bus
            }
        }
    }

    // MARK: - Spacing (4px scale)

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs:  CGFloat = 8
        static let sm:  CGFloat = 12
        static let md:  CGFloat = 16
        static let lg:  CGFloat = 24
        static let xl:  CGFloat = 32
        static let xxl: CGFloat = 48
    }

    // MARK: - Corner Radius

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    // MARK: - Shadows

    struct Shadow {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }

    enum Shadows {
        static let card: [Shadow] = [
            Shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: 8),
            Shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2),
        ]
        static let elevated: [Shadow] = [
            Shadow(color: .black.opacity(0.5), radius: 24, x: 0, y: 12),
            Shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3),
        ]
        static let subtle: [Shadow] = [
            Shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4),
        ]
    }
}

// MARK: - View Modifiers

extension View {
    func mvCardShadow() -> some View {
        self.modifier(MVShadowModifier(shadows: MV.Shadows.card))
    }

    func mvElevatedShadow() -> some View {
        self.modifier(MVShadowModifier(shadows: MV.Shadows.elevated))
    }

    func mvSubtleShadow() -> some View {
        self.modifier(MVShadowModifier(shadows: MV.Shadows.subtle))
    }

    func mvCard() -> some View {
        self
            .background(MV.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: MV.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MV.Radius.lg, style: .continuous)
                    .stroke(MV.Colors.border, lineWidth: 1)
            )
            .mvCardShadow()
    }

    func mvSurface() -> some View {
        self
            .background(MV.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: MV.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MV.Radius.md, style: .continuous)
                    .stroke(MV.Colors.border, lineWidth: 0.5)
            )
    }
}

private struct MVShadowModifier: ViewModifier {
    let shadows: [MV.Shadow]

    func body(content: Content) -> some View {
        shadows.reduce(AnyView(content)) { view, shadow in
            AnyView(view.shadow(
                color: shadow.color,
                radius: shadow.radius,
                x: shadow.x,
                y: shadow.y
            ))
        }
    }
}

// MARK: - Color Hex Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
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
