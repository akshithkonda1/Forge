import SwiftUI
import ForgeCore

// MARK: - ForgeWatchApp
//
// Entry point. Managers are created once here and injected through the
// Observation-based environment (watchOS 27). Complications deep-link in
// via forgewatch:// URLs and land pre-filled.

enum WatchRoute: Hashable {
    case mindfulness
    case context
    case workout
    case sleep
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
            Group {
                if contextEngine.hasOnboarded {
                    NavigationStack(path: $path) {
                        HomeView(path: $path)
                            .navigationDestination(for: WatchRoute.self) { route in
                                switch route {
                                case .mindfulness: MindfulnessView()
                                case .context:     LifestyleContextView()
                                case .workout:     WorkoutCoordinatorView(path: $path)
                                case .sleep:       SleepSummaryView()
                                }
                            }
                    }
                } else {
                    OnboardingView()
                }
            }
            .environment(health)
            .environment(contextEngine)
            .environment(aria)
            .environment(session)
            .environment(workout)
            .environment(\.forgeMinimalAnimation, contextEngine.minimalAnimation)
            .onOpenURL(perform: route(_:))
            .onReceive(NotificationCenter.default.publisher(for: PhoneLinkService.companionConfigDidUpdate)) { _ in
                // iPhone pushed ARIA base URL / first name — refresh greeting immediately.
                aria.refresh(
                    health: health,
                    context: contextEngine,
                    sessionsToday: session.sessionsCompletedToday
                )
            }
            .task {
                // Ensure WCSession is live whenever the scene is up (covers cold launch
                // after phone reinstall without requiring a workout start).
                PhoneLinkService.shared.activate()
            }
        }
    }

    /// Complication + Smart Stack deep links:
    ///   forgewatch://mindfulness → pre-filled session
    ///   forgewatch://workout     → workout coordinator (or live session)
    ///   forgewatch://sleep       → morning sleep summary
    ///   forgewatch://home        → pop to root
    private func route(_ url: URL) {
        switch url.host() ?? url.absoluteString {
        case "mindfulness":
            if path.last != .mindfulness { path.append(.mindfulness) }
        case "context":
            if path.last != .context { path.append(.context) }
        case "workout":
            if path.last != .workout { path.append(.workout) }
        case "sleep":
            if path.last != .sleep { path.append(.sleep) }
        default:
            path.removeAll()
        }
    }
}

// MARK: - Shared view helpers

extension View {
    /// Marks a button as the Double Tap gesture target (watchOS 27).
    func primaryDoubleTapShortcut() -> some View {
        self.handGestureShortcut(.primaryAction)
    }
}

// MARK: - Minimal Animation environment
//
// The user-facing "Minimal animation" toggle (Context screen) — forces
// static orb variants and disables aurora rings even when the system
// Reduce Motion setting is off. Components combine this with
// accessibilityReduceMotion; either one wins.

private struct MinimalAnimationKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var forgeMinimalAnimation: Bool {
        get { self[MinimalAnimationKey.self] }
        set { self[MinimalAnimationKey.self] = newValue }
    }
}
