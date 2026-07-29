import Foundation

/// ARIA cycle analyst: Understand → Evaluate → Teach.
/// Engine owns numbers; ARIA coaches, critiques data quality, and may recommend
/// lifestyle sexual-health / contraception *materials* (education) — never claims
/// Forge itself is birth control.
@MainActor
enum CycleAriaAnalyst {

    struct Brief: Equatable {
        var understood: String
        var evaluationGrade: CycleQualityGrade
        var evaluationPoints: [String]
        var teaching: String
        var actions: [String]
        /// Optional lifestyle sexual-health education (not app-as-contraception).
        var sexualHealthLifestyleNote: String?
        var disclaimer: String
        var privacyLine: String
        var source: String // local | aria
    }

    static let lifestyleDisclaimer =
        "Lifestyle coaching — not medical diagnosis. Forge timing estimates are not themselves birth control."

    static let privacyLine =
        "ARIA evaluates cycle context for coaching only when Share with ARIA is on — never sold."

    /// Local (offline) three-mode brief — always available.
    static func localBrief(
        evaluation: CycleDataEvaluation,
        snapshot: MenstrualCycleSnapshot,
        lastAction: String? = nil,
        isPartner: Bool = false
    ) -> Brief {
        let points = evaluation.issues.map(\.lifestyleCopy)
        let sexual: String? = {
            // Lifestyle education only — product review allows recommending materials.
            if snapshot.stage == .postPeriod {
                return "Bleed is over. Iron and hydration are worth a thought over the next few days, and training capacity usually rebuilds fast from here."
            }
            if snapshot.phase == .fertileWindow || snapshot.phase == .ovulation {
                return "If pregnancy timing matters for your lifestyle plans, consider clinician-approved contraception options and sexual-health resources — Forge’s phase labels are coaching aids, not a contraceptive method."
            }
            if snapshot.phase == .menstruation {
                return "Sexual-health basics (hygiene products, comfort, rest) are fair lifestyle topics — ask ARIA if you want product or recovery tips."
            }
            return nil
        }()

        let teach = evaluation.teachingSummary
            + (snapshot.accuracyMAE.map { mae in
                " Personal timing MAE: \(String(format: "%.1f", mae)) days over \(snapshot.accuracySampleCount) confirms."
            } ?? "")

        return Brief(
            understood: evaluation.understoodSummary,
            evaluationGrade: evaluation.qualityGrade,
            evaluationPoints: points.isEmpty
                ? [evaluation.userFacingSummary]
                : Array(points.prefix(3)),
            teaching: teach,
            actions: evaluation.recommendedActions,
            sexualHealthLifestyleNote: isPartner ? nil : sexual,
            disclaimer: lifestyleDisclaimer,
            privacyLine: privacyLine,
            source: "local"
        )
    }

    /// Build redacted AI context (numbers from engine + evaluator only).
    static func makeContext(
        snapshot: MenstrualCycleSnapshot,
        evaluation: CycleDataEvaluation,
        settings: MenstrualTrackingSettings,
        lastAction: String?,
        isPartner: Bool
    ) -> CycleAIContext {
        CycleAIContext(
            phase: snapshot.phase.rawValue,
            stage: snapshot.stage.rawValue,
            periodEndConfirmed: snapshot.periodEndConfirmed,
            daysSincePeriodEnd: snapshot.daysSincePeriodEnd,
            daysUntilNextPeriod: snapshot.daysUntilNextPeriod,
            dayInCycle: snapshot.dayInCycle,
            cycleLengthMedian: snapshot.cycleLengthMedian,
            cycleLengthMAD: snapshot.cycleLengthMAD,
            nextMedian: snapshot.nextPeriod?.medianDayKey,
            nextEarliest: snapshot.nextPeriod?.earliestDayKey,
            nextLatest: snapshot.nextPeriod?.latestDayKey,
            ovulationMethod: snapshot.ovulationMethod,
            confidence: snapshot.confidence,
            periodTimingConfidence: snapshot.periodTimingConfidence,
            ovulationConfidence: snapshot.ovulationConfidence,
            accuracyMAE: snapshot.accuracyMAE,
            accuracySampleCount: snapshot.accuracySampleCount,
            qualityGrade: evaluation.qualityGrade.rawValue,
            issues: evaluation.issues.map(\.rawValue),
            highAccuracyMode: settings.highAccuracyMode,
            hormonal: settings.usesHormonalContraception,
            irregular: snapshot.irregularityFlag,
            lastUserAction: lastAction,
            isPartner: isPartner
        )
    }

    /// System prompt fragment for chat / future Bedrock calls.
    static var systemDirective: String {
        """
        \(CyclePrivacy.ariaDirective)

        You are ARIA, a lifestyle coach (not a clinician). For cycle data you must:
        1) UNDERSTAND what the user logged or asked.
        2) EVALUATE data quality using provided issues/grade — never invent MAE, dates, or windows.
        3) TEACH next steps for sharper personal timing and training recovery.

        Numbers in context are ground truth from Forge’s local engine — do not change them.

        You MAY recommend lifestyle sexual-health education and contraception *materials/options*
        (e.g. discuss condom use, discussing methods with a clinician, reputable education resources)
        when relevant to the user’s life plans. You must clearly say Forge cycle tracking itself
        is NOT a contraceptive method and is not a substitute for clinician-guided birth control.

        Never diagnose conditions. If symptoms sound severe or frightening, gently suggest professional care.
        """
    }

    /// Chat prompt for full three-mode brief (user opens “Ask ARIA”).
    static func chatPrompt(
        context: CycleAIContext,
        evaluation: CycleDataEvaluation
    ) -> String {
        """
        Cycle coaching request. Respond in three short sections: Understood / Evaluation / Teaching.
        Use only these facts (do not invent numbers):
        phase=\(context.phase), stage=\(context.stage),
        periodFinishedConfirmed=\(context.periodEndConfirmed),
        daysSincePeriodEnd=\(context.daysSincePeriodEnd.map(String.init) ?? "n/a"),
        daysUntilNextPeriod=\(context.daysUntilNextPeriod.map(String.init) ?? "n/a"),
        day=\(context.dayInCycle.map(String.init) ?? "nil"),
        medianCycle=\(String(format: "%.1f", context.cycleLengthMedian)),
        MAD=\(String(format: "%.1f", context.cycleLengthMAD)),
        nextWindow=\(context.nextEarliest ?? "—")…\(context.nextMedian ?? "—")…\(context.nextLatest ?? "—"),
        ovuMethod=\(context.ovulationMethod ?? "none"),
        conf=\(String(format: "%.2f", context.confidence)),
        periodConf=\(String(format: "%.2f", context.periodTimingConfidence)),
        ovuConf=\(String(format: "%.2f", context.ovulationConfidence)),
        MAE=\(context.accuracyMAE.map { String(format: "%.1f" , $0) } ?? "n/a") over \(context.accuracySampleCount),
        quality=\(context.qualityGrade), issues=\(context.issues.joined(separator: ",")),
        lastAction=\(context.lastUserAction ?? "none"), partner=\(context.isPartner).

        Local evaluation summary: \(evaluation.userFacingSummary)
        Teaching seed: \(evaluation.teachingSummary)

        If stage is postPeriod, do NOT give period-day advice. The bleed is over: acknowledge it,
        then coach the rebuild — energy, training progression, and what is coming next.
        If fertile/ovulation phase and user might care about pregnancy timing, you may mention
        lifestyle sexual-health and contraception materials while stating Forge is not birth control.
        End with a one-line lifestyle disclaimer.
        """
    }

    /// Post-feedback science-lite teaching (deterministic).
    static func teachingAfterFeedback(
        errorDays: Int?,
        evaluation: CycleDataEvaluation,
        snapshot: MenstrualCycleSnapshot
    ) -> String {
        var lines: [String] = [evaluation.understoodSummary]
        if let e = errorDays {
            if abs(e) <= 1 {
                lines.append("Your last forecast was tight (±\(abs(e))d). Personal timing is stabilizing — useful for planning training load.")
            } else if e > 0 {
                lines.append("Actual start was \(e)d later than the mid-window. We applied bias correction so future estimates don’t keep landing early. This personalizes the forecast — it is not a medical finding.")
            } else {
                lines.append("Period arrived \(abs(e))d earlier than the mid-estimate. Model shifted earlier and keeps a range — single days are rarely perfect.")
            }
        }
        lines.append(evaluation.teachingSummary)
        if snapshot.phase == .fertileWindow || snapshot.phase == .ovulation {
            lines.append("Lifestyle note: if pregnancy timing matters, use clinician-approved contraception methods — Forge labels are coaching aids only.")
        }
        return lines.joined(separator: " ")
    }
}
