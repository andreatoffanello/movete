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
        let log = DebugLogger.shared
        log.log(.info, "Bootstrap started")
        isLoading = true
        do {
            try await dataProvider.load()
            log.log(.info, "Starting RT polling...")
            realtimeProvider.startPolling()
            locationProvider.requestPermission()
            isLoading = false
            log.log(.info, "Bootstrap complete")
        } catch {
            self.error = error.localizedDescription
            isLoading = false
            log.log(.error, "Bootstrap failed", detail: error.localizedDescription)
        }
    }
}
