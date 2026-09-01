import Foundation
import SwiftUI

// MARK: - Quality of Life (holistic, multi-aspect score)
//
// Grades life across seven independent pillars — sleep, activity, nutrition,
// hydration, body/vitals, mind, and connection — each counted exactly once.
// A missing pillar redistributes its weight and lowers confidence instead of
// being invented, so the score is always graded on whatever aspects are known.
//
// Accuracy model (v2):
//   • Non-linear response curves. Each signal maps through a curve that reflects
//     how the underlying variable actually relates to wellbeing: diminishing
//     returns for "more is better" signals (steps, protein), and an inverted-U
//     for signals with a real optimum (sleep duration, calories, respiration).
//     Crude linear ramps over/under-credited the mid-range and the top.
//   • Physiological plausibility. Values outside human range (e.g. HRV 400 ms,
//     500k steps) are treated as unmeasured, not as a perfect score — bad data
//     lowers confidence rather than inflating the grade.
//   • Depth-aware confidence. Confidence reflects not just which pillars have
//     data but how completely each is measured (a vitals pillar backed by 1 of
//     5 signals is less certain than one backed by all 5).
//   • Weighted sub-signals. Within a pillar the more predictive signals carry
//     more weight (protein/calories over fibre; HRV/resting-HR over SpO2).
//   • Personal baselines. HRV and resting HR are scored against the person's own
//     recent baseline when known; targets personalize from body mass, age, sex.
//   • Day-to-day smoothing. `smoothed(previousOverall:)` blends yesterday's score
//     so one noisy night doesn't swing a measure that is meant to be stable.

public enum QualityOfLifePillar: String, Codable, CaseIterable, Sendable {
    case sleep
    case activity
    case nutrition
    case hydration
    case vitals
    case mind
    case social

    /// Weight in a fully-populated blend. These sum to 1.0; a pillar with no
    /// data redistributes its weight over the pillars that do.
    public var weight: Double {
        switch self {
        case .sleep:     return 0.22
        case .activity:  return 0.18
        case .nutrition: return 0.15
        case .vitals:    return 0.15
        case .mind:      return 0.12
        case .social:    return 0.10
        case .hydration: return 0.08
        }
    }

    /// Number of distinct signals the pillar can be measured from. Used to
    /// express how deeply a pillar was covered (present signals / this).
    public var maxSignals: Int {
        switch self {
        case .sleep:     return 3   // duration, deep, REM
        case .activity:  return 3   // steps, active calories, exercise minutes
        case .nutrition: return 4   // protein, calories, fibre, added sugar
        case .vitals:    return 5   // HRV, resting HR, VO2max, SpO2, respiration
        case .mind:      return 3   // mindful minutes, stress, mood
        case .social:    return 2   // felt connection, meaningful interactions
        case .hydration: return 1   // intake vs need
        }
    }

    public var title: String {
        switch self {
        case .sleep:     return "Sleep"
        case .activity:  return "Activity"
        case .nutrition: return "Nutrition"
        case .hydration: return "Hydration"
        case .vitals:    return "Body & Vitals"
        case .mind:      return "Mind & Stress"
        case .social:    return "Connection"
        }
    }
}

public enum QualityOfLifeBand: String, Codable, CaseIterable, Sendable {
    case thriving
    case steady
    case strained
    case depleted

    public init(score: Int) {
        switch score {
        case 85...:    self = .thriving
        case 70..<85:  self = .steady
        case 50..<70:  self = .strained
        default:       self = .depleted
        }
    }

    public var label: String {
        switch self {
        case .thriving: return "Thriving"
        case .steady:   return "Steady"
        case .strained: return "Strained"
        case .depleted: return "Depleted"
        }
    }

    public var supportiveDescriptor: String {
        switch self {
        case .thriving: return "Life is in a good rhythm right now — protect what's working."
        case .steady:   return "A solid, balanced stretch. Small steady wins keep it here."
        case .strained: return "A few areas are asking for attention. Pick one to ease first."
        case .depleted: return "Several signals are low. Be gentle — recovery is the work today."
        }
    }

    public var color: Color {
        switch self {
        case .thriving: return ForgePalette.success
        case .steady:   return ForgePalette.steel
        case .strained: return ForgePalette.amber
        case .depleted: return ForgePalette.violet
        }
    }
}

/// Every signal is optional. The calculator scores whatever is present and
/// reports how much of life that covered. Personalization fields tune targets
/// and baselines; population defaults are used when they are absent.
public struct QualityOfLifeInputs: Sendable, Equatable {
    // Sleep
    public var sleepHours: Double?
    public var deepSleepMinutes: Double?
    public var remSleepMinutes: Double?
    // Activity
    public var steps: Int?
    public var activeCalories: Int?
    public var exerciseMinutes: Double?
    // Nutrition
    public var proteinGrams: Double?
    public var totalCalories: Int?
    public var fiberGrams: Double?
    public var addedSugarGrams: Double?
    // Hydration
    public var waterGlasses: Double?
    // Body / vitals
    public var hrvMs: Double?
    public var hrvBaselineMs: Double?
    public var restingHR: Double?
    public var restingHRBaseline: Double?
    public var vo2Max: Double?
    public var oxygenSaturationPercent: Double?
    public var respiratoryRate: Double?
    // Mind
    public var mindfulMinutes: Double?
    public var stressLevel0to1: Double?          // 0 = calm, 1 = maximally stressed
    public var selfReportedMood0to10: Double?
    // Connection
    public var socialConnection0to10: Double?
    public var meaningfulSocialInteractions: Int?

    // Personalization (optional; population defaults when absent)
    public var bodyMassKg: Double?
    public var age: Int?
    public var biologicalSexFemale: Bool?

    public init(
        sleepHours: Double? = nil,
        deepSleepMinutes: Double? = nil,
        remSleepMinutes: Double? = nil,
        steps: Int? = nil,
        activeCalories: Int? = nil,
        exerciseMinutes: Double? = nil,
        proteinGrams: Double? = nil,
        totalCalories: Int? = nil,
        fiberGrams: Double? = nil,
        addedSugarGrams: Double? = nil,
        waterGlasses: Double? = nil,
        hrvMs: Double? = nil,
        hrvBaselineMs: Double? = nil,
        restingHR: Double? = nil,
        restingHRBaseline: Double? = nil,
        vo2Max: Double? = nil,
        oxygenSaturationPercent: Double? = nil,
        respiratoryRate: Double? = nil,
        mindfulMinutes: Double? = nil,
        stressLevel0to1: Double? = nil,
        selfReportedMood0to10: Double? = nil,
        socialConnection0to10: Double? = nil,
        meaningfulSocialInteractions: Int? = nil,
        bodyMassKg: Double? = nil,
        age: Int? = nil,
        biologicalSexFemale: Bool? = nil
    ) {
        self.sleepHours = sleepHours
        self.deepSleepMinutes = deepSleepMinutes
        self.remSleepMinutes = remSleepMinutes
        self.steps = steps
        self.activeCalories = activeCalories
        self.exerciseMinutes = exerciseMinutes
        self.proteinGrams = proteinGrams
        self.totalCalories = totalCalories
        self.fiberGrams = fiberGrams
        self.addedSugarGrams = addedSugarGrams
        self.waterGlasses = waterGlasses
        self.hrvMs = hrvMs
        self.hrvBaselineMs = hrvBaselineMs
        self.restingHR = restingHR
        self.restingHRBaseline = restingHRBaseline
        self.vo2Max = vo2Max
        self.oxygenSaturationPercent = oxygenSaturationPercent
        self.respiratoryRate = respiratoryRate
        self.mindfulMinutes = mindfulMinutes
        self.stressLevel0to1 = stressLevel0to1
        self.selfReportedMood0to10 = selfReportedMood0to10
        self.socialConnection0to10 = socialConnection0to10
        self.meaningfulSocialInteractions = meaningfulSocialInteractions
        self.bodyMassKg = bodyMassKg
        self.age = age
        self.biologicalSexFemale = biologicalSexFemale
    }
}

public struct QualityOfLifeScore: Codable, Sendable, Equatable {
    /// The reported score (smoothed against prior days when available).
    public var overall: Int
    /// Today's score before any day-to-day smoothing.
    public var rawOverall: Int
    /// 0...1 — coverage × depth: how much of life's weighted pillars had data,
    /// and how completely each was measured. Below ~0.5 the UI should present
    /// the number as an estimate, never as fact.
    public var confidence: Double
    /// Per-pillar 0...100 scores, only for pillars that had a backing signal.
    public var pillarScores: [QualityOfLifePillar: Int]

    public init(overall: Int, rawOverall: Int, confidence: Double, pillarScores: [QualityOfLifePillar: Int]) {
        self.overall = overall
        self.rawOverall = rawOverall
        self.confidence = confidence
        self.pillarScores = pillarScores
    }

    public var band: QualityOfLifeBand { QualityOfLifeBand(score: overall) }
    public var isEstimate: Bool { confidence < 0.5 }
    public var gradedAspects: Int { pillarScores.count }

    public func score(for pillar: QualityOfLifePillar) -> Int? { pillarScores[pillar] }

    /// Blend with a previous day's overall so a single noisy day doesn't swing
    /// the score. `alpha` is the weight on today (0.6 → 60% today / 40% history).
    /// Smoothing is scaled by confidence: a low-confidence day moves the trend
    /// less. No previous value → returned unchanged.
    public func smoothed(previousOverall: Int?, alpha: Double = 0.6) -> QualityOfLifeScore {
        guard let previous = previousOverall else { return self }
        let effectiveAlpha = min(1, max(0, alpha)) * max(0.35, confidence)
        let blended = Double(rawOverall) * effectiveAlpha + Double(previous) * (1 - effectiveAlpha)
        var copy = self
        copy.overall = Int(blended.rounded())
        return copy
    }
}

public enum QualityOfLifeCalculator {

    /// Blend every pillar that has data, weighting each by its share and
    /// renormalizing over what is present. Absence of a signal lowers confidence,
    /// never the score.
    public static func score(from inputs: QualityOfLifeInputs) -> QualityOfLifeScore {
        var scores: [QualityOfLifePillar: Double] = [:]
        var depths: [QualityOfLifePillar: Double] = [:]

        func add(_ pillar: QualityOfLifePillar, _ result: PillarResult?) {
            guard let result else { return }
            scores[pillar] = clamp(result.score, 0, 100)
            depths[pillar] = clamp(result.depth, 0, 1)
        }

        add(.sleep, sleepPillar(inputs))
        add(.activity, activityPillar(inputs))
        add(.nutrition, nutritionPillar(inputs))
        add(.hydration, hydrationPillar(inputs))
        add(.vitals, vitalsPillar(inputs))
        add(.mind, mindPillar(inputs))
        add(.social, socialPillar(inputs))

        let coverage = scores.keys.reduce(0.0) { $0 + $1.weight }
        guard coverage > 0 else {
            // Nothing measured yet — reported honestly, never fabricated.
            return QualityOfLifeScore(overall: 0, rawOverall: 0, confidence: 0, pillarScores: [:])
        }

        let blended = scores.reduce(0.0) { $0 + $1.value * $1.key.weight } / coverage
        // Confidence rewards both breadth (which pillars) and depth (how fully
        // each was measured). A pillar with any signal is already informative,
        // so presence earns 60% of its weight and full depth earns the rest —
        // shallow coverage still reads as an estimate without being punitive.
        let confidence = scores.keys.reduce(0.0) { total, pillar in
            total + pillar.weight * (0.6 + 0.4 * (depths[pillar] ?? 0))
        }

        var rounded: [QualityOfLifePillar: Int] = [:]
        for (pillar, value) in scores { rounded[pillar] = Int(value.rounded()) }

        let overall = Int(clamp(blended, 0, 100).rounded())
        return QualityOfLifeScore(
            overall: overall,
            rawOverall: overall,
            confidence: clamp(confidence, 0, 1),
            pillarScores: rounded
        )
    }

    // MARK: - Pillars (independent; each counted once)

    private static func sleepPillar(_ i: QualityOfLifeInputs) -> PillarResult? {
        guard let hours = i.sleepHours, hours > 0, hours <= 16 else { return nil }
        let need = sleepNeedHours(age: i.age)
        var signals = [Signal(optimum(hours / need, sigma: 0.16), 0.70)]  // duration has a real optimum
        if let deep = i.deepSleepMinutes, deep >= 0, deep <= 360 {
            signals.append(Signal(rising(deep / 60.0), 0.15))
        }
        if let rem = i.remSleepMinutes, rem >= 0, rem <= 360 {
            signals.append(Signal(rising(rem / 90.0), 0.15))
        }
        return combine(signals, maxSignals: QualityOfLifePillar.sleep.maxSignals)
    }

    private static func activityPillar(_ i: QualityOfLifeInputs) -> PillarResult? {
        var signals: [Signal] = []
        if let steps = i.steps, steps >= 0, steps <= 80_000 {
            signals.append(Signal(rising(Double(steps) / 8_000.0), 1))
        }
        if let active = i.activeCalories, active >= 0, active <= 5_000 {
            signals.append(Signal(rising(Double(active) / 500.0), 1))
        }
        if let minutes = i.exerciseMinutes, minutes >= 0, minutes <= 600 {
            signals.append(Signal(rising(minutes / 30.0), 1))
        }
        return combine(signals, maxSignals: QualityOfLifePillar.activity.maxSignals)
    }

    private static func nutritionPillar(_ i: QualityOfLifeInputs) -> PillarResult? {
        var signals: [Signal] = []
        if let protein = i.proteinGrams, protein >= 0, protein <= 500 {
            signals.append(Signal(rising(protein / proteinTargetGrams(bodyMassKg: i.bodyMassKg)), 0.35))
        }
        if let calories = i.totalCalories, calories > 0, calories <= 12_000 {
            let target = calorieTarget(bodyMassKg: i.bodyMassKg, sexFemale: i.biologicalSexFemale)
            signals.append(Signal(optimum(Double(calories) / target, sigma: 0.22), 0.35))  // adequacy, not "more"
        }
        if let fiber = i.fiberGrams, fiber >= 0, fiber <= 150 {
            signals.append(Signal(rising(fiber / 30.0), 0.15))
        }
        if let sugar = i.addedSugarGrams, sugar >= 0, sugar <= 500 {
            signals.append(Signal(descending(sugar, zeroAt: 60), 0.15))  // less is better
        }
        return combine(signals, maxSignals: QualityOfLifePillar.nutrition.maxSignals)
    }

    private static func hydrationPillar(_ i: QualityOfLifeInputs) -> PillarResult? {
        guard let glasses = i.waterGlasses, glasses >= 0, glasses <= 40 else { return nil }
        let needGlasses = max(1.0, HydrationEngine.glasses(
            fromMilliliters: HydrationEngine.targetMilliliters(weightKilograms: i.bodyMassKg)
        ))
        return combine([Signal(rising(glasses / needGlasses), 1)],
                       maxSignals: QualityOfLifePillar.hydration.maxSignals)
    }

    private static func vitalsPillar(_ i: QualityOfLifeInputs) -> PillarResult? {
        var signals: [Signal] = []
        if let hrv = i.hrvMs, hrv > 0, hrv <= 250 {
            if let base = i.hrvBaselineMs, base > 0 {
                // Scored against the person's own baseline: ±30% → 50...100.
                signals.append(Signal(clamp(75 + (hrv / base - 1.0) / 0.30 * 25, 0, 100), 0.30))
            } else {
                signals.append(Signal(rising(hrv / 55.0), 0.30))
            }
        }
        if let rhr = i.restingHR, rhr >= 25, rhr <= 150 {
            if let base = i.restingHRBaseline, base > 0 {
                signals.append(Signal(clamp(80 - (rhr - base) / base / 0.15 * 30, 0, 100), 0.30))
            } else {
                // Age-graded expectation: a resting HR near ~55 is excellent.
                signals.append(Signal(descending(max(0, rhr - 45), zeroAt: 55), 0.30))
            }
        }
        if let vo2 = i.vo2Max, vo2 > 0, vo2 <= 90 {
            signals.append(Signal(rising((vo2 - 20) / (55 - 20)), 0.18))
        }
        if let spo2 = i.oxygenSaturationPercent, spo2 >= 50, spo2 <= 100 {
            signals.append(Signal(clamp((spo2 - 90) / (99 - 90), 0, 1) * 100, 0.12))
        }
        if let rr = i.respiratoryRate, rr >= 4, rr <= 40 {
            signals.append(Signal(optimum(rr / 15.0, sigma: 0.20), 0.10))  // ~15 breaths/min optimum
        }
        return combine(signals, maxSignals: QualityOfLifePillar.vitals.maxSignals)
    }

    private static func mindPillar(_ i: QualityOfLifeInputs) -> PillarResult? {
        var signals: [Signal] = []
        if let minutes = i.mindfulMinutes, minutes >= 0, minutes <= 600 {
            signals.append(Signal(rising(minutes / 10.0), 1))
        }
        if let stress = i.stressLevel0to1 {
            signals.append(Signal(clamp(1 - stress, 0, 1) * 100, 1))
        }
        if let mood = i.selfReportedMood0to10 {
            signals.append(Signal(rising(mood / 10.0), 1))
        }
        return combine(signals, maxSignals: QualityOfLifePillar.mind.maxSignals)
    }

    private static func socialPillar(_ i: QualityOfLifeInputs) -> PillarResult? {
        var signals: [Signal] = []
        if let connection = i.socialConnection0to10 {
            signals.append(Signal(rising(connection / 10.0), 1))
        }
        if let interactions = i.meaningfulSocialInteractions, interactions >= 0 {
            signals.append(Signal(clamp(25 + Double(interactions) * 20, 0, 100), 1))
        }
        return combine(signals, maxSignals: QualityOfLifePillar.social.maxSignals)
    }

    // MARK: - Signal combination

    private struct Signal {
        let value: Double
        let weight: Double
        init(_ value: Double, _ weight: Double) {
            self.value = value
            self.weight = weight
        }
    }

    private struct PillarResult {
        let score: Double
        let depth: Double
    }

    private static func combine(_ signals: [Signal], maxSignals: Int) -> PillarResult? {
        guard !signals.isEmpty else { return nil }
        let totalWeight = signals.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return nil }
        let score = signals.reduce(0) { $0 + $1.value * $1.weight } / totalWeight
        let depth = Double(signals.count) / Double(max(1, maxSignals))
        return PillarResult(score: score, depth: depth)
    }

    // MARK: - Response curves

    /// "More is better" with diminishing returns and a soft cap. Concave up to
    /// the target (r = 1 → 100), then a gentle penalty for gross overshoot so a
    /// data glitch or over-training does not read as perfect.
    static func rising(_ ratio: Double) -> Double {
        if ratio <= 0 { return 0 }
        if ratio <= 1 { return 100 * (1 - (1 - ratio) * (1 - ratio)) }
        return max(100 - (ratio - 1) * 20, 60)
    }

    /// Inverted-U for signals with a real optimum (sleep duration, calories,
    /// respiration): best at the target, worse on either side. Gaussian falloff.
    static func optimum(_ ratio: Double, sigma: Double) -> Double {
        let d = ratio - 1
        return clamp(100 * exp(-(d * d) / (2 * sigma * sigma)), 0, 100)
    }

    /// "Less is better": full marks at 0, zero at `zeroAt`, linear between.
    static func descending(_ value: Double, zeroAt: Double) -> Double {
        guard zeroAt > 0 else { return 0 }
        return clamp(100 * (1 - value / zeroAt), 0, 100)
    }

    // MARK: - Personalized targets

    private static func sleepNeedHours(age: Int?) -> Double {
        guard let age = age else { return 8.0 }
        if age < 18 { return 9.0 }
        if age >= 65 { return 7.5 }
        return 8.0
    }

    private static func proteinTargetGrams(bodyMassKg: Double?) -> Double {
        if let kg = bodyMassKg, kg > 0 { return max(60, 1.6 * kg) }
        return 130
    }

    private static func calorieTarget(bodyMassKg: Double?, sexFemale: Bool?) -> Double {
        if let kg = bodyMassKg, kg > 0 { return max(1_400, kg * 31) }
        return (sexFemale == true) ? 2_000 : 2_400
    }

    private static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}
