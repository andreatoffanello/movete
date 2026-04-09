import SwiftUI

struct GlassCard<Content: View>: View {
    var radius: CGFloat = MV.Radius.lg
    var padding: CGFloat = MV.Spacing.md
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(MV.Colors.border, lineWidth: 0.5)
            )
            .mvSubtleShadow()
    }
}

#Preview {
    ZStack {
        MV.Colors.background.ignoresSafeArea()

        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Fermata Colosseo")
                    .font(MV.Type.subheadline)
                    .foregroundStyle(MV.Colors.textPrimary)
                Text("3 min")
                    .font(MV.Type.monoLarge)
                    .foregroundStyle(MV.Colors.live)
            }
        }
    }
}
