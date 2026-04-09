import SwiftUI

@main
struct MoveteApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MapScreen()
                .environment(appState)
                .preferredColorScheme(.dark)
        }
    }
}
