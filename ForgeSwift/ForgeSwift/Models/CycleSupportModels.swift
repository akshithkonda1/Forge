import Foundation
import SwiftUI

/// Who you're supporting — drives ARIA tone (romantic vs parent vs family).
enum CycleSupportRole: String, Codable, CaseIterable, Identifiable {
    case romantic
    case child
    case family
    case friend
    case other

    var id: String { rawValue }

    /// Partner, relative, or parent — the only roles the owner can assign.
    static var selectableRoles: [CycleSupportRole] { [.romantic, .family, .child] }

    var label: String {
        switch self {
        case .romantic: return "Partner"
        case .child:    return "Parent"
        case .family:   return "Relative"
        case .friend:   return "Relative"
        case .other:    return "Relative"
        }
    }

    var shortLabel: String { label }

    var icon: String {
        switch self {
        case .romantic: return "heart.fill"
        case .child:    return "figure.and.child.holdinghands"
        case .family:   return "house.fill"
        case .friend:   return "house.fill"
        case .other:    return "house.fill"
        }
    }

    var pickerDetail: String {
        switch self {
        case .romantic:
            return "Girlfriend, boyfriend, wife, husband, spouse. Comfort and intimacy notes stay here."
            case .child:
                return "You are a parent — including of a minor — or they are your parent. Care and dignity, never a partner lens."
        case .family, .friend, .other:
            return "Sister, brother, mom, dad, family. No intimacy material."
        }
    }

    /// Preset relationship labels for the role.
    var suggestedLabels: [String] {
        switch self {
        case .romantic: return ["partner", "girlfriend", "boyfriend", "wife", "husband", "spouse", "fiancé"]
        case .child:    return ["parent", "mom", "dad", "mother", "father", "daughter", "child", "kid", "teen"]
        case .family:   return ["sister", "brother", "mom", "dad", "mother", "father", "sibling", "family"]
        case .friend:   return ["relative"]
        case .other:    return ["relative"]
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
        shareWithAria: false,
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

/// One person you support — partner, daughter, sister, friend.
///
/// First-class, not a costume on a single “partner” slot. Each row has its
/// own settings, logs, and optional CloudKit owner id so a period-finished
/// write cannot land on the wrong share.
struct SupportedPerson: Identifiable, Codable, Equatable {
    var id: String
    var settings: PartnerCycleSettings
    var logs: [CycleDayLog]
    /// CloudKit zone owner when they shared a digest with us. Links local
    /// notes to the incoming share so finish writes the right zone.
    var cloudKitOwnerID: String?
    var createdAt: Date
    var updatedAt: Date

    var displayName: String { settings.displayName }
    var role: CycleSupportRole { settings.resolvedRole }

    static func make(
        settings: PartnerCycleSettings = .default,
        logs: [CycleDayLog] = [],
        cloudKitOwnerID: String? = nil,
        id: String = UUID().uuidString
    ) -> SupportedPerson {
        let now = Date()
        return SupportedPerson(
            id: id,
            settings: settings,
            logs: logs,
            cloudKitOwnerID: cloudKitOwnerID,
            createdAt: now,
            updatedAt: now
        )
    }

    enum CodingKeys: String, CodingKey {
        case id, settings, logs, cloudKitOwnerID, createdAt, updatedAt
    }

    init(
        id: String,
        settings: PartnerCycleSettings,
        logs: [CycleDayLog],
        cloudKitOwnerID: String?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.settings = settings
        self.logs = logs
        self.cloudKitOwnerID = cloudKitOwnerID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        settings = try c.decode(PartnerCycleSettings.self, forKey: .settings)
        logs = try c.decodeIfPresent([CycleDayLog].self, forKey: .logs) ?? []
        cloudKitOwnerID = try c.decodeIfPresent(String.self, forKey: .cloudKitOwnerID)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
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
