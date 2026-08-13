import Foundation

// ============================================================
// MARK: - Daily water need
// ============================================================

/// How much water this person actually needs today, and whether they are on
/// pace to drink it.
///
/// The "eight glasses" rule is a slogan, not a measurement. Need scales with
/// body mass, rises with work already done, and ticks up in the luteal phase
/// and during a period. Evening is a taper, not a catch-up: slamming the
/// remaining target at 10pm just fragments sleep.
///
/// Pure arithmetic over numbers, deliberately, so the target and the pace
/// line are testable without HealthKit.
public enum HydrationEngine {

    /// Midpoint of the commonly cited 30–35 ml/kg range.
    public static let millilitersPerKilogram = 33.0
    /// One US cup. Kept as a display unit, not as the model of need.
    public static let glassMilliliters = 237.0
    public static let millilitersPerFluidOunce = 29.5735

    public static let minimumTargetMilliliters = 1_500.0
    public static let maximumTargetMilliliters = 5_000.0
    public static let defaultWeightKilograms = 70.0

    /// Extra milliliters when progesterone raises core temperature.
    public static let lutealBonusMilliliters = 200.0
    /// Extra milliliters across a bleed — fluid loss plus the usual advice.
    public static let menstruationBonusMilliliters = 300.0

    /// Hours after wake before the pace line starts, and hours before onset
    /// when it should already be finished.
    public static let morningRampHours = 0.5
    public static let eveningTaperHours = 2.0

    public enum CycleAdjustment: String, Equatable, Sendable {
        case none
        case luteal
        case menstruation
    }

    public enum Status: String, Equatable, Sendable {
        case behind
        case onTrack
        case met
        case over
    }

    public struct Preset: Equatable, Sendable, Identifiable {
        public let id: String
        public let title: String
        public let milliliters: Double
        public let symbolName: String

        public init(id: String, title: String, milliliters: Double, symbolName: String) {
            self.id = id
            self.title = title
            self.milliliters = milliliters
            self.symbolName = symbolName
        }
    }

    /// The four sizes people actually pour. Glasses first because that is
    /// what the Lifestyle card still logs in one tap.
    public static let presets: [Preset] = [
        Preset(id: "glass", title: "Glass", milliliters: 250, symbolName: "cup.and.saucer.fill"),
        Preset(id: "small", title: "Small bottle", milliliters: 350, symbolName: "drop.circle"),
        Preset(id: "bottle", title: "Bottle", milliliters: 500, symbolName: "drop.circle.fill"),
        Preset(id: "large", title: "Large", milliliters: 750, symbolName: "jug.fill"),
    ]

    // ------------------------------------------------------------
    // MARK: Target
    // ------------------------------------------------------------

    /// Today's need in milliliters.
    ///
    /// `activeCalories` adds 1 ml per kcal already burned — a 500 kcal session
    /// is half a litre, which is the usual gym-floor advice without pretending
    /// we measured sweat rate. Capped so a long ride cannot push the target
    /// into "drink a gallon" territory.
    public static func targetMilliliters(
        weightKilograms: Double?,
        activeCalories: Double = 0,
        cycle: CycleAdjustment = .none,
        hotEnvironment: Bool = false
    ) -> Double {
        let mass = max(35, weightKilograms ?? defaultWeightKilograms)
        let base = mass * millilitersPerKilogram
        let activity = min(1_200, max(0, activeCalories))
        let heat = hotEnvironment ? 400.0 : 0
        let cycleBonus: Double = {
            switch cycle {
            case .none: return 0
            case .luteal: return lutealBonusMilliliters
            case .menstruation: return menstruationBonusMilliliters
            }
        }()
        return min(maximumTargetMilliliters,
                   max(minimumTargetMilliliters, base + activity + heat + cycleBonus))
    }

    public static func glasses(fromMilliliters ml: Double) -> Double {
        ml / glassMilliliters
    }

    public static func milliliters(fromGlasses glasses: Double) -> Double {
        glasses * glassMilliliters
    }

    public static func milliliters(fromFluidOunces ounces: Double) -> Double {
        ounces * millilitersPerFluidOunce
    }

    public static func fluidOunces(fromMilliliters ml: Double) -> Double {
        ml / millilitersPerFluidOunce
    }

    // ------------------------------------------------------------
    // MARK: Pace
    // ------------------------------------------------------------

    /// How much of today's target should already be in by `hour`, given a
    /// wake and a bedtime. The line is flat overnight, climbs across the
    /// waking day, and is finished `eveningTaperHours` before onset so the
    /// last drinks are not happening in bed.
    public static func expectedMilliliters(
        atHour hour: Double,
        target: Double,
        wakeHour: Double = 7,
        onsetHour: Double = 23
    ) -> Double {
        let now = normalizedHour(hour)
        let wake = normalizedHour(wakeHour)
        let onset = normalizedHour(onsetHour)
        let sinceWake = normalizedHour(now - wake)
        let awakeSpan = normalizedHour(onset - wake)
        let drinkSpan = max(1, awakeSpan - morningRampHours - eveningTaperHours)

        if sinceWake < morningRampHours { return 0 }
        if sinceWake >= morningRampHours + drinkSpan { return target }
        let progressed = (sinceWake - morningRampHours) / drinkSpan
        return target * min(1, max(0, progressed))
    }

    public static func status(
        consumed: Double,
        target: Double,
        expected: Double
    ) -> Status {
        guard target > 0 else { return .onTrack }
        if consumed >= target * 1.15 { return .over }
        if consumed >= target { return .met }
        if consumed + 80 >= expected * 0.85 { return .onTrack }
        return .behind
    }

    /// One line on what to do with the rest of the day. Written as guidance,
    /// not a scolding — the model does not know about a long meeting.
    public static func guidance(
        status: Status,
        remaining: Double,
        hoursUntilOnset: Double
    ) -> String {
        let left = max(0, remaining)
        switch status {
        case .met:
            return "Need is covered. Sip if you are thirsty; there is nothing to catch up."
        case .over:
            return "Past today's need. Extra water is fine, but the next litre will not do extra work."
        case .onTrack:
            if hoursUntilOnset <= eveningTaperHours {
                return "On pace, and the evening taper has started. Small sips only from here."
            }
            return "On pace. Keep a bottle in reach and this finishes itself."
        case .behind:
            if hoursUntilOnset <= eveningTaperHours {
                return "Still short, but it is late to chase the number. A small glass, then stop."
            }
            let glasses = max(1, Int((left / glassMilliliters).rounded(.up)))
            return "About \(glasses) glass\(glasses == 1 ? "" : "es") behind the day's pace. Spread them, do not chug."
        }
    }

    // ------------------------------------------------------------
    // MARK: Clock
    // ------------------------------------------------------------

    public static func hourOfDay(_ date: Date, calendar: Calendar = .current) -> Double {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60.0
    }

    public static func normalizedHour(_ hour: Double) -> Double {
        let wrapped = hour.truncatingRemainder(dividingBy: 24)
        return wrapped < 0 ? wrapped + 24 : wrapped
    }
}
