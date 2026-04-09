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

    private let dotSize: CGFloat = 12
    private let coneLength: CGFloat = 18

    var body: some View {
        let color = route.map { Color(hex: $0.color) } ?? MV.Colors.bus

        ZStack {
            // Bearing cone (Google Maps style)
            if let bearing = vehicle.bearing {
                BearingCone(color: color)
                    .frame(width: dotSize + coneLength * 2, height: dotSize + coneLength * 2)
                    .rotationEffect(.degrees(bearing))
            }

            // Dot with white border
            Circle()
                .fill(color)
                .frame(width: dotSize, height: dotSize)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.8), lineWidth: 1.5)
                )
        }
        .frame(width: dotSize + coneLength * 2, height: dotSize + coneLength * 2)
        .allowsHitTesting(false)
    }
}

/// Cone-shaped gradient pointing up from center, fading out.
private struct BearingCone: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2
            let dotRadius: CGFloat = 6 // half of dotSize

            // Cone: 40° arc from center, starting just outside the dot
            let startAngle = Angle.degrees(-20)  // -90 is up, so -110 to -70
            let endAngle = Angle.degrees(20)

            var path = Path()
            let innerRadius = dotRadius + 1
            let outerRadius = radius

            // Start at inner arc
            path.addArc(center: center, radius: innerRadius,
                       startAngle: startAngle - .degrees(90),
                       endAngle: endAngle - .degrees(90),
                       clockwise: false)
            // Line to outer arc
            path.addArc(center: center, radius: outerRadius,
                       startAngle: endAngle - .degrees(90),
                       endAngle: startAngle - .degrees(90),
                       clockwise: true)
            path.closeSubpath()

            // Gradient fill: solid near dot, fading to transparent
            let gradient = Gradient(stops: [
                .init(color: color.opacity(0.35), location: 0),
                .init(color: color.opacity(0.08), location: 0.7),
                .init(color: color.opacity(0), location: 1.0),
            ])

            let shading = GraphicsContext.Shading.radialGradient(
                gradient,
                center: center,
                startRadius: innerRadius,
                endRadius: outerRadius
            )

            context.fill(path, with: shading)
        }
    }
}
