import SwiftUI
import Observation

@Observable
@MainActor
final class AppState {
    var dataProvider = DataProvider()
    var realtimeProvider = RealtimeProvider()
    var locationProvider = LocationProvider()
    var favoritesStore = FavoritesStore()

    var isLoading = true
    var error: String?

    func bootstrap() async {
        isLoading = true
        do {
            try await dataProvider.load()
            realtimeProvider.startPolling()
            locationProvider.requestPermission()
            isLoading = false
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }
}
