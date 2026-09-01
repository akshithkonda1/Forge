import SwiftUI

// MARK: - Quality of Life (holistic, multi-aspect score)
//
// The first QoL score averaged five sub-scores that were not independent —
// sleep, nutrition and activity each fed *multiple* of them, so a plain mean
// silently triple-counted sleep and under-counted everything else. Worse, with
// no HealthKit data the app returned a fabricated 82 (a fixed "looks healthy"
// number) or refused with a placeholder, which is exactly the kind of invented
// data ARIA's own engine is built to avoid.
//
// This calculator replaces both mistakes:
//
//  1. Life is graded across *independent* pillars — sleep, activity, nutrition,
//     hydration, body/vitals, mind, and connection — each backed by its own
//     signals and counted exactly once. "All aspects of life", not one wearing
//     several hats.
//  2. It degrades gracefully instead of fabricating. A missing pillar
//     redistributes its weight over the pillars that *do* have data and lowers
//     `confidence`; it never invents a number and never blocks the score. As
//     more of life is measured, coverage (and honesty) rises — the score is
//     always graded on whatever aspects are actually known.
//  3. Targets are personalized from the profile (body mass, age, sex) when
//     available, with population defaults as the fallback — so a 55 kg user and
//     a 95 kg user are not held to the same protein or calorie bar.

public enum QualityOfLifePillar: String, Codable, CaseIterable, Sendable {
    case sleep
    case activity
    case nutrition
    case hydration
    case vitals
    case mind
    case social

    /// Weight in a fully-populated blend. These sum to 1.0; when a pillar has no
    /// backing signal its weight is redistributed across the pillars that do, so
    /// a missing aspect lowers *confidence*, never the score.
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

    /// Supportive, non-judgemental framing — a low score is a signal, not a grade card.
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
/// reports how much of life that covered. Personalization fields (body mass,
/// age, sex) tune the targets; when absent, population defaults are used.
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
    public var overall: Int
    /// 0...1 — the share of life's weighted pillars that had data. Below ~0.5
    /// the UI should present the number as an estimate, never as fact.
    public var confidence: Double
    /// Per-pillar 0...100 scores, only for pillars that had a backing signal.
    public var pillarScores: [QualityOfLifePillar: Int]

    public init(overall: Int, confidence: Double, pillarScores: [QualityOfLifePillar: Int]) {
        self.overall = overall
        self.confidence = confidence
        self.pillarScores = pillarScores
    }

    public var band: QualityOfLifeBand { QualityOfLifeBand(score: overall) }
    public var isEstimate: Bool { confidence < 0.5 }
    public var gradedAspects: Int { pillarScores.count }

    public func score(for pillar: QualityOfLifePillar) -> Int? { pillarScores[pillar] }
}

public enum QualityOfLifeCalculator {

    /// Blend every pillar that has data, weighting each by its share and
    /// renormalizing over what is present. Absence of a signal is never treated
    /// as evidence of a low score — it lowers confidence and the remaining
    /// pillars carry the grade.
    public static func score(from inputs: QualityOfLifeInputs) -> QualityOfLifeScore {
        var pillars: [QualityOfLifePillar: Double] = [:]

        if let v = sleepScore(inputs)      { pillars[.sleep] = v }
        if let v = activityScore(inputs)   { pillars[.activity] = v }
        if let v = nutritionScore(inputs)  { pillars[.nutrition] = v }
        if let v = hydrationScore(inputs)  { pillars[.hydration] = v }
        if let v = vitalsScore(inputs)     { pillars[.vitals] = v }
        if let v = mindScore(inputs)       { pillars[.mind] = v }
        if let v = socialScore(inputs)     { pillars[.social] = v }

        let totalWeight = pillars.keys.reduce(0.0) { $0 + $1.weight }
        guard totalWeight > 0 else {
            // Nothing is measured yet — say so honestly (confidence 0) rather
            // than inventing a number. This is the only zero-coverage case.
            return QualityOfLifeScore(overall: 0, confidence: 0, pillarScores: [:])
        }

        let blended = pillars.reduce(0.0) { $0 + $1.value * $1.key.weight } / totalWeight

        var rounded: [QualityOfLifePillar: Int] = [:]
        for (pillar, value) in pillars {
            rounded[pillar] = Int(clamp(value, 0, 100).rounded())
        }

        return QualityOfLifeScore(
            overall: Int(clamp(blended, 0, 100).rounded()),
            confidence: clamp(totalWeight, 0, 1),
            pillarScores: rounded
        )
    }

    // MARK: - Pillars (each independent, counted once)

    private static func sleepScore(_ i: QualityOfLifeInputs) -> Double? {
        guard let hours = i.sleepHours, hours > 0 else { return nil }
        let need = sleepNeedHours(age: i.age)
        let ratio = hours / need
        // Under-sleep scales linearly; modest over-sleep is fine, large
        // over-sleep dips (oversleeping is a signal too, not a bonus).
        var base = ratio <= 1.0 ? ratio * 100 : max(100 - (ratio - 1.0) * 60, 55)

        // Architecture is a light adjustment, only when stages are known.
        var arch: [Double] = []
        if let deep = i.deepSleepMinutes { arch.append(clamp(deep / 60.0, 0, 1) * 100) }
        if let rem = i.remSleepMinutes { arch.append(clamp(rem / 90.0, 0, 1) * 100) }
        if let archScore = average(arch) {
            base = base * 0.85 + archScore * 0.15
        }
        return clamp(base, 0, 100)
    }

    private static func activityScore(_ i: QualityOfLifeInputs) -> Double? {
        var parts: [Double] = []
        if let steps = i.steps { parts.append(clamp(Double(steps) / 8_000.0, 0, 1) * 100) }
        if let active = i.activeCalories { parts.append(clamp(Double(active) / 500.0, 0, 1) * 100) }
        if let minutes = i.exerciseMinutes { parts.append(clamp(minutes / 30.0, 0, 1) * 100) }
        return average(parts)
    }

    private static func nutritionScore(_ i: QualityOfLifeInputs) -> Double? {
        var parts: [Double] = []
        if let protein = i.proteinGrams {
            let target = proteinTargetGrams(bodyMassKg: i.bodyMassKg)
            parts.append(clamp(protein / target, 0, 1) * 100)
        }
        if let calories = i.totalCalories, calories > 0 {
            let target = calorieTarget(bodyMassKg: i.bodyMassKg, sexFemale: i.biologicalSexFemale)
            // Adequacy, not "more is better": both under- and over-eating cost.
            let deviation = abs(Double(calories) - target) / target
            parts.append(clamp(100 - deviation * 100, 0, 100))
        }
        if let fiber = i.fiberGrams { parts.append(clamp(fiber / 30.0, 0, 1) * 100) }
        if let sugar = i.addedSugarGrams {
            // 0 g added sugar → 100; 50 g+ → 0.
            parts.append(clamp(100 - (sugar / 50.0) * 100, 0, 100))
        }
        return average(parts)
    }

    private static func hydrationScore(_ i: QualityOfLifeInputs) -> Double? {
        guard let glasses = i.waterGlasses else { return nil }
        let needGlasses = max(1.0, HydrationEngine.glasses(
            fromMilliliters: HydrationEngine.targetMilliliters(weightKilograms: i.bodyMassKg)
        ))
        return clamp(glasses / needGlasses, 0, 1) * 100
    }

    private static func vitalsScore(_ i: QualityOfLifeInputs) -> Double? {
        var parts: [Double] = []
        if let hrv = i.hrvMs, hrv > 0 {
            if let base = i.hrvBaselineMs, base > 0 {
                let ratio = hrv / base
                parts.append(clamp(75 + (ratio - 1.0) / 0.30 * 25, 0, 100))
            } else {
                parts.append(clamp(hrv / 60.0, 0, 1) * 100)
            }
        }
        if let rhr = i.restingHR, rhr > 0 {
            if let base = i.restingHRBaseline, base > 0 {
                let delta = (rhr - base) / base
                parts.append(clamp(80 - delta / 0.15 * 30, 0, 100))
            } else {
                parts.append(clamp(100 - (rhr - 50) * 2, 0, 100))
            }
        }
        if let vo2 = i.vo2Max, vo2 > 0 { parts.append(clamp((vo2 - 20) / (55 - 20), 0, 1) * 100) }
        if let spo2 = i.oxygenSaturationPercent, spo2 > 0 {
            parts.append(clamp((spo2 - 90) / (99 - 90), 0, 1) * 100)
        }
        if let rr = i.respiratoryRate, rr > 0 {
            // 12–18 breaths/min is the calm resting band; deviation reduces.
            let deviation = abs(rr - 15) / 15
            parts.append(clamp(100 - deviation * 120, 0, 100))
        }
        return average(parts)
    }

    private static func mindScore(_ i: QualityOfLifeInputs) -> Double? {
        var parts: [Double] = []
        if let minutes = i.mindfulMinutes { parts.append(clamp(minutes / 10.0, 0, 1) * 100) }
        if let stress = i.stressLevel0to1 { parts.append(clamp(1 - stress, 0, 1) * 100) }
        if let mood = i.selfReportedMood0to10 { parts.append(clamp(mood / 10.0, 0, 1) * 100) }
        return average(parts)
    }

    private static func socialScore(_ i: QualityOfLifeInputs) -> Double? {
        var parts: [Double] = []
        if let connection = i.socialConnection0to10 { parts.append(clamp(connection / 10.0, 0, 1) * 100) }
        if let interactions = i.meaningfulSocialInteractions {
            // 0 → 25 (isolating), 2 → ~65, 4+ → 100.
            parts.append(clamp(25 + Double(interactions) * 20, 0, 100))
        }
        return average(parts)
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

    // MARK: - Helpers

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}
