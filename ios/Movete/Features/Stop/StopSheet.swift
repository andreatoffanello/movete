import SwiftUI

struct StopSheet: View {
    @Environment(AppState.self) private var appState
    let stop: Stop

    @State private var departures: [Departure] = []
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, MV.Spacing.md + 4)
                    .padding(.top, MV.Spacing.sm)
                    .padding(.bottom, MV.Spacing.md)

                if isLoading {
                    VStack(spacing: 0) {
                        ForEach(0..<5, id: \.self) { _ in
                            DepartureRowSkeleton()
                        }
                    }
                } else if departures.isEmpty {
                    emptyState
                } else {
                    departuresList
                }
            }
            .padding(.bottom, MV.Spacing.xxl)
        }
        .task {
            await loadDepartures()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: MV.Spacing.xxs) {
                Text(stop.name)
                    .font(MV.Typography.headline)
                    .foregroundStyle(MV.Colors.textPrimary)

                if let lines = stop.lines, !lines.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(lines.prefix(8), id: \.self) { line in
                            let route = appState.dataProvider.routeByName[line]
                            LineBadge(
                                name: line,
                                color: route.map { Color(hex: $0.color) } ?? MV.Colors.bus,
                                textColor: route.map { Color(hex: $0.textColor) } ?? .white,
                                size: .small
                            )
                        }
                        if lines.count > 8 {
                            Text("+\(lines.count - 8)")
                                .font(MV.Typography.captionMedium)
                                .foregroundStyle(MV.Colors.textTertiary)
                        }
                    }
                }
            }

            Spacer()

            // Favorite button
            Button {
                appState.favoritesStore.toggle(stop.id)
                if appState.favoritesStore.isFavorite(stop.id) {
                    Haptics.success()
                } else {
                    Haptics.light()
                }
            } label: {
                Image(systemName: appState.favoritesStore.isFavorite(stop.id) ? "star.fill" : "star")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(
                        appState.favoritesStore.isFavorite(stop.id)
                        ? MV.Colors.accent
                        : MV.Colors.textTertiary
                    )
                    .contentTransition(.symbolEffect(.replace))
            }
        }
    }

    // MARK: - Departures list

    private var departuresList: some View {
        LazyVStack(spacing: 0) {
            ForEach(nextDepartures()) { dep in
                DepartureRow(departure: dep)
                    .padding(.horizontal, MV.Spacing.md + 4)

                if dep.id != nextDepartures().last?.id {
                    Divider()
                        .foregroundStyle(MV.Colors.borderSubtle)
                        .padding(.leading, MV.Spacing.md + 4 + 44)
                }
            }
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: MV.Spacing.sm) {
            Image(systemName: "clock")
                .font(.system(size: 28))
                .foregroundStyle(MV.Colors.textTertiary)
            Text("Nessuna partenza oggi")
                .font(MV.Typography.callout)
                .foregroundStyle(MV.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, MV.Spacing.xl)
    }

    // MARK: - Data

    private func loadDepartures() async {
        isLoading = true
        guard let schedule = await appState.dataProvider.loadStopSchedule(stopId: stop.id) else {
            isLoading = false
            return
        }
        let dayIndex = (Calendar.current.component(.weekday, from: Date()) + 5) % 7 // 0=Mon
        departures = appState.dataProvider.resolveDepartures(from: schedule, forDayIndex: dayIndex)
        isLoading = false
    }

    /// Filter to next departures from current time
    private func nextDepartures() -> [Departure] {
        let cal = Calendar.current
        let now = cal.component(.hour, from: Date()) * 60 + cal.component(.minute, from: Date())
        return departures
            .filter { $0.minutes >= now }
            .prefix(20)
            .map { $0 }
    }
}
