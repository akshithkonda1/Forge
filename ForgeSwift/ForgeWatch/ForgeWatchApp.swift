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
    case workout
}

@main
struct ForgeWatchApp: App {
    @State private var health = WatchHealthKitManager()
    @State private var contextEngine = ContextEngine()
    @State private var aria = ARIAWatchService()
    @State private var session = MindfulnessSessionManager()
    @State private var workout = WorkoutSessionManager()
    @State private var path: [WatchRoute] = []

    init() {
        // Activate the phone link early so Live Activity state flows from
        // the first workout tick.
        PhoneLinkService.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $path) {
                HomeView(path: $path)
                    .navigationDestination(for: WatchRoute.self) { route in
                        switch route {
                        case .mindfulness: MindfulnessView()
                        case .context:     LifestyleContextView()
                        case .workout:     WorkoutCoordinatorView(path: $path)
                        }
                    }
            }
            .environment(health)
            .environment(contextEngine)
            .environment(aria)
            .environment(session)
            .environment(workout)
            .onOpenURL(perform: route(_:))
        }
    }

    /// Complication + Smart Stack deep links:
    ///   forgewatch://mindfulness → pre-filled session
    ///   forgewatch://workout     → workout coordinator (or live session)
    ///   forgewatch://sleep       → Home (sleep glance) until Phase 4's
    ///                              SleepSummaryView lands
    ///   forgewatch://home        → pop to root
    private func route(_ url: URL) {
        switch url.host() ?? url.absoluteString {
        case "mindfulness":
            if path.last != .mindfulness { path.append(.mindfulness) }
        case "context":
            if path.last != .context { path.append(.context) }
        case "workout":
            if path.last != .workout { path.append(.workout) }
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
