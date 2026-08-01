import Foundation
import SwiftUI

// MARK: - Flow & signals

enum MenstrualFlowLevel: String, Codable, CaseIterable, Identifiable {
    case unspecified, none, spotting, light, medium, heavy
    var id: String { rawValue }

    var label: String {
        switch self {
        case .unspecified: return "Unspecified"
        case .none: return "None"
        case .spotting: return "Spotting"
        case .light: return "Light"
        case .medium: return "Medium"
        case .heavy: return "Heavy"
        }
    }

    var isBleeding: Bool {
        switch self {
        case .spotting, .light, .medium, .heavy: return true
        default: return false
        }
    }

    var sortWeight: Int {
        switch self {
        case .none: return 0
        case .unspecified: return 1
        case .spotting: return 2
        case .light: return 3
        case .medium: return 4
        case .heavy: return 5
        }
    }

    static func fromHealthKitLabel(_ raw: String) -> MenstrualFlowLevel {
        let l = raw.lowercased()
        if l.contains("heavy") { return .heavy }
        if l.contains("medium") { return .medium }
        if l.contains("light") { return .light }
        if l.contains("spot") { return .spotting }
        if l.contains("none") { return .none }
        return .unspecified
    }
}

enum OvulationTestResult: String, Codable, CaseIterable {
    case negative, lhSurge, estrogenSurge, positive, indeterminate, unknown

    var indicatesNearOvulation: Bool {
        self == .lhSurge || self == .positive || self == .estrogenSurge
    }

    var label: String {
        switch self {
        case .negative: return "Negative"
        case .lhSurge: return "LH surge"
        case .estrogenSurge: return "Estrogen surge"
        case .positive: return "Positive"
        case .indeterminate: return "Indeterminate"
        case .unknown: return "Unknown"
        }
    }
}

enum CervicalMucusQuality: String, Codable, CaseIterable {
    case dry, sticky, creamy, watery, eggWhite, unknown

    /// Higher = more fertile-type mucus (Billings / standard FAM).
    var fertilityScore: Int {
        switch self {
        case .eggWhite: return 5
        case .watery: return 4
        case .creamy: return 2
        case .sticky: return 1
        case .dry, .unknown: return 0
        }
    }

    var label: String {
        switch self {
        case .dry: return "Dry"
        case .sticky: return "Sticky"
        case .creamy: return "Creamy"
        case .watery: return "Watery"
        case .eggWhite: return "Egg white"
        case .unknown: return "Unknown"
        }
    }
}

enum CycleSymptom: String, Codable, CaseIterable, Identifiable {
    case cramps, headache, bloating, fatigue, moodLow, moodHigh
    case breastTenderness, backache, acne, cravings, insomnia, nausea
    case energyHigh, libidoHigh, brainFog
    // Extended symptom set
    case hotFlash, nightSweats, anxietyHigh, spotting, libidoLow
    case pelvicPain, constipation, diarrhea, appetiteUp, appetiteDown, vaginalDryness

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cramps: return "Cramps"
        case .headache: return "Headache"
        case .bloating: return "Bloating"
        case .fatigue: return "Fatigue"
        case .moodLow: return "Low mood"
        case .moodHigh: return "High mood"
        case .breastTenderness: return "Breast tenderness"
        case .backache: return "Backache"
        case .acne: return "Acne"
        case .cravings: return "Cravings"
        case .insomnia: return "Insomnia"
        case .nausea: return "Nausea"
        case .energyHigh: return "High energy"
        case .libidoHigh: return "Higher libido"
        case .brainFog: return "Brain fog"
        case .hotFlash: return "Hot flash"
        case .nightSweats: return "Night sweats"
        case .anxietyHigh: return "Anxiety"
        case .spotting: return "Spotting"
        case .libidoLow: return "Lower libido"
        case .pelvicPain: return "Pelvic pain"
        case .constipation: return "Constipation"
        case .diarrhea: return "Diarrhea"
        case .appetiteUp: return "Increased appetite"
        case .appetiteDown: return "Decreased appetite"
        case .vaginalDryness: return "Vaginal dryness"
        }
    }

    var icon: String {
        switch self {
        case .cramps: return "bolt.heart.fill"
        case .headache: return "brain.head.profile"
        case .bloating: return "circle.hexagongrid.fill"
        case .fatigue: return "battery.25"
        case .moodLow: return "cloud.rain.fill"
        case .moodHigh: return "sun.max.fill"
        case .breastTenderness: return "heart.fill"
        case .backache: return "figure.stand"
        case .acne: return "face.dashed"
        case .cravings: return "fork.knife"
        case .insomnia: return "moon.zzz.fill"
        case .nausea: return "cross.case.fill"
        case .energyHigh: return "bolt.fill"
        case .libidoHigh: return "flame.fill"
        case .brainFog: return "aqi.medium"
        case .hotFlash: return "thermometer.sun.fill"
        case .nightSweats: return "thermometer.medium"
        case .anxietyHigh: return "waveform.path.ecg.rectangle"
        case .spotting: return "drop"
        case .libidoLow: return "flame"
        case .pelvicPain: return "bolt.heart"
        case .constipation: return "arrow.down.circle"
        case .diarrhea: return "arrow.up.circle"
        case .appetiteUp: return "plus.circle.fill"
        case .appetiteDown: return "minus.circle.fill"
        case .vaginalDryness: return "humidity"
        }
    }
}

// MARK: - Daily log

struct CycleDayLog: Identifiable, Codable, Equatable, Hashable {
    var id: String { dayKey }
    /// yyyy-MM-dd in local calendar
    var dayKey: String
    var flow: MenstrualFlowLevel
    var symptoms: [CycleSymptom]
    var bbtCelsius: Double?
    var ovulationTest: OvulationTestResult?
    var mucus: CervicalMucusQuality?
    var notes: String?
    var source: String // "manual" | "healthkit" | "merged"
    var updatedAt: Date
    /// 0–10 pain intensity scale, used for endometriosis / pelvic pain tracking.
    var painScale: Int?

    init(
        dayKey: String,
        flow: MenstrualFlowLevel = .none,
        symptoms: [CycleSymptom] = [],
        bbtCelsius: Double? = nil,
        ovulationTest: OvulationTestResult? = nil,
        mucus: CervicalMucusQuality? = nil,
        notes: String? = nil,
        source: String = "manual",
        updatedAt: Date = Date(),
        painScale: Int? = nil
    ) {
        self.dayKey = dayKey
        self.flow = flow
        self.symptoms = symptoms
        self.bbtCelsius = bbtCelsius
        self.ovulationTest = ovulationTest
        self.mucus = mucus
        self.notes = notes
        self.source = source
        self.updatedAt = updatedAt
        self.painScale = painScale
    }

    enum CodingKeys: String, CodingKey {
        case dayKey, flow, symptoms, bbtCelsius, ovulationTest, mucus, notes, source, updatedAt, painScale
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dayKey = try c.decode(String.self, forKey: .dayKey)
        flow = try c.decodeIfPresent(MenstrualFlowLevel.self, forKey: .flow) ?? .none
        symptoms = try c.decodeIfPresent([CycleSymptom].self, forKey: .symptoms) ?? []
        bbtCelsius = try c.decodeIfPresent(Double.self, forKey: .bbtCelsius)
        ovulationTest = try c.decodeIfPresent(OvulationTestResult.self, forKey: .ovulationTest)
        mucus = try c.decodeIfPresent(CervicalMucusQuality.self, forKey: .mucus)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? "manual"
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        painScale = try c.decodeIfPresent(Int.self, forKey: .painScale)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(dayKey, forKey: .dayKey)
        try c.encode(flow, forKey: .flow)
        try c.encode(symptoms, forKey: .symptoms)
        try c.encodeIfPresent(bbtCelsius, forKey: .bbtCelsius)
        try c.encodeIfPresent(ovulationTest, forKey: .ovulationTest)
        try c.encodeIfPresent(mucus, forKey: .mucus)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encode(source, forKey: .source)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encodeIfPresent(painScale, forKey: .painScale)
    }
}

// MARK: - Episodes & phases

struct PeriodEpisode: Identifiable, Codable, Equatable {
    var id: String
    var startDayKey: String
    var endDayKey: String
    var peakFlow: MenstrualFlowLevel
    var dayCount: Int
    /// True when the user explicitly tapped "Period finished" for this episode, rather
    /// than the engine inferring the end from where bleeding logs stopped.
    var isConfirmedComplete: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, startDayKey, endDayKey, peakFlow, dayCount, isConfirmedComplete
    }

    init(
        id: String,
        startDayKey: String,
        endDayKey: String,
        peakFlow: MenstrualFlowLevel,
        dayCount: Int,
        isConfirmedComplete: Bool = false
    ) {
        self.id = id
        self.startDayKey = startDayKey
        self.endDayKey = endDayKey
        self.peakFlow = peakFlow
        self.dayCount = dayCount
        self.isConfirmedComplete = isConfirmedComplete
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        startDayKey = try c.decode(String.self, forKey: .startDayKey)
        endDayKey = try c.decode(String.self, forKey: .endDayKey)
        peakFlow = try c.decodeIfPresent(MenstrualFlowLevel.self, forKey: .peakFlow) ?? .medium
        dayCount = try c.decodeIfPresent(Int.self, forKey: .dayCount) ?? 1
        isConfirmedComplete = try c.decodeIfPresent(Bool.self, forKey: .isConfirmedComplete) ?? false
    }
}

/// Physiological bounds the whole engine agrees on.
///
/// These were previously scattered as inline magic numbers with inconsistent values —
/// period length was learned into a 2…10 day range in one place and clamped to 3+ in
/// another, so the "how long is my period" model and the "am I still bleeding" model
/// could disagree with each other.
enum CycleBiology {
    /// A menstrual bleed lasts 3–7 days. Learned period length is clamped to this.
    static let periodDayRange: ClosedRange<Int> = 3...7
    static let defaultPeriodDays = 5

    /// Luteal phase length — ovulation to next period. Stable within a person.
    static let lutealDayRange: ClosedRange<Int> = 10...16
    static let defaultLutealDays = 14

    /// Sperm survive ~5 days; the egg ~24 hours. The fertile window is therefore the
    /// 5 days before ovulation plus ovulation day itself.
    static let fertileDaysBeforeOvulation = 5
    static let fertileDaysAfterOvulation = 1

    static let defaultCycleDays = 28

    static func clampPeriodDays(_ days: Int) -> Int {
        min(periodDayRange.upperBound, max(periodDayRange.lowerBound, days))
    }

    static func clampLutealDays(_ days: Int) -> Int {
        min(lutealDayRange.upperBound, max(lutealDayRange.lowerBound, days))
    }
}

/// Where the user is in the arc of a single cycle. Distinct from `MenstrualPhase`:
/// this is the *lifecycle* state the UI and partner coaching key off, and it knows the
/// difference between "still bleeding" and "bleed confirmed finished".
enum CycleStage: String, Codable, Equatable {
    /// Actively bleeding.
    case period
    /// Bleed confirmed over, before the fertile window opens.
    case postPeriod
    /// Fertile window is open.
    case fertile
    /// Ovulation day.
    case ovulation
    /// After ovulation, before the next period.
    case premenstrual
    /// Not enough data.
    case unknown

    var label: String {
        switch self {
        case .period: return "On your period"
        case .postPeriod: return "Period finished"
        case .fertile: return "Fertile window"
        case .ovulation: return "Ovulation"
        case .premenstrual: return "Pre-menstrual"
        case .unknown: return "Learning your cycle"
        }
    }

    /// Same arc, phrased for the person supporting them.
    func partnerLabel(name: String) -> String {
        switch self {
        case .period: return "\(name) is on her period"
        case .postPeriod: return "\(name)'s period has finished"
        case .fertile: return "\(name) is in her fertile window"
        case .ovulation: return "\(name) is around ovulation"
        case .premenstrual: return "\(name) is pre-menstrual"
        case .unknown: return "Still learning \(name)'s rhythm"
        }
    }
}

enum MenstrualPhase: String, Codable, CaseIterable, Identifiable {
    case unknown
    case menstruation
    case follicular
    case fertileWindow
    case ovulation
    case luteal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .unknown: return "Learning your cycle"
        case .menstruation: return "Menstruation"
        case .follicular: return "Follicular"
        case .fertileWindow: return "Fertile window"
        case .ovulation: return "Ovulation"
        case .luteal: return "Luteal"
        }
    }

    var shortLabel: String {
        switch self {
        case .unknown: return "—"
        case .menstruation: return "Period"
        case .follicular: return "Follicular"
        case .fertileWindow: return "Fertile"
        case .ovulation: return "Ovulation"
        case .luteal: return "Luteal"
        }
    }

    var icon: String {
        switch self {
        case .unknown: return "circle.dashed"
        case .menstruation: return "drop.fill"
        case .follicular: return "leaf.fill"
        case .fertileWindow: return "waveform.path.ecg"
        case .ovulation: return "sparkles"
        case .luteal: return "moon.fill"
        }
    }

    var accentHex: String {
        switch self {
        case .unknown: return "6B7280"
        case .menstruation: return "EF4444"
        case .follicular: return "22C55E"
        case .fertileWindow: return "F59E0B"
        case .ovulation: return "A855F7"
        case .luteal: return "6366F1"
        }
    }

    var trainingBias: String {
        switch self {
        case .unknown: return "Use readiness as the primary dial until we learn your pattern."
        case .menstruation: return "Favor technique, mobility, and auto-regulated intensity; heavy compounds optional."
        case .follicular: return "Often a strong window for progressive overload and skill work."
        case .fertileWindow: return "Power and intensity can feel available — mind hydration and sleep."
        case .ovulation: return "Peak force potential for many; watch joint stiffness and warm up thoroughly."
        case .luteal: return "Volume and heat tolerance may dip; quality over ego, more recovery buffer."
        }
    }
}

// MARK: - Cycle Goal

enum CycleGoal: String, Codable, CaseIterable, Identifiable {
    case general, ttc, avoidPregnancy

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general: return "General Wellness"
        case .ttc: return "Trying to Conceive"
        case .avoidPregnancy: return "Family Planning"
        }
    }

    var icon: String {
        switch self {
        case .general: return "heart.text.square.fill"
        case .ttc: return "staroflife.fill"
        case .avoidPregnancy: return "shield.fill"
        }
    }
}

// MARK: - Condition modes

enum CycleCondition: String, Codable, CaseIterable, Identifiable {
    case none, pcos, endometriosis, perimenopause, thyroid, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "None / Not specified"
        case .pcos: return "PCOS"
        case .endometriosis: return "Endometriosis"
        case .perimenopause: return "Perimenopause"
        case .thyroid: return "Thyroid condition"
        case .other: return "Other condition"
        }
    }

    var icon: String {
        switch self {
        case .none: return "checkmark.circle"
        case .pcos: return "waveform.path.ecg"
        case .endometriosis: return "bolt.heart"
        case .perimenopause: return "thermometer.sun"
        case .thyroid: return "cross.case"
        case .other: return "ellipsis.circle"
        }
    }

    var ariaGuidance: String {
        switch self {
        case .none: return ""
        case .pcos: return "The user has PCOS. Cycles may be irregular or anovulatory — do not treat long or irregular cycles as anomalies. OPK tests may show multiple LH surges without ovulation. Discuss insulin resistance, androgen effects (acne, hirsutism), and that consistency in tracking over many cycles is key to identifying patterns. Never suggest PCOS is 'just' irregular periods."
        case .endometriosis: return "The user has endometriosis. Expect elevated pain scores, particularly pelvic and low-back pain during menstruation and sometimes throughout the cycle. Validate their experience — endometriosis pain is real and often underdiagnosed. Recommend phase-specific pain management strategies. Red flags to suggest seeing a doctor: pain that disrupts daily life or worsens over time."
        case .perimenopause: return "The user is perimenopausal. Cycle lengths are variable and unpredictable — do not treat irregularity as an error. Fertile window predictions are unreliable. Symptoms: hot flashes, night sweats, vaginal dryness, mood changes, sleep disruption are all perimenopausal. Discuss what is happening hormonally (falling estrogen + progesterone). HRT: acknowledge it exists and is evidence-based, recommend consulting a doctor for personal guidance."
        case .thyroid: return "The user has a thyroid condition. Both hypothyroid and hyperthyroid can affect cycle regularity and BBT baselines. BBT readings may be shifted (hypothyroid = lower baseline, hyperthyroid = higher). Account for this in temperature interpretation. Medication timing affects BBT — recommend taking temperature before any thyroid medication."
        case .other: return "The user has indicated a health condition affecting their cycle. Be attentive to patterns they describe and avoid making strong assumptions about cycle regularity."
        }
    }

    var suppressesIrregularityFlag: Bool {
        self == .pcos || self == .perimenopause
    }

    var suppressesFertileWindow: Bool {
        self == .perimenopause
    }

    /// Non-nil when a named condition is selected (UI hides condition context for `.none`).
    var activeCase: CycleCondition? {
        self == .none ? nil : self
    }

    /// User-facing note on how this condition changes cycle tracking and predictions.
    /// Shown under the phase orbit so people can see *why* windows behave differently.
    var trackingImplication: String {
        switch self {
        case .none:
            return ""
        case .pcos:
            return "Long and variable cycles count as real history, not errors. The irregularity flag stays quiet unless variance is extreme — patterns emerge over many cycles, not one."
        case .endometriosis:
            return "Pain and pelvic symptoms feed recovery guidance. Cycle timing still personalizes from your logs; pain that disrupts daily life is worth raising with a clinician."
        case .perimenopause:
            return "Fertile-window and ovulation labels are withheld because they aren’t reliable here. Period timing stays a range, not a fixed date."
        case .thyroid:
            return "BBT baselines can shift with thyroid status and medication. Take temperature before any morning dose so readings stay comparable."
        case .other:
            return "Predictions stay conservative and avoid strong assumptions about regularity. Keep logging — patterns you notice help personalize coaching."
        }
    }

    /// Inter-start lengths accepted as real cycle history (not outliers).
    /// PCOS and perimenopause keep longer/variable cycles so they are learned, not discarded.
    var plausibleCycleLengthRange: ClosedRange<Int> {
        switch self {
        case .pcos:
            return 18...90
        case .perimenopause:
            return 14...90
        case .thyroid:
            return 18...55
        case .endometriosis, .other, .none:
            return 18...45
        }
    }
}

// MARK: - Snapshot (engine output)

struct CyclePredictionRange: Codable, Equatable {
    var earliestDayKey: String
    var medianDayKey: String
    var latestDayKey: String
}

struct MenstrualCycleSnapshot: Codable, Equatable {
    var asOfDayKey: String
    var trackingEnabled: Bool
    var phase: MenstrualPhase
    var dayInCycle: Int?
    var cycleLengthMedian: Double
    var cycleLengthMAD: Double
    var periodLengthMedian: Double
    var cyclesObserved: Int
    var ovulationDayInCycle: Int?
    var ovulationMethod: String?
    var fertileStartDayInCycle: Int?
    var fertileEndDayInCycle: Int?
    var nextPeriod: CyclePredictionRange?
    var nextOvulationDayKey: String?
    /// 0…1 overall confidence in phase + timing
    var confidence: Double
    var dataQuality: String
    var recommendRecoveryBias: Bool
    var trainingNote: String
    var readinessNote: String
    var insights: [String]
    var disclaimer: String
    var lastPeriodStartDayKey: String?
    var isCurrentlyBleeding: Bool
    var irregularityFlag: Bool
    /// Prediction accuracy from user feedback (MAE days) when available.
    var accuracyMAE: Double?
    var accuracySampleCount: Int
    var accuracyGrade: String
    /// Days of calibration offset applied (auto-learned from actual starts).
    var calibrationOffsetDays: Double
    /// 0…1 confidence in period-start timing specifically.
    var periodTimingConfidence: Double
    /// 0…1 confidence in ovulation/fertile labeling.
    var ovulationConfidence: Double
    /// Learned luteal days when enough high-signal cycles exist.
    var learnedLutealDays: Double?
    /// Engine method summary for transparency.
    var predictionMethodSummary: String
    /// User's stated cycle goal, passed through from settings.
    var cycleGoal: CycleGoal?
    /// Days elapsed since confirmed ovulation (only set in luteal phase with confirmed ovulation).
    var twwDaysElapsed: Int?
    /// Active health condition affecting cycle interpretation (nil = none).
    var condition: CycleCondition?
    /// True when Apple Watch wrist temperature (Series 8+) is contributing to BBT.
    var wristTemperatureAvailable: Bool
    /// Real-time 0…100 fertile-window confidence signal (nil when tracking off,
    /// hormonal contraception, condition suppresses fertile window, or no cycle anchor).
    var fertileScore: Int?
    /// Lifecycle stage — distinguishes still-bleeding from period-confirmed-finished.
    /// Phase alone cannot express "the bleed is over"; UI and partner coaching key off this.
    var stage: CycleStage = .unknown
    /// User confirmed period finished for the current episode.
    var periodEndConfirmed: Bool = false
    /// Days since effective period end (confirmed or last bleed day); nil if unknown.
    var daysSincePeriodEnd: Int? = nil
    /// Day count of the current/most recent bleed episode; nil if unknown.
    var currentPeriodDayCount: Int? = nil
    /// Effective end day key (user confirmation wins over last logged bleed day).
    var currentPeriodEndDayKey: String? = nil
    /// Shared one-sentence stage description for UI / partner / ARIA.
    var stageNarrative: String = ""
    /// Days until next period median estimate (negative if overdue); nil when unknown.
    var daysUntilNextPeriod: Int? = nil

    static let empty = MenstrualCycleSnapshot(
        asOfDayKey: "",
        trackingEnabled: false,
        phase: .unknown,
        dayInCycle: nil,
        cycleLengthMedian: 28,
        cycleLengthMAD: 0,
        periodLengthMedian: 5,
        cyclesObserved: 0,
        ovulationDayInCycle: nil,
        ovulationMethod: nil,
        fertileStartDayInCycle: nil,
        fertileEndDayInCycle: nil,
        nextPeriod: nil,
        nextOvulationDayKey: nil,
        confidence: 0,
        dataQuality: "no_data",
        recommendRecoveryBias: false,
        trainingNote: "Cycle tracking off or no data yet.",
        readinessNote: "Readiness uses biometrics only.",
        insights: [],
        disclaimer: MenstrualCycleEngine.disclaimer,
        lastPeriodStartDayKey: nil,
        isCurrentlyBleeding: false,
        irregularityFlag: false,
        accuracyMAE: nil,
        accuracySampleCount: 0,
        accuracyGrade: "learning",
        calibrationOffsetDays: 0,
        periodTimingConfidence: 0,
        ovulationConfidence: 0,
        learnedLutealDays: nil,
        predictionMethodSummary: "",
        cycleGoal: nil,
        twwDaysElapsed: nil,
        condition: nil,
        wristTemperatureAvailable: false,
        fertileScore: nil,
        stage: .unknown,
        periodEndConfirmed: false,
        daysSincePeriodEnd: nil,
        currentPeriodDayCount: nil,
        currentPeriodEndDayKey: nil,
        stageNarrative: "",
        daysUntilNextPeriod: nil
    )
}

// MARK: - Forecast archive (frozen predictions for honest MAE)

/// Snapshot of what we advertised for the upcoming period — scored when actual start arrives.
struct CycleForecastRecord: Codable, Equatable, Identifiable {
    var id: String
    var asOfDayKey: String
    var anchorPeriodStartDayKey: String
    var predictedMedianDayKey: String
    var earliestDayKey: String
    var latestDayKey: String
    var cycleLengthUsed: Double
    var calibrationOffsetUsed: Double
    var confidence: Double
    var methodSummary: String
    var createdAt: Date
    /// When scored against an actual start.
    var scoredActualStartDayKey: String?
    var scoredErrorDays: Int?

    var isOpen: Bool { scoredActualStartDayKey == nil }
}

// MARK: - Data evaluation (lifestyle quality — not diagnosis)

enum CycleQualityGrade: String, Codable, CaseIterable {
    case sparse, noisy, mixed, solid, highSignal

    var label: String {
        switch self {
        case .sparse: return "Sparse"
        case .noisy: return "Noisy"
        case .mixed: return "Mixed"
        case .solid: return "Solid"
        case .highSignal: return "High signal"
        }
    }

    var accentHex: String {
        switch self {
        case .sparse: return "6B7280"
        case .noisy: return "F59E0B"
        case .mixed: return "38BDF8"
        case .solid: return "22C55E"
        case .highSignal: return "A855F7"
        }
    }
}

enum CycleEvalIssue: String, Codable, CaseIterable, Identifiable {
    case sparseCycles
    case highVariability
    case signalConflictLhBbt
    case spottingAmbiguous
    case missingBbtInWindow
    case missingOpkInWindow
    case hormonalSimplified
    case overdueWindow
    case lowFeedback
    case partnerSparse

    var id: String { rawValue }

    var lifestyleCopy: String {
        switch self {
        case .sparseCycles:
            return "Only a few cycles logged — estimates stay wide until history grows."
        case .highVariability:
            return "Cycle lengths jump around — we keep a wider window on purpose."
        case .signalConflictLhBbt:
            return "Mid-cycle signals don’t fully agree — hierarchy applies, confidence stays humble."
        case .spottingAmbiguous:
            return "Spotting alone may not mark a full period start — confirm if flow increased."
        case .missingBbtInWindow:
            return "High-accuracy mode is on but BBT is thin near the fertile window."
        case .missingOpkInWindow:
            return "Optional OPK logging near fertile days can sharpen mid-cycle labels."
        case .hormonalSimplified:
            return "Hormonal contraception noted — phase labels are simplified for coaching."
        case .overdueWindow:
            return "Past the usual window — range widened and confidence tempered."
        case .lowFeedback:
            return "Few confirmed starts vs forecasts — confirm starts to teach the model."
        case .partnerSparse:
            return "Support logs are light — coaching stays general until more starts are shared."
        }
    }
}

struct CycleDataEvaluation: Codable, Equatable {
    var qualityGrade: CycleQualityGrade
    var issues: [CycleEvalIssue]
    var trustForPrediction: String // low | medium | high
    var userFacingSummary: String
    var recommendedActions: [String]
    var understoodSummary: String
    var teachingSummary: String

    static let empty = CycleDataEvaluation(
        qualityGrade: .sparse,
        issues: [],
        trustForPrediction: "low",
        userFacingSummary: "Not enough cycle signal yet for a sharp lifestyle estimate.",
        recommendedActions: ["log_period_start"],
        understoodSummary: "No active cycle data.",
        teachingSummary: "Log period starts so Forge can learn your personal timing."
    )
}

/// Redacted context for ARIA — numbers from engine only.
struct CycleAIContext: Codable, Equatable {
    var phase: String
    /// Lifecycle stage — distinguishes "on her period" from "period just finished",
    /// which phase alone cannot express.
    var stage: String = CycleStage.unknown.rawValue
    var periodEndConfirmed: Bool = false
    var daysSincePeriodEnd: Int?
    var daysUntilNextPeriod: Int?
    var dayInCycle: Int?
    var cycleLengthMedian: Double
    var cycleLengthMAD: Double
    var nextMedian: String?
    var nextEarliest: String?
    var nextLatest: String?
    var ovulationMethod: String?
    var confidence: Double
    var periodTimingConfidence: Double
    var ovulationConfidence: Double
    var accuracyMAE: Double?
    var accuracySampleCount: Int
    var qualityGrade: String
    var issues: [String]
    var highAccuracyMode: Bool
    var hormonal: Bool
    var irregular: Bool
    var lastUserAction: String?
    var isPartner: Bool
}

// MARK: - Prediction feedback & accuracy

/// One actual period start vs the prediction that was live before it.
struct CyclePredictionFeedback: Codable, Equatable, Identifiable {
    var id: String { actualStartDayKey + "|" + predictedMedianDayKey }
    var predictedMedianDayKey: String
    var actualStartDayKey: String
    /// Signed error: actual − predicted (days). Negative = period came early.
    var errorDays: Int
    var recordedAt: Date
}

// MARK: - Period end feedback (learns coaching preferences)

/// Overall feel of this period — noninvasive, personalization only.
enum PeriodSeverity: String, Codable, CaseIterable, Identifiable {
    case mild, moderate, severe
    var id: String { rawValue }

    var label: String {
        switch self {
        case .mild: return "Mild"
        case .moderate: return "Moderate"
        case .severe: return "Hard"
        }
    }

    var icon: String {
        switch self {
        case .mild: return "leaf.fill"
        case .moderate: return "drop.fill"
        case .severe: return "bolt.heart.fill"
        }
    }
}

enum PeriodEnergyLevel: String, Codable, CaseIterable, Identifiable {
    case low, okay, high
    var id: String { rawValue }

    var label: String {
        switch self {
        case .low: return "Low energy"
        case .okay: return "Okay"
        case .high: return "Still solid"
        }
    }
}

/// Length relative to what feels normal for this person (not a medical measure).
enum PeriodLengthFeel: String, Codable, CaseIterable, Identifiable {
    case shorter, typical, longer
    var id: String { rawValue }

    var label: String {
        switch self {
        case .shorter: return "Shorter"
        case .typical: return "Typical"
        case .longer: return "Longer"
        }
    }
}

/// Overall flow heaviness feel for the episode.
enum PeriodFlowFeel: String, Codable, CaseIterable, Identifiable {
    case lighter, typical, heavier
    var id: String { rawValue }

    var label: String {
        switch self {
        case .lighter: return "Lighter"
        case .typical: return "Typical"
        case .heavier: return "Heavier"
        }
    }
}

enum PeriodSleepQuality: String, Codable, CaseIterable, Identifiable {
    case poor, okay, good
    var id: String { rawValue }

    var label: String {
        switch self {
        case .poor: return "Rough sleep"
        case .okay: return "Okay"
        case .good: return "Slept well"
        }
    }

    var icon: String {
        switch self {
        case .poor: return "moon.zzz"
        case .okay: return "moon"
        case .good: return "moon.stars.fill"
        }
    }
}

enum PeriodMoodOverall: String, Codable, CaseIterable, Identifiable {
    case rough, mixed, steady
    var id: String { rawValue }

    var label: String {
        switch self {
        case .rough: return "Rough"
        case .mixed: return "Mixed"
        case .steady: return "Steady"
        }
    }

    var icon: String {
        switch self {
        case .rough: return "cloud.rain.fill"
        case .mixed: return "cloud.sun.fill"
        case .steady: return "sun.max.fill"
        }
    }
}

/// How much the period disrupted training / work / daily life.
enum PeriodLifeImpact: String, Codable, CaseIterable, Identifiable {
    case low, medium, high
    var id: String { rawValue }

    var label: String {
        switch self {
        case .low: return "Barely"
        case .medium: return "Some"
        case .high: return "Limited me"
        }
    }
}

/// Self-reported stress during this cycle — lifestyle context only.
enum PeriodStressLevel: String, Codable, CaseIterable, Identifiable {
    case low, medium, high
    var id: String { rawValue }

    var label: String {
        switch self {
        case .low: return "Low stress"
        case .medium: return "Medium"
        case .high: return "High stress"
        }
    }
}

enum CoachingHelpfulness: String, Codable, CaseIterable, Identifiable {
    case notHelpful, somewhat, very
    var id: String { rawValue }

    var label: String {
        switch self {
        case .notHelpful: return "Not helpful"
        case .somewhat: return "Somewhat"
        case .very: return "Very helpful"
        }
    }

    var score: Double {
        switch self {
        case .notHelpful: return 0
        case .somewhat: return 0.5
        case .very: return 1
        }
    }
}

enum PeriodCoachingTopic: String, Codable, CaseIterable, Identifiable {
    case rest, lighterTraining, heat, hydration, sleep, nutrition, empathy, mobility
    var id: String { rawValue }

    var label: String {
        switch self {
        case .rest: return "Rest / recovery"
        case .lighterTraining: return "Lighter training"
        case .heat: return "Heat / comfort"
        case .hydration: return "Hydration"
        case .sleep: return "Sleep"
        case .nutrition: return "Food / iron / mag"
        case .empathy: return "Softer tone"
        case .mobility: return "Mobility / yoga"
        }
    }

    var icon: String {
        switch self {
        case .rest: return "bed.double.fill"
        case .lighterTraining: return "figure.walk"
        case .heat: return "thermometer.sun.fill"
        case .hydration: return "drop.fill"
        case .sleep: return "moon.zzz.fill"
        case .nutrition: return "fork.knife"
        case .empathy: return "heart.fill"
        case .mobility: return "figure.flexibility"
        }
    }
}

/// Captured when the user marks period finished — on-device coaching personalization only.
struct PeriodEndFeedback: Codable, Equatable, Identifiable {
    var id: String { startDayKey + "|" + endDayKey }
    var startDayKey: String
    var endDayKey: String
    var dayCount: Int
    /// How was your period overall?
    var severity: PeriodSeverity
    /// 0–10 peak pain this episode.
    var peakPain: Int
    var energy: PeriodEnergyLevel
    /// Optional lifestyle context (all skippable / default-safe).
    var lengthFeel: PeriodLengthFeel?
    var flowFeel: PeriodFlowFeel?
    var sleepQuality: PeriodSleepQuality?
    var moodOverall: PeriodMoodOverall?
    var lifeImpact: PeriodLifeImpact?
    var stressLevel: PeriodStressLevel?
    var coachingHelpfulness: CoachingHelpfulness
    var whatHelped: [PeriodCoachingTopic]
    var whatDidntHelp: [PeriodCoachingTopic]
    var wantMore: [PeriodCoachingTopic]
    var wantLess: [PeriodCoachingTopic]
    var notes: String?
    var recordedAt: Date

    enum CodingKeys: String, CodingKey {
        case startDayKey, endDayKey, dayCount, severity, peakPain, energy
        case lengthFeel, flowFeel, sleepQuality, moodOverall, lifeImpact, stressLevel
        case coachingHelpfulness, whatHelped, whatDidntHelp, wantMore, wantLess, notes, recordedAt
    }

    init(
        startDayKey: String,
        endDayKey: String,
        dayCount: Int,
        severity: PeriodSeverity,
        peakPain: Int,
        energy: PeriodEnergyLevel,
        lengthFeel: PeriodLengthFeel? = nil,
        flowFeel: PeriodFlowFeel? = nil,
        sleepQuality: PeriodSleepQuality? = nil,
        moodOverall: PeriodMoodOverall? = nil,
        lifeImpact: PeriodLifeImpact? = nil,
        stressLevel: PeriodStressLevel? = nil,
        coachingHelpfulness: CoachingHelpfulness,
        whatHelped: [PeriodCoachingTopic],
        whatDidntHelp: [PeriodCoachingTopic],
        wantMore: [PeriodCoachingTopic],
        wantLess: [PeriodCoachingTopic],
        notes: String?,
        recordedAt: Date
    ) {
        self.startDayKey = startDayKey
        self.endDayKey = endDayKey
        self.dayCount = dayCount
        self.severity = severity
        self.peakPain = peakPain
        self.energy = energy
        self.lengthFeel = lengthFeel
        self.flowFeel = flowFeel
        self.sleepQuality = sleepQuality
        self.moodOverall = moodOverall
        self.lifeImpact = lifeImpact
        self.stressLevel = stressLevel
        self.coachingHelpfulness = coachingHelpfulness
        self.whatHelped = whatHelped
        self.whatDidntHelp = whatDidntHelp
        self.wantMore = wantMore
        self.wantLess = wantLess
        self.notes = notes
        self.recordedAt = recordedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startDayKey = try c.decode(String.self, forKey: .startDayKey)
        endDayKey = try c.decode(String.self, forKey: .endDayKey)
        dayCount = try c.decode(Int.self, forKey: .dayCount)
        severity = try c.decode(PeriodSeverity.self, forKey: .severity)
        peakPain = try c.decode(Int.self, forKey: .peakPain)
        energy = try c.decode(PeriodEnergyLevel.self, forKey: .energy)
        lengthFeel = try c.decodeIfPresent(PeriodLengthFeel.self, forKey: .lengthFeel)
        flowFeel = try c.decodeIfPresent(PeriodFlowFeel.self, forKey: .flowFeel)
        sleepQuality = try c.decodeIfPresent(PeriodSleepQuality.self, forKey: .sleepQuality)
        moodOverall = try c.decodeIfPresent(PeriodMoodOverall.self, forKey: .moodOverall)
        lifeImpact = try c.decodeIfPresent(PeriodLifeImpact.self, forKey: .lifeImpact)
        stressLevel = try c.decodeIfPresent(PeriodStressLevel.self, forKey: .stressLevel)
        coachingHelpfulness = try c.decode(CoachingHelpfulness.self, forKey: .coachingHelpfulness)
        whatHelped = try c.decodeIfPresent([PeriodCoachingTopic].self, forKey: .whatHelped) ?? []
        whatDidntHelp = try c.decodeIfPresent([PeriodCoachingTopic].self, forKey: .whatDidntHelp) ?? []
        wantMore = try c.decodeIfPresent([PeriodCoachingTopic].self, forKey: .wantMore) ?? []
        wantLess = try c.decodeIfPresent([PeriodCoachingTopic].self, forKey: .wantLess) ?? []
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        recordedAt = try c.decodeIfPresent(Date.self, forKey: .recordedAt) ?? Date()
    }
}

/// Running personalization from period-end feedbacks (what to do next cycle).
struct PeriodCoachingPreferences: Codable, Equatable {
    /// 0…1 extra recovery bias during menstruation.
    var recoveryBias: Double
    var preferLighterTraining: Bool
    var preferHeatComfort: Bool
    var preferEmpathyTone: Bool
    var preferHydrationSleep: Bool
    var preferNutritionTips: Bool
    var preferMobility: Bool
    var avoidIntensityPush: Bool
    /// Prefer sleep-focused tips when periods tend to disrupt sleep.
    var preferSleepFocus: Bool
    /// Prefer mood-aware / softer check-ins.
    var preferMoodSupport: Bool
    var sampleCount: Int
    var averageSeverity: Double
    var averageHelpfulness: Double
    var averageLifeImpact: Double
    var averageStress: Double
    var lastLearnedSummary: String?

    static let neutral = PeriodCoachingPreferences(
        recoveryBias: 0.35,
        preferLighterTraining: true,
        preferHeatComfort: false,
        preferEmpathyTone: true,
        preferHydrationSleep: true,
        preferNutritionTips: true,
        preferMobility: false,
        avoidIntensityPush: true,
        preferSleepFocus: false,
        preferMoodSupport: false,
        sampleCount: 0,
        averageSeverity: 0.5,
        averageHelpfulness: 0.5,
        averageLifeImpact: 0.35,
        averageStress: 0.4,
        lastLearnedSummary: nil
    )

    enum CodingKeys: String, CodingKey {
        case recoveryBias, preferLighterTraining, preferHeatComfort, preferEmpathyTone
        case preferHydrationSleep, preferNutritionTips, preferMobility, avoidIntensityPush
        case preferSleepFocus, preferMoodSupport
        case sampleCount, averageSeverity, averageHelpfulness, averageLifeImpact, averageStress
        case lastLearnedSummary
    }

    init(
        recoveryBias: Double,
        preferLighterTraining: Bool,
        preferHeatComfort: Bool,
        preferEmpathyTone: Bool,
        preferHydrationSleep: Bool,
        preferNutritionTips: Bool,
        preferMobility: Bool,
        avoidIntensityPush: Bool,
        preferSleepFocus: Bool = false,
        preferMoodSupport: Bool = false,
        sampleCount: Int,
        averageSeverity: Double,
        averageHelpfulness: Double,
        averageLifeImpact: Double = 0.35,
        averageStress: Double = 0.4,
        lastLearnedSummary: String?
    ) {
        self.recoveryBias = recoveryBias
        self.preferLighterTraining = preferLighterTraining
        self.preferHeatComfort = preferHeatComfort
        self.preferEmpathyTone = preferEmpathyTone
        self.preferHydrationSleep = preferHydrationSleep
        self.preferNutritionTips = preferNutritionTips
        self.preferMobility = preferMobility
        self.avoidIntensityPush = avoidIntensityPush
        self.preferSleepFocus = preferSleepFocus
        self.preferMoodSupport = preferMoodSupport
        self.sampleCount = sampleCount
        self.averageSeverity = averageSeverity
        self.averageHelpfulness = averageHelpfulness
        self.averageLifeImpact = averageLifeImpact
        self.averageStress = averageStress
        self.lastLearnedSummary = lastLearnedSummary
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        recoveryBias = try c.decodeIfPresent(Double.self, forKey: .recoveryBias) ?? 0.35
        preferLighterTraining = try c.decodeIfPresent(Bool.self, forKey: .preferLighterTraining) ?? true
        preferHeatComfort = try c.decodeIfPresent(Bool.self, forKey: .preferHeatComfort) ?? false
        preferEmpathyTone = try c.decodeIfPresent(Bool.self, forKey: .preferEmpathyTone) ?? true
        preferHydrationSleep = try c.decodeIfPresent(Bool.self, forKey: .preferHydrationSleep) ?? true
        preferNutritionTips = try c.decodeIfPresent(Bool.self, forKey: .preferNutritionTips) ?? true
        preferMobility = try c.decodeIfPresent(Bool.self, forKey: .preferMobility) ?? false
        avoidIntensityPush = try c.decodeIfPresent(Bool.self, forKey: .avoidIntensityPush) ?? true
        preferSleepFocus = try c.decodeIfPresent(Bool.self, forKey: .preferSleepFocus) ?? false
        preferMoodSupport = try c.decodeIfPresent(Bool.self, forKey: .preferMoodSupport) ?? false
        sampleCount = try c.decodeIfPresent(Int.self, forKey: .sampleCount) ?? 0
        averageSeverity = try c.decodeIfPresent(Double.self, forKey: .averageSeverity) ?? 0.5
        averageHelpfulness = try c.decodeIfPresent(Double.self, forKey: .averageHelpfulness) ?? 0.5
        averageLifeImpact = try c.decodeIfPresent(Double.self, forKey: .averageLifeImpact) ?? 0.35
        averageStress = try c.decodeIfPresent(Double.self, forKey: .averageStress) ?? 0.4
        lastLearnedSummary = try c.decodeIfPresent(String.self, forKey: .lastLearnedSummary)
    }

    mutating func learn(from feedback: PeriodEndFeedback) {
        sampleCount += 1
        let alpha = min(0.45, 1.0 / Double(max(2, sampleCount)))

        let severityScore: Double = {
            switch feedback.severity {
            case .mild: return 0.2
            case .moderate: return 0.55
            case .severe: return 0.9
            }
        }()
        averageSeverity = averageSeverity * (1 - alpha) + severityScore * alpha
        averageHelpfulness = averageHelpfulness * (1 - alpha) + feedback.coachingHelpfulness.score * alpha

        let impactScore: Double = {
            switch feedback.lifeImpact {
            case .low?: return 0.15
            case .medium?: return 0.5
            case .high?: return 0.9
            case nil: return averageLifeImpact
            }
        }()
        averageLifeImpact = averageLifeImpact * (1 - alpha) + impactScore * alpha

        let stressScore: Double = {
            switch feedback.stressLevel {
            case .low?: return 0.2
            case .medium?: return 0.5
            case .high?: return 0.85
            case nil: return averageStress
            }
        }()
        averageStress = averageStress * (1 - alpha) + stressScore * alpha

        let painBoost = Double(min(10, max(0, feedback.peakPain))) / 10.0
        let energyLow = feedback.energy == .low ? 0.25 : 0
        let sleepRough = feedback.sleepQuality == .poor ? 0.15 : 0
        let moodRough = feedback.moodOverall == .rough ? 0.1 : 0
        recoveryBias = min(1, max(0.1, recoveryBias * (1 - alpha) + (severityScore * 0.45 + painBoost * 0.25 + energyLow + sleepRough + moodRough + impactScore * 0.15) * alpha))

        if feedback.sleepQuality == .poor {
            preferSleepFocus = true
            preferHydrationSleep = true
        }
        if feedback.moodOverall == .rough || feedback.stressLevel == .high {
            preferMoodSupport = true
            preferEmpathyTone = true
        }
        if feedback.lifeImpact == .high {
            avoidIntensityPush = true
            preferLighterTraining = true
        }
        if feedback.flowFeel == .heavier {
            preferNutritionTips = true
            recoveryBias = min(1, recoveryBias + 0.05)
        }

        func boost(_ topic: PeriodCoachingTopic, helped: Bool, wantMore: Bool, wantLess: Bool) {
            let positive = (helped ? 1 : 0) + (wantMore ? 1 : 0) - (wantLess ? 1 : 0)
            guard positive != 0 else { return }
            switch topic {
            case .rest:
                if positive > 0 { recoveryBias = min(1, recoveryBias + 0.08) }
            case .lighterTraining:
                preferLighterTraining = positive > 0 || preferLighterTraining
                if positive < 0 { preferLighterTraining = false }
            case .heat:
                preferHeatComfort = positive > 0
            case .hydration, .sleep:
                preferHydrationSleep = positive >= 0 ? (positive > 0 || preferHydrationSleep) : false
                if topic == .sleep, positive > 0 { preferSleepFocus = true }
            case .nutrition:
                preferNutritionTips = positive >= 0 ? (positive > 0 || preferNutritionTips) : false
            case .empathy:
                preferEmpathyTone = positive >= 0 ? (positive > 0 || preferEmpathyTone) : false
                if positive > 0 { preferMoodSupport = true }
            case .mobility:
                preferMobility = positive > 0
            }
        }

        for t in PeriodCoachingTopic.allCases {
            boost(
                t,
                helped: feedback.whatHelped.contains(t),
                wantMore: feedback.wantMore.contains(t),
                wantLess: feedback.wantLess.contains(t)
            )
        }

        if feedback.severity == .severe || feedback.peakPain >= 7 || feedback.energy == .low {
            avoidIntensityPush = true
            preferLighterTraining = true
            recoveryBias = min(1, recoveryBias + 0.1)
        }
        if feedback.coachingHelpfulness == .notHelpful {
            preferEmpathyTone = true
            preferLighterTraining = true
            recoveryBias = min(1, recoveryBias + 0.12)
        }

        var bits: [String] = []
        if preferLighterTraining { bits.append("lighter training") }
        if preferHeatComfort { bits.append("heat/comfort") }
        if preferSleepFocus || preferHydrationSleep { bits.append("sleep & hydration") }
        if preferNutritionTips { bits.append("nutrition") }
        if preferMobility { bits.append("mobility") }
        if preferEmpathyTone || preferMoodSupport { bits.append("softer tone") }
        if avoidIntensityPush { bits.append("no intensity push") }
        if averageLifeImpact >= 0.6 { bits.append("more recovery buffer") }
        lastLearnedSummary = bits.isEmpty
            ? "Logged episode · adapting coaching"
            : "Next period: lean on " + bits.prefix(4).joined(separator: ", ")
    }

    var ariaTags: [String] {
        var tags = ["cycle:period_feedback_n:\(sampleCount)"]
        tags.append("cycle:recovery_pref:\(Int(recoveryBias * 100))")
        if preferLighterTraining { tags.append("cycle:prefer:lighter_training") }
        if preferHeatComfort { tags.append("cycle:prefer:heat") }
        if preferEmpathyTone { tags.append("cycle:prefer:empathy") }
        if preferHydrationSleep { tags.append("cycle:prefer:hydration_sleep") }
        if preferNutritionTips { tags.append("cycle:prefer:nutrition") }
        if preferMobility { tags.append("cycle:prefer:mobility") }
        if avoidIntensityPush { tags.append("cycle:prefer:avoid_intensity") }
        if preferSleepFocus { tags.append("cycle:prefer:sleep_focus") }
        if preferMoodSupport { tags.append("cycle:prefer:mood_support") }
        if averageLifeImpact >= 0.55 { tags.append("cycle:life_impact:high") }
        if averageStress >= 0.6 { tags.append("cycle:stress:elevated") }
        return tags
    }

    var coachingDirective: String {
        guard sampleCount > 0 else { return "" }
        var parts: [String] = [
            "User has given \(sampleCount) period-end feedback(s). Adapt menstruation coaching to their learned preferences. This data is for personal coaching only — never for ads, sale, or third-party profiling."
        ]
        if recoveryBias >= 0.6 || avoidIntensityPush {
            parts.append("Strongly favor recovery, auto-regulation, and optional sessions — do not push intensity on period days.")
        }
        if preferLighterTraining {
            parts.append("They respond well to lighter training suggestions (walk, technique, mobility).")
        }
        if preferHeatComfort {
            parts.append("Mention heat packs / comfort strategies when relevant.")
        }
        if preferHydrationSleep || preferSleepFocus {
            parts.append("Prioritize sleep quality and hydration tips.")
        }
        if preferSleepFocus {
            parts.append("Periods often disrupt their sleep — offer wind-down and sleep hygiene cues early in menstruation.")
        }
        if preferNutritionTips {
            parts.append("Include iron/magnesium/anti-inflammatory food cues briefly.")
        }
        if preferMobility {
            parts.append("Offer gentle mobility or yoga as a default movement option.")
        }
        if preferEmpathyTone || preferMoodSupport {
            parts.append("Use a warm, validating tone — never minimize symptoms.")
        }
        if preferMoodSupport {
            parts.append("Mood can dip during their period — check in gently; avoid toxic positivity.")
        }
        if averageLifeImpact >= 0.55 {
            parts.append("Their period often limits daily life/training — default to optional sessions and recovery framing.")
        }
        if averageStress >= 0.55 {
            parts.append("Cycles often coincide with higher stress — keep plans simple and stress-aware.")
        }
        if averageHelpfulness < 0.4 {
            parts.append("Prior coaching was not helpful enough — be more concrete and less generic.")
        }
        if let summary = lastLearnedSummary {
            parts.append("Personal summary: \(summary).")
        }
        return parts.joined(separator: " ")
    }
}

struct CycleAccuracyReport: Codable, Equatable {
    var sampleCount: Int
    var maeDays: Double?
    var medianAbsErrorDays: Double?
    var withinOneDayRate: Double?
    var withinTwoDayRate: Double?
    /// EMA of signed errors applied as offset on next predictions.
    var calibrationOffsetDays: Double
    /// learning | solid | excellent | market_leading
    var gradeLabel: String
    var gradeDetail: String

    static let empty = CycleAccuracyReport(
        sampleCount: 0,
        maeDays: nil,
        medianAbsErrorDays: nil,
        withinOneDayRate: nil,
        withinTwoDayRate: nil,
        calibrationOffsetDays: 0,
        gradeLabel: "learning",
        gradeDetail: "Log a few period starts so we can measure prediction error."
    )

    static func compute(from feedback: [CyclePredictionFeedback], calibrationOffset: Double) -> CycleAccuracyReport {
        guard !feedback.isEmpty else {
            return .empty
        }
        let absErrors = feedback.map { abs($0.errorDays) }
        let mae = Double(absErrors.reduce(0, +)) / Double(absErrors.count)
        let sorted = absErrors.sorted()
        let med: Double = {
            let m = sorted.count / 2
            if sorted.count % 2 == 0 {
                return Double(sorted[m - 1] + sorted[m]) / 2
            }
            return Double(sorted[m])
        }()
        let w1 = Double(absErrors.filter { $0 <= 1 }.count) / Double(absErrors.count)
        let w2 = Double(absErrors.filter { $0 <= 2 }.count) / Double(absErrors.count)

        let grade: (String, String)
        if feedback.count >= 6, mae <= 1.2, w1 >= 0.7 {
            grade = ("market_leading", "Among the most accurate consumer cycle predictors — multi-signal + feedback-corrected.")
        } else if feedback.count >= 4, mae <= 1.8, w2 >= 0.75 {
            grade = ("excellent", "Excellent personal accuracy with feedback auto-correction active.")
        } else if feedback.count >= 2, mae <= 2.5 {
            grade = ("solid", "Solid personalization — keep logging starts to tighten the window.")
        } else {
            grade = ("learning", "Still learning your rhythm. Accuracy improves after 2–3 confirmed starts.")
        }

        return CycleAccuracyReport(
            sampleCount: feedback.count,
            maeDays: mae,
            medianAbsErrorDays: med,
            withinOneDayRate: w1,
            withinTwoDayRate: w2,
            calibrationOffsetDays: calibrationOffset,
            gradeLabel: grade.0,
            gradeDetail: grade.1
        )
    }
}

// MARK: - User settings

struct MenstrualTrackingSettings: Codable, Equatable {
    var enabled: Bool
    /// When true, ARIA uses cycle for training language + intensity bias (never medical claims).
    var shareWithAria: Bool
    var averageCycleOverride: Int?
    var averagePeriodOverride: Int?
    /// Typical luteal length if known (default 14).
    var typicalLutealDays: Int
    var usesHormonalContraception: Bool
    var notes: String
    /// User acknowledged cycle privacy policy before enabling share/tracking.
    var privacyAcknowledged: Bool
    /// Auto-learned day offset applied to next-period median (EMA of prediction errors).
    var calibrationOffsetDays: Double
    /// Encourages BBT/OPK + same-day confirm for sharper personal timing estimates.
    var highAccuracyMode: Bool
    /// Temporary widen when user reports still no period past the window.
    var overdueWidenDays: Int
    /// Personal luteal median learned from LH/BBT-confirmed cycles (nil = use typicalLutealDays).
    var learnedLutealDays: Double?
    // Notification preferences
    var bbtReminderEnabled: Bool
    var bbtReminderHour: Int
    var fertileWindowAlertEnabled: Bool
    var periodReminderEnabled: Bool
    /// User's stated cycle goal.
    var cycleGoal: CycleGoal
    /// Active health condition for personalised engine behaviour and ARIA coaching.
    var condition: CycleCondition
    /// Last bleeding day the user confirmed ("Period finished"). Belongs to the current
    /// episode only; a new period start must clear it so it cannot suppress a fresh bleed.
    var confirmedPeriodEndDayKey: String?

    enum CodingKeys: String, CodingKey {
        case enabled, shareWithAria, averageCycleOverride, averagePeriodOverride
        case typicalLutealDays, usesHormonalContraception, notes
        case privacyAcknowledged, calibrationOffsetDays, highAccuracyMode, overdueWidenDays
        case learnedLutealDays
        case bbtReminderEnabled, bbtReminderHour, fertileWindowAlertEnabled, periodReminderEnabled
        case cycleGoal, condition, confirmedPeriodEndDayKey
    }

    static let `default` = MenstrualTrackingSettings(
        enabled: false,
        shareWithAria: true,
        averageCycleOverride: nil,
        averagePeriodOverride: nil,
        typicalLutealDays: 14,
        usesHormonalContraception: false,
        notes: "",
        privacyAcknowledged: false,
        calibrationOffsetDays: 0,
        highAccuracyMode: false,
        overdueWidenDays: 0,
        learnedLutealDays: nil,
        cycleGoal: .general,
        condition: .none,
        confirmedPeriodEndDayKey: nil
    )

    init(
        enabled: Bool,
        shareWithAria: Bool,
        averageCycleOverride: Int?,
        averagePeriodOverride: Int?,
        typicalLutealDays: Int,
        usesHormonalContraception: Bool,
        notes: String,
        privacyAcknowledged: Bool = false,
        calibrationOffsetDays: Double = 0,
        highAccuracyMode: Bool = false,
        overdueWidenDays: Int = 0,
        learnedLutealDays: Double? = nil,
        bbtReminderEnabled: Bool = false,
        bbtReminderHour: Int = 7,
        fertileWindowAlertEnabled: Bool = false,
        periodReminderEnabled: Bool = false,
        cycleGoal: CycleGoal = .general,
        condition: CycleCondition = .none,
        confirmedPeriodEndDayKey: String? = nil
    ) {
        self.enabled = enabled
        self.shareWithAria = shareWithAria
        self.averageCycleOverride = averageCycleOverride
        self.averagePeriodOverride = averagePeriodOverride
        self.typicalLutealDays = typicalLutealDays
        self.usesHormonalContraception = usesHormonalContraception
        self.notes = notes
        self.privacyAcknowledged = privacyAcknowledged
        self.calibrationOffsetDays = calibrationOffsetDays
        self.highAccuracyMode = highAccuracyMode
        self.overdueWidenDays = overdueWidenDays
        self.learnedLutealDays = learnedLutealDays
        self.bbtReminderEnabled = bbtReminderEnabled
        self.bbtReminderHour = bbtReminderHour
        self.fertileWindowAlertEnabled = fertileWindowAlertEnabled
        self.periodReminderEnabled = periodReminderEnabled
        self.cycleGoal = cycleGoal
        self.condition = condition
        self.confirmedPeriodEndDayKey = confirmedPeriodEndDayKey
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        shareWithAria = try c.decode(Bool.self, forKey: .shareWithAria)
        averageCycleOverride = try c.decodeIfPresent(Int.self, forKey: .averageCycleOverride)
        averagePeriodOverride = try c.decodeIfPresent(Int.self, forKey: .averagePeriodOverride)
        typicalLutealDays = try c.decodeIfPresent(Int.self, forKey: .typicalLutealDays) ?? 14
        usesHormonalContraception = try c.decodeIfPresent(Bool.self, forKey: .usesHormonalContraception) ?? false
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        privacyAcknowledged = try c.decodeIfPresent(Bool.self, forKey: .privacyAcknowledged) ?? false
        calibrationOffsetDays = try c.decodeIfPresent(Double.self, forKey: .calibrationOffsetDays) ?? 0
        highAccuracyMode = try c.decodeIfPresent(Bool.self, forKey: .highAccuracyMode) ?? false
        overdueWidenDays = try c.decodeIfPresent(Int.self, forKey: .overdueWidenDays) ?? 0
        learnedLutealDays = try c.decodeIfPresent(Double.self, forKey: .learnedLutealDays)
        bbtReminderEnabled = try c.decodeIfPresent(Bool.self, forKey: .bbtReminderEnabled) ?? false
        bbtReminderHour = try c.decodeIfPresent(Int.self, forKey: .bbtReminderHour) ?? 7
        fertileWindowAlertEnabled = try c.decodeIfPresent(Bool.self, forKey: .fertileWindowAlertEnabled) ?? false
        periodReminderEnabled = try c.decodeIfPresent(Bool.self, forKey: .periodReminderEnabled) ?? false
        cycleGoal = try c.decodeIfPresent(CycleGoal.self, forKey: .cycleGoal) ?? .general
        condition = try c.decodeIfPresent(CycleCondition.self, forKey: .condition) ?? .none
        confirmedPeriodEndDayKey = try c.decodeIfPresent(String.self, forKey: .confirmedPeriodEndDayKey)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(shareWithAria, forKey: .shareWithAria)
        try c.encodeIfPresent(averageCycleOverride, forKey: .averageCycleOverride)
        try c.encodeIfPresent(averagePeriodOverride, forKey: .averagePeriodOverride)
        try c.encode(typicalLutealDays, forKey: .typicalLutealDays)
        try c.encode(usesHormonalContraception, forKey: .usesHormonalContraception)
        try c.encode(notes, forKey: .notes)
        try c.encode(privacyAcknowledged, forKey: .privacyAcknowledged)
        try c.encode(calibrationOffsetDays, forKey: .calibrationOffsetDays)
        try c.encode(highAccuracyMode, forKey: .highAccuracyMode)
        try c.encode(overdueWidenDays, forKey: .overdueWidenDays)
        try c.encodeIfPresent(learnedLutealDays, forKey: .learnedLutealDays)
        try c.encode(bbtReminderEnabled, forKey: .bbtReminderEnabled)
        try c.encode(bbtReminderHour, forKey: .bbtReminderHour)
        try c.encode(fertileWindowAlertEnabled, forKey: .fertileWindowAlertEnabled)
        try c.encode(periodReminderEnabled, forKey: .periodReminderEnabled)
        try c.encode(cycleGoal, forKey: .cycleGoal)
        try c.encode(condition, forKey: .condition)
        try c.encodeIfPresent(confirmedPeriodEndDayKey, forKey: .confirmedPeriodEndDayKey)
    }

    /// Effective luteal for calendar fallback.
    var effectiveLutealDays: Int {
        if let learned = learnedLutealDays {
            return max(10, min(16, Int(learned.rounded())))
        }
        return max(10, min(16, typicalLutealDays))
    }
}

// MARK: - Supported-person cycle (partner, child, family)

/// Who you're supporting — drives ARIA tone (romantic vs parent vs family).
enum CycleSupportRole: String, Codable, CaseIterable, Identifiable {
    case romantic
    case child
    case family
    case friend
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .romantic: return "Partner / spouse"
        case .child:    return "Daughter / child"
        case .family:   return "Family"
        case .friend:   return "Friend"
        case .other:    return "Someone I support"
        }
    }

    var shortLabel: String {
        switch self {
        case .romantic: return "Partner"
        case .child:    return "Child"
        case .family:   return "Family"
        case .friend:   return "Friend"
        case .other:    return "Support"
        }
    }

    var icon: String {
        switch self {
        case .romantic: return "heart.fill"
        case .child:    return "figure.and.child.holdinghands"
        case .family:   return "house.fill"
        case .friend:   return "person.2.fill"
        case .other:    return "hands.sparkles.fill"
        }
    }

    /// Preset relationship labels for the role.
    var suggestedLabels: [String] {
        switch self {
        case .romantic: return ["partner", "girlfriend", "boyfriend", "wife", "husband", "spouse", "fiancé"]
        case .child:    return ["daughter", "child", "kid", "teen"]
        case .family:   return ["sister", "mom", "mother", "sibling", "family"]
        case .friend:   return ["friend", "roommate"]
        case .other:    return ["person I support"]
        }
    }

    /// Infer role from free-text relationship label (backward compatible).
    static func infer(from label: String) -> CycleSupportRole {
        let l = label.lowercased()
        if l.contains("daughter") || l.contains("son") || l.contains("child")
            || l.contains("kid") || l.contains("teen") || l.contains("my girl") && l.contains("child") {
            return .child
        }
        // "my girl" alone is ambiguous — prefer romantic unless child keywords present
        if l.contains("sister") || l.contains("mother") || l.contains("mom")
            || l.contains("sibling") || l.contains("niece") || l.contains("aunt") {
            return .family
        }
        if l.contains("friend") || l.contains("roommate") {
            return .friend
        }
        if l.contains("wife") || l.contains("girlfriend") || l.contains("boyfriend")
            || l.contains("husband") || l.contains("spouse") || l.contains("fiancé")
            || l.contains("fiance") || l.contains("partner") {
            return .romantic
        }
        return .other
    }
}

/// Tracking another person's cycle so ARIA can coach *you* on support —
/// partners, daughters, family. Never medical advice for them. Consent required.
struct PartnerCycleSettings: Codable, Equatable {
    var enabled: Bool
    /// Optional first name / nickname used in ARIA copy ("Maya is in luteal…").
    var partnerName: String
    /// How you refer to them (partner, girlfriend, wife, daughter…).
    var relationshipLabel: String
    /// Explicit role for coaching tone. Defaults inferred from label if missing in old data.
    var supportRole: CycleSupportRole
    /// Share phase/day with ARIA for relationship / family coaching.
    var shareWithAria: Bool
    var averageCycleOverride: Int?
    var averagePeriodOverride: Int?
    var typicalLutealDays: Int
    var usesHormonalContraception: Bool
    /// User confirmed they have consent (partner) or appropriate caregiver context (child).
    var consentAcknowledged: Bool
    var notes: String
    /// Last bleeding day confirmed for the supported person. Drives the return from
    /// period-support coaching back to everyday support.
    var confirmedPeriodEndDayKey: String?

    enum CodingKeys: String, CodingKey {
        case enabled, partnerName, relationshipLabel, supportRole, shareWithAria
        case averageCycleOverride, averagePeriodOverride, typicalLutealDays
        case usesHormonalContraception, consentAcknowledged, notes
        case confirmedPeriodEndDayKey
    }

    static let `default` = PartnerCycleSettings(
        enabled: false,
        partnerName: "",
        relationshipLabel: "partner",
        supportRole: .romantic,
        shareWithAria: true,
        averageCycleOverride: nil,
        averagePeriodOverride: nil,
        typicalLutealDays: 14,
        usesHormonalContraception: false,
        consentAcknowledged: false,
        notes: "",
        confirmedPeriodEndDayKey: nil
    )

    init(
        enabled: Bool,
        partnerName: String,
        relationshipLabel: String,
        supportRole: CycleSupportRole = .romantic,
        shareWithAria: Bool,
        averageCycleOverride: Int?,
        averagePeriodOverride: Int?,
        typicalLutealDays: Int,
        usesHormonalContraception: Bool,
        consentAcknowledged: Bool,
        notes: String,
        confirmedPeriodEndDayKey: String? = nil
    ) {
        self.enabled = enabled
        self.partnerName = partnerName
        self.relationshipLabel = relationshipLabel
        self.supportRole = supportRole
        self.shareWithAria = shareWithAria
        self.averageCycleOverride = averageCycleOverride
        self.averagePeriodOverride = averagePeriodOverride
        self.typicalLutealDays = typicalLutealDays
        self.usesHormonalContraception = usesHormonalContraception
        self.consentAcknowledged = consentAcknowledged
        self.notes = notes
        self.confirmedPeriodEndDayKey = confirmedPeriodEndDayKey
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        partnerName = try c.decode(String.self, forKey: .partnerName)
        relationshipLabel = try c.decode(String.self, forKey: .relationshipLabel)
        shareWithAria = try c.decode(Bool.self, forKey: .shareWithAria)
        averageCycleOverride = try c.decodeIfPresent(Int.self, forKey: .averageCycleOverride)
        averagePeriodOverride = try c.decodeIfPresent(Int.self, forKey: .averagePeriodOverride)
        typicalLutealDays = try c.decodeIfPresent(Int.self, forKey: .typicalLutealDays) ?? 14
        usesHormonalContraception = try c.decodeIfPresent(Bool.self, forKey: .usesHormonalContraception) ?? false
        consentAcknowledged = try c.decodeIfPresent(Bool.self, forKey: .consentAcknowledged) ?? false
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        confirmedPeriodEndDayKey = try c.decodeIfPresent(String.self, forKey: .confirmedPeriodEndDayKey)
        if let role = try c.decodeIfPresent(CycleSupportRole.self, forKey: .supportRole) {
            supportRole = role
        } else {
            supportRole = CycleSupportRole.infer(from: relationshipLabel)
        }
    }

    var displayName: String {
        let trimmed = partnerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? relationshipLabel.capitalized : trimmed
    }

    /// Resolved role (prefers stored, falls back to label inference).
    var resolvedRole: CycleSupportRole {
        if supportRole != .other { return supportRole }
        let inferred = CycleSupportRole.infer(from: relationshipLabel)
        return inferred == .other ? supportRole : inferred
    }
}

/// Support playbook derived from phase (for the user — partner, parent, or family member).
struct PartnerSupportBrief: Equatable {
    var partnerLabel: String
    var role: CycleSupportRole
    var phase: MenstrualPhase
    /// Lifecycle position — lets the UI show the period-finished hand-off explicitly
    /// instead of silently swapping in generic follicular advice.
    var stage: CycleStage = .unknown
    var dayInCycle: Int?
    var confidence: Double
    var headline: String
    var supportMoves: [String]
    var avoidMoves: [String]
    /// Date ideas (romantic) or activity / family plan ideas (parent/family).
    var dateIdeas: [String]
    /// Intimacy note for romantic roles; privacy/dignity note for child/family.
    var intimacyNote: String
    var trainingTogetherNote: String
    var communicationTip: String
    var disclaimer: String

    static let disclaimer = """
    Supported-person cycle coaching is lifestyle guidance based on data you enter. \
    It is not medical advice for them, not birth control, and not a substitute for their clinician. \
    Only log what they (or, for a minor, what is appropriate in your caregiver role) consent to share. \
    For daughters and children: protect privacy, skip body commentary, and escalate severe pain to a clinician.

    \(CyclePrivacy.shortPromise) \(CyclePrivacy.partnerExtra)
    """
}

// MARK: - Day key helpers

enum CycleDayKey {
    /// Day keys are pure `yyyy-MM-dd` calendar labels. They are built from calendar
    /// components rather than a cached `DateFormatter` so a timezone change mid-session
    /// (travel, DST) can never emit a key for the wrong local day.
    static func key(for date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard let y = c.year, let m = c.month, let d = c.day else { return "" }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    /// Local **noon** of the given day. Noon (not midnight) keeps day arithmetic exact
    /// across DST transitions, including zones where 00:00 does not exist on some dates.
    static func date(from key: String) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        var comps = DateComponents()
        comps.year = y
        comps.month = m
        comps.day = d
        comps.hour = 12
        guard let date = Calendar.current.date(from: comps) else { return nil }
        // Reject non-existent dates that the calendar rolled over (e.g. 2026-02-31).
        let round = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard round.year == y, round.month == m, round.day == d else { return nil }
        return date
    }

    /// Midnight of the given day — for anything that needs a day *boundary* rather than
    /// a stable anchor (HealthKit sample windows, calendar comparisons).
    static func startOfDay(from key: String) -> Date? {
        date(from: key).map { Calendar.current.startOfDay(for: $0) }
    }

    static func addDays(_ key: String, _ days: Int) -> String? {
        guard let d = date(from: key),
              let next = Calendar.current.date(byAdding: .day, value: days, to: d) else { return nil }
        return self.key(for: next)
    }

    static func daysBetween(_ a: String, _ b: String) -> Int? {
        guard let da = date(from: a), let db = date(from: b) else { return nil }
        return Calendar.current.dateComponents([.day], from: da, to: db).day
    }

    /// Whole days from today to `key` (negative = in the past).
    static func daysFromToday(to key: String) -> Int? {
        daysBetween(self.key(), key)
    }

    /// Short, locale-aware display form ("Aug 3"). Falls back to the raw key.
    static func shortDisplay(_ key: String) -> String {
        guard let d = date(from: key) else { return key }
        return d.formatted(.dateTime.month(.abbreviated).day())
    }
}
