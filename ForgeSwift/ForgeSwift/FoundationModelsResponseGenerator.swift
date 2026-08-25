import Foundation
import ForgeCore
#if canImport(FoundationModels)
import FoundationModels
#endif

#if canImport(FoundationModels)
@available(iOS 26.0, *)
final class FoundationModelsResponseGenerator: TrainerResponseGenerator {
    private let session: LanguageModelSession
    private let model = SystemLanguageModel.default
    
    init() {
        // Base identity; per-turn voice directives are injected in buildPrompt.
        let instructions = """
        You are ARIA — an adaptive lifestyle coach inside Forge.
        You can lead someone to water; you cannot make them drink. They have intellect and autonomy.
        Improve the life they already have. Raise QOL with the smallest useful change.
        Compound interest: enough small changes and at some point they notice life is slightly different. Over time they see it and appreciate it — not a rewritten life.
        You can speak in infinite combinations of register, energy, metaphor, humor, and directness.
        Always follow the per-message VOICE PROFILE block when present.
        Reference biometrics when useful. Never invent medical advice.
        Theme the language when the user wants Solo Leveling / other narrative styles, but keep plans real and safe.
        Vary phrasing every turn — never sound like a script repeating itself.
        One next move. Never a new personality.
        """
        
        self.session = LanguageModelSession(instructions: instructions)
    }
    
    var isAvailable: Bool {
        switch model.availability {
        case .available:
            return true
        default:
            return false
        }
    }
    
    func generateResponse(for input: String, context: TrainerContext) async throws -> TrainerResponse {
        // Build contextual prompt
        let prompt = await buildPrompt(input: input, context: context)
        
        // Generate response from Foundation Models
        let response = try await session.respond(to: prompt)
        
        // Parse response and extract any rich card data
        return parseResponse(response.content, context: context, input: input)
    }
    
    @MainActor
    private func buildPrompt(input: String, context: TrainerContext) -> String {
        let theme = AriaThemeResolver.resolve(
            input: input,
            preferred: context.userProfile.trainingTheme,
            lifestyleTags: context.lifestyleTags,
            freeTimeTags: context.userProfile.interestTags
        )
        let lower = input.lowercased()
        let intent: AriaSpeechIntent = {
            if AriaEmotionalSupportCoach.detect(in: input, context: context) != nil { return .checkIn }
            if AriaThemeResolver.isPlanRequest(input) { return .trainingPlan }
            if lower.contains("tired") || lower.contains("exhausted") { return .lowEnergy }
            if lower.contains("sleep") { return .sleep }
            if lower.contains("pain") || lower.contains("hurt") { return .pain }
            if lower.contains("progress") { return .progress }
            if lower.contains("motivate") { return .motivation }
            if lower.contains("hello") || lower.contains("hey") { return .greeting }
            return .checkIn
        }()
        let voice = AriaVoiceEngine.resolveProfile(
            context: context,
            intent: intent,
            input: input,
            themeOverride: theme
        )
        let prompt = """
        \(voice.promptDirective)

        User: \(context.userProfile.name)
        Experience Level: \(context.userProfile.experienceLevel.label)
        Goals: \(context.userProfile.fitnessGoals.map { $0.label }.joined(separator: ", "))
        Coaching style preference: \(context.userProfile.coachingStyle.label)
        Training theme: \(theme.label) — \(theme.tagline)
        Equipment: \(context.userProfile.trainingEquipment.rawValue)
        Constraints: \(context.constraints.isEmpty ? "none" : context.constraints.joined(separator: ", "))
        
        Current Metrics:
        - Readiness: \(context.readiness.overall)/100 (\(theme.rankLabel(for: context.readiness.overall)))
        - HRV: \(context.dailyMetrics.hrv)ms
        - Resting HR: \(context.dailyMetrics.restingHR) bpm
        - Sleep Quality: \(context.readiness.sleepQuality)/100
        - Deep Sleep: \(context.dailyMetrics.deepSleep) min
        - Recovery Score: \(context.readiness.recoveryScore)/100
        
        Time: \(context.isEarlyMorning ? "Early morning (before 7am)" : context.isLateNight ? "Late night (after 10pm)" : "Daytime")
        \(cyclePromptBlock(context))
        
        \(CyclePrivacy.ariaDirective)
        
        User message: "\(input)"
        
        Respond in-character with the voice profile above. If they want a workout or themed plan, describe the session clearly.
        Use cycle context for training bias only — never medical or contraceptive advice.
        If emotional keywords appear (fight, anxious, overwhelmed, sad, parenting stress, PMS mood), lead with human emotional support: validate, practical moves, optional scripts. Not therapy. Crisis → urge real emergency resources.
        \(emotionalPromptBlock(input, context))
        """
        
        return prompt
    }

    private func emotionalPromptBlock(_ input: String, _ context: TrainerContext) -> String {
        guard let reading = AriaEmotionalSupportCoach.detect(in: input, context: context) else {
            return "Emotional read: none strong"
        }
        return """
        Emotional read: \(reading.primary.label) (score \(String(format: "%.1f", reading.score)))
        About someone else: \(reading.isAboutOther)
        Keywords: \(reading.matchedKeywords.joined(separator: ", "))
        """
    }

    @MainActor
    private func cyclePromptBlock(_ context: TrainerContext) -> String {
        var blocks: [String] = []
        if let c = context.cycleSnapshot, c.trackingEnabled {
            var lines = [
                "Self cycle phase: \(c.phase.label)",
                "Self day in cycle: \(c.dayInCycle.map(String.init) ?? "unknown")",
                "Self confidence: \(Int(c.confidence * 100))% (\(c.dataQuality))",
                "Training note: \(c.trainingNote)",
                "Readiness note: \(c.readinessNote)",
            ]
            if let next = c.nextPeriod {
                lines.append("Next period window: \(next.earliestDayKey)…\(next.latestDayKey)")
            }
            let phaseDirective = CyclePhaseCoachingDirective.directive(for: c.phase, domain: .general)
            if !phaseDirective.isEmpty {
                lines.append("## Phase Coaching Directive\n\(phaseDirective)")
            }
            blocks.append(lines.joined(separator: "\n"))
        } else {
            blocks.append("Self cycle: not shared / unavailable")
        }
        if !context.supportedPeople.isEmpty {
            var lines: [String] = [
                "The user supports \(context.supportedPeople.count) people. Each has their own role — never collapse a daughter through a partner lens.",
            ]
            for (index, person) in context.supportedPeople.enumerated() {
                let s = person.settings
                let p = person.snapshot
                lines.append(
                    "[\(index + 1)] \(s.resolvedRole.shortLabel) \(s.displayName): phase \(p.phase.label)"
                    + (p.dayInCycle.map { ", day \($0)" } ?? "")
                    + (p.periodEndConfirmed ? ", period finished" : "")
                )
            }
            if let p = context.partnerCycleSnapshot,
               let s = context.partnerCycleSettings {
                let adapt = AriaPersonRegistry.shared.adaptationForCurrentPartnerSettings(s)
                lines.append(adapt.promptDirective)
                lines.append("Active person this turn: \(s.resolvedRole.shortLabel) \(s.displayName).")
                lines.append("Their cycle phase: \(p.phase.label)")
                lines.append("Their day in cycle: \(p.dayInCycle.map(String.init) ?? "unknown")")
                lines.append("Confidence: \(Int(p.confidence * 100))%")
            }
            lines.append("VOICE: warm, human, specific. Coach the USER on how to show up — never medical advice for them.")
            lines.append("ASK natural follow-ups when context is thin (consent, last period start, how they're doing).")
            if let brief = MenstrualHealthStore.shared.partnerSupportBrief {
                lines.append("Support headline: \(brief.headline)")
                lines.append("Communication tip: \(brief.communicationTip)")
            }
            blocks.append(lines.joined(separator: "\n"))
        } else if let p = context.partnerCycleSnapshot,
           let s = context.partnerCycleSettings {
            let adapt = AriaPersonRegistry.shared.adaptationForCurrentPartnerSettings(s)
            var lines = [
                adapt.promptDirective,
                "Their cycle phase: \(p.phase.label)",
                "Their day in cycle: \(p.dayInCycle.map(String.init) ?? "unknown")",
                "Confidence: \(Int(p.confidence * 100))%",
                "VOICE: warm, human, specific. Coach the USER on how to show up — never medical advice for them.",
                "ASK natural follow-ups when context is thin (consent, last period start, how they're doing).",
            ]
            if let brief = MenstrualHealthStore.shared.partnerSupportBrief {
                lines.append("Support headline: \(brief.headline)")
                lines.append("Communication tip: \(brief.communicationTip)")
            }
            blocks.append(lines.joined(separator: "\n"))
        } else if let adapt = AriaPersonRegistry.shared.activeAdaptation {
            blocks.append(adapt.promptDirective)
        } else {
            blocks.append(
                "No active person lens. If user mentions wife/girlfriend/daughter/partner, INSTANTLY adapt tone to that label and ask gently about support coaching."
            )
        }
        return blocks.joined(separator: "\n")
    }
    
    private func parseResponse(_ content: String, context: TrainerContext, input: String) -> TrainerResponse {
        var richCard: RichCardData? = nil
        var suggested: [String]? = nil
        let lowerInput = input.lowercased()
        
        if AriaThemeResolver.isPlanRequest(input)
            || lowerInput.contains("workout")
            || lowerInput.contains("train") {
            let plan = AriaPlanEngine.evaluate(input: input, context: context)
            richCard = plan.richCard
            suggested = plan.suggestedActions
        } else if lowerInput.contains("sleep") {
            richCard = generateSleepChart(for: context)
        }
        
        return TrainerResponse(
            content: content,
            richCard: richCard,
            suggestedActions: suggested,
            confidence: 0.95
        )
    }
    
    private func generateSleepChart(for context: TrainerContext) -> RichCardData {
        let scores = context.sleepData.prefix(7).map { Double($0.score) }.reversed().map { $0 }
        let avg = context.averageWeeklySleepScore
        
        return RichCardData(
            type: .dataChart,
            chartTitle: "Sleep Quality (7 days)",
            chartValues: scores.isEmpty ? [68, 74, 91, 62, 93, 80, 88] : scores,
            chartInsight: "Average sleep score this week: \(Int(avg))/100. \(avg >= 80 ? "Solid week." : avg >= 70 ? "Could be better." : "This needs work.")",
            chartColor: .steel
        )
    }
}
#endif
