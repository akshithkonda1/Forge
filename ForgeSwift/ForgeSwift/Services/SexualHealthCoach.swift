import Foundation

/// ARIA coaching domain for sexual health and contraception.
/// Responses are grounded in reproductive biology and physiology.
/// All outputs include medical disclaimers.
@MainActor
enum SexualHealthCoach {

    // MARK: - ARIA Directive Appendix

    /// Appended to ARIA's system directive when sexual health context is active.
    /// Nonisolated so privacy/prompt builders can compose it off the main actor.
    nonisolated static let ariaDirective = """
    SEXUAL HEALTH COACHING DOMAIN:
    You coach healthy sex, safe sex, consent, comfort, positions, period sex, \
    and how a partner can help without becoming a clinician. You may discuss \
    trying to conceive and difficulty conceiving as literacy. \
    You must NOT present Forge as contraception, fertility-awareness-as-birth-control, \
    or an FDA-regulated method. Do not quote Pearl Index as a reason to use this app \
    to avoid pregnancy. If they ask about birth control, send them to a clinician \
    and barrier methods / STI protection as education only.
    Always include: "I'm an AI health coach, not a medical professional — consult a doctor or \
    qualified clinician for personal medical advice."
    When the user has cycle data, use their phase for comfort and desire — never to schedule sex they do not want.
    """

    // MARK: - Chat Prompt Builders

    /// Contraception overview — personalised to cycle data if available, educational for males.
    static func contraceptionOverviewPrompt(
        biologicalSex: BiologicalSex?,
        snapshot: MenstrualCycleSnapshot?,
        isEducational: Bool,
        isHormonal: Bool = false
    ) -> String {
        var parts: [String] = [ariaDirective]

        if isEducational || biologicalSex == .male {
            parts.append("MODE: Educational supporter. Explain the biology behind how contraception works. Do not assume the user is personally trying to avoid pregnancy.")
        } else if let snap = snapshot, snap.phase != .unknown {
            parts.append("USER CYCLE CONTEXT:")
            parts.append("Phase: \(snap.phase.label) (Day \(snap.dayInCycle ?? 0) of \(Int(snap.cycleLengthMedian))-day cycle)")
            parts.append("Cycle regularity: MAD=\(String(format: "%.1f", snap.cycleLengthMAD)) days")
            parts.append("Hormonal contraception: \(isHormonal ? "yes (predictions adjusted)" : "no")")
            parts.append("Ovulation method: \(snap.ovulationMethod ?? "calendar fallback")")
            parts.append("Accuracy grade: \(snap.accuracyGrade)")
        }

        parts.append("\nUSER REQUEST: Help me have healthy, safe sex. Cover consent, STI protection, lube, and how to talk about protection without making it a test.")
        parts.append("Do not present Forge as birth control. End with: \"\(SexualHealthCurriculum.medicalDisclaimer)\"")

        return parts.joined(separator: "\n")
    }

    /// FAM reliability — personalised to the user's actual cycle data.
    static func famReliabilityPrompt(snapshot: MenstrualCycleSnapshot) -> String {
        let famNote = SexualHealthCurriculum.famReliability(
            dataQuality: snapshot.dataQuality,
            cycleLengthMAD: snapshot.cycleLengthMAD
        )
        return """
        \(ariaDirective)

        USER CYCLE CONTEXT:
        Cycle regularity MAD: \(String(format: "%.1f", snapshot.cycleLengthMAD)) days
        Data quality: \(snapshot.dataQuality)
        Accuracy grade: \(snapshot.accuracyGrade)
        Ovulation method: \(snapshot.ovulationMethod ?? "calendar fallback")

        PERSONALISED FAM ASSESSMENT:
        \(famNote)

        USER REQUEST: How reliable is fertility awareness method for me specifically, given my cycle data?
        Use the assessment above. Explain the symptothermal method (BBT + mucus + LH) and how my tracking compares to what's needed for effective FAM.
        End with: "\(SexualHealthCurriculum.medicalDisclaimer)"
        """
    }

    /// TTC optimisation — uses prediction accuracy and ovulation method to personalise.
    static func ttcPrompt(snapshot: MenstrualCycleSnapshot) -> String {
        let ttcNote = SexualHealthCurriculum.ttcGuidance(snapshot: snapshot)
        let nextWindow: String
        if let next = snapshot.nextPeriod {
            nextWindow = "\(next.earliestDayKey) to \(next.latestDayKey)"
        } else {
            nextWindow = "not yet predicted (log more cycles)"
        }
        return """
        \(ariaDirective)

        USER CYCLE CONTEXT:
        Current phase: \(snapshot.phase.label)
        Day in cycle: \(snapshot.dayInCycle.map(String.init) ?? "unknown")
        Next fertile window (next period window): \(nextWindow)
        Overall confidence: \(Int(snapshot.confidence * 100))%
        Ovulation method: \(snapshot.ovulationMethod ?? "calendar fallback")
        Accuracy grade: \(snapshot.accuracyGrade)

        TTC GUIDANCE:
        \(ttcNote)

        USER REQUEST: Help me try to conceive without turning sex into a chore. Explain timing literacy, then send me to a clinician if it has been a long time. Forge is not a fertility clinic.
        End with: "\(SexualHealthCurriculum.medicalDisclaimer)"
        """
    }

    /// Phase-aware sexual wellness — grounds response in current hormonal state.
    static func phaseWellnessPrompt(phase: MenstrualPhase, snapshot: MenstrualCycleSnapshot?) -> String {
        let wellnessNote = SexualHealthCurriculum.phaseWellness(for: phase)
        return """
        \(ariaDirective)

        CURRENT PHASE: \(phase.label)
        PHYSIOLOGICAL CONTEXT:
        \(wellnessNote)

        USER REQUEST: Sexual health and intimacy in my current cycle phase — comfort, desire, period sex if relevant, positions that tend to feel better, tips for me and for a partner. Not a contraception lecture.
        End with: "\(SexualHealthCurriculum.medicalDisclaimer)"
        """
    }

    static func intimacyPrompt(phase: MenstrualPhase, snapshot: MenstrualCycleSnapshot?) -> String {
        """
        \(ariaDirective)

        CURRENT PHASE: \(phase.label)
        SAFE SEX:
        \(SexualHealthCurriculum.safeSexBasics())
        POSITIONS:
        \(SexualHealthCurriculum.positionsAndIdeas(for: phase))
        THINGS YOU CAN TRY:
        \(SexualHealthCurriculum.thingsYouCanTry(for: phase))
        PERIOD SEX:
        \(SexualHealthCurriculum.periodSex(phase: phase))
        YOU + A PARTNER (FRIEND → HELP → INTIMACY):
        \(SexualHealthCurriculum.partnerAndYouTips(roleHint: nil))

        USER REQUEST: Healthy sex, safe sex, positions, things we can try, and how a partner can help without crossing into interrogation. Take your time. On this iPhone only.
        End with: "\(SexualHealthCurriculum.medicalDisclaimer)"
        """
    }

    static func positionsPrompt(phase: MenstrualPhase) -> String {
        """
        \(ariaDirective)

        CURRENT PHASE: \(phase.label)
        \(SexualHealthCurriculum.positionsAndIdeas(for: phase))
        \(SexualHealthCurriculum.thingsYouCanTry(for: phase))

        USER REQUEST: Positions and things we can actually try. Comfort first. Optional, not a script.
        End with: "\(SexualHealthCurriculum.intimacyDisclaimer)"
        """
    }

    static func periodSexPrompt(phase: MenstrualPhase) -> String {
        """
        \(ariaDirective)

        CURRENT PHASE: \(phase.label)
        \(SexualHealthCurriculum.periodSex(phase: phase))
        \(SexualHealthCurriculum.positionsAndIdeas(for: phase))

        USER REQUEST: Sex during a period — mess, comfort, positions, how to talk about it. Optional, never owed.
        End with: "\(SexualHealthCurriculum.intimacyDisclaimer)"
        """
    }

    static func partnerHelpPrompt(phase: MenstrualPhase, relationshipLabel: String?) -> String {
        """
        \(ariaDirective)
        PHASE: \(phase.label)
        \(SexualHealthCurriculum.partnerAndYouTips(roleHint: relationshipLabel))
        USER REQUEST: How do I help without being weird — the border between friend and intimate partner.
        End with: "\(SexualHealthCurriculum.intimacyDisclaimer)"
        """
    }

    static func difficultyConceivingPrompt(snapshot: MenstrualCycleSnapshot) -> String {
        """
        \(ariaDirective)
        USER CYCLE CONTEXT: phase=\(snapshot.phase.label), MAD=\(String(format: "%.1f", snapshot.cycleLengthMAD)), accuracy=\(snapshot.accuracyGrade)
        \(SexualHealthCurriculum.difficultyConceiving())
        USER REQUEST: We have been trying and it is not happening yet. Literacy only — not a diagnosis.
        End with: "\(SexualHealthCurriculum.medicalDisclaimer)"
        """
    }

    // MARK: - Local (offline) fallback

    /// Deterministic summary when ARIA backend is unavailable.
    static func localContraceptionSummary(biologicalSex: BiologicalSex?) -> String {
        SexualHealthCurriculum.safeSexBasics()
    }

    static func localIntimacySummary(phase: MenstrualPhase) -> String {
        [
            SexualHealthCurriculum.safeSexBasics(),
            SexualHealthCurriculum.positionsAndIdeas(for: phase),
            SexualHealthCurriculum.thingsYouCanTry(for: phase),
            SexualHealthCurriculum.periodSex(phase: phase),
            SexualHealthCurriculum.partnerAndYouTips(roleHint: nil),
        ].joined(separator: "\n\n")
    }
}
