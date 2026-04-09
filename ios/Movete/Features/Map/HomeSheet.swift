import SwiftUI

struct HomeSheet: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MV.Spacing.md) {
                if appState.isLoading {
                    loadingState
                } else if let error = appState.error {
                    errorState(error)
                } else {
                    // Alert banner (if any active alerts)
                    alertBanner

                    // Favorites with live countdown (peek-visible, most important)
                    favoritesSection

                    // Nearby stops
                    nearbySection

                    // Stats
                    statsSection
                }
            }
            .padding(.top, MV.Spacing.xs)
            .padding(.bottom, MV.Spacing.xxl)
        }
    }

    // MARK: - Alert Banner

    @ViewBuilder
    private var alertBanner: some View {
        let alertCount = appState.realtimeProvider.alerts.count
        if alertCount > 0 {
            Button {
                appState.navigate(to: .alerts)
            } label: {
                HStack(spacing: MV.Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MV.Colors.warning)
                    Text("\(alertCount) avvis\(alertCount == 1 ? "o" : "i") di servizio")
                        .font(MV.Typography.calloutMedium)
                        .foregroundStyle(MV.Colors.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MV.Colors.textTertiary)
                }
                .padding(MV.Spacing.sm)
                .background(MV.Colors.warningSubtle)
                .clipShape(RoundedRectangle(cornerRadius: MV.Radius.md, style: .continuous))
            }
            .padding(.horizontal, MV.Spacing.md + 4)
        }
    }

    // MARK: - Nearby Stops

    @ViewBuilder
    private var nearbySection: some View {
        VStack(alignment: .leading, spacing: MV.Spacing.sm) {
            Label("Fermate vicine", systemImage: "location.fill")
                .font(MV.Typography.footnoteMedium)
                .foregroundStyle(MV.Colors.textSecondary)
                .padding(.horizontal, MV.Spacing.md + 4)

            if let location = appState.locationProvider.location {
                let nearby = appState.dataProvider.nearbyStops(
                    to: location, limit: 5, radiusMeters: 600
                )
                if nearby.isEmpty {
                    Text("Nessuna fermata nelle vicinanze")
                        .font(MV.Typography.callout)
                        .foregroundStyle(MV.Colors.textTertiary)
                        .padding(.horizontal, MV.Spacing.md + 4)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: MV.Spacing.sm) {
                            ForEach(nearby) { stop in
                                NearbyStopCard(stop: stop)
                                    .onTapGesture {
                                        appState.navigate(to: .stop(stop))
                                    }
                            }
                        }
                        .padding(.horizontal, MV.Spacing.md + 4)
                    }
                }
            } else {
                HStack(spacing: MV.Spacing.xs) {
                    Image(systemName: "location.slash")
                        .font(.system(size: 14))
                    Text("Abilita la posizione per vedere le fermate vicine")
                        .font(MV.Typography.callout)
                }
                .foregroundStyle(MV.Colors.textTertiary)
                .padding(.horizontal, MV.Spacing.md + 4)
            }
        }
    }

    // MARK: - Favorites

    @ViewBuilder
    private var favoritesSection: some View {
        if !appState.favoritesStore.stopIds.isEmpty {
            VStack(alignment: .leading, spacing: MV.Spacing.sm) {
                Label("Preferiti", systemImage: "star.fill")
                    .font(MV.Typography.footnoteMedium)
                    .foregroundStyle(MV.Colors.textSecondary)
                    .padding(.horizontal, MV.Spacing.md + 4)

                ForEach(Array(appState.favoritesStore.stopIds.prefix(5)), id: \.self) { stopId in
                    if let stop = appState.dataProvider.stopById[stopId] {
                        FavoriteStopRow(stop: stop)
                            .onTapGesture {
                                appState.navigate(to: .stop(stop))
                            }
                    }
                }
                .padding(.horizontal, MV.Spacing.md + 4)
            }
        }
    }

    // MARK: - Stats (subtle, bottom)

    private var statsSection: some View {
        HStack(spacing: MV.Spacing.lg) {
            StatBadge(value: "\(appState.dataProvider.routes.count)", label: "Linee")
            StatBadge(value: "\(appState.dataProvider.stops.count)", label: "Fermate")
            StatBadge(
                value: "\(appState.realtimeProvider.vehicles.count)",
                label: "Mezzi live"
            )
        }
        .padding(.horizontal, MV.Spacing.md + 4)
        .padding(.top, MV.Spacing.sm)
    }

    // MARK: - Loading / Error

    private var loadingState: some View {
        VStack(spacing: MV.Spacing.md) {
            ForEach(0..<3, id: \.self) { _ in
                DepartureRowSkeleton()
            }
        }
    }

    private func errorState(_ error: String) -> some View {
        VStack(spacing: MV.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(MV.Colors.warning)
            Text(error)
                .font(MV.Typography.callout)
                .foregroundStyle(MV.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(MV.Spacing.xl)
    }
}

// MARK: - Subviews

private struct NearbyStopCard: View {
    let stop: Stop

    var body: some View {
        VStack(alignment: .leading, spacing: MV.Spacing.xs) {
            Text(stop.name)
                .font(MV.Typography.calloutMedium)
                .foregroundStyle(MV.Colors.textPrimary)
                .lineLimit(1)

            if let lines = stop.lines, !lines.isEmpty {
                HStack(spacing: 4) {
                    ForEach(lines.prefix(4), id: \.self) { line in
                        Text(line)
                            .font(MV.Typography.captionMedium)
                            .foregroundStyle(MV.Colors.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(MV.Colors.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                    if lines.count > 4 {
                        Text("+\(lines.count - 4)")
                            .font(MV.Typography.captionMedium)
                            .foregroundStyle(MV.Colors.textTertiary)
                    }
                }
            }
        }
        .padding(MV.Spacing.sm)
        .frame(width: 160, alignment: .leading)
        .mvSurface()
    }
}

private struct FavoriteStopRow: View {
    let stop: Stop

    var body: some View {
        HStack(spacing: MV.Spacing.sm) {
            Image(systemName: "star.fill")
                .font(.system(size: 12))
                .foregroundStyle(MV.Colors.accent)

            Text(stop.name)
                .font(MV.Typography.calloutMedium)
                .foregroundStyle(MV.Colors.textPrimary)
                .lineLimit(1)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MV.Colors.textTertiary)
        }
        .padding(MV.Spacing.sm)
        .mvSurface()
    }
}

private struct StatBadge: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(MV.Typography.mono)
                .foregroundStyle(MV.Colors.accent)
            Text(label)
                .font(MV.Typography.caption)
                .foregroundStyle(MV.Colors.textTertiary)
        }
    }
}
