import Foundation

/// The phone's copy of ARIA's one safety classifier.
///
/// `backend/infra/lambda/aria_core/guidance.py` decides every 911, triage, and
/// refer-out turn for `/ai/chat`. The phone has to decide the same turns with
/// no network — Dummy, Local testing, and the offline fallback — so this file
/// mirrors that module's control flow line for line, and `AriaSafetyLexicon`
/// (generated from the same module) supplies the exact needles, patterns, and
/// copy. `shared/aria-safety-corpus.json` is asserted row for row by both the
/// Python suite and `AriaSafetyTriageTests`, so the two cannot drift.
///
/// Bands are the backend's strings on purpose: `coach`, `first_aid`,
/// `emergency`, `refer_out`, `triage`, `coach_with_care`.
public enum AriaSafetyBand {
    public static let coach = "coach"
    public static let firstAid = "first_aid"
    public static let emergency = "emergency"
    public static let referOut = "refer_out"
    public static let triage = "triage"
    public static let care = "coach_with_care"
}

/// When ARIA posts the relationship check-in, and what it says.
public struct AriaSafetyCheckIn: Codable, Equatable, Sendable {
    /// `escalation` — after the call is placed. `resolution` — right after
    /// this reply is spoken.
    public var after: String
    public var message: String

    public init(after: String, message: String) {
        self.after = after
        self.message = message
    }
}

/// Voice-first safety session — the same JSON `/ai/chat` returns as `safety`.
public struct AriaSafetySession: Codable, Equatable, Sendable {
    public var schema: Int
    /// `triage` | `escalate` | `resolved`
    public var phase: String
    public var topic: String
    /// `self` | `other`
    public var subject: String
    /// `on` | `off`
    public var voice: String
    public var outcome: String?
    public var questions: [String]?
    /// Echo this as `triage_topic` on the next turn.
    public var replyTopic: String?
    public var checkIn: AriaSafetyCheckIn?

    enum CodingKeys: String, CodingKey {
        case schema, phase, topic, subject, voice, outcome, questions
        case replyTopic = "reply_topic"
        case checkIn = "check_in"
    }

    public init(
        schema: Int = 1,
        phase: String,
        topic: String,
        subject: String,
        voice: String,
        outcome: String? = nil,
        questions: [String]? = nil,
        replyTopic: String? = nil,
        checkIn: AriaSafetyCheckIn? = nil
    ) {
        self.schema = schema
        self.phase = phase
        self.topic = topic
        self.subject = subject
        self.voice = voice
        self.outcome = outcome
        self.questions = questions
        self.replyTopic = replyTopic
        self.checkIn = checkIn
    }

    public var wantsVoice: Bool { voice == "on" }
    public var isTriage: Bool { phase == "triage" }
    public var isEscalation: Bool { phase == "escalate" }
    public var isResolved: Bool { phase == "resolved" }
}

/// One safety decision: the band, the exact copy, and the voice session.
public struct AriaSafetyDecision: Equatable, Sendable {
    public var band: String
    public var prose: String
    public var suggestedActions: [String]
    public var wantsEscalation: Bool
    public var safety: AriaSafetySession?

    public init(
        band: String,
        prose: String,
        suggestedActions: [String],
        wantsEscalation: Bool,
        safety: AriaSafetySession?
    ) {
        self.band = band
        self.prose = prose
        self.suggestedActions = suggestedActions
        self.wantsEscalation = wantsEscalation
        self.safety = safety
    }
}

public enum AriaSafetyTriage {

    typealias L = AriaSafetyLexicon

    static let subjectSelf = "self"
    static let subjectOther = "other"

    // MARK: - Public API (mirrors guidance.py)

    /// Lowercase + straight quotes: the one form every needle is written in.
    public static func normalize(_ message: String?) -> String {
        var text = message ?? ""
        for (from, to) in L.quoteFolds {
            text = text.replacingOccurrences(of: from, with: to)
        }
        return text.lowercased()
    }

    public static func classifyBand(_ message: String, triageTopic: String? = nil) -> String {
        classify(normalize(message), pending: parseTriageTopic(triageTopic))
    }

    /// Whitelist-parse a client echo. Unknown or malformed tokens are ignored.
    public static func parseTriageTopic(_ raw: String?) -> (topic: String, subject: String)? {
        let text = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty, text.count <= 32 else { return nil }
        let topic: String
        var subject: String
        if let dot = text.firstIndex(of: ".") {
            topic = String(text[..<dot])
            subject = String(text[text.index(after: dot)...])
        } else {
            topic = text
            subject = ""
        }
        if subject.isEmpty { subject = subjectSelf }
        guard L.triageTopics.contains(topic),
              subject == subjectSelf || subject == subjectOther else { return nil }
        return (topic, subject)
    }

    public static func triageReplyTopic(topic: String, subject: String) -> String {
        "\(topic).\(subject)"
    }

    /// Nil for ordinary coaching. `triageTopic` is the previous turn's
    /// `safety.replyTopic`; `relationshipLevel` (1-10) shapes the check-in.
    public static func assess(
        _ message: String,
        triageTopic: String? = nil,
        relationshipLevel: Int = 1
    ) -> AriaSafetyDecision? {
        let lower = normalize(message)
        let pending = parseTriageTopic(triageTopic)
        let band = classify(lower, pending: pending)
        if band == AriaSafetyBand.coach { return nil }

        if band == AriaSafetyBand.emergency {
            let prose: String
            let kind: String
            let subject: String
            if let pending, classify(lower, pending: nil) != AriaSafetyBand.emergency {
                let escalated = triageEmergencyProse(topic: pending.topic, subject: pending.subject, lower: lower)
                prose = escalated.prose
                kind = escalated.kind
                subject = pending.subject
            } else {
                prose = emergencyProse(lower)
                kind = emergencyKind(lower)
                subject = emergencySubject(lower, kind: kind)
            }
            var actions = ["Call 911", "Stay on the line"]
            if kind == "self_harm" {
                actions = ["Call or text 988", "Call 911", "Stay on the line"]
            } else if subject == subjectOther {
                actions = ["Call 911", "Start first aid", "Stay on the line"]
            }
            return AriaSafetyDecision(
                band: AriaSafetyBand.emergency,
                prose: prose,
                suggestedActions: actions,
                wantsEscalation: true,
                safety: session(
                    phase: "escalate",
                    topic: kind,
                    subject: subject,
                    outcome: AriaSafetyBand.emergency,
                    relationshipLevel: relationshipLevel
                )
            )
        }

        if band == AriaSafetyBand.firstAid {
            let body = detectFirstAidTopics(lower)
                .compactMap { L.firstAidSteps[$0] }
                .joined(separator: "\n")
            let prose = "Here's how to help — and call 911 (or have someone nearby call) right "
                + "away:\n" + body + "\n" + L.boundaryInfo
            return AriaSafetyDecision(
                band: AriaSafetyBand.firstAid,
                prose: prose,
                suggestedActions: ["Call 911", "Follow the steps", "Stay with them"],
                wantsEscalation: false,
                safety: nil
            )
        }

        if band == AriaSafetyBand.triage {
            let found = triageTopic(lower) ?? (topic: "faint", subject: subjectSelf)
            let key = triageReplyTopic(topic: found.topic, subject: found.subject)
            let fallbackKey = triageReplyTopic(topic: found.topic, subject: subjectSelf)
            guard let copy = L.triageCopy[key] ?? L.triageCopy[fallbackKey] else { return nil }
            var questions = copy.questions
            if found.topic == "ingestion", hasWord(lower, L.youngChildCues) {
                questions = Array(questions.prefix(1))
            }
            let prose = ([copy.lead] + questions + [copy.net]).joined(separator: " ")
            return AriaSafetyDecision(
                band: AriaSafetyBand.triage,
                prose: prose,
                suggestedActions: ["Yes", "No", "Call 911"],
                wantsEscalation: false,
                safety: session(
                    phase: "triage",
                    topic: found.topic,
                    subject: found.subject,
                    questions: questions,
                    relationshipLevel: relationshipLevel
                )
            )
        }

        if let pending, band == AriaSafetyBand.referOut || band == AriaSafetyBand.care {
            let prose = L.triageResolution["\(pending.topic).\(pending.subject).\(band)"]
                ?? L.triageResolution["\(pending.topic).\(pending.subject).\(AriaSafetyBand.referOut)"]
                ?? L.triageResolution["\(pending.topic).\(subjectSelf).\(AriaSafetyBand.referOut)"]
                ?? ""
            let actions: [String]
            if pending.topic == "ingestion" {
                actions = ["Call Poison Control", "Call 911"]
            } else if band == AriaSafetyBand.referOut {
                actions = ["Get it checked today", "Call 911"]
            } else if pending.topic == "bleeding" {
                actions = ["Keep pressure on it", "Call 911"]
            } else {
                actions = ["Keep today easy", "Call 911"]
            }
            return AriaSafetyDecision(
                band: band,
                prose: prose,
                suggestedActions: actions,
                wantsEscalation: false,
                safety: session(
                    phase: "resolved",
                    topic: pending.topic,
                    subject: pending.subject,
                    outcome: band,
                    relationshipLevel: relationshipLevel
                )
            )
        }

        if band == AriaSafetyBand.referOut {
            let prose = isChestCleared(lower) ? L.chestClearedRefer : referOutProse(lower)
            return AriaSafetyDecision(
                band: AriaSafetyBand.referOut,
                prose: prose,
                suggestedActions: ["Talk to a clinician", "Work on the lifestyle side", "Ask me something else"],
                wantsEscalation: false,
                safety: nil
            )
        }
        return nil
    }

    /// Warm, relationship-aware check-in for after the safety session ends.
    public static func checkInMessage(
        outcome: String,
        subject: String = "self",
        relationshipLevel: Int = 1,
        selfHarm: Bool = false
    ) -> String {
        let tier = relationshipTier(relationshipLevel)
        let key: String
        if selfHarm && subject == subjectSelf {
            key = "self_harm.self"
        } else if outcome == AriaSafetyBand.emergency {
            key = "emergency.\(subject)"
        } else {
            key = "resolved.\(subject)"
        }
        let lines = L.checkIn[key] ?? L.checkIn["resolved.self"] ?? []
        return lines.indices.contains(tier) ? lines[tier] : ""
    }

    // MARK: - Classification (guidance._classify)

    static func classify(_ lower: String, pending: (topic: String, subject: String)?) -> String {
        if isSelfHarm(lower) { return AriaSafetyBand.emergency }
        if has(lower, L.escalationRequest) || has(lower, L.emergencyState) {
            return AriaSafetyBand.emergency
        }
        if isAcuteRedFlag(lower) { return AriaSafetyBand.emergency }
        if has(lower, L.howtoCues) && hasWord(lower, L.firstAidTopics) {
            return AriaSafetyBand.firstAid
        }
        if matches(L.chokingPattern, lower) { return AriaSafetyBand.emergency }
        if let pending {
            return resolveTriage(topic: pending.topic, subject: pending.subject, lower: lower)
        }
        if isChestCleared(lower) { return AriaSafetyBand.referOut }
        if triageTopic(lower) != nil { return AriaSafetyBand.triage }
        if has(lower, L.eatingDisorder) { return AriaSafetyBand.referOut }
        if isPrescriptionRequest(lower) || isDiagnosisRequest(lower) {
            return AriaSafetyBand.referOut
        }
        return AriaSafetyBand.coach
    }

    static func isSelfHarm(_ lower: String) -> Bool {
        if has(lower, L.selfHarm) || matches(L.selfHarmPattern, lower) { return true }
        guard matches(L.hurtSelfPattern, lower) else { return false }
        return !matches(L.hurtSelfInjuryPattern, lower)
    }

    static func isLiftChestSoreness(_ lower: String) -> Bool {
        if has(lower, L.liftNotSoreness) { return false }
        if !has(lower, L.liftSoreness) { return false }
        return has(lower, L.liftChestContext) || lower.contains("bench")
    }

    static func isCardiacRedFlag(_ lower: String) -> Bool {
        if isLiftChestSoreness(lower) { return false }
        if has(lower, L.severeChest) { return true }
        if lower.contains("crushing") && has(lower, L.chestMarkers) { return true }
        if !has(lower, L.chestMarkers) { return false }
        if isHelperPhrasing(lower) { return true }
        if has(lower, L.chestCompanions) { return true }
        return hasWord(lower, L.jawWord) && has(lower, L.jawPain)
    }

    static func isStrokeRedFlag(_ lower: String) -> Bool {
        if has(lower, L.strokeStandalone) || has(lower, L.havingAStroke) { return true }
        if matches(L.cantTalkRightPattern, lower) { return true }
        if matches(L.oneSidedDeficitPattern, lower) { return true }
        let hits = L.strokeDomainPatterns.filter { matches($0, lower) }.count
        return hits >= 2
    }

    static func isSyncopeRedFlag(_ lower: String) -> Bool {
        has(lower, L.syncopeStandalone)
    }

    static func isAllergyEmergency(_ lower: String) -> Bool {
        has(lower, L.allergyEmergency) || matches(L.allergyComboPattern, lower)
    }

    static func isHeadInjuryEmergency(_ lower: String) -> Bool {
        matches(L.headInjuryPattern, lower) && matches(L.headInjuryRedFlagPattern, lower)
    }

    static func isIngestion(_ lower: String) -> Bool {
        matches(L.ingestionMedPattern, lower)
            || matches(L.ingestionToxinPattern, lower)
            || matches(L.childIngestionPattern, lower)
            || matches(L.poisonedPattern, lower)
    }

    static func isIngestionEmergency(_ lower: String) -> Bool {
        guard isIngestion(lower) else { return false }
        return matches(L.ingestionIntentPattern, lower) || matches(L.ingestionDangerPattern, lower)
    }

    static func isCardiacReply(_ lower: String) -> Bool {
        isCardiacRedFlag(lower) || has(lower, L.heartAttack)
    }

    static func needsCPR(_ lower: String) -> Bool {
        has(lower, L.notBreathing) || has(lower, L.unresponsive) || has(lower, L.noCirculation)
    }

    static func isAcuteRedFlag(_ lower: String) -> Bool {
        isCardiacRedFlag(lower)
            || isStrokeRedFlag(lower)
            || isSyncopeRedFlag(lower)
            || isAllergyEmergency(lower)
            || matches(L.bleedingPattern, lower)
            || isHeadInjuryEmergency(lower)
            || isIngestionEmergency(lower)
    }

    static func isDiagnosisRequest(_ lower: String) -> Bool {
        if has(lower, L.directDiagnosis) { return true }
        return has(lower, L.diagnosisAsk) && has(lower, L.conditionTerms)
    }

    static func isPrescriptionRequest(_ lower: String) -> Bool {
        if has(lower, L.directMed) { return true }
        return has(lower, L.takeCues) && (has(lower, L.symptomTerms) || has(lower, L.medTerms))
    }

    static func isHelperPhrasing(_ lower: String) -> Bool {
        if has(lower, L.helperPerson) { return true }
        return matches(L.helperPronounPattern, lower)
    }

    static func isChestCleared(_ lower: String) -> Bool {
        has(lower, L.chestMarkers) && has(lower, L.chestCleared)
    }

    static func detectFirstAidTopics(_ lower: String) -> [String] {
        var topics = L.firstAidTopicCues.filter { has(lower, $0.cues) }.map { $0.topic }
        if hasWord(lower, L.firstAidBurnWords) {
            topics.append("burn")
        }
        return topics.isEmpty ? ["general"] : topics
    }

    // MARK: - Emergency copy (guidance._emergency_*)

    static func selfHarmProse() -> String {
        let crisis = L.crisisLine.trimmingCharacters(in: .whitespacesAndNewlines)
        var tail = crisis.lowercased()
        while tail.hasSuffix(".") { tail.removeLast() }
        if tail.hasSuffix("call 911 now") { return crisis }
        return "\(L.emergencyOpen) \(crisis)"
    }

    static func referOutProse(_ lower: String) -> String {
        if has(lower, L.eatingDisorder) { return L.eatingDisorderRefer }
        if isPrescriptionRequest(lower) { return L.medicationRefer }
        let habit = has(lower, L.sleepRefer) ? "sleep habits" : "the day-to-day stuff around it"
        return "\(L.diagnosisReferOpen)\(habit)."
    }

    static func emergencyKind(_ lower: String) -> String {
        if isSelfHarm(lower) { return "self_harm" }
        if needsCPR(lower) { return "arrest" }
        if isIngestion(lower) && matches(L.ingestionIntentPattern, lower) { return "ingestion_intent" }
        if isCardiacReply(lower) { return "cardiac" }
        if isStrokeRedFlag(lower) { return "stroke" }
        if isSyncopeRedFlag(lower) { return "faint" }
        if isAllergyEmergency(lower) { return "allergy" }
        if matches(L.chokingPattern, lower) { return "choking" }
        if matches(L.bleedingPattern, lower) { return "bleeding" }
        if isHeadInjuryEmergency(lower) { return "head_injury" }
        if has(lower, L.seizureWords) { return "seizure" }
        if isIngestion(lower) || has(lower, L.overdoseWords) { return "ingestion" }
        return "general"
    }

    static func emergencySubject(_ lower: String, kind: String) -> String {
        if kind == "self_harm" { return subjectSelf }
        if isHelperPhrasing(lower) { return subjectOther }
        if kind == "arrest" || kind == "general" {
            return matches(L.firstPersonPattern, lower) ? subjectSelf : subjectOther
        }
        return subjectSelf
    }

    static func emergencyProse(_ lower: String) -> String {
        let helper = isHelperPhrasing(lower)
        let kind = emergencyKind(lower)
        let open = L.emergencyOpen
        if kind == "self_harm" { return selfHarmProse() }
        if kind == "arrest" { return "\(open) \(L.emergencyCpr)" }
        if kind == "ingestion_intent" {
            return "\(open) \(helper ? L.ingestionHelper : L.ingestionIntent)"
        }
        let steps: [String: (patient: String, helper: String)] = [
            "cardiac": (L.cardiac, L.cardiacHelper),
            "stroke": (L.stroke, L.strokeHelper),
            "faint": (L.faint, L.faintHelper),
            "allergy": (L.allergy, L.allergyHelper),
            "choking": (L.choking, L.chokingHelper),
            "bleeding": (L.bleeding, L.bleedingHelper),
            "head_injury": (L.head, L.headHelper),
        ]
        if let pair = steps[kind] {
            return "\(open) \(helper ? pair.helper : pair.patient)"
        }
        if kind == "seizure" && helper { return "\(open) \(L.seizureHelper)" }
        if kind == "ingestion" && !has(lower, L.overdoseWords) {
            return "\(open) \(helper ? L.ingestionHelper : L.ingestion)"
        }
        if helper { return "\(open) \(L.emergencyCprIfNeeded)" }
        if matches(L.firstPersonPattern, lower) { return "\(open) \(L.patientFallback)" }
        return "\(open) \(L.emergencyCprIfNeeded)"
    }

    // MARK: - Voice-first triage (guidance._triage_* / _resolve_triage)

    static func triageTopic(_ lower: String) -> (topic: String, subject: String)? {
        let helper = isHelperPhrasing(lower)
        let subject = helper ? subjectOther : subjectSelf
        if isIngestion(lower) { return ("ingestion", subject) }
        if matches(L.bleedingTriagePattern, lower) { return ("bleeding", subject) }
        if !helper,
           has(lower, L.chestMarkers),
           !isLiftChestSoreness(lower),
           !isChestCleared(lower) {
            return ("chest_pain", subjectSelf)
        }
        if has(lower, L.faintCues) { return ("faint", subject) }
        return nil
    }

    /// "no arm or jaw pain" negates the cue; "no, but it's worse" does not.
    static func cueIsNegated(_ lower: String, at location: Int) -> Bool {
        let prefix = (lower as NSString).substring(to: location)
        var clauseStart = 0
        if let regex = try? NSRegularExpression(pattern: L.clauseBreakPattern) {
            let range = NSRange(location: 0, length: (prefix as NSString).length)
            if let last = regex.matches(in: prefix, range: range).last {
                clauseStart = last.range.location + last.range.length
            }
        }
        let clause = (prefix as NSString).substring(from: clauseStart)
        var words: [String] = []
        if let wordRegex = try? NSRegularExpression(pattern: "[a-z']+") {
            let range = NSRange(location: 0, length: (clause as NSString).length)
            words = wordRegex.matches(in: clause, range: range).map {
                (clause as NSString).substring(with: $0.range)
            }
        }
        return words.suffix(3).contains { L.negators.contains($0) }
    }

    static func hasLiveCue(_ pattern: String, _ lower: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(location: 0, length: (lower as NSString).length)
        return regex.matches(in: lower, range: range).contains {
            !cueIsNegated(lower, at: $0.range.location)
        }
    }

    static func resolveTriage(topic: String, subject: String, lower: String) -> String {
        let danger = L.triageDangerPatterns[topic].map { hasLiveCue($0, lower) } ?? false
        let saidYes = matches(L.yesLeadPattern, lower) && !matches(L.noLeadPattern, lower)
        if danger || saidYes { return AriaSafetyBand.emergency }
        let saidNo = matches(L.noLeadPattern, lower)
        switch topic {
        case "chest_pain":
            if saidNo && has(lower, L.chestMskCues) { return AriaSafetyBand.care }
            return AriaSafetyBand.referOut
        case "faint":
            return has(lower, L.recurringCues) ? AriaSafetyBand.referOut : AriaSafetyBand.care
        case "bleeding":
            return has(lower, L.woundNeedsLookCues) ? AriaSafetyBand.referOut : AriaSafetyBand.care
        default:
            return AriaSafetyBand.referOut
        }
    }

    static func triageEmergencyProse(topic: String, subject: String, lower: String) -> (prose: String, kind: String) {
        let other = subject == subjectOther
        let open = L.emergencyOpen
        if topic == "ingestion" {
            let dangerPattern = L.triageDangerPatterns[topic] ?? ""
            let bareYes = matches(L.yesLeadPattern, lower) && !matches(dangerPattern, lower)
            if other { return ("\(open) \(L.ingestionHelper)", "ingestion") }
            if bareYes || hasLiveCue(L.triageIntentCuePattern, lower) {
                return ("\(open) \(L.ingestionIntent)", "ingestion_intent")
            }
            return ("\(open) \(L.ingestion)", "ingestion")
        }
        if topic == "bleeding" {
            return ("\(open) \(other ? L.bleedingHelper : L.bleeding)", "bleeding")
        }
        if topic == "faint" && !hasLiveCue(L.triageCardiacCuePattern, lower) {
            return ("\(open) \(other ? L.faintHelper : L.faint)", "faint")
        }
        return ("\(open) \(other ? L.cardiacHelper : L.cardiac)", "cardiac")
    }

    // MARK: - Session + check-in

    static func relationshipTier(_ level: Int) -> Int {
        if level <= 2 { return 0 }
        if level <= 5 { return 1 }
        return 2
    }

    static func session(
        phase: String,
        topic: String,
        subject: String,
        outcome: String? = nil,
        questions: [String] = [],
        relationshipLevel: Int
    ) -> AriaSafetySession {
        let voice = (phase == "triage" || phase == "escalate") ? "on" : "off"
        if phase == "triage" {
            return AriaSafetySession(
                phase: phase,
                topic: topic,
                subject: subject,
                voice: voice,
                outcome: outcome,
                questions: questions,
                replyTopic: triageReplyTopic(topic: topic, subject: subject),
                checkIn: nil
            )
        }
        let checkIn = AriaSafetyCheckIn(
            after: phase == "escalate" ? "escalation" : "resolution",
            message: checkInMessage(
                outcome: outcome ?? AriaSafetyBand.referOut,
                subject: subject,
                relationshipLevel: relationshipLevel,
                selfHarm: topic == "self_harm"
            )
        )
        return AriaSafetySession(
            phase: phase,
            topic: topic,
            subject: subject,
            voice: voice,
            outcome: outcome,
            questions: nil,
            replyTopic: nil,
            checkIn: checkIn
        )
    }

    // MARK: - Matching helpers (guidance._has / _has_word / re.search)

    static func has(_ lower: String, _ needles: [String]) -> Bool {
        needles.contains { lower.contains($0) }
    }

    static func hasWord(_ lower: String, _ needles: [String]) -> Bool {
        let alternation = needles.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        return matches("\\b(?:\(alternation))\\b", lower)
    }

    static func matches(_ pattern: String, _ lower: String) -> Bool {
        guard !pattern.isEmpty, let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(location: 0, length: (lower as NSString).length)
        return regex.firstMatch(in: lower, range: range) != nil
    }
}
