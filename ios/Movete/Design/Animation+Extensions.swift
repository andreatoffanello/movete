import SwiftUI

extension Animation {
    /// Tap, toggle, piccole interazioni — veloce e reattivo
    static let snappy = Animation.spring(response: 0.3, dampingFraction: 0.8)

    /// Sheet, card transitions — fluido e naturale
    static let smooth = Animation.spring(response: 0.5, dampingFraction: 0.85)

    /// Map zoom, hero transitions — drammatico e cinematico
    static let dramatic = Animation.spring(response: 0.7, dampingFraction: 0.75)

    /// Veicolo che si muove sulla mappa — continuo, no bounce
    static let vehicleMove = Animation.spring(response: 1.0, dampingFraction: 0.95)

    /// Pulse per indicatori live
    static let pulse = Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true)
}

// MARK: - Convenience View Extensions

extension View {
    func animateSnappy<V: Equatable>(value: V) -> some View {
        self.animation(.snappy, value: value)
    }

    func animateSmooth<V: Equatable>(value: V) -> some View {
        self.animation(.smooth, value: value)
    }

    func animateDramatic<V: Equatable>(value: V) -> some View {
        self.animation(.dramatic, value: value)
    }
}
