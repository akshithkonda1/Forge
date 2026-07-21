import Foundation

// MARK: - Canonical relationship labels

/// Specific relationship labels ARIA understands instantly.
/// Broader than CycleSupportRole — “wife” ≠ “girlfriend” ≠ “daughter”.
enum AriaRelationshipLabel: String, Codable, CaseIterable, Identifiable {
    case wife, husband, girlfriend, boyfriend, partner, spouse, fiance
    case daughter, son, child, teen
    case sister, brother, mom, mother, dad, father, sibling, family
    case friend, roommate, coworker
    case other

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .fiance: return "fiancé(e)"
        default: return rawValue
        }
    }

    var role: CycleSupportRole {
        switch self {
        case .wife, .husband, .girlfriend, .boyfriend, .partner, .spouse, .fiance:
            return .romantic
        case .daughter, .son, .child, .teen:
            return .child
        case .sister, .brother, .mom, .mother, .dad, .father, .sibling, .family:
            return .family
        case .friend, .roommate, .coworker:
            return .friend
        case .other:
            return .other
        }
    }

    /// How ARIA refers to them in speech (“your wife”, “your daughter”).
    func possessivePhrase(name: String?) -> String {
        if let name, !name.isEmpty { return name }
        switch self {
        case .wife: return "your wife"
        case .husband: return "your husband"
        case .girlfriend: return "your girlfriend"
        case .boyfriend: return "your boyfriend"
        case .partner: return "your partner"
        case .spouse: return "your spouse"
        case .fiance: return "your fiancé(e)"
        case .daughter: return "your daughter"
        case .son: return "your son"
        case .child: return "your child"
        case .teen: return "your teen"
        case .sister: return "your sister"
        case .brother: return "your brother"
        case .mom, .mother: return "your mom"
        case .dad, .father: return "your dad"
        case .sibling: return "your sibling"
        case .family: return "your family member"
        case .friend: return "your friend"
        case .roommate: return "your roommate"
        case .coworker: return "your coworker"
        case .other: return "them"
        }
    }

    static func parse(from raw: String) -> AriaRelationshipLabel {
        let l = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if l.contains("wife") { return .wife }
        if l.contains("husband") { return .husband }
        if l.contains("girlfriend") || l == "gf" { return .girlfriend }
        if l.contains("boyfriend") || l == "bf" { return .boyfriend }
        if l.contains("fiancé") || l.contains("fiance") { return .fiance }
        if l.contains("spouse") { return .spouse }
        if l.contains("daughter") { return .daughter }
        if l.contains("son") && !l.contains("person") { return .son }
        if l.contains("teen") { return .teen }
        if l.contains("child") || l.contains("kid") { return .child }
        if l.contains("sister") { return .sister }
        if l.contains("brother") { return .brother }
        if l.contains("mother") || l == "mom" || l.contains(" mom") { return .mom }
        if l.contains("father") || l == "dad" { return .dad }
        if l.contains("sibling") { return .sibling }
        if l.contains("roommate") { return .roommate }
        if l.contains("coworker") || l.contains("colleague") { return .coworker }
        if l.contains("friend") { return .friend }
        if l.contains("family") { return .family }
        if l.contains("partner") { return .partner }
        return .other
    }

    /// Extract all relationship labels mentioned in free text.
    static func allMentioned(in text: String) -> [AriaRelationshipLabel] {
        let lower = text.lowercased()
        var found: [AriaRelationshipLabel] = []
        let checks: [(String, AriaRelationshipLabel)] = [
            ("wife", .wife), ("husband", .husband), ("girlfriend", .girlfriend),
            ("boyfriend", .boyfriend), ("fiancé", .fiance), ("fiance", .fiance),
            ("spouse", .spouse), ("daughter", .daughter), ("my son", .son),
            ("my teen", .teen), ("my kid", .child), ("my child", .child),
            ("sister", .sister), ("brother", .brother), ("my mom", .mom),
            ("my mother", .mother), ("roommate", .roommate), ("coworker", .coworker),
            ("my friend", .friend), ("my partner", .partner),
        ]
        for (key, label) in checks where lower.contains(key) {
            if !found.contains(label) { found.append(label) }
        }
        return found
    }
}

// MARK: - Relationship dynamics (learned + label defaults)

struct AriaRelationshipDynamics: Codable, Equatable {
    /// 0...1 closeness
    var closeness: Double
    /// 0...1 current tension
    var tension: Double
    /// How the user usually communicates with them
    var communication: CommunicationStyle
    /// How conflicts tend to go
    var conflictStyle: ConflictStyle
    /// Freeform tags the user taught ARIA (“hates calm down”, “needs space first”)
    var userTags: [String]
    /// Living situation hint
    var proximity: Proximity
    var lastUpdated: Date

    enum CommunicationStyle: String, Codable, CaseIterable {
        case direct, soft, playful, careful, sparse
        var label: String {
            switch self {
            case .direct: return "direct"
            case .soft: return "soft"
            case .playful: return "playful"
            case .careful: return "careful"
            case .sparse: return "few words"
            }
        }
    }

    enum ConflictStyle: String, Codable, CaseIterable {
        case repairFast, needsSpace, escalates, avoids, unknown
        var label: String {
            switch self {
            case .repairFast: return "repairs quickly"
            case .needsSpace: return "needs space first"
            case .escalates: return "can escalate"
            case .avoids: return "tends to avoid"
            case .unknown: return "unknown yet"
            }
        }
    }

    enum Proximity: String, Codable, CaseIterable {
        case together, longDistance, mixed, unknown
    }

    static func defaults(for label: AriaRelationshipLabel) -> AriaRelationshipDynamics {
        switch label {
        case .wife, .spouse, .husband:
            return AriaRelationshipDynamics(
                closeness: 0.85, tension: 0.25, communication: .direct,
                conflictStyle: .repairFast, userTags: [], proximity: .together, lastUpdated: Date()
            )
        case .girlfriend, .boyfriend, .fiance, .partner:
            return AriaRelationshipDynamics(
                closeness: 0.75, tension: 0.3, communication: .soft,
                conflictStyle: .needsSpace, userTags: [], proximity: .mixed, lastUpdated: Date()
            )
        case .daughter, .teen:
            return AriaRelationshipDynamics(
                closeness: 0.8, tension: 0.35, communication: .careful,
                conflictStyle: .needsSpace, userTags: ["privacy-first"], proximity: .together, lastUpdated: Date()
            )
        case .son, .child:
            return AriaRelationshipDynamics(
                closeness: 0.8, tension: 0.3, communication: .careful,
                conflictStyle: .unknown, userTags: ["privacy-first"], proximity: .together, lastUpdated: Date()
            )
        case .sister, .brother, .sibling:
            return AriaRelationshipDynamics(
                closeness: 0.65, tension: 0.25, communication: .playful,
                conflictStyle: .repairFast, userTags: [], proximity: .mixed, lastUpdated: Date()
            )
        case .mom, .mother, .dad, .father:
            return AriaRelationshipDynamics(
                closeness: 0.7, tension: 0.2, communication: .soft,
                conflictStyle: .needsSpace, userTags: [], proximity: .mixed, lastUpdated: Date()
            )
        case .friend, .roommate:
            return AriaRelationshipDynamics(
                closeness: 0.55, tension: 0.2, communication: .playful,
                conflictStyle: .avoids, userTags: [], proximity: .mixed, lastUpdated: Date()
            )
        case .coworker:
            return AriaRelationshipDynamics(
                closeness: 0.35, tension: 0.2, communication: .careful,
                conflictStyle: .avoids, userTags: ["professional boundary"], proximity: .mixed, lastUpdated: Date()
            )
        case .family, .other:
            return AriaRelationshipDynamics(
                closeness: 0.5, tension: 0.25, communication: .soft,
                conflictStyle: .unknown, userTags: [], proximity: .unknown, lastUpdated: Date()
            )
        }
    }
}

// MARK: - Instant adaptation profile

/// Snapshot of how ARIA should speak/act with this relationship *right now*.
struct AriaPersonAdaptation: Equatable {
    var label: AriaRelationshipLabel
    var role: CycleSupportRole
    var name: String?
    var dynamics: AriaRelationshipDynamics

    var who: String { label.possessivePhrase(name: name) }

    /// Short coach voice line.
    var voicePreamble: String {
        switch label {
        case .wife:
            return "You're talking about \(who) — marriage weight. Long-game care, not scorekeeping."
        case .husband:
            return "You're talking about \(who) — partnership as a team. Steady and respectful."
        case .girlfriend:
            return "You're talking about \(who) — close and chosen. Warm, not parental."
        case .boyfriend:
            return "You're talking about \(who) — peer romance. Equal footing."
        case .fiance:
            return "You're talking about \(who) — building a life. Thoughtful and future-aware."
        case .partner, .spouse:
            return "You're talking about \(who) — real partnership. Direct care, no games."
        case .daughter:
            return "You're talking about \(who) — parent mode. Safety, dignity, zero romance framing."
        case .teen:
            return "You're talking about \(who) — teen + parent. Privacy, short words, no lectures."
        case .son, .child:
            return "You're talking about \(who) — caregiver mode. Practical protection first."
        case .sister:
            return "You're talking about \(who) — sibling bond. Loyal, light on hierarchy."
        case .brother:
            return "You're talking about \(who) — sibling. Straight, low drama."
        case .mom, .mother:
            return "You're talking about \(who) — parent-as-elder. Respect + boundaries."
        case .dad, .father:
            return "You're talking about \(who) — parent-as-elder. Clear and respectful."
        case .friend:
            return "You're talking about \(who) — friendship. Help without overstepping."
        case .roommate:
            return "You're talking about \(who) — shared space. Practical + considerate."
        case .coworker:
            return "You're talking about \(who) — work context. Professional boundaries."
        case .family, .sibling, .other:
            return "You're talking about \(who). Match closeness; don't assume romance or authority."
        }
    }

    var intimacyCoachingAllowed: Bool {
        switch label {
        case .wife, .husband, .girlfriend, .boyfriend, .partner, .spouse, .fiance:
            return true
        default:
            return false
        }
    }

    var caregiverMode: Bool {
        role == .child
    }

    /// What not to do for this relationship type.
    var hardBoundaries: [String] {
        switch label {
        case .daughter, .teen, .son, .child:
            return [
                "No sexual/intimacy framing",
                "No public shaming or period jokes",
                "No surveillance language — support logistics only",
                "Escalate medical red flags to a clinician",
            ]
        case .mom, .mother, .dad, .father:
            return [
                "Don't parent your parent unless asked",
                "Respect generational boundaries",
            ]
        case .coworker:
            return [
                "No oversharing private health details at work",
                "Keep advice professional",
            ]
        case .wife, .husband, .spouse:
            return [
                "Don't keep score of chores as weapons",
                "Repair > winning the argument",
            ]
        case .girlfriend, .boyfriend, .fiance, .partner:
            return [
                "Don't treat commitment level as entitlement",
                "Ask before assuming shared plans",
            ]
        default:
            return ["Don't overstep the actual relationship"]
        }
    }

    /// Default emotional stance when supporting this person.
    var supportStance: String {
        switch label {
        case .wife, .spouse:
            return "Team marriage: protect the bond, share load, speak like a spouse not a coach on a clipboard."
        case .girlfriend, .boyfriend, .fiance, .partner:
            return "Chosen partner: warmth, consent, and curiosity — earn closeness, don't demand it."
        case .daughter, .teen:
            return "Parent: be the safe base. Short sentences, supplies, sports/school logistics, emotional room."
        case .son, .child:
            return "Caregiver: protect dignity and routine; keep explanations age-appropriate."
        case .sister, .brother, .sibling:
            return "Sibling: loyal ally. Less hierarchy, more solidarity."
        case .mom, .mother, .dad, .father:
            return "Adult child: respect + clear boundaries; offer help without taking over."
        case .friend, .roommate:
            return "Friend: optional support — ask once, don't manage their life."
        case .coworker:
            return "Colleague: kind and contained."
        default:
            return "Match the relationship you actually have."
        }
    }

    var conflictAdvice: String {
        switch dynamics.conflictStyle {
        case .needsSpace:
            return "With \(who), space first usually helps — don't chase a cool-down with more words."
        case .repairFast:
            return "With \(who), clean repairs land well — short apology + next action."
        case .escalates:
            return "With \(who), lower volume and shorten sentences; heat escalates fast."
        case .avoids:
            return "With \(who), gentle openers work better than cornering them into a talk."
        case .unknown:
            return "You haven't told me how conflict usually goes with \(who) — default to calm and short."
        }
    }

    var communicationAdvice: String {
        switch dynamics.communication {
        case .direct: return "They handle direct language — be clear, not harsh."
        case .soft: return "Softer tone lands better — lead with care, then the ask."
        case .playful: return "Lightness helps — but not about pain or periods."
        case .careful: return "Go carefully — one question at a time, no pile-ons."
        case .sparse: return "Few words. Presence > speeches."
        }
    }

    /// Block injected into Foundation Models / local narrative.
    var promptDirective: String {
        var lines = [
            "ACTIVE PERSON: \(who) [label=\(label.rawValue), role=\(role.label)]",
            "STANCE: \(supportStance)",
            "VOICE: \(voicePreamble)",
            "COMMUNICATION: \(communicationAdvice)",
            "CONFLICT: \(conflictAdvice)",
            "CLOSENESS=\(String(format: "%.2f", dynamics.closeness)) TENSION=\(String(format: "%.2f", dynamics.tension))",
            "INTIMACY_COACHING=\(intimacyCoachingAllowed ? "allowed_if_relevant" : "FORBIDDEN")",
            "BOUNDARIES: \(hardBoundaries.joined(separator: "; "))",
        ]
        if !dynamics.userTags.isEmpty {
            lines.append("USER-TAUGHT TAGS: \(dynamics.userTags.joined(separator: ", "))")
        }
        lines.append("Adapt every sentence to THIS relationship — do not use girlfriend advice for a daughter or coworker tone for a wife.")
        return lines.joined(separator: "\n")
    }

    static func resolve(
        labelRaw: String,
        name: String? = nil,
        dynamics: AriaRelationshipDynamics? = nil
    ) -> AriaPersonAdaptation {
        let label = AriaRelationshipLabel.parse(from: labelRaw)
        return AriaPersonAdaptation(
            label: label,
            role: label.role,
            name: name,
            dynamics: dynamics ?? .defaults(for: label)
        )
    }
}

// MARK: - Known person registry entry

struct AriaKnownPerson: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var primaryLabel: String
    var extraLabels: [String]
    var role: CycleSupportRole
    var dynamics: AriaRelationshipDynamics
    var notes: String
    var isActive: Bool

    var adaptation: AriaPersonAdaptation {
        AriaPersonAdaptation.resolve(
            labelRaw: primaryLabel,
            name: name.isEmpty ? nil : name,
            dynamics: dynamics
        )
    }

    static func make(name: String, label: String) -> AriaKnownPerson {
        let parsed = AriaRelationshipLabel.parse(from: label)
        return AriaKnownPerson(
            id: UUID().uuidString,
            name: name,
            primaryLabel: label,
            extraLabels: [],
            role: parsed.role,
            dynamics: .defaults(for: parsed),
            notes: "",
            isActive: true
        )
    }
}
