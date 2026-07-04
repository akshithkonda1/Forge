import SwiftUI
import ForgeCore

// MARK: - ForgeWatchApp
//
// Entry point. Managers are created once here and injected through the
// Observation-based environment (watchOS 10+). Complications deep-link in
// via forgewatch:// URLs and land pre-filled.

enum WatchRoute: Hashable {
    case mindfulness
    case context
}

@main
struct ForgeWatchApp: App {
    @State private var health = WatchHealthKitManager()
    @State private var contextEngine = ContextEngine()
    @State private var aria = ARIAWatchService()
    @State private var session = MindfulnessSessionManager()
    @State private var path: [WatchRoute] = []

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $path) {
                HomeView(path: $path)
                    .navigationDestination(for: WatchRoute.self) { route in
                        switch route {
                        case .mindfulness: MindfulnessView()
                        case .context:     LifestyleContextView()
                        }
                    }
            }
            .environment(health)
            .environment(contextEngine)
            .environment(aria)
            .environment(session)
            .onOpenURL(perform: route(_:))
        }
    }

    /// Complication + Smart Stack deep links:
    ///   forgewatch://mindfulness → pre-filled session
    ///   forgewatch://sleep       → Home (sleep glance) until Phase 4's
    ///                              SleepSummaryView lands
    ///   forgewatch://home        → pop to root
    private func route(_ url: URL) {
        switch url.host() ?? url.absoluteString {
        case "mindfulness":
            if path.last != .mindfulness { path.append(.mindfulness) }
        case "context":
            if path.last != .context { path.append(.context) }
        default:
            path.removeAll()
        }
    }
}

// MARK: - Shared view helpers

extension View {
    /// Marks a button as the Double Tap gesture target on watchOS 11+,
    /// no-op on watchOS 10 (deployment target).
    @ViewBuilder
    func primaryDoubleTapShortcut() -> some View {
        if #available(watchOS 11.0, *) {
            self.handGestureShortcut(.primaryAction)
        } else {
            self
        }
    }
}
