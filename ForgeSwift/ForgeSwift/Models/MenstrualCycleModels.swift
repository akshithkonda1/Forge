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
}

enum CycleSymptom: String, Codable, CaseIterable, Identifiable {
    case cramps, headache, bloating, fatigue, moodLow, moodHigh
    case breastTenderness, backache, acne, cravings, insomnia, nausea
    case energyHigh, libidoHigh, brainFog

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

    init(
        dayKey: String,
        flow: MenstrualFlowLevel = .none,
        symptoms: [CycleSymptom] = [],
        bbtCelsius: Double? = nil,
        ovulationTest: OvulationTestResult? = nil,
        mucus: CervicalMucusQuality? = nil,
        notes: String? = nil,
        source: String = "manual",
        updatedAt: Date = Date()
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
    }
}

// MARK: - Episodes & phases

struct PeriodEpisode: Identifiable, Codable, Equatable {
    var id: String
    var startDayKey: String
    var endDayKey: String
    var peakFlow: MenstrualFlowLevel
    var dayCount: Int
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
        irregularityFlag: false
    )
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

    static let `default` = MenstrualTrackingSettings(
        enabled: false,
        shareWithAria: true,
        averageCycleOverride: nil,
        averagePeriodOverride: nil,
        typicalLutealDays: 14,
        usesHormonalContraception: false,
        notes: ""
    )
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

    enum CodingKeys: String, CodingKey {
        case enabled, partnerName, relationshipLabel, supportRole, shareWithAria
        case averageCycleOverride, averagePeriodOverride, typicalLutealDays
        case usesHormonalContraception, consentAcknowledged, notes
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
        notes: ""
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
        notes: String
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
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = Calendar.current.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func key(for date: Date = Date()) -> String {
        formatter.string(from: Calendar.current.startOfDay(for: date))
    }

    static func date(from key: String) -> Date? {
        formatter.date(from: key)
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
}
