import Foundation
import ForgeCore

/// On-device tools ARIA runs when the question is cycle, intimacy, training
/// around a period, or a clinician pack. Reads Apple Health / Cycle Vault on
/// this iPhone. Nothing here is a Forge database round-trip.
enum AriaCycleTools {

    static func shouldHandle(_ text: String) -> Bool {
        AriaCoachAgentRouter.isCycleQuery(text)
    }

    struct PeriodSexContext: Equatable {
        var isBleeding: Bool
        var flow: MenstrualFlowLevel?
        var painScale: Int?
        var symptoms: [CycleSymptom]
        var dayInCycle: Int?
    }

    static func reportWindowMonths(in text: String) -> Int? {
        let lower = text.lowercased()
        let wantsReport = lower.contains("rhythm report") || lower.contains("clinician")
            || lower.contains("gynecologist") || lower.contains("gynaecologist")
            || lower.contains("tracking summary") || lower.contains("cycle report")
            || lower.contains("apple cycle")
            || lower.contains("3-month") || lower.contains("3 month")
            || lower.contains("6-month") || lower.contains("6 month")
            || lower.contains("12-month") || lower.contains("12 month")
            || lower.contains("three month") || lower.contains("six month")
            || lower.contains("twelve month")
        guard wantsReport else { return nil }
        if lower.contains("3-month") || lower.contains("3 month") || lower.contains("three month") {
            return 3
        }
        if lower.contains("6-month") || lower.contains("6 month") || lower.contains("six month") {
            return 6
        }
        return 12
    }

    /// Pure composition so tests do not need AppStore / HealthKit.
    static func compose(
        text: String,
        phase: MenstrualPhase,
        relationshipLabel: String?,
        reportText: String?,
        trainingText: String?,
        periodSex: PeriodSexContext? = nil
    ) -> String? {
        let lower = text.lowercased()
        var chunks: [String] = []

        if let reportText, reportWindowMonths(in: text) != nil {
            chunks.append(reportText)
        }

        if let trainingText, wantsTraining(lower), !wantsIntimacy(lower) {
            chunks.append(trainingText)
        }

        if wantsPeriodSex(lower) {
            if let periodSex {
                let eval = SexualHealthCurriculum.periodSexEvaluation(
                    phase: phase,
                    isBleeding: periodSex.isBleeding,
                    flow: periodSex.flow,
                    painScale: periodSex.painScale,
                    symptoms: periodSex.symptoms,
                    dayInCycle: periodSex.dayInCycle
                )
                chunks.append(eval.asAriaSpeech)
            }
            chunks.append(SexualHealthCurriculum.periodSex(phase: phase))
            chunks.append(SexualHealthCurriculum.positionsAndIdeas(for: phase))
        }
        if wantsPositions(lower) {
            chunks.append(SexualHealthCurriculum.positionsAndIdeas(for: phase))
            chunks.append(SexualHealthCurriculum.thingsYouCanTry(for: phase))
        }
        if wantsPartnerHelp(lower) {
            chunks.append(SexualHealthCurriculum.partnerAndYouTips(roleHint: relationshipLabel))
        }
        if wantsSafeSex(lower) || (wantsIntimacy(lower) && chunks.isEmpty) {
            chunks.append(SexualHealthCurriculum.safeSexBasics())
        }
        if wantsDifficultyConceiving(lower) {
            chunks.append(SexualHealthCurriculum.difficultyConceiving())
            chunks.append(DifficultyConceivingGuide.copy.joined(separator: "\n"))
        } else if wantsTTC(lower) {
            chunks.append(
                "Trying to conceive is literacy, not a clinic. Time sex you actually want across the days you track — Forge does not diagnose infertility."
            )
            chunks.append(SexualHealthCurriculum.medicalDisclaimer)
        }

        if chunks.isEmpty, shouldHandle(text) {
            if wantsIntimacy(lower) {
                chunks.append(SexualHealthCurriculum.safeSexBasics())
                chunks.append(SexualHealthCurriculum.positionsAndIdeas(for: phase))
                chunks.append(SexualHealthCurriculum.thingsYouCanTry(for: phase))
                chunks.append(SexualHealthCurriculum.partnerAndYouTips(roleHint: relationshipLabel))
            }
        }

        guard !chunks.isEmpty else { return nil }
        let header = "On this iPhone — ARIA read your cycle ledger locally. Nothing below was uploaded to Forge."
        return ([header] + chunks).joined(separator: "\n\n")
    }

    @MainActor
    static func run(text: String) -> String? {
        let cycle = MenstrualHealthStore.shared
        let phase = cycle.snapshot.phase
        let role = cycle.selectedPerson?.settings.relationshipLabel
            ?? cycle.consentedPeople.first?.settings.relationshipLabel
        var report: String?
        if let months = reportWindowMonths(in: text), cycle.settings.enabled {
            report = cycle.clinicianRhythmReportText(windowMonths: months)
        }
        var training: String?
        if cycle.settings.enabled, wantsTraining(text.lowercased()), !wantsIntimacy(text.lowercased()) {
            let rx = cycle.trainingPrescription
            training = [rx.headline, rx.volumeLine, rx.intensityLine, rx.returnLine, rx.disclaimer]
                .joined(separator: "\n")
        }
        var periodCtx: PeriodSexContext?
        if cycle.settings.enabled {
            let todayKey = CycleDayKey.key()
            let today = cycle.logs.first(where: { $0.dayKey == todayKey })
            periodCtx = PeriodSexContext(
                isBleeding: cycle.snapshot.isCurrentlyBleeding || (today?.flow.isBleeding ?? false),
                flow: today?.flow,
                painScale: today?.painScale,
                symptoms: today?.symptoms ?? [],
                dayInCycle: cycle.snapshot.dayInCycle
            )
        }
        return compose(
            text: text,
            phase: phase,
            relationshipLabel: role,
            reportText: report,
            trainingText: training,
            periodSex: periodCtx
        )
    }

    private static func wantsIntimacy(_ lower: String) -> Bool {
        wantsPeriodSex(lower) || wantsPositions(lower) || wantsPartnerHelp(lower)
            || wantsSafeSex(lower) || wantsTTC(lower) || wantsDifficultyConceiving(lower)
            || AriaMessageTokens.containsAnyWord(lower, ["sex", "intimate", "intimacy"])
    }

    private static func wantsPeriodSex(_ lower: String) -> Bool {
        lower.contains("period sex") || lower.contains("sex during")
            || (lower.contains("bleeding") && AriaMessageTokens.containsAnyWord(lower, ["sex"]))
    }

    private static func wantsPositions(_ lower: String) -> Bool {
        lower.contains("positions") || lower.contains("things to try")
            || lower.contains("things we can try") || lower.contains("sex position")
    }

    private static func wantsPartnerHelp(_ lower: String) -> Bool {
        lower.contains("tips for you") || lower.contains("tips for a partner")
            || lower.contains("tips for my partner") || lower.contains("friend and help")
            || lower.contains("without being weird") || lower.contains("how do i help")
            || lower.contains("border between friend")
    }

    private static func wantsSafeSex(_ lower: String) -> Bool {
        lower.contains("safe sex") || lower.contains("healthy sex")
            || AriaMessageTokens.containsAnyWord(lower, ["condom", "lube"])
            || lower.contains("sti")
    }

    private static func wantsTTC(_ lower: String) -> Bool {
        lower.contains("trying to conceive") || lower.contains("trying to get pregnant")
            || AriaMessageTokens.containsAnyWord(lower, ["conceive", "ttc"])
    }

    private static func wantsDifficultyConceiving(_ lower: String) -> Bool {
        lower.contains("can't conceive") || lower.contains("cant conceive")
            || lower.contains("cannot conceive") || lower.contains("taking longer")
            || lower.contains("not getting pregnant") || lower.contains("difficulty conceiv")
    }

    private static func wantsTraining(_ lower: String) -> Bool {
        lower.contains("train") || lower.contains("run today") || lower.contains("workout")
            || lower.contains("mileage")
    }
}
