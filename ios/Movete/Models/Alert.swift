import Foundation

struct ServiceAlert: Identifiable {
    let id: String
    let headerText: String
    let descriptionText: String
    let affectedRouteIds: [String]
    let affectedStopIds: [String]
    let activePeriodStart: Date?
    let activePeriodEnd: Date?
}
