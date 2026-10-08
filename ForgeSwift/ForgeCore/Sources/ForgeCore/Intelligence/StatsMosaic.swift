import Foundation

/// Progress mosaic — five lifestyle tracks ARIA can read as one picture.
///
/// Sleep, Train, Water, Move, Habits. Not a medical score. Copy must never
/// diagnose, treat, prescribe, or claim a clinical read. Health ingest and
/// manual entry are sources of the same tiles; missing stays honest.
public enum StatsMosaic: Sendable {

    public enum Track: String, CaseIterable, Sendable, Equatable {
        case sleep, train, water, move, habits

        public var title: String {
            switch self {
            case .sleep: return "Sleep"
            case .train: return "Train"
            case .water: return "Water"
            case .move: return "Move"
            case .habits: return "Habits"
            }
        }
    }

    public enum Source: String, Sendable, Equatable {
        case health
        case manual
        case empty
    }

    public struct Input: Equatable, Sendable {
        public var sleepHours: Double?
        public var sleepGoalHours: Double
        public var sleepManual: Bool
        public var workoutsThisWeek: Int
        public var workoutGoal: Int
        public var waterGlasses: Double?
        public var waterGoal: Double
        public var waterManual: Bool
        public var steps: Int?
        public var stepGoal: Int
        public var stepsManual: Bool
        public var habitsDone: Int
        public var habitsGoal: Int

        public init(
            sleepHours: Double? = nil,
            sleepGoalHours: Double = 8,
            sleepManual: Bool = false,
            workoutsThisWeek: Int = 0,
            workoutGoal: Int = 3,
            waterGlasses: Double? = nil,
            waterGoal: Double = 8,
            waterManual: Bool = false,
            steps: Int? = nil,
            stepGoal: Int = 8_000,
            stepsManual: Bool = false,
            habitsDone: Int = 0,
            habitsGoal: Int = 3
        ) {
            self.sleepHours = sleepHours
            self.sleepGoalHours = sleepGoalHours
            self.sleepManual = sleepManual
            self.workoutsThisWeek = workoutsThisWeek
            self.workoutGoal = workoutGoal
            self.waterGlasses = waterGlasses
            self.waterGoal = waterGoal
            self.waterManual = waterManual
            self.steps = steps
            self.stepGoal = stepGoal
            self.stepsManual = stepsManual
            self.habitsDone = habitsDone
            self.habitsGoal = habitsGoal
        }
    }

    public struct Tile: Equatable, Sendable, Identifiable {
        public var track: Track
        public var progress: Double
        public var headline: String
        public var detail: String
        public var source: Source
        public var ariaPrompt: String
        public var almostThere: Bool
        public var id: String { track.rawValue }
    }

    public struct Snapshot: Equatable, Sendable {
        public var tiles: [Tile]
        public var dayPercent: Int
        public var mosaicLine: String
        public var doneCount: Int
        public var almostThereCount: Int
        public var closing: Bool { doneCount == Track.allCases.count - HomeReadinessTokens.closingRemaining }
    }

    public static let bannedMedicalTokens = ["diagnos", "treat", "prescribe", "cure", "medical advice"]

    public static func snapshot(_ input: Input) -> Snapshot {
        let tiles = Track.allCases.map { tile(for: $0, input: input) }
        let filled = tiles.filter { $0.source != .empty }
        let mean = filled.isEmpty ? 0 : filled.map(\.progress).reduce(0, +) / Double(filled.count)
        let percent = Int((mean * 100).rounded())
        let done = tiles.filter { $0.progress >= 1 }.count
        let almost = tiles.filter(\.almostThere).count
        let mosaic = mosaicLine(tiles: tiles, percent: percent, done: done, almost: almost)
        return Snapshot(
            tiles: tiles,
            dayPercent: percent,
            mosaicLine: mosaic,
            doneCount: done,
            almostThereCount: almost
        )
    }

    public static func containsBannedMedical(_ text: String) -> Bool {
        let lower = text.lowercased()
        return bannedMedicalTokens.contains { lower.contains($0) }
    }

    // MARK: - Tiles

    private static func tile(for track: Track, input: Input) -> Tile {
        switch track {
        case .sleep:
            let hours = input.sleepHours
            let goal = max(0.5, input.sleepGoalHours)
            let progress = clamp((hours ?? 0) / goal)
            let source: Source = hours == nil ? .empty : (input.sleepManual ? .manual : .health)
            let headline = hours.map { String(format: "%.1fh", $0) } ?? "—"
            let detail = source == .empty ? "Not in yet" : (input.sleepManual ? "You logged this" : "From Apple Health")
            let fill = hours == nil ? 0 : progress
            return Tile(
                track: .sleep,
                progress: fill,
                headline: headline,
                detail: detail,
                source: source,
                ariaPrompt: "How did I sleep, and what should tonight look like? Lifestyle only.",
                almostThere: HomeReadinessTokens.tileAlmostThere(fill)
            )
        case .train:
            let done = max(0, input.workoutsThisWeek)
            let goal = max(1, input.workoutGoal)
            let progress = clamp(Double(done) / Double(goal))
            let source: Source = done == 0 ? .empty : .health
            return Tile(
                track: .train,
                progress: progress,
                headline: "\(done)/\(goal)",
                detail: done == 0 ? "No session this week — the week is still open." : "Sessions this week",
                source: source,
                ariaPrompt: "What should I train with the body I have today?",
                almostThere: HomeReadinessTokens.tileAlmostThere(progress)
            )
        case .water:
            let glasses = input.waterGlasses
            let goal = max(1, input.waterGoal)
            let progress = clamp((glasses ?? 0) / goal)
            let source: Source = glasses == nil ? .empty : (input.waterManual ? .manual : .health)
            let headline = glasses.map { String(format: "%.0f", $0) } ?? "—"
            let fill = glasses == nil ? 0 : progress
            return Tile(
                track: .water,
                progress: fill,
                headline: headline,
                detail: source == .empty ? "Not in yet" : "of \(Int(goal)) glasses",
                source: source,
                ariaPrompt: "How is my water today, and when should I drink next?",
                almostThere: HomeReadinessTokens.tileAlmostThere(fill)
            )
        case .move:
            let steps = input.steps
            let goal = max(1, input.stepGoal)
            let progress = clamp(Double(steps ?? 0) / Double(goal))
            let source: Source = steps == nil ? .empty : (input.stepsManual ? .manual : .health)
            let headline = steps.map { compact($0) } ?? "—"
            let fill = steps == nil ? 0 : progress
            return Tile(
                track: .move,
                progress: fill,
                headline: headline,
                detail: source == .empty ? "Not in yet" : "of \(compact(goal)) steps",
                source: source,
                ariaPrompt: "How did I move today, and what’s one walk that still fits?",
                almostThere: HomeReadinessTokens.tileAlmostThere(fill)
            )
        case .habits:
            let done = max(0, input.habitsDone)
            let goal = max(1, input.habitsGoal)
            let progress = clamp(Double(done) / Double(goal))
            let source: Source = done == 0 ? .empty : .manual
            return Tile(
                track: .habits,
                progress: progress,
                headline: "\(done)/\(goal)",
                detail: done == 0 ? "Nothing marked — still open." : "Marked today",
                source: source,
                ariaPrompt: "Which habit still fits today — nights, move, or staying close?",
                almostThere: HomeReadinessTokens.tileAlmostThere(progress)
            )
        }
    }

    private static func mosaicLine(tiles: [Tile], percent: Int, done: Int, almost: Int) -> String {
        let bits = tiles.map { "\($0.track.title) \($0.headline)" }.joined(separator: ", ")
        if done == Track.allCases.count {
            return "Today’s mosaic — ring closed. \(bits). Lifestyle coaching only — not a clinical score."
        }
        if almost > 0 || done == Track.allCases.count - HomeReadinessTokens.closingRemaining {
            return "Today’s mosaic — \(percent)% of the day picture, \(done) of 5 tracks filled, \(almost) almost there. \(bits). Lifestyle coaching only — not a clinical score."
        }
        return "Today’s mosaic — \(percent)% of the day picture, \(done) of 5 tracks filled. \(bits). Lifestyle coaching only — not a clinical score."
    }

    private static func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    private static func compact(_ value: Int) -> String {
        if value >= 1000 {
            return String(format: "%.1fk", Double(value) / 1000)
        }
        return String(value)
    }
}
