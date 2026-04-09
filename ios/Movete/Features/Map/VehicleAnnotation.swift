import SwiftUI
import MapKit

struct VehicleAnnotationView: View {
    let vehicle: Vehicle
    let route: Route?

    var body: some View {
        let color = route.map { MV.Colors.transitColor(for: $0.transitType) } ?? MV.Colors.bus

        ZStack {
            // Outer glow
            Circle()
                .fill(color.opacity(0.25))
                .frame(width: 24, height: 24)

            // Inner dot
            Circle()
                .fill(color)
                .frame(width: 14, height: 14)
                .overlay(
                    Circle()
                        .stroke(MV.Colors.background, lineWidth: 1.5)
                )

            // Direction indicator
            if let bearing = vehicle.bearing {
                Image(systemName: "arrowtriangle.up.fill")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(bearing))
                    .offset(y: -1)
            }
        }
    }
}
