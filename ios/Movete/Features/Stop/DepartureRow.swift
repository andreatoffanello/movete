import SwiftUI

struct DepartureRow: View {
    let departure: Departure
    @State private var now = Date()
    private let timer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: MV.Spacing.sm) {
            // Line badge
            LineBadge(
                name: departure.lineName,
                color: Color(hex: departure.lineColor),
                textColor: Color(hex: departure.lineTextColor)
            )
            .frame(width: 44)

            // Headsign + transit type
            VStack(alignment: .leading, spacing: 2) {
                Text(departure.headsign)
                    .font(MV.Typography.calloutMedium)
                    .foregroundStyle(MV.Colors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    TransitIcon(type: departure.transitType, size: 11, weight: .medium)

                    if let dock = departure.dock {
                        Text("Banchina \(dock)")
                            .font(MV.Typography.caption)
                            .foregroundStyle(MV.Colors.textTertiary)
                    }
                }
            }

            Spacer()

            // Live indicator + countdown
            HStack(spacing: MV.Spacing.xs) {
                if departure.isLive {
                    LiveIndicator(style: .dot)
                }

                countdownView
            }
        }
        .padding(.vertical, MV.Spacing.sm)
        .onReceive(timer) { _ in now = Date() }
    }

    // MARK: - Countdown

    @ViewBuilder
    private var countdownView: some View {
        let mins = minutesUntilDeparture

        if mins < 0 {
            Text("Partito")
                .font(MV.Typography.monoSmall)
                .foregroundStyle(MV.Colors.textTertiary)
        } else if mins == 0 {
            Text("Ora")
                .font(MV.Typography.mono)
                .foregroundStyle(MV.Colors.warning)
        } else if mins <= 60 {
            HStack(spacing: 2) {
                Text("\(mins)")
                    .font(MV.Typography.monoLarge)
                    .foregroundStyle(mins <= 3 ? MV.Colors.warning : MV.Colors.live)
                Text("min")
                    .font(MV.Typography.monoSmall)
                    .foregroundStyle(MV.Colors.textSecondary)
            }
        } else {
            Text(departure.time)
                .font(MV.Typography.mono)
                .foregroundStyle(MV.Colors.textSecondary)
        }
    }

    private var minutesUntilDeparture: Int {
        let cal = Calendar.current
        let nowMinutes = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        var depMinutes = departure.minutes

        // Handle delay from RT
        if let delay = departure.delaySeconds {
            depMinutes += delay / 60
        }

        return depMinutes - nowMinutes
    }
}
