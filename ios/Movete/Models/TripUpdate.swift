import Foundation

struct TripUpdate: Identifiable {
    let id: String          // trip_id
    let routeId: String
    let stopTimeUpdates: [StopTimeUpdate]
}

struct StopTimeUpdate {
    let stopSequence: Int
    let stopId: String
    let arrivalDelay: Int?      // secondi di ritardo (positivo = in ritardo)
    let departureDelay: Int?    // secondi di ritardo
}
