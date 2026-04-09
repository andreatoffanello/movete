import SwiftUI

/// Standalone countdown label for use in cards/widgets
struct CountdownLabel: View {
    let departureMinutes: Int
    let isLive: Bool
    @State private var now = Date()
    private let timer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    var body: some View {
        let mins = minutesRemaining

        Group {
            if mins <= 0 {
                Text("Ora")
                    .foregroundStyle(MV.Colors.warning)
            } else if mins <= 60 {
                HStack(spacing: 1) {
                    Text("\(mins)")
                        .foregroundStyle(mins <= 3 ? MV.Colors.warning : (isLive ? MV.Colors.live : MV.Colors.textPrimary))
                    Text("'")
                        .foregroundStyle(MV.Colors.textTertiary)
                }
            } else {
                let h = mins / 60
                let m = mins % 60
                Text(String(format: "%d:%02d", h, m))
                    .foregroundStyle(MV.Colors.textSecondary)
            }
        }
        .font(MV.Typography.mono)
        .onReceive(timer) { _ in now = Date() }
    }

    private var minutesRemaining: Int {
        let cal = Calendar.current
        let nowMinutes = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        return departureMinutes - nowMinutes
    }
}
