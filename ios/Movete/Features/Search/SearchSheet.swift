import SwiftUI

struct SearchSheet: View {
    @Environment(AppState.self) private var appState
    @State private var query = ""
    @State private var results: [SearchIndex.Entry] = []
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Search input
            searchField
                .padding(.horizontal, MV.Spacing.md + 4)
                .padding(.top, MV.Spacing.sm)
                .padding(.bottom, MV.Spacing.sm)

            Divider().foregroundStyle(MV.Colors.borderSubtle)

            // Results
            if query.isEmpty {
                recentAndSuggested
            } else if results.isEmpty {
                emptyResults
            } else {
                resultsList
            }
        }
        .onAppear {
            isFocused = true
        }
    }

    // MARK: - Search field with debounce

    private var searchField: some View {
        HStack(spacing: MV.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(MV.Colors.textTertiary)

            TextField("Fermata o linea", text: $query)
                .font(MV.Typography.body)
                .foregroundStyle(MV.Colors.textPrimary)
                .focused($isFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: query) { _, newValue in
                    debouncedSearch(newValue)
                }

            if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(MV.Colors.textTertiary)
                }
            }
        }
        .padding(.horizontal, MV.Spacing.sm)
        .padding(.vertical, MV.Spacing.xs)
        .background(MV.Colors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: MV.Radius.md, style: .continuous))
    }

    // MARK: - Debounced search (300ms)

    private func debouncedSearch(_ query: String) {
        searchTask?.cancel()
        guard !query.isEmpty else {
            results = []
            return
        }
        searchTask = Task {
            // 200ms debounce — short enough to feel instant, long enough to avoid thrashing
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            let found = appState.dataProvider.search(query, limit: 50)
            results = found
        }
    }

    // MARK: - Results list (lazy, virtualized)

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(results) { entry in
                    SearchResultRow(entry: entry)
                        .padding(.horizontal, MV.Spacing.md + 4)

                    if entry.id != results.last?.id {
                        Divider()
                            .foregroundStyle(MV.Colors.borderSubtle)
                            .padding(.leading, MV.Spacing.md + 4 + 36)
                    }
                }
            }
        }
    }

    // MARK: - Empty results

    private var emptyResults: some View {
        VStack(spacing: MV.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(MV.Colors.textTertiary)
            Text("Nessun risultato per \"\(query)\"")
                .font(MV.Typography.callout)
                .foregroundStyle(MV.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, MV.Spacing.xxl)
    }

    // MARK: - Recent / suggested (when no query)

    private var recentAndSuggested: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MV.Spacing.lg) {
                // Favorites as quick access
                if !appState.favoritesStore.stopIds.isEmpty {
                    VStack(alignment: .leading, spacing: MV.Spacing.sm) {
                        Label("Preferiti", systemImage: "star.fill")
                            .font(MV.Typography.footnoteMedium)
                            .foregroundStyle(MV.Colors.textSecondary)

                        ForEach(Array(appState.favoritesStore.stopIds.prefix(5)), id: \.self) { stopId in
                            if let stop = appState.dataProvider.stopById[stopId] {
                                SearchResultRow(entry: SearchIndex.Entry(
                                    id: stop.id,
                                    type: .stop,
                                    name: stop.name,
                                    searchKey: "",
                                    subtitle: stop.lines?.prefix(6).joined(separator: ", ")
                                ))
                            }
                        }
                    }
                    .padding(.horizontal, MV.Spacing.md + 4)
                }

                // Nearby
                if let loc = appState.locationProvider.location {
                    VStack(alignment: .leading, spacing: MV.Spacing.sm) {
                        Label("Nelle vicinanze", systemImage: "location.fill")
                            .font(MV.Typography.footnoteMedium)
                            .foregroundStyle(MV.Colors.textSecondary)

                        let nearby = appState.dataProvider.nearbyStops(to: loc, limit: 8, radiusMeters: 800)
                        ForEach(nearby) { stop in
                            SearchResultRow(entry: SearchIndex.Entry(
                                id: stop.id,
                                type: .stop,
                                name: stop.name,
                                searchKey: "",
                                subtitle: stop.lines?.prefix(6).joined(separator: ", ")
                            ))
                        }
                    }
                    .padding(.horizontal, MV.Spacing.md + 4)
                }
            }
            .padding(.top, MV.Spacing.md)
            .padding(.bottom, MV.Spacing.xxl)
        }
    }
}

// MARK: - Result Row

struct SearchResultRow: View {
    let entry: SearchIndex.Entry

    var body: some View {
        HStack(spacing: MV.Spacing.sm) {
            // Icon
            Image(systemName: entry.type == .route ? "arrow.triangle.branch" : "mappin.circle.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(entry.type == .route ? MV.Colors.accent : MV.Colors.textTertiary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(MV.Typography.calloutMedium)
                    .foregroundStyle(MV.Colors.textPrimary)
                    .lineLimit(1)

                if let subtitle = entry.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(MV.Typography.caption)
                        .foregroundStyle(MV.Colors.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MV.Colors.textTertiary)
        }
        .padding(.vertical, MV.Spacing.sm)
        .contentShape(Rectangle())
    }
}
