import Foundation

/// First-launch walk-through of every Forge surface. Learn-by-doing, Skip
/// always available. ARIA orients — never pitches.
public enum ForgeTutorial: Sendable {

    public static let storageKey = "forge.tutorial.potential.v3"
    public static let nailSeconds: Double = 1.8
    public static let hesitateSeconds: Double = 6.0

    public enum Opening: String, Codable, CaseIterable, Sendable {
        case beginner
        case everyday
        case competitor

        public static func resolve(experience: String, goals: [String]) -> Opening {
            let exp = experience.lowercased()
            let blob = (goals.joined(separator: " ") + " " + exp).lowercased()
            if exp.contains("beginner") || exp.contains("new") {
                return .beginner
            }
            if exp.contains("elite") || exp.contains("advanced")
                || blob.contains("competition") || blob.contains("pr ")
                || blob.contains("personal record") || blob.contains("race") {
                return .competitor
            }
            return .everyday
        }

        public var welcome: String {
            switch self {
            case .beginner:
                return "You downloaded Forge. I'll show you what I can actually do for you — no jargon. Home is the picture of your day. Tap Got it."
            case .competitor:
                return "You downloaded Forge. I'll walk the surfaces that keep load, sleep and the next session honest — not a sales pitch. Tap Got it."
            case .everyday:
                return "You downloaded Forge. Here's what I can really do for you, screen by screen. Tap Got it."
            }
        }
    }

    public enum Beat: String, Codable, CaseIterable, Sendable {
        case welcome
        case home
        case sleep
        case seeHistory
        case personalIndex
        case train
        case askAria
        case hobbyFit
        case lifestyle
        case trainingModel
        case settings
        case watchWidgets
        case mosaicWin
        case done

        public var isOptional: Bool {
            self == .personalIndex || self == .watchWidgets
        }

        public var index: Int {
            Self.teachingOrder.firstIndex(of: self) ?? Self.teachingOrder.count
        }

        public static let teachingOrder: [Beat] = [
            .welcome, .home, .sleep, .seeHistory, .personalIndex, .train,
            .askAria, .hobbyFit, .lifestyle, .trainingModel, .settings,
            .watchWidgets, .mosaicWin, .done,
        ]

        public func prompt(opening: Opening = .everyday) -> String {
            switch self {
            case .welcome:
                return opening.welcome
            case .home:
                return "Home is the day at a glance — readiness, the mosaic, one next move. That's how you start without hunting."
            case .sleep:
                return "Sleep is last night and the night ahead. I use it to size the day — not to grade you."
            case .seeHistory:
                return "Open Progress. That's nights, movement, work, stress, habits — sitting there. Untapped, not a verdict."
            case .personalIndex:
                return "Read a tile. That's your index, from your own days — not a BMI headline, not a one-size score."
            case .train:
                return "Train is the session hub. Exercises that fit the gym and gear you actually have. I never coach form."
            case .askAria:
                return "Ask ARIA how you're doing. I talk with you — light, warm, adult. How you live is the curriculum."
            case .hobbyFit:
                return "Hobby Fit is the free-day picture. A quiet stretch or a night out still counts as the life we're coaching."
            case .lifestyle:
                return "Lifestyle is sleep, food, stress and people weighted for you. Movement is one tile, not the product."
            case .trainingModel:
                return "Your adaptive training model is your words. I coach against that — mindset and method, never form, never past comfort."
            case .settings:
                return "Settings is personalization and Aria's memory. You can see, edit or delete anything I remember."
            case .watchWidgets:
                return "Watch and widgets, if you use them, show the same picture — glanceable, not a second app."
            case .mosaicWin:
                return "First win is a tile that fits this week. Tap it. Sleep, work, stress, movement, habits are one picture."
            case .done:
                return "That's the tour. Skip was always here. Ask me anything when you want."
            }
        }

        public var prompt: String { prompt(opening: .everyday) }

        public var voiceOverHint: String {
            switch self {
            case .welcome: return "Double tap Got it to begin. Skip is available."
            case .home: return "You are on Home. Double tap Got it, or Skip."
            case .sleep: return "Double tap the Sleep tab."
            case .seeHistory: return "Double tap the Progress tab at the bottom of the screen."
            case .personalIndex: return "Swipe to a mosaic tile and hear its name, number, and fill."
            case .train: return "Double tap the Train tab."
            case .askAria: return "Double tap Ask ARIA about this picture."
            case .hobbyFit: return "Double tap Lifestyle, then Hobby Fit."
            case .lifestyle: return "Double tap the Lifestyle tab."
            case .trainingModel: return "Open Settings, then Adaptive training model."
            case .settings: return "Double tap You, then Settings."
            case .watchWidgets: return "Optional. Skip if you don't use Watch or widgets."
            case .mosaicWin: return "Double tap a mosaic tile to take the first win."
            case .done: return "Tutorial complete."
            }
        }

        public var target: Target {
            switch self {
            case .welcome, .home: return .acknowledge
            case .sleep: return .tabSleep
            case .seeHistory: return .tabProgress
            case .personalIndex, .mosaicWin: return .mosaicTile
            case .train: return .tabTrain
            case .askAria: return .askAria
            case .hobbyFit, .lifestyle: return .tabLifestyle
            case .trainingModel, .settings: return .tabYou
            case .watchWidgets: return .acknowledge
            case .done: return .none
            }
        }
    }

    public enum Target: String, Sendable {
        case acknowledge
        case tabSleep
        case tabProgress
        case tabTrain
        case tabLifestyle
        case tabYou
        case mosaicTile
        case askAria
        case none
    }

    public enum Gesture: String, Sendable {
        case skip
        case acknowledge
        case openedHome
        case openedSleep
        case openedProgress
        case focusedTile
        case openedTrain
        case askedAria
        case openedHobbyFit
        case openedLifestyle
        case openedTrainingModel
        case openedSettings
        case openedWatch
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
        public var opening: Opening
        public var ariaPaused: Bool

        public var isComplete: Bool { beat == .done }

        public init(
            beat: Beat = .welcome,
            nailStreak: Int = 0,
            hesitateStreak: Int = 0,
            usingDemoMosaic: Bool = false,
            rehint: Bool = false,
            winPulse: Int = 0,
            opening: Opening = .everyday,
            ariaPaused: Bool = false
        ) {
            self.beat = beat
            self.nailStreak = nailStreak
            self.hesitateStreak = hesitateStreak
            self.usingDemoMosaic = usingDemoMosaic
            self.rehint = rehint
            self.winPulse = winPulse
            self.opening = opening
            self.ariaPaused = ariaPaused
        }
    }

    public struct Outcome: Equatable, Sendable {
        public var state: State
        public var rewarded: Bool
        public var skippedAhead: Bool
        public var rehint: Bool
    }

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

    public static func start(
        hasRealMosaicData: Bool,
        experience: String = "",
        goals: [String] = [],
        ariaPaused: Bool = false
    ) -> State {
        State(
            usingDemoMosaic: !hasRealMosaicData,
            opening: Opening.resolve(experience: experience, goals: goals),
            ariaPaused: ariaPaused
        )
    }

    public static func hasRealMosaicData(_ snapshot: StatsMosaic.Snapshot) -> Bool {
        snapshot.tiles.contains { $0.source != .empty }
    }

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

        let matched: Beat
        if gesture == .acknowledge {
            if next.beat.target == .acknowledge {
                matched = next.beat
            } else {
                return Outcome(state: next, rewarded: false, skippedAhead: false, rehint: false)
            }
        } else if let hit = matchedBeat(for: gesture) {
            matched = hit
        } else {
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
        case .openedHome: return .home
        case .openedSleep: return .sleep
        case .openedProgress: return .seeHistory
        case .focusedTile: return .personalIndex
        case .openedTrain: return .train
        case .askedAria: return .askAria
        case .openedHobbyFit: return .hobbyFit
        case .openedLifestyle: return .lifestyle
        case .openedTrainingModel: return .trainingModel
        case .openedSettings: return .settings
        case .openedWatch: return .watchWidgets
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

    public static let pausedLine =
        "ARIA is taking a break. You can keep walking the app, or Skip."
}
