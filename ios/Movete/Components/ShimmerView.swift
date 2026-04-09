import SwiftUI

struct ShimmerView: View {
    var width: CGFloat? = nil
    var height: CGFloat = 16
    var radius: CGFloat = MV.Radius.sm

    @State private var phase: CGFloat = 0

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(MV.Colors.surfaceElevated)
            .frame(width: width, height: height)
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [
                            .clear,
                            Color.white.opacity(0.08),
                            .clear,
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: -geo.size.width * 0.3 + phase * geo.size.width * 1.6)
                }
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            )
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

/// Skeleton loading per una riga partenza
struct DepartureRowSkeleton: View {
    var body: some View {
        HStack(spacing: MV.Spacing.sm) {
            ShimmerView(width: 40, height: 28, radius: MV.Radius.sm)
            VStack(alignment: .leading, spacing: 6) {
                ShimmerView(width: 140, height: 14)
                ShimmerView(width: 80, height: 12)
            }
            Spacer()
            ShimmerView(width: 48, height: 24, radius: MV.Radius.sm)
        }
        .padding(.horizontal, MV.Spacing.md)
        .padding(.vertical, MV.Spacing.sm)
    }
}

#Preview {
    VStack(spacing: 0) {
        DepartureRowSkeleton()
        DepartureRowSkeleton()
        DepartureRowSkeleton()
    }
    .background(MV.Colors.background)
}
