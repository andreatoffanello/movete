import SwiftUI

struct LineBadge: View {
    let name: String
    let color: Color
    let textColor: Color?
    var size: Size = .regular

    enum Size {
        case small, regular, large

        var font: Font {
            switch self {
            case .small:   return MV.Type.caption.bold()
            case .regular: return MV.Type.badge
            case .large:   return MV.Type.badgeLarge
            }
        }

        var padding: EdgeInsets {
            switch self {
            case .small:   return EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6)
            case .regular: return EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
            case .large:   return EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
            }
        }

        var minWidth: CGFloat {
            switch self {
            case .small:   return 28
            case .regular: return 36
            case .large:   return 44
            }
        }
    }

    var body: some View {
        Text(name)
            .font(size.font)
            .foregroundStyle(resolvedTextColor)
            .padding(size.padding)
            .frame(minWidth: size.minWidth)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: MV.Radius.sm, style: .continuous))
    }

    /// Auto-detect text color for WCAG contrast if not specified
    private var resolvedTextColor: Color {
        if let textColor { return textColor }
        return color.luminance > 0.5 ? .black : .white
    }
}

// MARK: - Color Luminance (WCAG 2.1)

private extension Color {
    var luminance: Double {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)

        func linearize(_ c: CGFloat) -> Double {
            let v = Double(c)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
    }
}

#Preview {
    VStack(spacing: 12) {
        LineBadge(name: "64", color: MV.Colors.bus, textColor: nil)
        LineBadge(name: "19", color: MV.Colors.tram, textColor: nil)
        LineBadge(name: "MA", color: MV.Colors.metro, textColor: nil)
        LineBadge(name: "FL1", color: MV.Colors.rail, textColor: nil, size: .large)
        LineBadge(name: "H", color: .yellow, textColor: nil, size: .small)
    }
    .padding()
    .background(MV.Colors.background)
}
