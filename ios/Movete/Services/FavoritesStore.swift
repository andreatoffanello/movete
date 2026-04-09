import Foundation
import Observation

@Observable
@MainActor
final class FavoritesStore {
    private static let key = "movete_favorites"

    var stopIds: Set<String> {
        didSet { save() }
    }

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
        self.stopIds = Set(saved)
    }

    func toggle(_ stopId: String) {
        if stopIds.contains(stopId) {
            stopIds.remove(stopId)
        } else {
            stopIds.insert(stopId)
        }
    }

    func isFavorite(_ stopId: String) -> Bool {
        stopIds.contains(stopId)
    }

    private func save() {
        UserDefaults.standard.set(Array(stopIds), forKey: Self.key)
    }
}
