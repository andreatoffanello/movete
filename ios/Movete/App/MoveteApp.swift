import SwiftUI

@main
struct MoveteApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ZStack(alignment: .bottom) {
                MapScreen()
                    .environment(appState)
                    .preferredColorScheme(.dark)

                #if DEBUG
                debugLayer
                #endif
            }
        }
    }

    #if DEBUG
    @ViewBuilder
    private var debugLayer: some View {
        VStack {
            Spacer()
            DebugOverlay()

            // Triple-tap trigger zone
            Color.clear
                .frame(height: 44)
                .contentShape(Rectangle())
                .onTapGesture(count: 3) {
                    withAnimation(.snappy) {
                        DebugLogger.shared.toggle()
                    }
                }
        }
        .allowsHitTesting(DebugLogger.shared.isVisible || true)
    }
    #endif
}
