import SwiftUI
import Observation

// MARK: - Sheet Content State Machine

enum SheetContent: Equatable {
    case home
    case search
    case stop(Stop)
    case line(Route)
    case trip(Vehicle)
    case alerts

    static func == (lhs: SheetContent, rhs: SheetContent) -> Bool {
        switch (lhs, rhs) {
        case (.home, .home), (.search, .search), (.alerts, .alerts):
            return true
        case (.stop(let a), .stop(let b)):
            return a.id == b.id
        case (.line(let a), .line(let b)):
            return a.id == b.id
        case (.trip(let a), .trip(let b)):
            return a.id == b.id
        default:
            return false
        }
    }

    var preferredDetent: PresentationDetent {
        switch self {
        case .home:    return .fraction(0.22)
        case .search:  return .large
        case .stop:    return .fraction(0.5)
        case .line:    return .fraction(0.5)
        case .trip:    return .fraction(0.5)
        case .alerts:  return .fraction(0.5)
        }
    }
}

// MARK: - App State

@Observable
@MainActor
final class AppState {
    var dataProvider = DataProvider()
    var realtimeProvider = RealtimeProvider()
    var locationProvider = LocationProvider()
    var favoritesStore = FavoritesStore()

    var isLoading = true
    var error: String?

    // Navigation
    var sheetContent: SheetContent = .home
    var sheetDetent: PresentationDetent = .fraction(0.22)
    private var navigationStack: [SheetContent] = []

    /// Max navigation depth — prevents user from getting lost
    private let maxStackDepth = 3

    // MARK: - Navigation

    func navigate(to content: SheetContent) {
        if sheetContent != .home {
            if navigationStack.count >= maxStackDepth {
                navigationStack.removeFirst()
            }
            navigationStack.append(sheetContent)
        }
        sheetContent = content
        sheetDetent = content.preferredDetent
        Haptics.light()
    }

    func navigateBack() {
        if let previous = navigationStack.popLast() {
            sheetContent = previous
            sheetDetent = previous.preferredDetent
        } else {
            sheetContent = .home
            sheetDetent = .fraction(0.22)
        }
    }

    func navigateHome() {
        navigationStack.removeAll()
        sheetContent = .home
        sheetDetent = .fraction(0.22)
    }

    var canNavigateBack: Bool {
        !navigationStack.isEmpty
    }

    // MARK: - Bootstrap

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
