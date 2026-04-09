import SwiftUI

struct LiveIndicator: View {
    var style: Style = .dot
    @State private var isPulsing = false

    enum Style {
        case dot       // Pallino pulsante
        case badge     // "LIVE" badge
    }

    var body: some View {
        switch style {
        case .dot:
            Circle()
                .fill(MV.Colors.live)
                .frame(width: 8, height: 8)
                .scaleEffect(isPulsing ? 1.3 : 1.0)
                .opacity(isPulsing ? 0.6 : 1.0)
                .onAppear {
                    withAnimation(.pulse) {
                        isPulsing = true
                    }
                }

        case .badge:
            HStack(spacing: 4) {
                Circle()
                    .fill(MV.Colors.live)
                    .frame(width: 6, height: 6)
                    .scaleEffect(isPulsing ? 1.3 : 1.0)
                    .opacity(isPulsing ? 0.6 : 1.0)

                Text("LIVE")
                    .font(MV.Typography.captionMedium)
                    .foregroundStyle(MV.Colors.live)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(MV.Colors.liveSubtle)
            .clipShape(Capsule())
            .onAppear {
                withAnimation(.pulse) {
                    isPulsing = true
                }
            }
        }
    }
}

#Preview {
    HStack(spacing: 20) {
        LiveIndicator(style: .dot)
        LiveIndicator(style: .badge)
    }
    .padding()
    .background(MV.Colors.background)
}
