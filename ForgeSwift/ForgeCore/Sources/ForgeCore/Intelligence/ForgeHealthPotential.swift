import Foundation

/// The tutorial / Home jump-point: unused Health history → personal indexes
/// (this person's baselines; BMI is never the headline) → ARIA conversation
/// about how they're doing → mosaic win.
///
/// Coach copy only. No diagnosis. No "recovery". No shame. No ranking
/// against a national average in this picture — that comparison is not how
/// Forge talks to people.
public enum ForgeHealthPotential: Sendable {

    public struct History: Equatable, Sendable {
        public var name: String
        public var sleepHours: [Double]
        public var steps: [Double]
        public var workoutsThisWeek: Int
        public var workoutGoal: Int
        public var waterGlasses: Double?
        public var habitsDone: Int
        public var habitsGoal: Int
        public var weightKg: Double?
        public var heightCm: Double?

        public init(
            name: String = "",
            sleepHours: [Double] = [],
            steps: [Double] = [],
            workoutsThisWeek: Int = 0,
            workoutGoal: Int = 3,
            waterGlasses: Double? = nil,
            habitsDone: Int = 0,
            habitsGoal: Int = 3,
            weightKg: Double? = nil,
            heightCm: Double? = nil
        ) {
            self.name = name
            self.sleepHours = sleepHours
            self.steps = steps
            self.workoutsThisWeek = workoutsThisWeek
            self.workoutGoal = workoutGoal
            self.waterGlasses = waterGlasses
            self.habitsDone = habitsDone
            self.habitsGoal = habitsGoal
            self.weightKg = weightKg
            self.heightCm = heightCm
        }

        public var hasHealthHistory: Bool {
            sleepHours.contains { $0 > 0 } || steps.contains { $0 > 0 }
        }
    }

    public struct Index: Equatable, Sendable, Identifiable {
        public var id: String
        public var title: String
        public var personalLine: String
    }

    public struct Picture: Equatable, Sendable {
        public var unusedLine: String
        public var indexes: [Index]
        public var howYoureDoing: String
        public var mosaicInput: StatsMosaic.Input
        public var firstWinLine: String
        public var usingDemoMosaic: Bool
        public var clinicianLine: String
        /// Quiet BMI / standard-category note. Nil unless the caller drills in.
        /// Never placed in `indexes` or tutorial prompts.
        public var backgroundReference: String?
    }

    public static let clinicianLine =
        "Lifestyle coaching only — not a diagnosis. Anything medical, run past a doctor."

    public static func picture(from history: History, includeBackground: Bool = false) -> Picture {
        let who = ForgePersonalization.firstName(from: history.name)
        let unused = unusedLine(history: history, who: who)
        let indexes = personalIndexes(history: history)
        let demo = !history.hasHealthHistory
        let mosaic = mosaicInput(history: history, demo: demo)
        let win = firstWinLine(history: history, mosaic: StatsMosaic.snapshot(mosaic), who: who)
        let doing = howYoureDoing(history: history, who: who)
        let background = includeBackground ? bmiBackground(kg: history.weightKg, cm: history.heightCm) : nil
        return Picture(
            unusedLine: unused,
            indexes: indexes,
            howYoureDoing: doing,
            mosaicInput: mosaic,
            firstWinLine: win,
            usingDemoMosaic: demo,
            clinicianLine: clinicianLine,
            backgroundReference: background
        )
    }

    // MARK: - Act 1: unused potential (never shame)

    public static func unusedLine(history: History, who: String) -> String {
        let nights = history.sleepHours.filter { $0 > 0 }.count
        let stepDays = history.steps.filter { $0 > 0 }.count
        let named = who.isEmpty ? "This phone" : "\(who), this phone"
        if nights == 0 && stepDays == 0 {
            return "\(named) has Health sitting quiet. When nights and steps land, Forge will put them to work — how you already live, not a spreadsheet of you. Until then, a seeded mosaic shows how the tiles fill."
        }
        var bits: [String] = []
        if nights > 0 {
            let mean = average(history.sleepHours)
            bits.append("\(nights) night\(nights == 1 ? "" : "s") averaging \(fmt(mean, 1)) hours")
        }
        if stepDays > 0 {
            bits.append("\(stepDays) day\(stepDays == 1 ? "" : "s") of steps")
        }
        return "\(named) already has \(bits.joined(separator: " and ")). That picture has been sitting unused. Forge turns it into a way to optimize the life you already have — sleep, work, stress, movement, habits."
    }

    // MARK: - Act 2: personal indexes (own baselines; BMI never headlines)

    public static func personalIndexes(history: History) -> [Index] {
        var rows: [Index] = []
        if let sleep = sleepIndex(history) { rows.append(sleep) }
        if let move = moveIndex(history) { rows.append(move) }
        rows.append(trainIndex(history))
        return rows
    }

    private static func sleepIndex(_ history: History) -> Index? {
        let nights = history.sleepHours.filter { $0 > 0 }
        guard !nights.isEmpty else { return nil }
        let mean = average(nights)
        let baseline = PersonalBaseline.fromDailyValues(nights, logScaled: false, minimumDays: 5)
        let last = nights.last ?? mean
        let vsSelf: String
        if let baseline, let z = baseline.zScore(last, floor: 0.15, ceiling: 1.5) {
            if abs(z) < 0.4 {
                vsSelf = "Last night sits on your own \(baseline.days)-night line (\(fmt(baseline.mean, 1)) h)."
            } else if z > 0 {
                vsSelf = "Last night is \(fmt(z, 1)) above your own \(baseline.days)-night line — extra in the bank, not a trophy."
            } else {
                vsSelf = "Last night is \(fmt(-z, 1)) below your own \(baseline.days)-night line. That's a signal for tonight, not a failing grade."
            }
        } else {
            vsSelf = "Your nights average \(fmt(mean, 1)) h across \(nights.count) reads. We'll index to you as the week fills — not a one-size chart."
        }
        return Index(id: "sleep", title: "Your night index", personalLine: vsSelf)
    }

    private static func moveIndex(_ history: History) -> Index? {
        let days = history.steps.filter { $0 > 0 }
        guard !days.isEmpty else { return nil }
        let mean = average(days)
        let baseline = PersonalBaseline.fromDailyValues(days, logScaled: false, minimumDays: 5)
        let vsSelf: String
        if let baseline {
            vsSelf = "Your move index is \(Int(mean.rounded())) steps against your own \(baseline.days)-day center of \(Int(baseline.mean.rounded()))."
        } else {
            vsSelf = "\(days.count) day\(days.count == 1 ? "" : "s") of steps, averaging \(Int(mean.rounded())). That's your line, not a 10k slogan."
        }
        return Index(id: "move", title: "Your move index", personalLine: vsSelf)
    }

    private static func trainIndex(_ history: History) -> Index {
        let goal = max(1, history.workoutGoal)
        let done = max(0, history.workoutsThisWeek)
        let line: String
        if done == 0 {
            line = "No session this week yet. The week is still open — one honest session is the index, not a streak badge."
        } else {
            line = "\(done) of \(goal) sessions this week. That's your training index, sized to this week."
        }
        return Index(id: "train", title: "Your training index", personalLine: line)
    }

    // MARK: - Act 3: how you're doing (ARIA conversation, not a dashboard rank)

    public static func howYoureDoing(history: History, who: String) -> String {
        let named = who.isEmpty ? "You" : who
        if !history.hasHealthHistory {
            return "\(named) — how you're doing lives in this conversation. Forge will learn your ecosystem as nights and movement land. Ask ARIA; she coaches the life you have."
        }
        return "\(named) — how you're doing comes first, and it lives here with ARIA: sleep, work, stress, movement, habits as one ecosystem. Not a rank against everyone. Forge adapts to how you already live."
    }

    // MARK: - Quiet background (drill-in only)

    /// CDC adult BMI categories as quiet context. Never a headline. Omit when
    /// height/weight are missing.
    public static func bmiBackground(kg: Double?, cm: Double?) -> String? {
        guard let kg, let cm, kg > 0, cm > 0 else { return nil }
        let meters = cm / 100
        let bmi = kg / (meters * meters)
        let band: String
        switch bmi {
        case ..<18.5: band = "under 18.5"
        case 18.5..<25: band = "18.5–24.9"
        case 25..<30: band = "25.0–29.9"
        default: band = "30.0+"
        }
        return "Background reference only — BMI \(fmt(bmi, 1)) sits in the standard adult \(band) band (CDC). This is not how Forge measures you."
    }

    // MARK: - Act 4: mosaic first win

    public static func mosaicInput(history: History, demo: Bool) -> StatsMosaic.Input {
        if demo { return ForgeTutorial.demoMosaicInput }
        let lastSleep = history.sleepHours.last
        let lastSteps = history.steps.last.map { Int($0.rounded()) }
        return StatsMosaic.Input(
            sleepHours: lastSleep,
            sleepManual: false,
            workoutsThisWeek: history.workoutsThisWeek,
            workoutGoal: max(1, history.workoutGoal),
            waterGlasses: history.waterGlasses,
            waterManual: false,
            steps: lastSteps,
            stepsManual: false,
            habitsDone: history.habitsDone,
            habitsGoal: max(1, history.habitsGoal)
        )
    }

    public static func firstWinLine(history: History, mosaic: StatsMosaic.Snapshot, who: String) -> String {
        let named = who.isEmpty ? "You" : who
        if let open = mosaic.tiles.first(where: { $0.source == .empty || $0.progress < 1 }) {
            return "\(named): first win is filling \(open.track.title) — tap that tile. Sleep, work, stress, movement, habits are the same picture."
        }
        return "\(named): the mosaic is full. First win is asking ARIA what to protect tomorrow — not a new score."
    }

    public static func containsBanned(_ line: String) -> Bool {
        let lower = line.lowercased()
        if lower.contains("don't worry") || lower.contains("do not worry") { return true }
        if lower.contains("national average") { return true }
        if lower.contains("percentile") { return true }
        return ForgePersonalization.containsBannedCopy(line)
    }

    /// Tutorial-facing lines must never lead with BMI.
    public static func tutorialLeadsWithBMI(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.hasPrefix("bmi") || lower.contains("your bmi")
    }

    private static func average(_ values: [Double]) -> Double {
        let real = values.filter { $0 > 0 }
        guard !real.isEmpty else { return 0 }
        return real.reduce(0, +) / Double(real.count)
    }

    private static func fmt(_ value: Double, _ digits: Int) -> String {
        String(format: "%.\(digits)f", value)
    }
}
