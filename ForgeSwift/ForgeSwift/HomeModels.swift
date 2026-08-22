import SwiftUI

/// One rhythm for the whole Home surface. Every section reads its inset, gap,
/// padding and radius from here instead of hand-picking a number.
///
/// Before this existed the page carried four corner radii (22/18/14/12, plus 24
/// on the celebration banner) in two curve styles, card padding of 16/18/22 with
/// no rule, and thirteen separate per-child bottom paddings.
enum HomeMetrics {
    /// Horizontal inset for every section. The header used `FDS.Spacing.lg`
    /// while the other eleven used a literal `16` — the same number, two spellings.
    static let inset: CGFloat = FDS.Spacing.lg
    /// Vertical gap between sections, applied once by the VStack.
    static let sectionGap: CGFloat = 14
    /// Interior padding for every card.
    static let cardPadding: CGFloat = 18
    /// Radius for elements *inside* a card. Cards themselves use the
    /// `forgeGlassCard` default (`FDS.Radius.xl`).
    static let innerRadius: CGFloat = FDS.Radius.md
    /// Clearance past the tab bar and floating orb at the end of the scroll.
    static let scrollBottomClearance: CGFloat = 28
    /// How far a section rises as it fades in.
    static let entranceRise: CGFloat = 12
}

/// `MainTabView` sets `.id(store.activeTab)` (ContentView.swift), so `HomeView`
/// is destroyed and rebuilt on every tab switch. Without a gate the entire
/// entrance cascade replayed each time you came back to Home. This survives the
/// rebuild and resets on process launch, so the choreography plays once per
/// launch and later visits render immediately.
private final class HomeEntranceSession: @unchecked Sendable {
    static let shared = HomeEntranceSession()
    private(set) var hasPlayed = false
    private var scheduled = false
    private init() {}

    /// Called by every section on first appear. Sections all appear within the
    /// same runloop turn, so the flag must not flip until the longest stagger
    /// has finished — otherwise later sections would snap in mid-cascade.
    func markPlayed() {
        guard !scheduled else { return }
        scheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { self.hasPlayed = true }
    }
}

/// One entrance rule for every Home section, replacing nine hand-rolled variants
/// whose offsets ran −12/12/14/18/20/none. The header used to be the only
/// section that slid *down* while everything else rose.
private struct HomeEntrance: ViewModifier {
    let delay: Double
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : HomeMetrics.entranceRise)
            .onAppear {
                guard !HomeEntranceSession.shared.hasPlayed else {
                    appeared = true
                    return
                }
                withAnimation(FDS.Spring.hero.delay(delay)) { appeared = true }
                HomeEntranceSession.shared.markPlayed()
            }
    }
}

extension View {
    /// `delay` encodes the section's position down the page.
    func homeEntrance(delay: Double) -> some View {
        modifier(HomeEntrance(delay: delay))
    }
}

struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

@MainActor
enum HomePrimaryAction: Equatable {
    case startWorkout(id: String, name: String)
    case continueWorkout
    case recoveryDay(reason: String)
    case buildPlan

    static func resolve(store: AppStore) -> HomePrimaryAction {
        if store.isWorkoutActive { return .continueWorkout }

        let score = store.readiness.overall
        let guidanceOnly = AriaContextStore.shared.context.constraints
            .contains { $0.contains("guidance_only") }
        let life = store.hasMeaningfulLifeSignal

        // No Health signal yet: still start the session written from profile/equipment,
        // rather than pretending readiness is low.
        if !life {
            if let plan = store.todayWorkout {
                return .startWorkout(id: plan.id, name: plan.name)
            }
            return .buildPlan
        }

        if score < 55 {
            let reason = guidanceOnly
                ? "Recovery-first day — structure and rest over intensity."
                : "Readiness is low. Protect recovery and go light."
            return .recoveryDay(reason: reason)
        }

        if let plan = store.todayWorkout {
            if score < 70 {
                return .recoveryDay(reason: "You're at \(score)%. This session is already pulled back.")
            }
            return .startWorkout(id: plan.id, name: plan.name)
        }

        return .buildPlan
    }

    var title: String {
        switch self {
        case .startWorkout:              return "Start session"
        case .continueWorkout:           return "Continue"
        case .recoveryDay:               return "Start recovery"
        case .buildPlan:                 return "Write session"
        }
    }

    func subtitle(store: AppStore) -> String? {
        switch self {
        case .startWorkout(_, let name):
            return displaySessionName(name)
        case .continueWorkout:
            if let plan = store.todayWorkout {
                return "\(displaySessionName(plan.name)) · \(plan.duration) min"
            }
            return "Pick up the session"
        case .recoveryDay(let reason):
            return reason
        case .buildPlan:
            return "From how you live today — not a catalog"
        }
    }

    var icon: String {
        switch self {
        case .startWorkout:    return "play.fill"
        case .continueWorkout: return "arrow.clockwise"
        case .recoveryDay:     return "leaf.fill"
        case .buildPlan:       return "sparkles"
        }
    }

    var isRecovery: Bool {
        if case .recoveryDay = self { return true }
        return false
    }

    func usesRecoveryChrome(store: AppStore) -> Bool {
        if isRecovery { return true }
        if store.readiness.overall < 55 { return true }
        if store.todayWorkout?.intensity == .low { return true }
        return false
    }
}
