import Foundation
import SwiftUI
import ForgeCore

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
    /// Running / strength / mixed — ARIA translates this into phase-aware volume.
    var lifestyleGoal: CycleLifestyleGoal
    /// How to train while bleeding. Default easy miles, not a forced rest day.
    var periodTrainingStyle: CyclePeriodTrainingStyle
    /// Lock screen / Home / Watch: stealth, kind, or clinical.
    var discretionMode: CycleDiscretionMode
    /// Face ID (or device passcode) before Cycle Health opens.
    var cycleLockEnabled: Bool
    /// Owner tapped “need extra care” on this day; digest stays thoughtfulness-only.
    var needExtraCareDayKey: String?
    /// Active health condition for personalised engine behaviour and ARIA coaching.
    var condition: CycleCondition
    /// Last bleeding day the user confirmed ("Period finished"). Belongs to the current
    /// episode only; a new period start must clear it so it cannot suppress a fresh bleed.
    var confirmedPeriodEndDayKey: String?
    /// How much a support person may see. Default is Support coach — never a chart.
    var partnerShareTier: PartnerShareTier

    enum CodingKeys: String, CodingKey {
        case enabled, shareWithAria, averageCycleOverride, averagePeriodOverride
        case typicalLutealDays, usesHormonalContraception, notes
        case privacyAcknowledged, calibrationOffsetDays, highAccuracyMode, overdueWidenDays
        case learnedLutealDays
        case bbtReminderEnabled, bbtReminderHour, fertileWindowAlertEnabled, periodReminderEnabled
        case cycleGoal, lifestyleGoal, periodTrainingStyle, discretionMode, cycleLockEnabled, needExtraCareDayKey
        case condition, confirmedPeriodEndDayKey, partnerShareTier
    }

    static let `default` = MenstrualTrackingSettings(
        enabled: false,
        shareWithAria: false,
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
        lifestyleGoal: CycleLifestyleGoal = .none,
        periodTrainingStyle: CyclePeriodTrainingStyle = .easy,
        discretionMode: CycleDiscretionMode = .clinical,
        cycleLockEnabled: Bool = false,
        needExtraCareDayKey: String? = nil,
        condition: CycleCondition = .none,
        confirmedPeriodEndDayKey: String? = nil,
        partnerShareTier: PartnerShareTier = .supportCoach
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
        self.lifestyleGoal = lifestyleGoal
        self.periodTrainingStyle = periodTrainingStyle
        self.discretionMode = discretionMode
        self.cycleLockEnabled = cycleLockEnabled
        self.needExtraCareDayKey = needExtraCareDayKey
        self.condition = condition
        self.confirmedPeriodEndDayKey = confirmedPeriodEndDayKey
        self.partnerShareTier = partnerShareTier
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        shareWithAria = try c.decodeIfPresent(Bool.self, forKey: .shareWithAria) ?? false
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
        lifestyleGoal = try c.decodeIfPresent(CycleLifestyleGoal.self, forKey: .lifestyleGoal) ?? .none
        periodTrainingStyle = try c.decodeIfPresent(CyclePeriodTrainingStyle.self, forKey: .periodTrainingStyle) ?? .easy
        discretionMode = try c.decodeIfPresent(CycleDiscretionMode.self, forKey: .discretionMode) ?? .clinical
        cycleLockEnabled = try c.decodeIfPresent(Bool.self, forKey: .cycleLockEnabled) ?? false
        needExtraCareDayKey = try c.decodeIfPresent(String.self, forKey: .needExtraCareDayKey)
        condition = try c.decodeIfPresent(CycleCondition.self, forKey: .condition) ?? .none
        confirmedPeriodEndDayKey = try c.decodeIfPresent(String.self, forKey: .confirmedPeriodEndDayKey)
        partnerShareTier = try c.decodeIfPresent(PartnerShareTier.self, forKey: .partnerShareTier) ?? .supportCoach
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
        try c.encode(lifestyleGoal, forKey: .lifestyleGoal)
        try c.encode(periodTrainingStyle, forKey: .periodTrainingStyle)
        try c.encode(discretionMode, forKey: .discretionMode)
        try c.encode(cycleLockEnabled, forKey: .cycleLockEnabled)
        try c.encodeIfPresent(needExtraCareDayKey, forKey: .needExtraCareDayKey)
        try c.encode(condition, forKey: .condition)
        try c.encodeIfPresent(confirmedPeriodEndDayKey, forKey: .confirmedPeriodEndDayKey)
        try c.encode(partnerShareTier, forKey: .partnerShareTier)
    }

    /// Effective luteal for calendar fallback.
    var effectiveLutealDays: Int {
        if let learned = learnedLutealDays {
            return max(10, min(16, Int(learned.rounded())))
        }
        return max(10, min(16, typicalLutealDays))
    }

    /// Extra-care ping is live for today and yesterday — then it expires.
    func extraCareIsActive(asOf dayKey: String = CycleDayKey.key()) -> Bool {
        guard let start = needExtraCareDayKey,
              let days = CycleDayKey.daysBetween(start, dayKey) else { return false }
        return (0...1).contains(days)
    }
}
