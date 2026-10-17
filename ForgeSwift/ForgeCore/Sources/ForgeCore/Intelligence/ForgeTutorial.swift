import Foundation

/// Learn-by-doing jump point: unused Health data → personal indexes → ARIA
/// conversation about how you're doing → first mosaic win.
///
/// One gesture per beat, in the real UI, never blocking. Adaptation lives
/// here so Linux `swift test` can lock it. National ranking is not a beat —
/// Forge does not score the person against everyone.
public enum ForgeTutorial: Sendable {

    public static let storageKey = "forge.tutorial.potential.v2"
    public static let nailSeconds: Double = 1.8
    public static let hesitateSeconds: Double = 6.0

    /// Four-act teaching, adapted to day-to-day life (sleep, work, stress,
    /// movement, habits) rather than a game. Optional beats skip when the
    /// user nails the previous one or already performed a later gesture.
    public enum Beat: String, Codable, CaseIterable, Sendable {
        case welcome
        case seeHistory
        case personalIndex
        case askAria
        case mosaicWin
        case done

        public var isOptional: Bool {
            self == .personalIndex
        }

        public var index: Int {
            Self.teachingOrder.firstIndex(of: self) ?? Self.teachingOrder.count
        }

        public static let teachingOrder: [Beat] = [
            .welcome, .seeHistory, .personalIndex, .askAria, .mosaicWin, .done,
        ]

        public var prompt: String {
            switch self {
            case .welcome:
                return "Your Health data has been sitting unused — nowhere near its potential. Forge makes it work for how you already live. Tap Got it."
            case .seeHistory:
                return "Open Progress. That's nights, movement, work, stress, habits — sitting there. Untapped, not a verdict."
            case .personalIndex:
                return "Read a tile. That's your index, from your own days — not a BMI headline, not a one-size score."
            case .askAria:
                return "Ask ARIA how you're doing. She talks with you — light, warm, adult. How you live is the curriculum."
            case .mosaicWin:
                return "First win is a tile that fits this week. Tap it. Sleep, work, stress, movement, habits are one picture."
            case .done:
                return "Forge learns how you live and builds on it. Skip was always here."
            }
        }

        public var voiceOverHint: String {
            switch self {
            case .welcome:
                return "Double tap Got it to begin. Skip is available."
            case .seeHistory:
                return "Double tap the Progress tab at the bottom of the screen."
            case .personalIndex:
                return "Swipe to a mosaic tile and hear its name, number, and fill. That number is yours."
            case .askAria:
                return "Double tap Ask ARIA about this picture."
            case .mosaicWin:
                return "Double tap a mosaic tile to take the first win."
            case .done:
                return "Tutorial complete."
            }
        }

        public var target: Target {
            switch self {
            case .welcome: return .acknowledge
            case .seeHistory: return .tabProgress
            case .personalIndex: return .mosaicTile
            case .askAria: return .askAria
            case .mosaicWin: return .mosaicTile
            case .done: return .none
            }
        }
    }

    public enum Target: String, Sendable {
        case acknowledge
        case tabProgress
        case mosaicTile
        case askAria
        case none
    }

    public enum Gesture: String, Sendable {
        case skip
        case acknowledge
        case openedProgress
        case focusedTile
        case askedAria
        case expandedTile
        case hesitated
    }

    public struct State: Codable, Equatable, Sendable {
        public var beat: Beat
        public var nailStreak: Int
        public var hesitateStreak: Int
        public var usingDemoMosaic: Bool
        public var rehint: Bool
        public var winPulse: Int

        public var isComplete: Bool { beat == .done }

        public init(
            beat: Beat = .welcome,
            nailStreak: Int = 0,
            hesitateStreak: Int = 0,
            usingDemoMosaic: Bool = false,
            rehint: Bool = false,
            winPulse: Int = 0
        ) {
            self.beat = beat
            self.nailStreak = nailStreak
            self.hesitateStreak = hesitateStreak
            self.usingDemoMosaic = usingDemoMosaic
            self.rehint = rehint
            self.winPulse = winPulse
        }
    }

    public struct Outcome: Equatable, Sendable {
        public var state: State
        public var rewarded: Bool
        public var skippedAhead: Bool
        public var rehint: Bool
    }

    /// Seeded mosaic used when Health has nothing yet. Honest demo, not fake
    /// clinical data — partial fills, one empty track.
    public static let demoMosaicInput = StatsMosaic.Input(
        sleepHours: 7.2,
        sleepGoalHours: 8,
        sleepManual: false,
        workoutsThisWeek: 2,
        workoutGoal: 3,
        waterGlasses: 6,
        waterGoal: 8,
        waterManual: true,
        steps: 6_400,
        stepGoal: 8_000,
        stepsManual: false,
        habitsDone: 0,
        habitsGoal: 3
    )

    public static func start(hasRealMosaicData: Bool) -> State {
        State(usingDemoMosaic: !hasRealMosaicData)
    }

    public static func hasRealMosaicData(_ snapshot: StatsMosaic.Snapshot) -> Bool {
        snapshot.tiles.contains { $0.source != .empty }
    }

    /// Core adapter. Never blocks: unknown gestures are ignored.
    public static func apply(
        state: State,
        gesture: Gesture,
        latency: Double
    ) -> Outcome {
        var next = state
        next.rehint = false

        if next.isComplete {
            return Outcome(state: next, rewarded: false, skippedAhead: false, rehint: false)
        }

        if gesture == .skip {
            next.beat = .done
            next.rehint = false
            return Outcome(state: next, rewarded: false, skippedAhead: false, rehint: false)
        }

        if gesture == .hesitated {
            next.rehint = true
            next.hesitateStreak += 1
            next.nailStreak = 0
            return Outcome(state: next, rewarded: false, skippedAhead: false, rehint: true)
        }

        guard let matched = matchedBeat(for: gesture) else {
            return Outcome(state: next, rewarded: false, skippedAhead: false, rehint: false)
        }

        if matched.index < next.beat.index {
            return Outcome(state: next, rewarded: false, skippedAhead: false, rehint: false)
        }

        let nailed = latency <= nailSeconds
        let skippedAhead = matched.index > next.beat.index
        if nailed {
            next.nailStreak += 1
            next.hesitateStreak = 0
        } else {
            next.nailStreak = 0
        }

        let skipOptional = nailed || skippedAhead || next.nailStreak >= 1
        next.beat = successor(after: matched, skipOptional: skipOptional)
        next.winPulse += 1
        return Outcome(state: next, rewarded: true, skippedAhead: skippedAhead, rehint: false)
    }

    public static func successor(after beat: Beat, skipOptional: Bool) -> Beat {
        let order = Beat.teachingOrder
        guard let idx = order.firstIndex(of: beat) else { return .done }
        var i = idx + 1
        while i < order.count {
            let candidate = order[i]
            if candidate == .done { return .done }
            if skipOptional && candidate.isOptional {
                i += 1
                continue
            }
            return candidate
        }
        return .done
    }

    public static func matchedBeat(for gesture: Gesture) -> Beat? {
        switch gesture {
        case .acknowledge: return .welcome
        case .openedProgress: return .seeHistory
        case .focusedTile: return .personalIndex
        case .askedAria: return .askAria
        case .expandedTile: return .mosaicWin
        case .skip, .hesitated: return nil
        }
    }

    public static func mosaic(for state: State, live: StatsMosaic.Snapshot) -> StatsMosaic.Snapshot {
        if state.usingDemoMosaic || !hasRealMosaicData(live) {
            return StatsMosaic.snapshot(demoMosaicInput)
        }
        return live
    }
}
