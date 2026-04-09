import Foundation
import Observation

@Observable
@MainActor
final class RealtimeProvider {
    // Public state
    var vehicles: [Vehicle] = []
    var tripUpdates: [TripUpdate] = []
    var alerts: [ServiceAlert] = []
    var lastUpdate: Date?

    // Indexed lookups (O(1))
    private(set) var vehicleByTripId: [String: Vehicle] = [:]
    private(set) var vehiclesByRouteId: [String: [Vehicle]] = [:]
    private(set) var tripUpdateByTripId: [String: TripUpdate] = [:]

    // Polling
    private var vpTask: Task<Void, Never>?
    private var tuTask: Task<Void, Never>?
    private var alertTask: Task<Void, Never>?

    // Feed URLs (Roma)
    private let vpURL = URL(string: "https://romamobilita.it/sites/default/files/rome_rtgtfs_vehicle_positions_feed.pb")!
    private let tuURL = URL(string: "https://romamobilita.it/sites/default/files/rome_rtgtfs_trip_updates_feed.pb")!
    private let alertURL = URL(string: "https://romamobilita.it/sites/default/files/rome_rtgtfs_service_alerts_feed.pb")!

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    // MARK: - Lifecycle

    func startPolling() {
        stopPolling()

        vpTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.fetchVehiclePositions()
                try? await Task.sleep(for: .seconds(30))
            }
        }

        tuTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.fetchTripUpdates()
                try? await Task.sleep(for: .seconds(30))
            }
        }

        alertTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.fetchAlerts()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func stopPolling() {
        vpTask?.cancel(); vpTask = nil
        tuTask?.cancel(); tuTask = nil
        alertTask?.cancel(); alertTask = nil
    }

    // MARK: - Query methods

    func vehicle(forTripId tripId: String) -> Vehicle? {
        vehicleByTripId[tripId]
    }

    func vehicles(forRouteId routeId: String) -> [Vehicle] {
        vehiclesByRouteId[routeId] ?? []
    }

    func isLive(tripId: String) -> Bool {
        vehicleByTripId[tripId] != nil
    }

    func delay(forTripId tripId: String, stopId: String) -> Int? {
        guard let tu = tripUpdateByTripId[tripId] else { return nil }
        // Find the closest stop time update
        if let stu = tu.stopTimeUpdates.last(where: { $0.stopId == stopId }) {
            return stu.departureDelay ?? stu.arrivalDelay
        }
        // Fallback: use the last known delay
        return tu.stopTimeUpdates.last?.departureDelay ?? tu.stopTimeUpdates.last?.arrivalDelay
    }

    func alertsForRoute(_ routeId: String) -> [ServiceAlert] {
        alerts.filter { $0.affectedRouteIds.contains(routeId) }
    }

    func alertsForStop(_ stopId: String) -> [ServiceAlert] {
        alerts.filter { $0.affectedStopIds.contains(stopId) }
    }

    // MARK: - Fetch

    private func fetchVehiclePositions() async {
        do {
            let (data, _) = try await session.data(from: vpURL)
            let decoded = decodeGtfsRtVehicles(from: data)

            self.vehicles = decoded
            self.vehicleByTripId = Dictionary(decoded.map { ($0.tripId, $0) }, uniquingKeysWith: { _, new in new })
            self.vehiclesByRouteId = Dictionary(grouping: decoded, by: { $0.routeId })
            self.lastUpdate = Date()
        } catch {
            // Silent — RT is optional
        }
    }

    private func fetchTripUpdates() async {
        do {
            let (data, _) = try await session.data(from: tuURL)
            let decoded = decodeGtfsRtTripUpdates(from: data)

            self.tripUpdates = decoded
            self.tripUpdateByTripId = Dictionary(decoded.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        } catch {
            // Silent
        }
    }

    private func fetchAlerts() async {
        do {
            let (data, _) = try await session.data(from: alertURL)
            self.alerts = decodeGtfsRtAlerts(from: data)
        } catch {
            // Silent
        }
    }
}
