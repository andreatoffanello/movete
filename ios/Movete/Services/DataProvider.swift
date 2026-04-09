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

    // Indexes for O(1) lookup
    private(set) var stopById: [String: Stop] = [:]
    private(set) var routeById: [String: Route] = [:]
    private(set) var routeByName: [String: Route] = [:]

    // Cache for on-demand data
    private var stopScheduleCache: [String: StopSchedule] = [:]

    // CDN base URL (GitHub Pages or local bundle)
    private let cdnBase = "https://andreatoffanello.github.io/movete/roma"

    // MARK: - Boot: load core.json

    func load() async throws {
        let log = DebugLogger.shared
        let core: CoreData

        // Try local bundle first (for development), then CDN
        if let bundleURL = Bundle.main.url(forResource: "core", withExtension: "json"),
           let data = try? Data(contentsOf: bundleURL) {
            core = try JSONDecoder().decode(CoreData.self, from: data)
            log.log(.data, "Loaded core.json from bundle", detail: "\(data.count) bytes")
        } else if let cached = loadFromDisk() {
            core = cached
            log.log(.data, "Loaded core.json from disk cache")
            Task { await refreshFromCDN() }
        } else {
            log.log(.network, "Downloading core.json from CDN...")
            core = try await downloadCore()
            saveToDisk(core)
            log.log(.data, "Downloaded & cached core.json")
        }

        apply(core)
        log.log(.info, "Data loaded: \(stops.count) stops, \(routes.count) routes")
    }

    private func apply(_ core: CoreData) {
        self.stops = core.stops
        self.routes = core.routes
        self.headsigns = core.headsigns
        self.lineNames = core.lineNames
        self.routeIds = core.routeIds

        // Build indexes
        self.stopById = Dictionary(uniqueKeysWithValues: core.stops.map { ($0.id, $0) })
        self.routeById = Dictionary(uniqueKeysWithValues: core.routes.map { ($0.id, $0) })
        self.routeByName = Dictionary(uniqueKeysWithValues: core.routes.map { ($0.name, $0) })

        self.isLoaded = true
    }

    // MARK: - On-demand: stop schedule

    func loadStopSchedule(stopId: String) async -> StopSchedule? {
        if let cached = stopScheduleCache[stopId] { return cached }

        // Try bundle
        if let bundleURL = Bundle.main.url(forResource: stopId, withExtension: "json", subdirectory: "stops"),
           let data = try? Data(contentsOf: bundleURL),
           let schedule = try? JSONDecoder().decode(StopSchedule.self, from: data) {
            stopScheduleCache[stopId] = schedule
            return schedule
        }

        // CDN
        guard let url = URL(string: "\(cdnBase)/stops/\(stopId).json") else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let schedule = try JSONDecoder().decode(StopSchedule.self, from: data)
            stopScheduleCache[stopId] = schedule
            return schedule
        } catch {
            DebugLogger.shared.log(.error, "Stop \(stopId) load failed", detail: error.localizedDescription)
            return nil
        }
    }

    /// Resolve indexed departures into UI-ready Departure objects
    func resolveDepartures(from schedule: StopSchedule, forDayIndex dayIndex: Int) -> [Departure] {
        // Find the day key that contains this day index
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

            // Parse time to minutes
            let parts = time.split(separator: ":")
            let h = Int(parts.first ?? "0") ?? 0
            let m = Int(parts.last ?? "0") ?? 0
            let minutes = h * 60 + m

            result.append(Departure(
                id: tripIdx.map { "trip_\($0)" } ?? "dep_\(idx)",
                time: time,
                minutes: minutes,
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

    // MARK: - Nearby stops

    func nearbyStops(to coordinate: CLLocationCoordinate2D, limit: Int = 5, radiusMeters: Double = 500) -> [Stop] {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return stops
            .map { stop in
                let dist = location.distance(from: CLLocation(latitude: stop.lat, longitude: stop.lng))
                return (stop, dist)
            }
            .filter { $0.1 <= radiusMeters }
            .sorted { $0.1 < $1.1 }
            .prefix(limit)
            .map { $0.0 }
    }

    // MARK: - Disk cache

    private var cacheURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Movete", isDirectory: true)
            .appendingPathComponent("core.json")
    }

    private func loadFromDisk() -> CoreData? {
        guard FileManager.default.fileExists(atPath: cacheURL.path),
              let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(CoreData.self, from: data)
    }

    private func saveToDisk(_ core: CoreData) {
        let dir = cacheURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(core) {
            try? data.write(to: cacheURL)
        }
    }

    private func downloadCore() async throws -> CoreData {
        guard let url = URL(string: "\(cdnBase)/core.json") else {
            throw URLError(.badURL)
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(CoreData.self, from: data)
    }

    private func refreshFromCDN() async {
        guard let core = try? await downloadCore() else { return }
        saveToDisk(core)
        apply(core)
    }
}
