import SwiftUI
import MapKit

/// Lightweight vehicle marker — Equatable to prevent unnecessary SwiftUI re-renders.
/// MapKit will only redraw when position/bearing/routeId actually change.
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
        let color = route.map { MV.Colors.transitColor(for: $0.transitType) } ?? MV.Colors.bus

        ZStack {
            Circle()
                .fill(color.opacity(0.25))
                .frame(width: 22, height: 22)

            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.4), lineWidth: 1)
                )

            if let bearing = vehicle.bearing {
                Image(systemName: "arrowtriangle.up.fill")
                    .font(.system(size: 5, weight: .black))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(bearing))
                    .offset(y: -1)
            }
        }
        .frame(width: 22, height: 22)
        .allowsHitTesting(false)
    }
}
