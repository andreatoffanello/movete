import UIKit

@MainActor
enum Haptics {
    private static let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private static let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private static let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private static let notification = UINotificationFeedbackGenerator()
    private static let selectionGenerator = UISelectionFeedbackGenerator()

    /// Tap su fermata, toggle piccolo
    static func light() {
        lightImpact.impactOccurred()
    }

    /// Selezione linea, azione media
    static func medium() {
        mediumImpact.impactOccurred()
    }

    /// Azione importante
    static func heavy() {
        heavyImpact.impactOccurred()
    }

    /// Aggiunta preferito
    static func success() {
        notification.notificationOccurred(.success)
    }

    /// Alert servizio
    static func warning() {
        notification.notificationOccurred(.warning)
    }

    /// Errore
    static func error() {
        notification.notificationOccurred(.error)
    }

    /// Scroll tra opzioni
    static func selection() {
        self.selectionGenerator.selectionChanged()
    }

    /// Prepara i generatori per risposta immediata
    static func prepare() {
        lightImpact.prepare()
        mediumImpact.prepare()
        notification.prepare()
    }
}
