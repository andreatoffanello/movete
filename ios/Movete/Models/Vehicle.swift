import Foundation
import CoreLocation

struct Vehicle: Identifiable {
    let id: String
    let tripId: String
    let routeId: String
    let label: String
    let latitude: Double
    let longitude: Double
    let bearing: Double?
    let speed: Double?
    let timestamp: Date
    let currentStopSequence: Int?
    let stopId: String?
    let occupancyStatus: OccupancyStatus

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    enum OccupancyStatus: Int {
        case empty = 0
        case manySeatsAvailable = 1
        case fewSeatsAvailable = 2
        case standingRoomOnly = 3
        case crushedStandingRoomOnly = 4
        case full = 5
        case notAcceptingPassengers = 6
        case unknown = -1
    }
}
