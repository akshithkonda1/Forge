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
    case week
}

@main
struct ForgeWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var health = WatchHealthKitManager()
    @State private var contextEngine = ContextEngine()
    @State private var aria = ARIAWatchService()
    @State private var session = MindfulnessSessionManager()
    @State private var workout = WorkoutSessionManager()
    @State private var hydration = HydrationManager()
    @State private var path: [WatchRoute] = []

    init() {
        // Earlier builds wrote the session token the phone sends into
        // UserDefaults in the clear, on both the shared suite and standard.
        // Clear those before anything reads either — a token copied into the
        // Keychain while the plaintext stays behind has moved nothing.
        PhoneLinkService.migrateStoredSecrets()
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
                                case .week:        WeekView()
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
            .environment(hydration)
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
                // watchOS keeps an HKWorkoutSession running through app suspension
                // and termination. Reattach before anything renders, so a session
                // that outlived the app can still be ended and saved instead of
                // burning battery behind a start screen.
                await workout.recoverIfNeeded()
                // A shortcut, a Siri phrase or the Ultra's Action Button can
                // ask for a screen before the app is even running. The intent
                // leaves a destination in the App Group; this is where it is
                // honoured. Consumed on read, and ignored if stale, so an
                // ordinary launch lands on Home.
                routeFromIntentIfRequested()
            }
            .onChange(of: scenePhase) { _, phase in
                // Also on activation: the app may already have been running
                // when the shortcut fired.
                if phase == .active { routeFromIntentIfRequested() }
            }
        }
    }

    private func routeFromIntentIfRequested() {
        guard let destination = WatchIntentRoute.consume() else { return }
        switch destination {
        case .workout:     if path.last != .workout { path.append(.workout) }
        case .mindfulness: if path.last != .mindfulness { path.append(.mindfulness) }
        }
    }

    /// Complication + Smart Stack deep links:
    ///   forgewatch://mindfulness → pre-filled session
    ///   forgewatch://workout     → workout coordinator (or live session)
    ///   forgewatch://sleep       → morning sleep summary
    ///   forgewatch://week        → this week's history
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
        case "week":
            if path.last != .week { path.append(.week) }
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
