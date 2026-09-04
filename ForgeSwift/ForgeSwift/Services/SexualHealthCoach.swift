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
    All sexual health and contraception responses must be rooted in reproductive biology and \
    physiology (e.g., LH surge mechanisms, progesterone's role in BBT rise, cervical mucus \
    changes, Pearl Index effectiveness data). Do not rely on anecdote or general web advice.
    Always include: "I'm an AI health coach, not a medical professional — consult a doctor or \
    qualified clinician for personal medical advice."
    Never prescribe a specific contraceptive method without understanding the user's health history.
    When the user has cycle data, use their specific phase, regularity grade, and accuracy to \
    personalise advice. For educational (supporter) mode, use physiology-first language that \
    builds genuine understanding.
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

        parts.append("\nUSER REQUEST: Provide a contraception overview relevant to my situation.")
        parts.append("Include: how each main method works biologically, typical vs perfect use effectiveness (Pearl Index), and how each interacts with natural cycle tracking.")
        parts.append("End with: \"\(SexualHealthCurriculum.medicalDisclaimer)\"")

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

        USER REQUEST: Help me optimise timing for trying to conceive.
        Explain the biology of the fertile window, how LH surge timing and BBT confirmation work, and what I can do to improve ovulation detection accuracy.
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

        USER REQUEST: Tell me about sexual health and wellbeing in my current cycle phase.
        Ground your response in the hormonal changes happening right now. Cover: energy, mood physiology, libido, and any relevant sexual wellness considerations.
        End with: "\(SexualHealthCurriculum.medicalDisclaimer)"
        """
    }

    // MARK: - Local (offline) fallback

    /// Deterministic summary when ARIA backend is unavailable.
    static func localContraceptionSummary(biologicalSex: BiologicalSex?) -> String {
        let intro = biologicalSex == .male || biologicalSex == nil
            ? "Here's a biology-first overview of how contraception works:"
            : "Here's how the main contraception methods work biologically:"
        let methods = SexualHealthCurriculum.contraceptionMethods.prefix(4).map { m in
            "**\(m.name)**: \(m.mechanism) Typical use: \(m.typicalUseEffectiveness)."
        }.joined(separator: "\n\n")
        return "\(intro)\n\n\(methods)\n\n\(SexualHealthCurriculum.medicalDisclaimer)"
    }
}
