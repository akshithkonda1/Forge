import Foundation
import Combine
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Tab Enum

enum TabItem: String, CaseIterable, Identifiable {
    case home, workout, chat, lifestyle, sleep, progress, profile
    var id: String { rawValue }
    var label: String {
        switch self {
        case .home: return "Home"
        case .workout: return "Workout"
        case .chat: return "ARIA"
        case .lifestyle: return "Lifestyle"
        case .sleep: return "Sleep"
        case .progress: return "Progress"
        case .profile: return "Profile"
        }
    }
    var systemImage: String {
        switch self {
        case .home:      return "house"
        case .chat:      return "message"
        case .workout:   return "dumbbell"
        case .lifestyle: return "leaf"
        case .sleep:     return "moon"
        case .progress:  return "chart.line.uptrend.xyaxis"
        case .profile:   return "person"
        }
    }
}

// MARK: - AI Response Protocol

/// Protocol for AI response generators
protocol TrainerResponseGenerator {
    func generateResponse(for input: String, context: TrainerContext) async throws -> TrainerResponse
}

// MARK: - Trainer Context

/// Context data passed to AI for response generation
struct TrainerContext {
    let userProfile: UserProfile
    let readiness: ReadinessData
    let dailyMetrics: DailyMetrics
    let sleepData: [SleepData]
    let workoutHistory: [WorkoutHistory]
    let currentTime: Date
    let conversationHistory: [ChatMessage]
    /// Living ARIA tags (lifestyle + training theme preference).
    var lifestyleTags: [String] = []
    /// Coach boundaries (conditions, guidance_only, etc.).
    var constraints: [String] = []
    /// Optional menstrual cycle snapshot when tracking is shared with ARIA.
    var cycleSnapshot: MenstrualCycleSnapshot? = nil
    /// Partner cycle (relationship sync) when user opted in with consent.
    var partnerCycleSnapshot: MenstrualCycleSnapshot? = nil
    var partnerCycleSettings: PartnerCycleSettings? = nil
    
    var hour: Int {
        Calendar.current.component(.hour, from: currentTime)
    }
    
    var isEarlyMorning: Bool { hour < 7 }
    var isLateNight: Bool { hour >= 22 }
    var averageWeeklySleepScore: Double {
        let scores = sleepData.prefix(7).map { Double($0.score) }
        return scores.isEmpty ? 0 : scores.reduce(0, +) / Double(scores.count)
    }

    /// Resolved theme for this turn (profile + tags; chat input applied by plan engine).
    var preferredTrainingTheme: AriaTrainingTheme {
        AriaThemeResolver.resolve(
            preferred: userProfile.trainingTheme,
            lifestyleTags: lifestyleTags,
            freeTimeTags: userProfile.interestTags
        )
    }

    /// Effective readiness for programming: soft-lifts expected luteal/period dips so ARIA doesn't over-react.
    var programmingReadiness: Int {
        let bonus = cycleSnapshot.map { MenstrualCycleEngine.readinessInterpretationBonus(for: $0) } ?? 0
        return min(100, readiness.overall + bonus)
    }
}

// MARK: - Trainer Response

struct TrainerResponse {
    let content: String
    let richCard: RichCardData?
    let suggestedActions: [String]?
    let confidence: Double // 0.0 to 1.0
    
    init(content: String, richCard: RichCardData? = nil, suggestedActions: [String]? = nil, confidence: Double = 1.0) {
        self.content = content
        self.richCard = richCard
        self.suggestedActions = suggestedActions
        self.confidence = confidence
    }
}

// MARK: - Foundation Models AI Response Generator

#if canImport(FoundationModels)
@available(iOS 26.0, *)
final class FoundationModelsResponseGenerator: TrainerResponseGenerator {
    private let session: LanguageModelSession
    private let model = SystemLanguageModel.default
    
    init() {
        // Base identity; per-turn voice directives are injected in buildPrompt.
        let instructions = """
        You are ARIA — an adaptive lifestyle & training coach inside Forge.
        You can speak in infinite combinations of register, energy, metaphor, humor, and directness.
        Always follow the per-message VOICE PROFILE block when present.
        Reference biometrics when useful. Never invent medical advice.
        Theme the language when the user wants Solo Leveling / other narrative styles, but keep plans real and safe.
        Vary phrasing every turn — never sound like a script repeating itself.
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
        let prompt = buildPrompt(input: input, context: context)
        
        // Generate response from Foundation Models
        let response = try await session.respond(to: prompt)
        
        // Parse response and extract any rich card data
        return parseResponse(response.content, context: context, input: input)
    }
    
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
            blocks.append(lines.joined(separator: "\n"))
        } else {
            blocks.append("Self cycle: not shared / unavailable")
        }
        if let p = context.partnerCycleSnapshot,
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

// MARK: - Fallback Rule-Based Response Generator

/// Rule-based fallback when Foundation Models aren't available
final class RuleBasedResponseGenerator: TrainerResponseGenerator {
    
    func generateResponse(for input: String, context: TrainerContext) async throws -> TrainerResponse {
        let lower = input.lowercased()
        
        // Context-aware greetings
        if isGreeting(lower) {
            return generateGreeting(context: context)
        }

        // Invent / enrich archetypes (Claude when available)
        if let intent = AriaArchetypeIntent.parse(input) {
            return await generateArchetypeStudioResponse(intent: intent, context: context, input: input)
        }

        // Emotional support (keywords + family/partner context) — before pure training when loaded
        if let reading = AriaEmotionalSupportCoach.detect(in: input, context: context) {
            // Pure training asks without emotional load still go to training below
            let trainingOnly = AriaThemeResolver.isPlanRequest(input)
                && reading.matchedKeywords.count <= 1
                && reading.primary != .crisis
                && !lower.contains("feel") && !lower.contains("upset") && !lower.contains("fight")
            if !trainingOnly {
                return await AriaEmotionalSupportCoach.respond(
                    reading: reading,
                    context: context,
                    input: input
                )
            }
        }
        
        // Training / themed plan request (Solo Leveling, daily quest, etc.)
        if AriaThemeResolver.isPlanRequest(input) || isTrainingRequest(lower) {
            return generateTrainingResponse(input: input, context: context)
        }

        // Menstrual / cycle coaching
        if isCycleQuery(lower) {
            return await generateCycleResponse(context: context, input: input)
        }
        
        // Low energy
        if isLowEnergyMention(lower) {
            return generateLowEnergyResponse(context: context)
        }
        
        // Sleep analysis
        if isSleepQuery(lower) {
            return generateSleepAnalysis(context: context)
        }
        
        // Pain/injury
        if isPainMention(lower) {
            return generatePainResponse(input: lower, context: context)
        }
        
        // Progress check
        if isProgressQuery(lower) {
            return generateProgressResponse(context: context)
        }
        
        // Gratitude
        if isGratitude(lower) {
            return generateGratitudeResponse(context: context)
        }
        
        // Motivation
        if isMotivationRequest(lower) {
            return generateMotivationResponse(context: context)
        }
        
        // Fallback
        return generateFallbackResponse(context: context)
    }
    
    // MARK: - Query Detection
    
    private func isGreeting(_ text: String) -> Bool {
        text.contains("hello") || text.contains("hey") || text.contains("hi ") || 
        text.contains("what's up") || text.contains("sup")
    }
    
    private func isTrainingRequest(_ text: String) -> Bool {
        AriaThemeResolver.isPlanRequest(text)
    }

    private func isCycleQuery(_ text: String) -> Bool {
        text.contains("period") || text.contains("menstrual") || text.contains("cycle day")
            || text.contains("luteal") || text.contains("follicular") || text.contains("ovulat")
            || text.contains("pms") || text.contains("cramp") || text.contains("my cycle")
            || text.contains("time of the month")
            || text.contains("partner cycle") || text.contains("her period") || text.contains("her cycle")
            || text.contains("girlfriend") || text.contains("wife") || text.contains("my partner")
            || text.contains("support her") || text.contains("sync with") || text.contains("her pms")
            || text.contains("date night") && (text.contains("cycle") || text.contains("period"))
    }

    private func isPartnerCycleQuery(_ text: String) -> Bool {
        text.contains("partner") || text.contains("girlfriend") || text.contains("wife")
            || text.contains("her period") || text.contains("her cycle") || text.contains("her pms")
            || text.contains("support her") || text.contains("spouse") || text.contains("fiancé")
            || text.contains("fiance") || text.contains("my girl")
            || text.contains("daughter") || text.contains("my kid") || text.contains("my child")
            || text.contains("my teen") || text.contains("as a dad") || text.contains("as a father")
            || text.contains("as a parent") || text.contains("my sister") || text.contains("for my daughter")
    }
    
    private func isLowEnergyMention(_ text: String) -> Bool {
        text.contains("not feeling") || text.contains("tired") || 
        text.contains("exhausted") || text.contains("low energy") || text.contains("drained")
    }
    
    private func isSleepQuery(_ text: String) -> Bool {
        (text.contains("sleep") || text.contains("slept") || text.contains("rest")) && 
        !text.contains("restaurant")
    }
    
    private func isPainMention(_ text: String) -> Bool {
        text.contains("injury") || text.contains("pain") || text.contains("hurt") || 
        (text.contains("sore") && !text.contains("not sore"))
    }
    
    private func isProgressQuery(_ text: String) -> Bool {
        text.contains("progress") || text.contains("how am i doing") || 
        text.contains("gains") || text.contains("getting stronger")
    }
    
    private func isGratitude(_ text: String) -> Bool {
        text.contains("thank") || text.contains("appreciate") || text.contains("grateful")
    }
    
    private func isMotivationRequest(_ text: String) -> Bool {
        text.contains("motivate") || text.contains("pump me up") || 
        text.contains("need motivation") || text.contains("inspire")
    }
    
    // MARK: - Response Generation
    
    private func generateArchetypeStudioResponse(
        intent: AriaArchetypeIntent,
        context: TrainerContext,
        input: String
    ) async -> TrainerResponse {
        _ = await AriaPersonRegistry.shared.adapt(to: input)
        let studio = AriaArchetypeStudio.shared
        let personName = await AriaPersonRegistry.shared.activePerson?.name
            ?? context.partnerCycleSettings?.displayName
            ?? "them"

        switch intent {
        case .list:
            let builtin = AriaPersonalArchetype.allCases.filter { $0 != .unknown }.map(\.label)
            let custom = await studio.customArchetypes.prefix(12).map { "\($0.name) (\($0.source.displayName))" }
            var msg = "**Built-in archetypes:** " + builtin.joined(separator: ", ") + "."
            if custom.isEmpty {
                msg += "\n\nNo custom ones yet — say “create an archetype for someone who…” and I’ll invent one through ARIA’s backend intelligence (or on-device if you’re offline)."
            } else {
                msg += "\n\n**ARIA-invented:** " + custom.joined(separator: ", ") + "."
            }
            return TrainerResponse(
                content: msg,
                suggestedActions: [
                    "Create an archetype for my wife",
                    "Invent an archetype for my daughter",
                    "List archetypes again",
                ],
                confidence: 0.95
            )

        case .create(let description, let name):
            let crafted = await studio.createArchetype(from: description, preferredName: name)
            await studio.apply(crafted, toPersonId: AriaPersonRegistry.shared.activePersonId)
            let sourceNote = "Forged via \(crafted.source.displayName)."
            let msg = """
            New archetype locked for **\(personName)**:

            **\(crafted.name)** — \(crafted.tagline)

            Speak to them: \(crafted.speechGuidance)
            Stance: \(crafted.supportStance)
            Avoid: \(crafted.avoid.prefix(4).joined(separator: "; "))
            Example: “\(crafted.exampleScript)”

            \(sourceNote)

            I’ll use this the next time we talk about \(personName). Teach me more anytime (“she texts short”, “deepen this archetype”).
            """
            return TrainerResponse(
                content: msg,
                suggestedActions: [
                    "Deepen this archetype",
                    "How do I support them today?",
                    "Create another archetype",
                    "What should I train?",
                ],
                confidence: 0.92
            )

        case .enrich(let extra):
            if let activeId = await AriaPersonRegistry.shared.activePerson?.customArchetypeId,
               let existing = await studio.archetype(id: activeId) {
                let refined = await studio.enrich(existing, with: extra)
                await studio.apply(refined, toPersonId: AriaPersonRegistry.shared.activePersonId)
                return TrainerResponse(
                    content: """
                    Refined **\(refined.name)** for \(personName).

                    \(refined.tagline)

                    Speak-to-them: \(refined.speechGuidance)
                    Via \(refined.source.displayName).
                    """,
                    suggestedActions: ["How should I talk to them tonight?", "List archetypes"],
                    confidence: 0.9
                )
            }
            let crafted = await studio.createArchetype(from: extra, preferredName: nil)
            await studio.apply(crafted, toPersonId: AriaPersonRegistry.shared.activePersonId)
            return TrainerResponse(
                content: "No custom archetype was attached yet — I forged **\(crafted.name)** and applied it to \(personName).",
                suggestedActions: ["Deepen this archetype", "Support script"],
                confidence: 0.88
            )

        case .assign(let name):
            if let existing = await studio.findByName(name) {
                await studio.apply(existing, toPersonId: AriaPersonRegistry.shared.activePersonId)
                return TrainerResponse(
                    content: "Attached **\(existing.name)** to \(personName).",
                    suggestedActions: ["How do I support them?", "Deepen this archetype"],
                    confidence: 0.9
                )
            }
            let crafted = await studio.createArchetype(from: input, preferredName: name)
            await studio.apply(crafted, toPersonId: AriaPersonRegistry.shared.activePersonId)
            return TrainerResponse(
                content: "Created and attached **\(crafted.name)** to \(personName).",
                suggestedActions: ["Support script", "List archetypes"],
                confidence: 0.9
            )
        }
    }

    private func generateGreeting(context: TrainerContext) -> TrainerResponse {
        var content = AriaVoiceEngine.speak(intent: .greeting, context: context)
        let salt = UInt64(context.conversationHistory.count * 17 + context.readiness.overall)
        if let addon = AriaRelationalCoach.greetingAddon(
            settings: context.partnerCycleSettings,
            snapshot: context.partnerCycleSnapshot,
            salt: salt
        ) {
            content += "\n\n" + addon
        } else if context.partnerCycleSettings == nil,
                  context.userProfile.gender == .male,
                  context.conversationHistory.count < 4 {
            // Soft humanizing invite early in the relationship with ARIA
            var rng = AriaSeededRNG(seed: salt == 0 ? 7 : salt)
            if rng.chance(0.4) {
                content += "\n\n" + rng.pick([
                    "By the way — I can also help you support a partner or a kid's cycle days if that's part of your life. Just say so in plain words.",
                    "Random but real: a lot of guys use me to show up better for a wife, girlfriend, or daughter. No pressure — only if you want that.",
                ])
            }
        }
        return TrainerResponse(
            content: content,
            suggestedActions: context.partnerCycleSettings != nil
                ? ["How do I support them today?", "What should I train?"]
                : ["What should I train today?", "I support my partner's cycle", "I'm a dad — help with my daughter"],
            confidence: 0.9
        )
    }

    @MainActor
    private func generateCycleResponse(context: TrainerContext, input: String) -> TrainerResponse {
        let lower = input.lowercased()
        let mention = AriaRelationalCoach.detectSupportMention(in: input)

        // Learn names/roles from natural language ("my wife Maya", "my daughter").
        if let mention {
            Task { @MainActor in
                AriaRelationalCoach.applyMentionIfNeeded(mention, store: MenstrualHealthStore.shared)
            }
        }

        // Partner / family / parent sync coaching.
        if isPartnerCycleQuery(lower)
            || mention != nil
            || (context.partnerCycleSnapshot != nil && !lower.contains("my period") && !lower.contains("my cycle")) {
            if let partnerSnap = context.partnerCycleSnapshot,
               let partnerSettings = context.partnerCycleSettings,
               partnerSettings.enabled,
               partnerSettings.consentAcknowledged {
                let name = context.userProfile.name.split(separator: " ").first.map(String.init) ?? ""
                let msg = AriaRelationalCoach.humanizeSupportReply(
                    snapshot: partnerSnap,
                    settings: partnerSettings,
                    userName: name,
                    input: input
                )
                let role = partnerSettings.resolvedRole
                let actions: [String] = {
                    switch role {
                    case .child:
                        return [
                            "How do I support my daughter today?",
                            "School / sports tips",
                            "What should I avoid saying?",
                            "Log her period start",
                        ]
                    case .romantic:
                        return [
                            "Date ideas for this phase",
                            "How should I train with her?",
                            "Log her period start",
                            "What should I avoid saying?",
                        ]
                    default:
                        return [
                            "How should I show up?",
                            "Low-key plan ideas",
                            "Log period start",
                            "What should I avoid?",
                        ]
                    }
                }()
                return TrainerResponse(
                    content: msg,
                    suggestedActions: actions,
                    confidence: max(0.85, partnerSnap.confidence)
                )
            }
            // Mentioned support person but not fully set up — human invite
            if isPartnerCycleQuery(lower) || mention != nil {
                return TrainerResponse(
                    content: AriaRelationalCoach.humanSetupReply(mention: mention),
                    suggestedActions: [
                        "My partner — set this up",
                        "My daughter — parent support",
                        "She said it's okay to track starts",
                        "What should I train today?",
                    ],
                    confidence: 0.88
                )
            }
        }

        guard let cycle = context.cycleSnapshot, cycle.trackingEnabled else {
            let msg = """
            I can coach around your cycle once tracking is on — open Cycle Health to log periods, BBT, and OPKs, or sync Apple Health.

            If you want to support a partner instead, enable **Partner Cycle** and log her period starts (with consent).

            \(MenstrualCycleEngine.disclaimer)
            """
            return TrainerResponse(
                content: msg,
                suggestedActions: ["Open cycle health", "Set up partner cycle", "What should I train today?"],
                confidence: 0.8
            )
        }

        var lines: [String] = []
        lines.append("You're in **\(cycle.phase.label)**" + (cycle.dayInCycle.map { " · day \($0)" } ?? "") + ".")
        lines.append("Engine confidence \(Int(cycle.confidence * 100))% (\(cycle.dataQuality)). Cycles observed: \(cycle.cyclesObserved).")
        if let method = cycle.ovulationMethod, let ovu = cycle.ovulationDayInCycle {
            lines.append("Ovulation estimate: day \(ovu) via \(method.replacingOccurrences(of: "_", with: " ")).")
        }
        if let next = cycle.nextPeriod {
            lines.append("Next period window: \(next.earliestDayKey) → \(next.latestDayKey) (median \(next.medianDayKey)).")
        }
        lines.append(cycle.trainingNote)
        lines.append(cycle.readinessNote)
        for insight in cycle.insights.prefix(3) {
            lines.append("• \(insight)")
        }
        lines.append("\n" + cycle.disclaimer)

        // Offer a phase-aware plan when they ask what to do.
        if lower.contains("train") || lower.contains("workout") || lower.contains("should i") {
            let plan = AriaPlanEngine.evaluate(input: input, context: context)
            return TrainerResponse(
                content: lines.joined(separator: "\n\n") + "\n\n" + plan.narrative,
                richCard: plan.richCard,
                suggestedActions: plan.suggestedActions,
                confidence: max(0.85, cycle.confidence)
            )
        }

        return TrainerResponse(
            content: lines.joined(separator: "\n\n"),
            suggestedActions: ["Build a phase-aware workout", "Log period start", "Explain fertile window"],
            confidence: max(0.85, cycle.confidence)
        )
    }
    
    private func generateTrainingResponse(input: String, context: TrainerContext) -> TrainerResponse {
        let plan = AriaPlanEngine.evaluate(input: input, context: context)
        return TrainerResponse(
            content: plan.narrative,
            richCard: plan.richCard,
            suggestedActions: plan.suggestedActions,
            confidence: 0.92
        )
    }
    
    private func generateLowEnergyResponse(context: TrainerContext) -> TrainerResponse {
        let recovery = AriaPlanEngine.evaluate(input: "low energy recovery session", context: context)
        // Force soft recovery framing even if readiness is high — user said they're tired.
        let facts = AriaSpeechFacts(
            sessionTitle: "Recovery Flow",
            sessionDuration: 30,
            sessionIntensity: "low intensity",
            sessionFlavor: "Mobility, blood flow, no ego."
        )
        let content = AriaVoiceEngine.speak(
            intent: .lowEnergy,
            context: context,
            input: "tired",
            facts: facts
        )
        let workoutPlan = recovery.richCard.type == .workoutPlan && recovery.readiness < 70
            ? recovery.richCard
            : RichCardData(type: .workoutPlan, workoutName: "Recovery Flow", workoutDuration: 30, workoutExercises: [
                ("Foam Rolling", 1, "5 min"), ("World's Greatest Stretch", 2, "8 each side"),
                ("Band Pull-Aparts", 3, "15"), ("Goblet Squats (light)", 2, "10"),
                ("Dead Hangs", 3, "30 sec"), ("Walk or Bike (easy)", 1, "10 min"),
            ])
        return TrainerResponse(
            content: content,
            richCard: workoutPlan,
            suggestedActions: ["Start recovery flow", "Just talk", "Plan an easier week"],
            confidence: 0.9
        )
    }
    
    private func generateSleepAnalysis(context: TrainerContext) -> TrainerResponse {
        let lastSleep = context.sleepData.first
        let deepMin = lastSleep?.deepMinutes ?? context.dailyMetrics.deepSleep
        let totalHrs = lastSleep?.totalHours ?? Double(context.dailyMetrics.totalSleep) / 60
        let scores = context.sleepData.prefix(7).map { Double($0.score) }.reversed().map { $0 }
        let avg = context.averageWeeklySleepScore

        let band: AriaSpeechFacts.SleepSpeechBand = {
            if deepMin >= 90 && totalHrs >= 7 { return .strong }
            if deepMin < 60 { return .weak }
            return .ok
        }()

        let facts = AriaSpeechFacts(
            sleepHours: totalHrs,
            deepMinutes: deepMin,
            sleepAvg: Int(avg),
            sleepBand: band
        )
        let analysis = AriaVoiceEngine.speak(intent: .sleep, context: context, facts: facts)
        
        let chartData = RichCardData(
            type: .dataChart,
            chartTitle: "Sleep Quality (7 days)",
            chartValues: scores.isEmpty ? [68, 74, 91, 62, 93, 80, 88] : scores,
            chartInsight: "Average sleep score this week: \(Int(avg))/100. \(avg >= 80 ? "Solid week." : avg >= 70 ? "Could be better." : "This needs work.")",
            chartColor: .steel
        )
        
        return TrainerResponse(content: analysis, richCard: chartData, confidence: 0.9)
    }
    
    private func generatePainResponse(input: String, context: TrainerContext) -> TrainerResponse {
        let content = AriaVoiceEngine.speak(intent: .pain, context: context, input: input)
        return TrainerResponse(content: content, confidence: 0.88)
    }
    
    private func generateProgressResponse(context: TrainerContext) -> TrainerResponse {
        let facts = AriaSpeechFacts(
            recentSessions: context.workoutHistory.count,
            streak: nil
        )
        let content = AriaVoiceEngine.speak(intent: .progress, context: context, facts: facts)
        
        let chartData = RichCardData(
            type: .dataChart,
            chartTitle: "Bench Press Progress (4 weeks)",
            chartValues: [185, 195, 205, 215, 225],
            chartInsight: "Bench: +40 lbs in 4 weeks. Estimated 1RM: 245 lbs. Strength is climbing fast.",
            chartColor: .ember
        )
        
        return TrainerResponse(content: content, richCard: chartData, confidence: 0.88)
    }
    
    private func generateGratitudeResponse(context: TrainerContext) -> TrainerResponse {
        let content = AriaVoiceEngine.speak(intent: .gratitude, context: context)
        return TrainerResponse(content: content, confidence: 0.9)
    }
    
    private func generateMotivationResponse(context: TrainerContext) -> TrainerResponse {
        let content = AriaVoiceEngine.speak(intent: .motivation, context: context)
        return TrainerResponse(content: content, confidence: 0.9)
    }
    
    private func generateFallbackResponse(context: TrainerContext) -> TrainerResponse {
        let content = AriaVoiceEngine.speak(intent: .fallback, context: context)
        return TrainerResponse(content: content, confidence: 0.7)
    }
}

// MARK: - AppStore (Production-ready state management)

@MainActor
final class AppStore: ObservableObject {

    // MARK: - Published State
    
    // Onboarding
    @Published var isOnboarded: Bool = false {
        didSet { UserDefaults.standard.set(isOnboarded, forKey: Self.onboardedDefaultsKey) }
    }
    @Published var onboardingStep: Int = 0

    // Auth (local session gate — production wires IdP tokens)
    @Published var isAuthenticated: Bool = false {
        didSet { UserDefaults.standard.set(isAuthenticated, forKey: Self.authDefaultsKey) }
    }
    @Published var authProvider: String = ""
    @Published var authEmail: String = ""

    // User Profile
    @Published var userProfile: UserProfile = mockProfile {
        didSet { persistUserProfile() }
    }

    // Readiness & Metrics
    @Published var readiness: ReadinessData = mockReadiness
    @Published var dailyMetrics: DailyMetrics = mockMetrics

    // Today's Workout
    @Published var todayWorkout: WorkoutPlan? = mockWorkout

    // Active Workout State
    @Published var isWorkoutActive: Bool = false
    @Published var currentExerciseIndex: Int = 0
    @Published var currentSet: Int = 1

    // Chat
    @Published var chatMessages: [ChatMessage] = []
    @Published var isGeneratingResponse: Bool = false

    // Sleep
    @Published var sleepData: [SleepData] = []

    // History & Records
    @Published var workoutHistory: [WorkoutHistory] = []
    @Published var personalRecords: [PersonalRecord] = []

    // Navigation
    @Published var activeTab: TabItem = .home
    @Published var pendingProfileSubTab: String? = nil
    /// When true, Home presents Cycle Health full-screen (Settings deep-link).
    @Published var pendingCycleHealthOpen: Bool = false
    /// Optional Cycle pane: "me" or "partner".
    @Published var pendingCyclePane: String? = nil

    // Quiet mode — damp proactive noise (persisted)
    @Published var quietMode: Bool = UserDefaults.standard.bool(forKey: "forge.quiet.mode.v1") {
        didSet {
            UserDefaults.standard.set(quietMode, forKey: "forge.quiet.mode.v1")
            AriaContextStore.shared.setQuietMode(quietMode)
        }
    }

    // ARIA bridge
    @Published var ariaVoiceMode: Bool = false
    @Published var ariaPendingChatPrompt: String? = nil
    @Published var lastSuggestedActions: [String] = []
    @Published var healthKitLive: Bool = false
    /// Last successful metrics refresh (Home status pill).
    @Published var lastMetricsRefresh: Date? = nil
    
    // Streak tracking
    @Published var currentStreak: Int = 7
    
    // AI Configuration
    @Published var aiModelAvailable: Bool = false
    
    // MARK: - Private Properties
    
    private var responseGenerator: TrainerResponseGenerator
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init() {
        // Initialize AI response generator
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let foundationModelsGenerator = FoundationModelsResponseGenerator()
            self.aiModelAvailable = foundationModelsGenerator.isAvailable
            self.responseGenerator = foundationModelsGenerator.isAvailable ?
                foundationModelsGenerator : RuleBasedResponseGenerator()
        } else {
            self.responseGenerator = RuleBasedResponseGenerator()
            self.aiModelAvailable = false
        }
        #else
        self.responseGenerator = RuleBasedResponseGenerator()
        self.aiModelAvailable = false
        #endif
        
        AriaContextStore.shared.configure()
        AriaPersonRegistry.shared.bootstrapFromPartnerSettingsIfNeeded()

        // Restore persisted onboarding so a returning user skips setup entirely.
        restoreOnboardingState()

        // Load seed data, then hydrate from HealthKit when authorized
        Task { @MainActor in
            self.chatMessages = mockChatMessages
            self.sleepData = mockSleepData
            self.workoutHistory = mockWorkoutHistory
            self.personalRecords = mockPersonalRecords
            await self.refreshDailyData()
        }
    }

    // MARK: - Onboarding Persistence

    private static let onboardedDefaultsKey = "forge.onboarding.completed"
    private static let profileDefaultsKey = "forge.user.profile.v1"
    private static let authDefaultsKey = "forge.auth.session.v1"
    private static let authProviderKey = "forge.auth.provider.v1"
    private static let authEmailKey = "forge.auth.email.v1"

    /// Rehydrates auth + completed onboarding on cold launch.
    private func restoreOnboardingState() {
        isAuthenticated = UserDefaults.standard.bool(forKey: Self.authDefaultsKey)
        authProvider = UserDefaults.standard.string(forKey: Self.authProviderKey) ?? ""
        authEmail = UserDefaults.standard.string(forKey: Self.authEmailKey) ?? ""
        // Legacy: onboarded users from before auth gate count as signed in.
        if !isAuthenticated, UserDefaults.standard.bool(forKey: Self.onboardedDefaultsKey) {
            isAuthenticated = true
            authProvider = authProvider.isEmpty ? "legacy" : authProvider
        }
        guard UserDefaults.standard.bool(forKey: Self.onboardedDefaultsKey) else { return }
        if let data = UserDefaults.standard.data(forKey: Self.profileDefaultsKey),
           let saved = try? JSONDecoder().decode(UserProfile.self, from: data) {
            userProfile = saved
        }
        isOnboarded = true
    }

    /// Sign-up path: mark authenticated then run onboarding (HealthKit + profile).
    func beginSignUp() {
        isAuthenticated = true
        authProvider = "signup"
        UserDefaults.standard.set("signup", forKey: Self.authProviderKey)
        isOnboarded = false
        onboardingStep = 0
    }

    /// Completes auth for returning or new social/email users.
    func authenticate(provider: String, email: String, displayName: String, isNewAccount: Bool) {
        isAuthenticated = true
        authProvider = provider
        authEmail = email
        UserDefaults.standard.set(provider, forKey: Self.authProviderKey)
        UserDefaults.standard.set(email, forKey: Self.authEmailKey)
        if !displayName.isEmpty, userProfile.name.isEmpty || userProfile.name == "Alex" || isNewAccount {
            userProfile.name = displayName
        }
        if isNewAccount || !UserDefaults.standard.bool(forKey: Self.onboardedDefaultsKey) {
            isOnboarded = false
            onboardingStep = 0
        } else {
            isOnboarded = true
            Task { await refreshDailyData() }
        }
    }

    private func persistUserProfile() {
        guard let data = try? JSONEncoder().encode(userProfile) else { return }
        UserDefaults.standard.set(data, forKey: Self.profileDefaultsKey)
    }

    // MARK: - Onboarding → ARIA handoff

    /// Replaces mock chat with a personalized ARIA first message after onboarding.
    func seedAriaWelcomeFromOnboarding(message: String, suggestedActions: [String] = []) {
        let welcome = ChatMessage(
            id: "aria-onboarding-\(UUID().uuidString.prefix(8))",
            role: .trainer,
            content: message,
            timestamp: Date(),
            confidence: 0.92,
            suggestedActions: suggestedActions.isEmpty
                ? ["Show today's plan", "How does readiness work?", "Adjust my goals"]
                : suggestedActions
        )
        chatMessages = [welcome]
        lastSuggestedActions = welcome.suggestedActions ?? []
    }

    // MARK: - Workout Actions

    func startWorkout() {
        currentExerciseIndex = 0
        currentSet = 1
        isWorkoutActive = true
    }

    func nextSet() {
        currentSet += 1
    }

    func nextExercise() {
        currentExerciseIndex += 1
        currentSet = 1
    }

    func endWorkout(completed: Bool = true) {
        isWorkoutActive = false
        currentExerciseIndex = 0
        currentSet = 1
        
        // Update streak and history
        if completed { currentStreak += 1 }
        
        let planId = todayWorkout?.id ?? "today-workout"
        if let workout = todayWorkout, completed {
            let history = WorkoutHistory(
                id: UUID().uuidString,
                date: ISO8601DateFormatter().string(from: Date()),
                name: workout.name,
                type: workout.type,
                duration: workout.duration,
                volume: workout.exercises.reduce(0) { $0 + ($1.sets * ($1.weight ?? 0)) },
                intensity: workout.intensity
            )
            workoutHistory.insert(history, at: 0)
        }

        Task {
            await FeedbackService.shared.processPlanOutcome(
                userId: AriaContextStore.shared.context.userId,
                planId: planId,
                completed: completed
            )
        }
    }

    // MARK: - Chat Actions

    func addMessage(_ message: ChatMessage) {
        chatMessages.append(message)
    }
    
    /// Send a message through ARIA (remote when available, local fallback).
    func sendMessage(_ text: String) async {
        let userMessage = ChatMessage(
            id: UUID().uuidString,
            role: .user,
            content: text,
            timestamp: Date()
        )
        chatMessages.append(userMessage)
        isGeneratingResponse = true

        do {
            // Learn theme preference from chat ("train like Solo Leveling", locks, etc.).
            applyTrainingThemeIfDetected(from: text)
            // Learn voice dials ("be hype", "just the facts", "keep it short", …).
            applyVoicePreferenceIfDetected(from: text)
            // Learn partner/daughter/family support context from plain language.
            applySupportContextIfDetected(from: text)

            let aria = try await AriaService.shared.sendMessage(
                text,
                store: self,
                localGenerator: responseGenerator,
                voiceMode: ariaVoiceMode
            )

            lastSuggestedActions = aria.suggestedActions ?? []

            // If ARIA built a session, surface it as today's plan.
            if let card = aria.toRichCardData(), card.type == .workoutPlan {
                adoptWorkoutFromRichCard(card)
            }

            let trainerMessage = ChatMessage(
                id: UUID().uuidString,
                role: .trainer,
                content: aria.message,
                timestamp: Date(),
                richCard: aria.toRichCardData(),
                confidence: aria.confidence,
                suggestedActions: aria.suggestedActions,
                memoryReference: aria.memoryReference,
                confidenceReason: aria.confidenceReason
            )
            chatMessages.append(trainerMessage)
        } catch {
            let errorMessage = ChatMessage(
                id: UUID().uuidString,
                role: .trainer,
                content: "Sorry, I'm having trouble processing that right now. Can you try again?",
                timestamp: Date()
            )
            chatMessages.append(errorMessage)
            print("Error generating ARIA response: \(error)")
        }

        isGeneratingResponse = false
    }

    /// One-shot ARIA insight for non-chat surfaces (e.g. Lifestyle cards).
    /// Uses the same remote-first path as `sendMessage` (with on-device fallback)
    /// but does NOT append to the chat transcript. Returns nil only if both the
    /// remote call and local generation throw — callers should fall back to their
    /// existing local content in that case.
    func ariaInsight(prompt: String, voiceMode: Bool = false) async -> AriaResponse? {
        try? await AriaService.shared.sendMessage(
            prompt,
            store: self,
            localGenerator: responseGenerator,
            voiceMode: voiceMode
        )
    }

    /// Legacy method for backward compatibility - converts to async
    func trainerResponse(for text: String) -> (content: String, richCard: RichCardData?) {
        // This is synchronous fallback for compatibility
        // In production, you should use sendMessage() instead
        var result: (String, RichCardData?) = ("I'm thinking...", nil)
        
        Task { @MainActor in
            let context = makeTrainerContext()
            
            do {
                let response = try await responseGenerator.generateResponse(for: text, context: context)
                result = (response.content, response.richCard)
            } catch {
                result = ("Sorry, I couldn't process that. Try again?", nil)
            }
        }
        
        return result
    }

    /// Builds a full `TrainerContext` including living ARIA tags/constraints + cycle.
    func makeTrainerContext() -> TrainerContext {
        let ctx = AriaContextStore.shared.context
        let cycleStore = MenstrualHealthStore.shared
        cycleStore.refresh(from: self)
        let cycle: MenstrualCycleSnapshot? = {
            guard cycleStore.settings.enabled, cycleStore.settings.shareWithAria else { return nil }
            return cycleStore.snapshot
        }()
        let partner: MenstrualCycleSnapshot? = {
            guard cycleStore.partnerSettings.enabled,
                  cycleStore.partnerSettings.consentAcknowledged,
                  cycleStore.partnerSettings.shareWithAria else { return nil }
            return cycleStore.partnerSnapshot
        }()
        let partnerSettings: PartnerCycleSettings? = {
            guard cycleStore.partnerSettings.enabled,
                  cycleStore.partnerSettings.consentAcknowledged else { return nil }
            return cycleStore.partnerSettings
        }()
        return TrainerContext(
            userProfile: userProfile,
            readiness: readiness,
            dailyMetrics: dailyMetrics,
            sleepData: sleepData,
            workoutHistory: workoutHistory,
            currentTime: Date(),
            conversationHistory: chatMessages,
            lifestyleTags: ctx.lifestyleTags,
            constraints: ctx.constraints,
            cycleSnapshot: cycle,
            partnerCycleSnapshot: partner,
            partnerCycleSettings: partnerSettings
        )
    }

    /// Detects fandom/theme requests and persists preference for future plans.
    func applyTrainingThemeIfDetected(from text: String) {
        guard let theme = AriaThemeResolver.detect(in: text) else { return }
        let lock = AriaThemeResolver.isThemePreferenceLock(text)
        // Always remember an explicit franchise ask; locks force persist even if already set.
        if lock || userProfile.trainingTheme != theme {
            setTrainingTheme(theme, source: "chat")
        }
    }

    /// Soft-learns who the user supports (partner, daughter, family) from chat.
    func applySupportContextIfDetected(from text: String) {
        // Instant adaptation from any relationship label/name in the message.
        _ = AriaPersonRegistry.shared.adapt(to: text)
        AriaPersonRegistry.shared.bootstrapFromPartnerSettingsIfNeeded()

        guard let mention = AriaRelationalCoach.detectSupportMention(in: text) else {
            // Still learn dynamics / archetype / speech for active person
            if let id = AriaPersonRegistry.shared.activePersonId {
                AriaPersonRegistry.shared.learnDynamics(from: text, personId: id)
            }
            // Global archetype teaching without an active person name
            if AriaPersonalArchetype.detect(in: text) != nil || text.lowercased().contains("she talks")
                || text.lowercased().contains("he talks") || text.lowercased().contains("texts short") {
                if let id = AriaPersonRegistry.shared.activePersonId {
                    AriaPersonRegistry.shared.learnDynamics(from: text, personId: id)
                }
            }
            return
        }
        AriaRelationalCoach.applyMentionIfNeeded(mention, store: MenstrualHealthStore.shared)
        if let id = AriaPersonRegistry.shared.activePersonId {
            AriaPersonRegistry.shared.learnDynamics(from: text, personId: id)
        }
        // Natural consent phrases unlock full coaching.
        let lower = text.lowercased()
        if lower.contains("she said it's okay") || lower.contains("she is okay")
            || lower.contains("with her consent") || lower.contains("she knows")
            || lower.contains("we're okay tracking") || lower.contains("as her dad")
            || lower.contains("as her father") || lower.contains("i'm her parent") {
            MenstrualHealthStore.shared.updatePartnerSettings {
                $0.consentAcknowledged = true
                $0.enabled = true
                $0.shareWithAria = true
            }
            AriaContextStore.shared.addInsight(
                "Support consent acknowledged in chat — relational coaching unlocked."
            )
        }
        // Period start for them: "her period started today"
        if lower.contains("period started") || lower.contains("started her period")
            || lower.contains("on her period") && (lower.contains("today") || lower.contains("now")) {
            if MenstrualHealthStore.shared.partnerSettings.consentAcknowledged {
                MenstrualHealthStore.shared.logPartnerPeriodStart(flow: .medium)
            }
        }
    }

    /// Sticky voice dials from natural language so ARIA can be steered mid-conversation.
    func applyVoicePreferenceIfDetected(from text: String) {
        let lower = text.lowercased()
        var tags: [String] = []
        if lower.contains("be hype") || lower.contains("hype me") || lower.contains("pump me") {
            tags.append("voice:hype")
        }
        if lower.contains("be gentle") || lower.contains("softer") || lower.contains("be soft") {
            tags.append("voice:soft")
        }
        if lower.contains("just the facts") || lower.contains("data mode") || lower.contains("be clinical")
            || lower.contains("talk data") || lower.contains("numbers only") {
            tags.append("voice:clinical")
        }
        if lower.contains("talk street") || lower.contains("be casual") || lower.contains("less formal") {
            tags.append("voice:street")
        }
        if lower.contains("in character") || lower.contains("full theme") || lower.contains("mythic") {
            tags.append("voice:mythic")
        }
        if lower.contains("keep it short") || lower.contains("tl;dr") || lower.contains("be brief") {
            tags.append("voice:tight")
        }
        if lower.contains("go deep") || lower.contains("in detail") || lower.contains("explain more") {
            tags.append("voice:expansive")
        }
        if lower.contains("be funny") || lower.contains("lighten up") {
            tags.append("voice:playful")
        }
        if lower.contains("no bs") || lower.contains("be blunt") || lower.contains("be real") {
            tags.append("voice:blunt")
        }
        if lower.contains("reset voice") || lower.contains("normal voice") || lower.contains("default voice") {
            AriaContextStore.shared.clearVoicePreferenceTags()
            return
        }
        guard !tags.isEmpty else { return }
        AriaContextStore.shared.setVoicePreferenceTags(tags)
    }

    func setTrainingTheme(_ theme: AriaTrainingTheme, source: String = "settings") {
        let changed = userProfile.trainingTheme != theme
        userProfile.trainingTheme = theme
        AriaContextStore.shared.setTrainingTheme(theme)
        guard changed else {
            objectWillChange.send()
            return
        }
        AriaContextStore.shared.addInsight(
            "Training theme set to \(theme.label) via \(source)."
        )
        // Rebuild today's plan under the new lens when readiness is known.
        if readiness.overall > 0 {
            let plan = AriaPlanEngine.evaluate(
                input: "Build today's \(theme.label) training plan",
                context: makeTrainerContext()
            )
            todayWorkout = plan.workoutPlan
        }
        objectWillChange.send()
    }

    func adoptWorkoutFromRichCard(_ card: RichCardData) {
        guard card.type == .workoutPlan,
              let name = card.workoutName,
              let duration = card.workoutDuration,
              let moves = card.workoutExercises else { return }
        let exercises = moves.enumerated().map { idx, move in
            Exercise(
                id: "aria-live-\(idx)",
                name: move.name,
                sets: move.sets,
                reps: move.reps,
                weight: nil,
                restSeconds: 60,
                notes: nil
            )
        }
        let intensity: WorkoutIntensity = {
            if duration >= 50 { return .high }
            if duration >= 35 { return .moderate }
            return .low
        }()
        todayWorkout = WorkoutPlan(
            id: "aria-today-\(UUID().uuidString.prefix(6))",
            name: name,
            type: .strength,
            duration: duration,
            intensity: intensity,
            exercises: exercises
        )
    }
    
    // MARK: - Data Management
    
    func refreshDailyData() async {
        let hk = HealthKitManager.shared
        let authorized = await hk.checkAuthorizationStatus()
        healthKitLive = authorized

        if authorized, let snapshot = await hk.fetchRecentSnapshot() {
            updateMetrics(
                steps: snapshot.steps,
                activeCalories: snapshot.activeCalories,
                hrv: snapshot.hrv.map { Int($0) },
                restingHR: snapshot.restingHeartRate,
                deepSleep: nil,
                totalSleep: snapshot.sleepHours.map { Int($0 * 60) }
            )
            if let weight = userProfile.weight {
                userProfile.weight = weight
            }
        }

        let samples = BiometricsObserveService.shared.samplesFromStore(self)
        _ = await BiometricsObserveService.shared.observe(store: self, samples: samples)

        // Menstrual cycle: auto-enable + quiet weekly HealthKit sync (or immediate if broken).
        MenstrualHealthStore.shared.enableForFemaleProfileIfNeeded(gender: userProfile.gender)
        if let sex = userProfile.biologicalSex {
            MenstrualHealthStore.shared.enableForBiologicalSexIfNeeded(sex)
        }
        if MenstrualHealthStore.shared.settings.enabled {
            await MenstrualHealthStore.shared.quietWeeklyHealthKitSync(force: !authorized)
            MenstrualHealthStore.shared.refresh(from: self)
        }

        lastMetricsRefresh = Date()
        objectWillChange.send()
    }

    func openChat(with prompt: String, voice: Bool = false) {
        if quietMode, !voice {
            // Still allow explicit user-initiated chat; only damp auto prompts elsewhere.
        }
        ariaPendingChatPrompt = prompt
        ariaVoiceMode = voice
        activeTab = .chat
    }

    /// Deep-link into Home Cycle Health full-screen (optional Support pane).
    func openCycleHealth(pane: String? = nil) {
        pendingCyclePane = pane
        pendingCycleHealthOpen = true
        activeTab = .home
    }

    func setQuietMode(_ on: Bool) {
        quietMode = on
    }
    
    /// Update user metrics (typically from HealthKit integration)
    func updateMetrics(
        steps: Int? = nil,
        activeCalories: Int? = nil,
        hrv: Int? = nil,
        restingHR: Int? = nil,
        deepSleep: Int? = nil,
        totalSleep: Int? = nil
    ) {
        if let steps = steps { dailyMetrics.steps = steps }
        if let activeCalories = activeCalories { dailyMetrics.activeCalories = activeCalories }
        if let hrv = hrv { dailyMetrics.hrv = hrv }
        if let restingHR = restingHR { dailyMetrics.restingHR = restingHR }
        if let deepSleep = deepSleep { dailyMetrics.deepSleep = deepSleep }
        if let totalSleep = totalSleep { dailyMetrics.totalSleep = totalSleep }
        
        // Recalculate readiness based on new metrics
        recalculateReadiness()
    }
    
    /// Recalculate readiness score based on current metrics
    private func recalculateReadiness() {
        // Simplified readiness calculation
        // In production, this would use more sophisticated algorithms
        
        let sleepScore = calculateSleepScore()
        let hrvScore = calculateHRVScore()
        let restingHRScore = calculateRestingHRScore()
        
        readiness.overall = (sleepScore + hrvScore + restingHRScore) / 3
        readiness.sleepQuality = sleepScore
        readiness.recoveryScore = (hrvScore + restingHRScore) / 2
    }
    
    private func calculateSleepScore() -> Int {
        let totalHours = Double(dailyMetrics.totalSleep) / 60
        let deepMinutes = dailyMetrics.deepSleep
        
        var score = 0
        
        // Total sleep score (0-50 points)
        if totalHours >= 7.5 {
            score += 50
        } else if totalHours >= 7 {
            score += 40
        } else if totalHours >= 6 {
            score += 25
        } else {
            score += 10
        }
        
        // Deep sleep score (0-50 points)
        if deepMinutes >= 90 {
            score += 50
        } else if deepMinutes >= 70 {
            score += 40
        } else if deepMinutes >= 50 {
            score += 25
        } else {
            score += 10
        }
        
        return min(score, 100)
    }
    
    private func calculateHRVScore() -> Int {
        // HRV scoring (typical range: 20-100ms)
        let hrv = dailyMetrics.hrv
        
        if hrv >= 60 {
            return 90
        } else if hrv >= 50 {
            return 80
        } else if hrv >= 40 {
            return 65
        } else if hrv >= 30 {
            return 50
        } else {
            return 30
        }
    }
    
    private func calculateRestingHRScore() -> Int {
        // Resting HR scoring (lower is better for athletes)
        let hr = dailyMetrics.restingHR
        
        if hr <= 55 {
            return 95
        } else if hr <= 60 {
            return 85
        } else if hr <= 65 {
            return 75
        } else if hr <= 70 {
            return 60
        } else {
            return 40
        }
    }
    
    // MARK: - Profile Management
    
    func updateProfile(
        name: String? = nil,
        coachingStyle: CoachingStyle? = nil,
        fitnessGoals: [UserFitnessGoal]? = nil,
        experienceLevel: ExperienceLevel? = nil,
        preferredWorkouts: [WorkoutType]? = nil,
        weeklySchedule: [Int]? = nil,
        trainingEquipment: TrainingEquipment? = nil,
        connectedDevices: [String]? = nil,
        age: Int? = nil,
        weightKg: Double? = nil,
        trainingTheme: AriaTrainingTheme? = nil,
        interestTags: [String]? = nil
    ) {
        if let name = name { userProfile.name = name }
        if let style = coachingStyle { userProfile.coachingStyle = style }
        if let goals = fitnessGoals { userProfile.fitnessGoals = goals }
        if let level = experienceLevel { userProfile.experienceLevel = level }
        if let preferredWorkouts { userProfile.preferredWorkouts = preferredWorkouts }
        if let weeklySchedule { userProfile.weeklySchedule = weeklySchedule.sorted() }
        if let trainingEquipment { userProfile.trainingEquipment = trainingEquipment }
        if let connectedDevices { userProfile.connectedDevices = connectedDevices }
        if let age { userProfile.age = age }
        if let weightKg { userProfile.weight = weightKg }
        if let interestTags { userProfile.interestTags = interestTags }
        if let trainingTheme {
            setTrainingTheme(trainingTheme, source: "profile")
            return
        }
        objectWillChange.send()
    }
    
    // MARK: - Sleep Management
    
    func mergeSleepDataLocally(_ local: [SleepData]) {
        guard !local.isEmpty else { return }
        var merged = Dictionary(sleepData.map { ($0.date, $0) }, uniquingKeysWith: { _, new in new })
        for night in local {
            merged[night.date] = night
        }
        sleepData = merged.values.sorted { $0.date > $1.date }
        if let latest = sleepData.first {
            dailyMetrics.totalSleep = Int(latest.totalHours * 60)
            dailyMetrics.deepSleep = latest.deepMinutes
            recalculateReadiness()
        }
    }

    func addSleepData(_ sleep: SleepData) {
        sleepData.insert(sleep, at: 0)
        
        // Update daily metrics
        dailyMetrics.totalSleep = Int(sleep.totalHours * 60)
        dailyMetrics.deepSleep = sleep.deepMinutes
        
        // Recalculate readiness
        recalculateReadiness()
    }
    
    // MARK: - Personal Records
    
    func updatePersonalRecord(exercise: String, value: Double, unit: String) {
        if let index = personalRecords.firstIndex(where: { $0.exercise == exercise }) {
            // Update existing record if new value is better
            if value > personalRecords[index].value {
                personalRecords[index] = PersonalRecord(
                    exercise: exercise,
                    value: value,
                    unit: unit,
                    date: ISO8601DateFormatter().string(from: Date())
                )
            }
        } else {
            // Add new record
            let newRecord = PersonalRecord(
                exercise: exercise,
                value: value,
                unit: unit,
                date: ISO8601DateFormatter().string(from: Date())
            )
            personalRecords.append(newRecord)
        }
    }
}

// MARK: - AppStore Extensions

extension AppStore {
    /// Calculate weekly workout frequency
    var weeklyWorkoutFrequency: Int {
        let calendar = Calendar.current
        let now = Date()
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now)!
        
        return workoutHistory.filter { history in
            guard let date = ISO8601DateFormatter().date(from: history.date) else { return false }
            return date >= weekAgo && date <= now
        }.count
    }
    
    /// Get readiness trend (improving, declining, stable)
    enum ReadinessTrend {
        case improving, stable, declining
    }
    
    var readinessTrend: ReadinessTrend {
        // Compare current readiness with 7-day average
        let recentScores = sleepData.prefix(7).map { $0.score }
        guard !recentScores.isEmpty else { return .stable }
        
        let average = Double(recentScores.reduce(0, +)) / Double(recentScores.count)
        let difference = Double(readiness.overall) - average
        
        if difference > 5 {
            return .improving
        } else if difference < -5 {
            return .declining
        } else {
            return .stable
        }
    }
    
    /// Check if user should train today based on readiness
    var shouldTrainToday: Bool {
        readiness.overall >= 50
    }
    
    /// Get recommended intensity for today
    var recommendedIntensity: WorkoutIntensity {
        if readiness.overall >= 80 {
            return .high
        } else if readiness.overall >= 65 {
            return .moderate
        } else {
            return .low
        }
    }
}
