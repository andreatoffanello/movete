import Foundation
import Observation
import CoreLocation

@Observable
@MainActor
final class DataProvider {
    // Core data (loaded at boot)
    var stops: [Stop] = []
    var routes: [Route] = []
    var headsigns: [String] = []
    var lineNames: [String] = []
    var routeIds: [String] = []
    var isLoaded = false

    // Agencies
    var agencies: [Agency] = []

    // Indexes for O(1) lookup
    private(set) var stopById: [String: Stop] = [:]
    private(set) var routeById: [String: Route] = [:]
    private(set) var routeByName: [String: Route] = [:]
    private(set) var agencyById: [String: Agency] = [:]

    // Spatial index for fast viewport queries (5000+ stops)
    private(set) var stopSpatialIndex = SpatialIndex<Stop>()

    // Search index (pre-built, normalized)
    private(set) var searchIndex = SearchIndex()

    // Cache for on-demand stop schedules
    private var stopScheduleCache: [String: StopSchedule] = [:]

    private let cdnBase = "https://andreatoffanello.github.io/movete/roma"

    // MARK: - Boot: load core.json (heavy work off main thread)

    func load() async throws {
        let log = DebugLogger.shared
        let data: Data

        if let bundleURL = Bundle.main.url(forResource: "core", withExtension: "json"),
           let bundleData = try? Data(contentsOf: bundleURL) {
            data = bundleData
            log.log(.data, "Loaded core.json from bundle", detail: "\(data.count) bytes")
        } else if let diskData = loadDataFromDisk() {
            data = diskData
            log.log(.data, "Loaded core.json from disk cache")
            Task.detached { [cdnBase] in
                await Self.backgroundRefreshFromCDN(cdnBase: cdnBase, cacheURL: self.cacheURL)
            }
        } else {
            log.log(.network, "Downloading core.json from CDN...")
            data = try await downloadCoreData()
            saveDataToDisk(data)
            log.log(.data, "Downloaded & cached core.json")
        }

        // Parse + index on background thread
        let parsed = try await Task.detached(priority: .userInitiated) {
            try Self.parseAndIndex(data: data)
        }.value

        // Apply to main actor
        self.stops = parsed.stops
        self.routes = parsed.routes
        self.agencies = parsed.agencies
        self.headsigns = parsed.headsigns
        self.lineNames = parsed.lineNames
        self.routeIds = parsed.routeIds
        self.stopById = parsed.stopById
        self.routeById = parsed.routeById
        self.routeByName = parsed.routeByName
        self.agencyById = parsed.agencyById
        self.stopSpatialIndex = parsed.spatialIndex
        self.searchIndex = parsed.searchIndex
        self.isLoaded = true

        let sampleRoute = self.routeById["105"]
        log.log(.info, "Data loaded: \(stops.count) stops, \(routes.count) routes, routeById=\(self.routeById.count)")
        log.log(.data, "Route 105: color=\(sampleRoute?.color ?? "NIL") agency=\(sampleRoute?.agencyId ?? "NIL")")
    }

    // MARK: - Background parse + index (runs off main thread)

    private struct ParsedData: Sendable {
        let stops: [Stop]
        let routes: [Route]
        let agencies: [Agency]
        let headsigns: [String]
        let lineNames: [String]
        let routeIds: [String]
        let stopById: [String: Stop]
        let routeById: [String: Route]
        let routeByName: [String: Route]
        let agencyById: [String: Agency]
        let spatialIndex: SpatialIndex<Stop>
        let searchIndex: SearchIndex
    }

    nonisolated private static func parseAndIndex(data: Data) throws -> ParsedData {
        let core = try JSONDecoder().decode(CoreData.self, from: data)

        // Build indexes
        let stopById = Dictionary(uniqueKeysWithValues: core.stops.map { ($0.id, $0) })
        let routeById = Dictionary(uniqueKeysWithValues: core.routes.map { ($0.id, $0) })
        let routeByName = Dictionary(uniqueKeysWithValues: core.routes.map { ($0.name, $0) })
        let agencies = core.agencies ?? []
        let agencyById = Dictionary(uniqueKeysWithValues: agencies.map { ($0.id, $0) })

        // Build spatial index
        let spatial = SpatialIndex<Stop>()
        spatial.buildFromItems(core.stops.map { ($0, $0.lat, $0.lng) })

        // Build search index
        let search = SearchIndex.build(stops: core.stops, routes: core.routes)

        return ParsedData(
            stops: core.stops, routes: core.routes, agencies: agencies,
            headsigns: core.headsigns, lineNames: core.lineNames, routeIds: core.routeIds,
            stopById: stopById, routeById: routeById, routeByName: routeByName,
            agencyById: agencyById,
            spatialIndex: spatial, searchIndex: search
        )
    }

    // MARK: - Viewport query (uses spatial index)

    func stopsInRegion(minLat: Double, maxLat: Double, minLng: Double, maxLng: Double) -> [Stop] {
        stopSpatialIndex.query(minLat: minLat, maxLat: maxLat, minLng: minLng, maxLng: maxLng)
    }

    // MARK: - Nearby stops (uses spatial index + CLLocation for exact distance)

    func nearbyStops(to coordinate: CLLocationCoordinate2D, limit: Int = 5, radiusMeters: Double = 500) -> [Stop] {
        // ~0.005 degrees ≈ 500m at Rome's latitude
        let degRadius = radiusMeters / 111_000
        let candidates = stopSpatialIndex.query(
            minLat: coordinate.latitude - degRadius,
            maxLat: coordinate.latitude + degRadius,
            minLng: coordinate.longitude - degRadius,
            maxLng: coordinate.longitude + degRadius
        )

        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return candidates
            .map { ($0, location.distance(from: CLLocation(latitude: $0.lat, longitude: $0.lng))) }
            .filter { $0.1 <= radiusMeters }
            .sorted { $0.1 < $1.1 }
            .prefix(limit)
            .map { $0.0 }
    }

    // MARK: - Search

    func search(_ query: String, limit: Int = 50) -> [SearchIndex.Entry] {
        searchIndex.search(query, limit: limit)
    }

    // MARK: - On-demand: stop schedule (background decode)

    func loadStopSchedule(stopId: String) async -> StopSchedule? {
        if let cached = stopScheduleCache[stopId] { return cached }

        // Try bundle
        if let bundleURL = Bundle.main.url(forResource: stopId, withExtension: "json", subdirectory: "stops"),
           let data = try? Data(contentsOf: bundleURL) {
            return await decodeStopSchedule(data: data, stopId: stopId)
        }

        // CDN
        guard let url = URL(string: "\(cdnBase)/stops/\(stopId).json") else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return await decodeStopSchedule(data: data, stopId: stopId)
        } catch {
            DebugLogger.shared.log(.error, "Stop \(stopId) load failed", detail: error.localizedDescription)
            return nil
        }
    }

    private func decodeStopSchedule(data: Data, stopId: String) async -> StopSchedule? {
        // Decode on background thread
        do {
            let schedule = try await Task.detached(priority: .userInitiated) {
                try JSONDecoder().decode(StopSchedule.self, from: data)
            }.value
            stopScheduleCache[stopId] = schedule
            return schedule
        } catch {
            DebugLogger.shared.log(.error, "Stop \(stopId) decode failed", detail: error.localizedDescription)
            return nil
        }
    }

    /// Resolve indexed departures into UI-ready Departure objects
    func resolveDepartures(from schedule: StopSchedule, forDayIndex dayIndex: Int) -> [Departure] {
        let dayNames = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
        guard dayIndex >= 0, dayIndex < 7 else { return [] }
        let targetDay = dayNames[dayIndex]

        var matchedKey: String?
        for key in schedule.departures.keys {
            if key.split(separator: ",").contains(Substring(targetDay)) {
                matchedKey = key
                break
            }
        }

        guard let key = matchedKey, let entries = schedule.departures[key] else { return [] }

        var result: [Departure] = []
        result.reserveCapacity(entries.count)

        for (idx, entry) in entries.enumerated() {
            guard entry.count >= 3 else { continue }

            let time = entry[0].stringValue
            let lineIdx = entry[1].intValue ?? 0
            let headsignIdx = entry[2].intValue ?? 0

            let lineName = lineIdx < lineNames.count ? lineNames[lineIdx] : "?"
            let headsign = headsignIdx < headsigns.count ? headsigns[headsignIdx] : ""
            let routeId = lineIdx < routeIds.count ? routeIds[lineIdx] : ""
            let route = routeById[routeId]

            let dock = entry.count > 3 ? entry[3].stringValue : nil
            let tripIdx = entry.count > 5 ? entry[5].intValue : nil

            let parts = time.split(separator: ":")
            let h = Int(parts.first ?? "0") ?? 0
            let m = Int(parts.last ?? "0") ?? 0

            result.append(Departure(
                id: tripIdx.map { "trip_\($0)" } ?? "dep_\(idx)",
                time: time,
                minutes: h * 60 + m,
                lineName: lineName,
                lineColor: route?.color ?? "#3B82F6",
                lineTextColor: route?.textColor ?? "#FFFFFF",
                headsign: headsign,
                transitType: route?.transitType ?? .bus,
                routeId: routeId,
                tripId: nil,
                dock: dock == "" ? nil : dock
            ))
        }

        return result
    }

    // MARK: - Disk cache (raw Data, not re-encoded)

    private var cacheURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Movete", isDirectory: true)
            .appendingPathComponent("core.json")
    }

    private func loadDataFromDisk() -> Data? {
        guard FileManager.default.fileExists(atPath: cacheURL.path) else { return nil }
        return try? Data(contentsOf: cacheURL)
    }

    private func saveDataToDisk(_ data: Data) {
        let dir = cacheURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: cacheURL)
    }

    private func downloadCoreData() async throws -> Data {
        guard let url = URL(string: "\(cdnBase)/core.json") else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }

    private static func backgroundRefreshFromCDN(cdnBase: String, cacheURL: URL) async {
        guard let url = URL(string: "\(cdnBase)/core.json"),
              let (data, _) = try? await URLSession.shared.data(from: url) else { return }
        let dir = cacheURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: cacheURL)
    }
}
