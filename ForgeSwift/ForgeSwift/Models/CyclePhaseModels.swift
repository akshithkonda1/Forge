import Foundation
import SwiftUI

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

    /// How the end of the *current* bleed was determined. The UI must not present a
    /// projection the same way it presents a fact: `.projected` is offered for
    /// confirmation, the other two are simply true.
    enum PeriodEndSource: String, Codable, Hashable {
        /// The user tapped "Period finished". Always wins, takes effect immediately.
        case confirmed
        /// A logged non-bleeding day after the last bleeding day — real evidence
        /// the flow stopped, not merely an absence of logs.
        case observed
        /// Derived from the learned period length, clamped to `periodDayRange`.
        /// Used when logging stopped without any signal that the bleeding did.
        case projected
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
    /// How `currentPeriodEndDayKey` was arrived at. `.projected` means it was derived
    /// from the learned period length rather than observed, so the UI should offer it
    /// for confirmation rather than state it as fact.
    var periodEndSource: CycleBiology.PeriodEndSource? = nil
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
