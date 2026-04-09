import SwiftUI

struct StopSheet: View {
    @Environment(AppState.self) private var appState
    let stop: Stop

    @State private var departures: [Departure] = []
    @State private var isLoading = true
    @State private var visibleCount = 15  // Incremental: start with 15, load more on scroll

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, MV.Spacing.md + 4)
                    .padding(.top, MV.Spacing.sm)
                    .padding(.bottom, MV.Spacing.md)

                if isLoading {
                    skeletonState
                } else if departures.isEmpty {
                    emptyState
                } else {
                    departuresList
                }
            }
            .padding(.bottom, MV.Spacing.xxl)
        }
        .task(id: stop.id) {
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
                    linesBadges(lines)
                }
            }

            Spacer()

            favoriteButton
        }
    }

    @ViewBuilder
    private func linesBadges(_ lines: [String]) -> some View {
        HStack(spacing: 4) {
            ForEach(lines.prefix(8), id: \.self) { line in
                let route = appState.dataProvider.routeByName[line]
                LineBadge(
                    name: line,
                    color: route.map { Color(hex: $0.color) } ?? MV.Colors.bus,
                    textColor: route.map { Color(hex: $0.textColor) } ?? .white,
                    size: .small
                )
                .onTapGesture {
                    if let route {
                        appState.navigate(to: .line(route))
                    }
                }
            }
            if lines.count > 8 {
                Text("+\(lines.count - 8)")
                    .font(MV.Typography.captionMedium)
                    .foregroundStyle(MV.Colors.textTertiary)
            }
        }
    }

    private var favoriteButton: some View {
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

    // MARK: - Departures list (lazy + incremental)

    private var departuresList: some View {
        LazyVStack(spacing: 0) {
            let visible = Array(departures.prefix(visibleCount))
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, dep in
                DepartureRow(departure: dep)
                    .padding(.horizontal, MV.Spacing.md + 4)

                if index < visible.count - 1 {
                    Divider()
                        .foregroundStyle(MV.Colors.borderSubtle)
                        .padding(.leading, MV.Spacing.md + 4 + 44)
                }
            }

            // "Load more" trigger — appears when user scrolls near bottom
            if visibleCount < departures.count {
                Color.clear
                    .frame(height: 1)
                    .onAppear {
                        // Load next batch
                        withAnimation(.snappy) {
                            visibleCount = min(visibleCount + 20, departures.count)
                        }
                    }

                // Loading indicator
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(MV.Colors.textTertiary)
                    Spacer()
                }
                .padding(.vertical, MV.Spacing.md)
            }
        }
    }

    // MARK: - Loading skeleton

    private var skeletonState: some View {
        VStack(spacing: 0) {
            ForEach(0..<5, id: \.self) { _ in
                DepartureRowSkeleton()
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

    // MARK: - Data loading (background decode)

    private func loadDepartures() async {
        isLoading = true
        visibleCount = 15  // Reset on new stop

        guard let schedule = await appState.dataProvider.loadStopSchedule(stopId: stop.id) else {
            departures = []
            isLoading = false
            return
        }

        // Resolve on background, filter to upcoming
        let dayIndex = (Calendar.current.component(.weekday, from: Date()) + 5) % 7
        let all = appState.dataProvider.resolveDepartures(from: schedule, forDayIndex: dayIndex)

        let cal = Calendar.current
        let now = cal.component(.hour, from: Date()) * 60 + cal.component(.minute, from: Date())
        departures = all.filter { $0.minutes >= now }

        isLoading = false
    }
}
