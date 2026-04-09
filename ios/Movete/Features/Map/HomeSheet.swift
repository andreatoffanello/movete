import SwiftUI

struct HomeSheet: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MV.Spacing.lg) {
                // Header
                HStack {
                    Text("Movete")
                        .font(MV.Type.displayMedium)
                        .foregroundStyle(MV.Colors.textPrimary)
                    Spacer()
                }
                .padding(.horizontal, MV.Spacing.md + 4)
                .padding(.top, MV.Spacing.sm)

                if appState.isLoading {
                    loadingState
                } else if let error = appState.error {
                    errorState(error)
                } else {
                    nearbySection
                    favoritesSection
                    statsSection
                }
            }
            .padding(.bottom, MV.Spacing.xxl)
        }
    }

    // MARK: - Nearby Stops

    @ViewBuilder
    private var nearbySection: some View {
        VStack(alignment: .leading, spacing: MV.Spacing.sm) {
            Label("Fermate vicine", systemImage: "location.fill")
                .font(MV.Type.footnoteMedium)
                .foregroundStyle(MV.Colors.textSecondary)
                .padding(.horizontal, MV.Spacing.md + 4)

            if let location = appState.locationProvider.location {
                let nearby = appState.dataProvider.nearbyStops(
                    to: location, limit: 5, radiusMeters: 600
                )
                if nearby.isEmpty {
                    Text("Nessuna fermata nelle vicinanze")
                        .font(MV.Type.callout)
                        .foregroundStyle(MV.Colors.textTertiary)
                        .padding(.horizontal, MV.Spacing.md + 4)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: MV.Spacing.sm) {
                            ForEach(nearby) { stop in
                                NearbyStopCard(stop: stop)
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
                        .font(MV.Type.callout)
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
                    .font(MV.Type.footnoteMedium)
                    .foregroundStyle(MV.Colors.textSecondary)
                    .padding(.horizontal, MV.Spacing.md + 4)

                ForEach(Array(appState.favoritesStore.stopIds.prefix(5)), id: \.self) { stopId in
                    if let stop = appState.dataProvider.stopById[stopId] {
                        FavoriteStopRow(stop: stop)
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
                .font(MV.Type.callout)
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
                .font(MV.Type.calloutMedium)
                .foregroundStyle(MV.Colors.textPrimary)
                .lineLimit(1)

            if let lines = stop.lines, !lines.isEmpty {
                HStack(spacing: 4) {
                    ForEach(lines.prefix(4), id: \.self) { line in
                        Text(line)
                            .font(MV.Type.captionMedium)
                            .foregroundStyle(MV.Colors.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(MV.Colors.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                    if lines!.count > 4 {
                        Text("+\(lines!.count - 4)")
                            .font(MV.Type.captionMedium)
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
                .font(MV.Type.calloutMedium)
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
                .font(MV.Type.mono)
                .foregroundStyle(MV.Colors.accent)
            Text(label)
                .font(MV.Type.caption)
                .foregroundStyle(MV.Colors.textTertiary)
        }
    }
}
