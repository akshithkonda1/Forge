import Foundation

// ============================================================
// MARK: - Sleep debt and the energy curve
// ============================================================

/// Predicts when you will feel alert and when you will not, from your own sleep
/// history.
///
/// This is the two-process model (Borbély, 1982), which is the actual science
/// under every "energy schedule" feature: alertness is the difference between a
/// homeostatic pressure that builds the longer you are awake, and a circadian
/// rhythm that runs on its own ~24-hour clock regardless. Neither alone explains
/// a day — pressure cannot say why 3am is worse than 3pm after the same hours
/// awake, and the rhythm alone cannot say why a night awake feels worse each
/// hour. The afternoon dip is a third thing, added explicitly; see `dipDepth`.
///
/// Everything is derived from the user's own nights. There is no questionnaire
/// and no chronotype quiz: mid-sleep time is the standard phase marker, and we
/// already have it from HealthKit.
///
/// Pure arithmetic over dates, deliberately, so the whole thing is testable
/// without a device — which matters more here than usual, because the failure
/// mode of a wrong phase estimate is confidently telling someone to go to bed at
/// the wrong time.
public enum CircadianRhythm {

    // ------------------------------------------------------------
    // MARK: Tunables
    // ------------------------------------------------------------

    /// Time constants for process S. Rise is slow (you can stay up), decay is
    /// fast (sleep pays down pressure quickly). Standard values from the
    /// literature rather than fitted here — we do not have the data to fit them
    /// per person, and pretending otherwise would be false precision.
    static let pressureRiseHours = 18.2
    static let pressureDecayHours = 4.2

    /// The circadian alertness minimum sits roughly two hours before habitual
    /// wake — close to core body temperature minimum. Everything else in the day
    /// is positioned relative to this.
    static let nadirHoursBeforeWake = 2.0

    /// Melatonin onset is about two hours before habitual sleep onset. The
    /// window between them is the one genuinely actionable moment in the day:
    /// bright light here is what pushes a schedule later.
    static let melatoninLeadHours = 2.0

    /// Where the afternoon dip sits relative to habitual wake, how wide it is,
    /// and how far it pulls the curve down.
    ///
    /// This is the one term here that is empirical rather than derived, and it
    /// is worth being plain about why. The two-process model does not produce a
    /// mid-afternoon slump on its own: process S is monotonic, a single-harmonic
    /// process C is unimodal, and their combination therefore climbs smoothly
    /// from wake to an evening crest. Adding harmonics does not rescue it — the
    /// Daan/Beersma skewed waveform is asymmetric, not bimodal.
    ///
    /// The dip is nonetheless among the best-replicated findings in the
    /// alertness literature (Monk, 2005), survives skipping lunch, and is the
    /// part of the day people most want named. Modelling it explicitly is
    /// honest. Bending a waveform until a slump falls out, and calling that
    /// derivation, is not.
    static let dipHoursAfterWake = 7.5
    static let dipWidthHours = 1.5
    static let dipDepth = 0.30

    /// Physiological bounds on sleep need. Estimating outside this range from
    /// noisy consumer data says more about the sensor than the person.
    static let minSleepNeedHours = 6.5
    static let maxSleepNeedHours = 9.5
    /// Public because it is the default argument of `energy` and `curve`, and a
    /// default argument expression is inlined at the call site — an internal one
    /// would make those functions uncallable from outside the module.
    public static let defaultSleepNeedHours = 8.0

    /// Sleep debt accumulates over a rolling fortnight. Longer and it stops
    /// responding to a good week; shorter and one bad night dominates.
    public static let debtWindowNights = 14

    // ------------------------------------------------------------
    // MARK: Inputs
    // ------------------------------------------------------------

    /// One night, reduced to the three things the model needs.
    public struct Night: Equatable, Sendable {
        public let onset: Date
        public let wake: Date
        /// Actual time asleep, which is not `wake - onset` — time in bed
        /// includes the awake segments.
        public let asleepHours: Double

        public init(onset: Date, wake: Date, asleepHours: Double) {
            self.onset = onset
            self.wake = wake
            self.asleepHours = asleepHours
        }

        /// Mid-sleep, the standard circadian phase marker. Preferred over
        /// bedtime because bedtime is a decision and mid-sleep is closer to
        /// biology.
        public var midSleep: Date {
            Date(timeIntervalSince1970: (onset.timeIntervalSince1970 + wake.timeIntervalSince1970) / 2)
        }
    }

    // ------------------------------------------------------------
    // MARK: Sleep need
    // ------------------------------------------------------------

    /// How much sleep this person actually needs, estimated from their own best
    /// nights.
    ///
    /// Uses a high percentile rather than a mean, because the mean of a
    /// sleep-deprived person's nights is their deprivation, not their need. On
    /// the nights nothing got in the way, people sleep roughly to satiety — so
    /// the upper tail is the better estimator. Clamped to a physiological range
    /// so a single 14-hour flu night does not redefine "need".
    public static func sleepNeedHours(from nights: [Night]) -> Double {
        sleepNeedHours(fromAsleepHours: nights.map(\.asleepHours))
    }

    /// Durations only, for callers whose history carries no bedtimes. Need and
    /// debt are the two figures here that genuinely do not require a phase, and
    /// forcing a caller to fabricate `Night` timestamps to reach them would put
    /// invented dates one refactor away from the phase estimator.
    ///
    /// Oldest first, like everything else here — the trailing window is a
    /// `suffix`.
    public static func sleepNeedHours(fromAsleepHours hours: [Double]) -> Double {
        let durations = hours.filter { $0 > 1 }.sorted()
        // Under a week there is not enough signal; a confident wrong number is
        // worse than the population default.
        guard durations.count >= 5 else { return defaultSleepNeedHours }

        let index = Int((Double(durations.count - 1) * 0.9).rounded())
        let estimate = durations[min(index, durations.count - 1)]
        return min(max(estimate, minSleepNeedHours), maxSleepNeedHours)
    }

    /// Hours of sleep owed, over the trailing window.
    ///
    /// Only shortfalls count. Sleeping an extra hour does not bank credit
    /// against a future late night — the physiology is not symmetric, and a
    /// number that can be "paid forward" invites exactly the behaviour this is
    /// meant to discourage.
    public static func sleepDebtHours(nights: [Night],
                                      need: Double,
                                      window: Int = debtWindowNights) -> Double {
        sleepDebtHours(asleepHours: nights.map(\.asleepHours), need: need, window: window)
    }

    /// Durations only. Oldest first — the window is a `suffix`.
    public static func sleepDebtHours(asleepHours hours: [Double],
                                      need: Double,
                                      window: Int = debtWindowNights) -> Double {
        hours.suffix(window).reduce(0.0) { total, asleep in
            total + max(0, need - asleep)
        }
    }

    // ------------------------------------------------------------
    // MARK: Phase
    // ------------------------------------------------------------

    /// The user's circadian phase, expressed as habitual wake and onset times of
    /// day (hours past local midnight, fractional).
    public struct Phase: Equatable, Sendable {
        public let wakeHour: Double
        public let onsetHour: Double
        /// How much the recent nights agree, 0...1. Low confidence should make
        /// the UI hedge rather than assert.
        public let confidence: Double

        public init(wakeHour: Double, onsetHour: Double, confidence: Double) {
            self.wakeHour = wakeHour
            self.onsetHour = onsetHour
            self.confidence = confidence
        }
    }

    /// Estimate phase from recent nights.
    ///
    /// Averaged as angles, not as numbers. A 23:30 bedtime and a 00:30 bedtime
    /// average to midnight, but naive arithmetic on 23.5 and 0.5 gives noon —
    /// the exact opposite. Every clock-time average here goes through the unit
    /// circle for that reason.
    public static func phase(from nights: [Night],
                             calendar: Calendar = .current) -> Phase? {
        let recent = Array(nights.suffix(debtWindowNights))
        guard !recent.isEmpty else { return nil }

        let wakeHours = recent.map { hourOfDay($0.wake, calendar: calendar) }
        let onsetHours = recent.map { hourOfDay($0.onset, calendar: calendar) }

        let wake = circularMean(wakeHours)
        let onset = circularMean(onsetHours)

        // Spread of wake times is the honest confidence signal: a shift worker
        // has no stable phase and should be told so, not given a curve.
        let spread = circularSpread(wakeHours)
        let confidence = max(0, min(1, 1 - spread / 3.0))

        return Phase(wakeHour: wake, onsetHour: onset, confidence: confidence)
    }

    // ------------------------------------------------------------
    // MARK: The curve
    // ------------------------------------------------------------

    /// Predicted alertness at a moment, 0...1.
    ///
    /// `hoursAwake` drives process S; `hour` drives process C. Sleep debt
    /// depresses the whole curve rather than changing its shape, which is what
    /// being tired actually feels like — the dip is still a dip, everything is
    /// just lower.
    public static func energy(atHour hour: Double,
                              phase: Phase,
                              hoursAwake: Double,
                              sleepDebtHours: Double = 0,
                              sleepNeedHours: Double = defaultSleepNeedHours) -> Double {
        // Process C: cosine peaking in the evening, trough ~2h before wake.
        let nadir = normalizedHour(phase.wakeHour - nadirHoursBeforeWake)
        let radians = (hour - nadir) / 24.0 * 2 * .pi
        var circadian = (1 - cos(radians)) / 2      // 0 at nadir, 1 twelve hours later

        // The afternoon dip, placed by clock offset from wake rather than by
        // `hoursAwake`. That distinction matters: overnight, `hoursAwake` is a
        // decaying residue rather than a real elapsed time, and it sweeps back
        // down through 7.5 in the small hours — anchoring the dip to it would
        // carve a phantom slump into the middle of the night.
        let sinceWake = normalizedHour(hour - phase.wakeHour)
        let fromDipCentre = (sinceWake - dipHoursAfterWake) / dipWidthHours
        circadian -= dipDepth * exp(-fromDipCentre * fromDipCentre / 2)

        // Process S: pressure rises the longer you have been awake, and
        // alertness is what is left over.
        let pressure = 1 - exp(-max(0, hoursAwake) / pressureRiseHours)
        let recovered = 1 - pressure

        // Weighted so neither process can flatten the other out.
        var value = 0.55 * circadian + 0.45 * recovered

        // Debt is expressed relative to need, so eight hours owed means more to
        // someone who needs seven than to someone who needs nine.
        let debtRatio = min(1.5, sleepDebtHours / max(1, sleepNeedHours))
        value -= 0.22 * debtRatio

        return min(1, max(0, value))
    }

    /// Samples the curve across a day. `samplesPerHour` of 4 gives a smooth
    /// enough path to draw without the view doing its own interpolation.
    public static func curve(phase: Phase,
                             sleepDebtHours: Double = 0,
                             sleepNeedHours: Double = defaultSleepNeedHours,
                             samplesPerHour: Int = 4) -> [(hour: Double, energy: Double)] {
        let step = 1.0 / Double(max(1, samplesPerHour))
        var out: [(Double, Double)] = []
        var hour = 0.0
        while hour < 24 {
            out.append((hour, energy(atHour: hour,
                                     phase: phase,
                                     hoursAwake: hoursAwake(atHour: hour, phase: phase),
                                     sleepDebtHours: sleepDebtHours,
                                     sleepNeedHours: sleepNeedHours)))
            hour += step
        }
        return out.map { (hour: $0.0, energy: $0.1) }
    }

    /// Hours since habitual wake, wrapping across midnight, clamped to zero
    /// during the sleep window — pressure decays while asleep rather than
    /// continuing to build.
    public static func hoursAwake(atHour hour: Double, phase: Phase) -> Double {
        let since = normalizedHour(hour - phase.wakeHour)
        let awakeSpan = normalizedHour(phase.onsetHour - phase.wakeHour)
        // Past onset the person is asleep; pressure is falling, so report the
        // residue rather than a number that keeps climbing all night.
        if since > awakeSpan {
            let asleepFor = since - awakeSpan
            let atOnset = awakeSpan
            return max(0, atOnset * exp(-asleepFor / pressureDecayHours))
        }
        return since
    }

    // ------------------------------------------------------------
    // MARK: Named windows
    // ------------------------------------------------------------

    /// The parts of the day worth naming, because "your energy is 0.61" is not
    /// something anyone can act on.
    public enum Window: String, Equatable, Sendable, CaseIterable {
        case sleep
        case grogginess
        case morningPeak
        case afternoonDip
        case eveningPeak
        case melatoninWindow
        case windingDown

        public var title: String {
            switch self {
            case .sleep:           return "Sleep window"
            case .grogginess:      return "Grogginess"
            case .morningPeak:     return "Morning peak"
            case .afternoonDip:    return "Afternoon dip"
            case .eveningPeak:     return "Evening peak"
            case .melatoninWindow: return "Melatonin window"
            case .windingDown:     return "Winding down"
            }
        }

        /// One line on what to do with it. Written as guidance, not instruction —
        /// the model is a prediction about a body, not a schedule someone agreed to.
        public var guidance: String {
            switch self {
            case .sleep:
                return "Your body expects to be asleep now."
            case .grogginess:
                return "Sleep inertia is normal and passes. Light and movement shorten it; a decision made now is worth remaking later."
            case .morningPeak:
                return "Sharpest stretch of the day. Worth spending on the thing that needs thinking."
            case .afternoonDip:
                return "A real circadian trough, not a failure of will. Good for routine work, bad for anything hard."
            case .eveningPeak:
                return "A second wind, and the hardest time to fall asleep even when tired."
            case .melatoninWindow:
                return "Melatonin is rising. Bright light and screens here are what push tomorrow later."
            case .windingDown:
                return "The runway into sleep. Dim, quiet, and boring is the goal."
            }
        }
    }

    /// Which window a given hour falls into.
    ///
    /// Offsets are from habitual wake, which is why they hold for an early riser
    /// and a night owl alike: the afternoon dip is not at 3pm, it is about seven
    /// hours after you got up.
    public static func window(atHour hour: Double, phase: Phase) -> Window {
        let sinceWake = normalizedHour(hour - phase.wakeHour)
        let awakeSpan = normalizedHour(phase.onsetHour - phase.wakeHour)
        let melatoninStart = normalizedHour(awakeSpan - melatoninLeadHours)

        if sinceWake >= awakeSpan { return .sleep }
        if sinceWake < 1.0 { return .grogginess }
        if sinceWake >= melatoninStart { return .melatoninWindow }
        if sinceWake >= melatoninStart - 1.0 { return .windingDown }
        if sinceWake >= 2.0 && sinceWake < 5.0 { return .morningPeak }
        if sinceWake >= 6.5 && sinceWake < 9.0 { return .afternoonDip }
        if sinceWake >= 10.5 && sinceWake < 13.0 { return .eveningPeak }
        // Between the named stretches. Not every hour deserves a label, and
        // inventing one for all of them would make the real ones meaningless.
        return sinceWake < 6.5 ? .morningPeak : .eveningPeak
    }

    /// When melatonin starts rising, given a phase — the practical start of the
    /// evening. Exposed as a function rather than by publishing the lead time,
    /// so callers cannot accidentally apply it to the wrong end of the night.
    public static func melatoninOnsetHour(phase: Phase) -> Double {
        normalizedHour(phase.onsetHour - melatoninLeadHours)
    }

    /// The next window boundary after `hour`, for "what's next" UI.
    public static func nextWindow(afterHour hour: Double,
                                  phase: Phase) -> (window: Window, startsInHours: Double)? {
        let current = window(atHour: hour, phase: phase)
        var probe = hour
        var elapsed = 0.0
        // Quarter-hour steps over a full day. Bounded, so a phase that somehow
        // produces one uniform window returns nil instead of spinning.
        while elapsed < 24 {
            probe = normalizedHour(probe + 0.25)
            elapsed += 0.25
            let next = window(atHour: probe, phase: phase)
            if next != current { return (next, elapsed) }
        }
        return nil
    }

    // ------------------------------------------------------------
    // MARK: Clock arithmetic
    // ------------------------------------------------------------

    /// Hours past local midnight, fractional.
    public static func hourOfDay(_ date: Date, calendar: Calendar = .current) -> Double {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60.0
    }

    /// Wrap into 0..<24, including for negative inputs — `-1.5` is 22:30, not a
    /// negative time.
    public static func normalizedHour(_ hour: Double) -> Double {
        let wrapped = hour.truncatingRemainder(dividingBy: 24)
        return wrapped < 0 ? wrapped + 24 : wrapped
    }

    /// Mean of clock times, via the unit circle. See the note on `phase`.
    static func circularMean(_ hours: [Double]) -> Double {
        guard !hours.isEmpty else { return 0 }
        var x = 0.0, y = 0.0
        for hour in hours {
            let radians = hour / 24 * 2 * .pi
            x += cos(radians)
            y += sin(radians)
        }
        let angle = atan2(y / Double(hours.count), x / Double(hours.count))
        return normalizedHour(angle / (2 * .pi) * 24)
    }

    /// Circular standard deviation, in hours. Zero when every night matches.
    public static func circularSpread(_ hours: [Double]) -> Double {
        guard hours.count > 1 else { return 0 }
        var x = 0.0, y = 0.0
        for hour in hours {
            let radians = hour / 24 * 2 * .pi
            x += cos(radians)
            y += sin(radians)
        }
        let n = Double(hours.count)
        let resultant = (x * x + y * y).squareRoot() / n
        guard resultant > 0, resultant <= 1 else { return 0 }
        // Standard circular SD, converted from radians back to hours.
        return (-2 * log(resultant)).squareRoot() / (2 * .pi) * 24
    }
}
