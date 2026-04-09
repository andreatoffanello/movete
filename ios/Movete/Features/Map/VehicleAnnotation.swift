import SwiftUI
import MapKit

struct VehicleAnnotationView: View, Equatable {
    let vehicle: Vehicle
    let route: Route?

    static func == (lhs: VehicleAnnotationView, rhs: VehicleAnnotationView) -> Bool {
        lhs.vehicle.id == rhs.vehicle.id &&
        lhs.vehicle.latitude == rhs.vehicle.latitude &&
        lhs.vehicle.longitude == rhs.vehicle.longitude &&
        lhs.vehicle.bearing == rhs.vehicle.bearing &&
        lhs.vehicle.routeId == rhs.vehicle.routeId
    }

    var body: some View {
        let color = route.map { Color(hex: $0.color) } ?? MV.Colors.bus

        Circle()
            .fill(color)
            .frame(width: 14, height: 14)
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.5), lineWidth: 1.5)
            )
            .frame(width: 14, height: 14)
            .allowsHitTesting(false)
    }
}
