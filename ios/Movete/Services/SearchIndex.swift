import Foundation

/// Pre-built search index for instant fuzzy search over stops and routes.
/// Built once at boot on background thread. Searches in O(n) but on pre-lowercased strings.
struct SearchIndex {
    struct Entry: Identifiable {
        let id: String
        let type: EntryType
        let name: String           // original display name
        let searchKey: String      // lowercased, normalized for search
        let subtitle: String?      // lines for stops, long name for routes

        enum EntryType {
            case stop
            case route
        }
    }

    private(set) var entries: [Entry] = []

    /// Build from core data — call on background thread
    static func build(stops: [Stop], routes: [Route]) -> SearchIndex {
        var index = SearchIndex()
        index.entries.reserveCapacity(stops.count + routes.count)

        for stop in stops {
            let linesStr = stop.lines?.prefix(6).joined(separator: ", ")
            index.entries.append(Entry(
                id: stop.id,
                type: .stop,
                name: stop.name,
                searchKey: stop.name.lowercased().folding(options: .diacriticInsensitive, locale: .current),
                subtitle: linesStr
            ))
        }

        for route in routes {
            index.entries.append(Entry(
                id: "route_\(route.id)",
                type: .route,
                name: route.name,
                searchKey: "\(route.name.lowercased()) \(route.longName?.lowercased() ?? "")",
                subtitle: route.longName
            ))
        }

        return index
    }

    /// Search with fuzzy matching — returns max `limit` results
    func search(_ query: String, limit: Int = 50) -> [Entry] {
        guard !query.isEmpty else { return [] }

        let q = query.lowercased().folding(options: .diacriticInsensitive, locale: .current)

        // Phase 1: prefix match (highest relevance)
        var prefixMatches: [Entry] = []
        // Phase 2: contains match
        var containsMatches: [Entry] = []

        for entry in entries {
            if entry.searchKey.hasPrefix(q) || entry.name.lowercased().hasPrefix(q) {
                prefixMatches.append(entry)
            } else if entry.searchKey.contains(q) {
                containsMatches.append(entry)
            }

            // Early exit if we have enough prefix matches
            if prefixMatches.count >= limit { break }
        }

        // Routes first if query looks like a number (searching for line)
        let isNumericQuery = q.allSatisfy { $0.isNumber || $0.isLetter }
        if isNumericQuery && q.count <= 4 {
            let routeResults = prefixMatches.filter { $0.type == .route }
            let stopResults = prefixMatches.filter { $0.type == .stop }
            return (routeResults + stopResults + containsMatches).prefix(limit).map { $0 }
        }

        return (prefixMatches + containsMatches).prefix(limit).map { $0 }
    }
}
