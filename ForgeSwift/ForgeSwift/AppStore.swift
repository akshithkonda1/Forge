import Foundation
import Combine
import UIKit
import ForgeCore
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Tab Enum

enum TabItem: String, CaseIterable, Identifiable {
    /// Order is visual nav order: Home · Train · Life · ARIA · Sleep · Stats · You
    case home, workout, lifestyle, chat, sleep, progress, profile
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
    /// Recent turns only — older history is compressed into `conversationSummary`
    /// so prompts stay cheap without losing continuity.
    let conversationHistory: [ChatMessage]
    /// Total turns exchanged ever, including those trimmed out of
    /// `conversationHistory`. Use this (not `conversationHistory.count`) for any
    /// relationship-depth or "early conversation" heuristic.
    var totalMessageCount: Int = 0
    /// Compressed memory anchors for everything older than the recent window.
    var conversationSummary: String? = nil
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

        // Mission-critical safety: never green-light high intensity when recovery
        // signals dominate. Matches SimRunner directional-correctness hard gate.
        if wantsHighIntensityOverride(lower), context.readiness.overall < 55 {
            return generateSafetyRecoveryHold(context: context, input: input)
        }
        
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

    private func wantsHighIntensityOverride(_ text: String) -> Bool {
        let needles = [
            "train hard", "as hard as possible", "train as hard", "push through",
            "max effort", "go hard", "pr day", "hit a pr", "hiit", "all out",
            "ignore my readiness", "override readiness",
        ]
        return needles.contains { text.contains($0) }
    }

    private func generateSafetyRecoveryHold(context: TrainerContext, input: String) -> TrainerResponse {
        let r = context.readiness.overall
        let name = context.userProfile.name.split(separator: " ").first.map(String.init) ?? "there"
        let content = """
        I hear the drive, \(name) — and I'm not going to green-light max effort today.

        Your readiness is \(r)/100. Pushing high intensity here is how niggles become setbacks. \
        What I *will* back: Zone 2, mobility, technique work, or a full rest day. That choice \
        protects tomorrow's sessions, not just today's ego.

        Want a recovery-shaped session or a clean rest plan?
        """
        return TrainerResponse(
            content: content,
            suggestedActions: ["Build a recovery session", "Full rest day", "Why is readiness low?"],
            confidence: 0.95
        )
    }
    
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
    
    @MainActor
    private func generateArchetypeStudioResponse(
        intent: AriaArchetypeIntent,
        context: TrainerContext,
        input: String
    ) async -> TrainerResponse {
        _ = AriaPersonRegistry.shared.adapt(to: input)
        let studio = AriaArchetypeStudio.shared
        let personName = AriaPersonRegistry.shared.activePerson?.name
            ?? context.partnerCycleSettings?.displayName
            ?? "them"

        switch intent {
        case .list:
            let builtin = AriaPersonalArchetype.allCases.filter { $0 != .unknown }.map(\.label)
            let custom = studio.customArchetypes.prefix(12).map { "\($0.name) (\($0.source.displayName))" }
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
            studio.apply(crafted, toPersonId: AriaPersonRegistry.shared.activePersonId)
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
            if let activeId = AriaPersonRegistry.shared.activePerson?.customArchetypeId,
               let existing = studio.archetype(id: activeId) {
                let refined = await studio.enrich(existing, with: extra)
                studio.apply(refined, toPersonId: AriaPersonRegistry.shared.activePersonId)
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
            studio.apply(crafted, toPersonId: AriaPersonRegistry.shared.activePersonId)
            return TrainerResponse(
                content: "No custom archetype was attached yet — I forged **\(crafted.name)** and applied it to \(personName).",
                suggestedActions: ["Deepen this archetype", "Support script"],
                confidence: 0.88
            )

        case .assign(let name):
            if let existing = studio.findByName(name) {
                studio.apply(existing, toPersonId: AriaPersonRegistry.shared.activePersonId)
                return TrainerResponse(
                    content: "Attached **\(existing.name)** to \(personName).",
                    suggestedActions: ["How do I support them?", "Deepen this archetype"],
                    confidence: 0.9
                )
            }
            let crafted = await studio.createArchetype(from: input, preferredName: name)
            studio.apply(crafted, toPersonId: AriaPersonRegistry.shared.activePersonId)
            return TrainerResponse(
                content: "Created and attached **\(crafted.name)** to \(personName).",
                suggestedActions: ["Support script", "List archetypes"],
                confidence: 0.9
            )
        }
    }

    private func generateGreeting(context: TrainerContext) -> TrainerResponse {
        var content = AriaVoiceEngine.speak(intent: .greeting, context: context)
        let salt = UInt64(context.totalMessageCount * 17 + context.readiness.overall)
        if let addon = AriaRelationalCoach.greetingAddon(
            settings: context.partnerCycleSettings,
            snapshot: context.partnerCycleSnapshot,
            salt: salt
        ) {
            content += "\n\n" + addon
        } else if context.partnerCycleSettings == nil,
                  context.userProfile.gender == .male,
                  context.totalMessageCount < 4 {
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
                RichCardExercise(name: "Foam Rolling", sets: 1, reps: "5 min"),
                RichCardExercise(name: "World's Greatest Stretch", sets: 2, reps: "8 each side"),
                RichCardExercise(name: "Band Pull-Aparts", sets: 3, reps: "15"),
                RichCardExercise(name: "Goblet Squats (light)", sets: 2, reps: "10"),
                RichCardExercise(name: "Dead Hangs", sets: 3, reps: "30 sec"),
                RichCardExercise(name: "Walk or Bike (easy)", sets: 1, reps: "10 min"),
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
    @Published var userProfile: UserProfile = emptyProfile {
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

    // Chat momentum — lives here (not in the view) so XP and level survive
    // relaunches and stay consistent with the rest of the ARIA context.
    @Published var chatXP: Int = UserDefaults.standard.integer(forKey: AppStore.chatXPKey) {
        didSet { UserDefaults.standard.set(chatXP, forKey: Self.chatXPKey) }
    }
    @Published var chatLevel: Int = max(1, UserDefaults.standard.integer(forKey: AppStore.chatLevelKey)) {
        didSet { UserDefaults.standard.set(chatLevel, forKey: Self.chatLevelKey) }
    }

    // Sleep
    @Published var sleepData: [SleepData] = []

    // History & Records
    @Published var workoutHistory: [WorkoutHistory] = []
    @Published var personalRecords: [PersonalRecord] = []

    // Navigation
    @Published var activeTab: TabItem = .home
    @Published var pendingProfileSubTab: String? = nil
    /// When true, main shell presents Cycle Health full-screen (Settings / Home deep-link).
    @Published var pendingCycleHealthOpen: Bool = false
    /// Optional Cycle pane: "me" or "partner".
    @Published var pendingCyclePane: String? = nil
    /// When true, Cycle Health opens the sharing sheet on top. Set by the
    /// `forge://cycle/sharing` deep link the Messages extension uses when it has
    /// no invite staged and has to hand the user back to the app.
    @Published var pendingCycleSharingOpen: Bool = false
    /// Lifestyle sub-segment deep link: `nutrition` | `restaurants` | `wellbeing` | `aiOptimization`
    @Published var pendingLifestyleSegment: String? = nil
    /// When true, main shell presents Hydration full-screen.
    @Published var pendingHydrationOpen: Bool = false

    // Quiet mode — damp proactive noise (persisted)
    @Published var quietMode: Bool = UserDefaults.standard.bool(forKey: "forge.quiet.mode.v1") {
        didSet {
            UserDefaults.standard.set(quietMode, forKey: "forge.quiet.mode.v1")
            AriaContextStore.shared.setQuietMode(quietMode)
        }
    }

    // Settings — @Published so SwiftUI observes them directly, instead of
    // decoding UserDefaults on every access with a manual objectWillChange.
    // didSet persists (and reschedules notifications) the same way as before.
    @Published var notificationSettings: AppNotificationSettings = ForgePersistence.loadNotificationSettings() {
        didSet {
            ForgePersistence.saveNotificationSettings(notificationSettings)
            Task { await resyncNotifications() }
        }
    }
    @Published var briefNotificationsEnabled: Bool = ForgePersistence.loadBriefNotificationsEnabled() {
        didSet {
            ForgePersistence.saveBriefNotificationsEnabled(briefNotificationsEnabled)
            Task { await resyncNotifications() }
        }
    }
    @Published var nutritionPreferences: NutritionPreferences = ForgePersistence.loadNutritionPreferences() {
        didSet { ForgePersistence.saveNutritionPreferences(nutritionPreferences) }
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

        // Chat transcript is restored synchronously so the first render of
        // ChatView already has real history — no mock flash on cold launch.
        restoreChatHistory()

        // Load seed data, then hydrate from HealthKit when authorized
        Task { @MainActor in
            self.sleepData = mockSleepData
            self.workoutHistory = mockWorkoutHistory
            self.personalRecords = mockPersonalRecords
            await self.refreshDailyData()
            // Apply brief-default migration (6 AM / 6 PM) and weekly ARIA.
            await self.resyncNotifications()
        }
    }

    // MARK: - Chat Persistence & Momentum

    /// Versioned single-document session: transcript + XP/level + durable anchors.
    /// Survives app restarts without mock flash; migrates from legacy v1/v2 keys.
    private static let chatSessionKey = "forge.chat.session.v3"
    private static let chatHistoryKeyLegacyV2 = "forge.chat.history.v2"
    private static let chatHistoryKeyLegacyV1 = "forge.chat.history.v1"
    private static let chatXPKey = "forge.chat.xp.v1"
    private static let chatLevelKey = "forge.chat.level.v1"
    private static let durableMemoryKey = "forge.chat.durable_memory.v1"
    /// Enough transcript for real continuity, small enough to stay cheap to
    /// store and to summarize into the prompt context.
    private static let maxPersistedMessages = 80
    private static let xpPerChatLevel = 100
    /// Verbatim turns that ride with every remote/local prompt.
    private static let recentTurnWindow = 10
    /// Cap for durable memory anchors persisted independently of the transcript.
    private static let maxDurableAnchors = 12

    /// Durable memory anchors (goals, injuries, standing insights) — not full history.
    @Published private(set) var durableMemoryAnchors: [String] = []

    /// Message currently being typewriter-revealed (nil when idle).
    @Published var streamingMessageId: String? = nil
    @Published var streamingVisibleCount: Int = 0

    var chatXPProgress: Double { Double(chatXP % Self.xpPerChatLevel) / Double(Self.xpPerChatLevel) }
    var chatXPToNextLevel: Int { Self.xpPerChatLevel - (chatXP % Self.xpPerChatLevel) }

    private struct ChatSessionDocument: Codable {
        var version: Int
        var messages: [ChatMessage]
        var xp: Int
        var level: Int
        var durableAnchors: [String]
        var updatedAt: Date
    }

    /// Awards XP and returns `true` when the award crossed a level boundary,
    /// so the caller can fire the celebration without owning the numbers.
    @discardableResult
    func awardChatXP(_ amount: Int) -> Bool {
        guard amount > 0 else { return false }
        chatXP += amount
        let newLevel = (chatXP / Self.xpPerChatLevel) + 1
        guard newLevel > chatLevel else {
            persistChatSession()
            return false
        }
        chatLevel = newLevel
        persistChatSession()
        return true
    }

    /// Records a standing fact ARIA should remember across sessions (goal, injury, preference).
    func rememberDurable(_ anchor: String) {
        let trimmed = anchor.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        durableMemoryAnchors.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        durableMemoryAnchors.insert(trimmed, at: 0)
        if durableMemoryAnchors.count > Self.maxDurableAnchors {
            durableMemoryAnchors = Array(durableMemoryAnchors.prefix(Self.maxDurableAnchors))
        }
        persistChatSession()
    }

    private func persistChatSession() {
        let recent = Array(chatMessages.suffix(Self.maxPersistedMessages))
        let doc = ChatSessionDocument(
            version: 3,
            messages: recent,
            xp: chatXP,
            level: max(1, chatLevel),
            durableAnchors: durableMemoryAnchors,
            updatedAt: Date()
        )
        guard let data = try? JSONEncoder().encode(doc) else { return }
        UserDefaults.standard.set(data, forKey: Self.chatSessionKey)
        // Keep legacy XP keys warm for any older readers.
        UserDefaults.standard.set(chatXP, forKey: Self.chatXPKey)
        UserDefaults.standard.set(chatLevel, forKey: Self.chatLevelKey)
        if let anchors = try? JSONEncoder().encode(durableMemoryAnchors) {
            UserDefaults.standard.set(anchors, forKey: Self.durableMemoryKey)
        }
    }

    /// Back-compat alias used throughout the chat pipeline.
    private func persistChatHistory() { persistChatSession() }

    private func restoreChatHistory() {
        // Preferred: single v3 session document.
        if let data = UserDefaults.standard.data(forKey: Self.chatSessionKey),
           let doc = try? JSONDecoder().decode(ChatSessionDocument.self, from: data) {
            chatMessages = doc.messages
            chatXP = max(0, doc.xp)
            // Level is always derived from XP so the two never drift.
            chatLevel = max(1, doc.level, (chatXP / Self.xpPerChatLevel) + 1)
            durableMemoryAnchors = doc.durableAnchors
            return
        }

        // Migrate v2 transcript array + separate XP keys.
        if let data = UserDefaults.standard.data(forKey: Self.chatHistoryKeyLegacyV2)
            ?? UserDefaults.standard.data(forKey: Self.chatHistoryKeyLegacyV1),
           let saved = try? JSONDecoder().decode([ChatMessage].self, from: data),
           !saved.isEmpty {
            chatMessages = saved
            chatXP = max(0, UserDefaults.standard.integer(forKey: Self.chatXPKey))
            chatLevel = max(1, UserDefaults.standard.integer(forKey: Self.chatLevelKey), (chatXP / Self.xpPerChatLevel) + 1)
            if let anchorData = UserDefaults.standard.data(forKey: Self.durableMemoryKey),
               let anchors = try? JSONDecoder().decode([String].self, from: anchorData) {
                durableMemoryAnchors = anchors
            }
            persistChatSession()
            UserDefaults.standard.removeObject(forKey: Self.chatHistoryKeyLegacyV2)
            UserDefaults.standard.removeObject(forKey: Self.chatHistoryKeyLegacyV1)
            return
        }

        // First launch (or a transcript we can no longer decode): seed the
        // demo conversation only when the user hasn't onboarded yet.
        chatMessages = isOnboarded ? [] : mockChatMessages
        chatLevel = max(1, (chatXP / Self.xpPerChatLevel) + 1)
        if let anchorData = UserDefaults.standard.data(forKey: Self.durableMemoryKey),
           let anchors = try? JSONDecoder().decode([String].self, from: anchorData) {
            durableMemoryAnchors = anchors
        }
    }

    /// Wipes the transcript and momentum — used by sign-out / reset flows.
    func clearChatHistory() {
        chatMessages = []
        chatXP = 0
        chatLevel = 1
        durableMemoryAnchors = []
        streamingMessageId = nil
        streamingVisibleCount = 0
        UserDefaults.standard.removeObject(forKey: Self.chatSessionKey)
        UserDefaults.standard.removeObject(forKey: Self.chatHistoryKeyLegacyV2)
        UserDefaults.standard.removeObject(forKey: Self.chatHistoryKeyLegacyV1)
        UserDefaults.standard.removeObject(forKey: Self.chatXPKey)
        UserDefaults.standard.removeObject(forKey: Self.chatLevelKey)
        UserDefaults.standard.removeObject(forKey: Self.durableMemoryKey)
    }

    /// Progressive reveal of the latest ARIA reply — feels like streaming even
    /// when the backend returns a full message. Does not mutate stored content.
    func beginStreamingReveal(for messageId: String, fullLength: Int) {
        streamingMessageId = messageId
        streamingVisibleCount = min(24, fullLength)
        Task { @MainActor in
            let step = max(3, fullLength / 40)
            while streamingMessageId == messageId, streamingVisibleCount < fullLength {
                try? await Task.sleep(nanoseconds: 18_000_000)
                streamingVisibleCount = min(fullLength, streamingVisibleCount + step)
            }
            if streamingMessageId == messageId {
                streamingMessageId = nil
                streamingVisibleCount = 0
            }
        }
    }

    func visibleContent(for message: ChatMessage) -> String {
        guard streamingMessageId == message.id, streamingVisibleCount > 0 else {
            return message.content
        }
        let end = min(streamingVisibleCount, message.content.count)
        let idx = message.content.index(message.content.startIndex, offsetBy: end)
        return String(message.content[..<idx])
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
        persistChatHistory()
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
        persistChatHistory()
    }
    
    /// Send a message through ARIA (remote when available, local fallback).
    func sendMessage(_ text: String, ariaPayload: String? = nil) async {
        let userMessage = ChatMessage(
            id: UUID().uuidString,
            role: .user,
            content: text,
            timestamp: Date()
        )
        chatMessages.append(userMessage)
        isGeneratingResponse = true
        let outbound = ariaPayload ?? text

        do {
            // Learn theme preference from chat ("train like Solo Leveling", locks, etc.).
            applyTrainingThemeIfDetected(from: outbound)
            // Learn voice dials ("be hype", "just the facts", "keep it short", …).
            applyVoicePreferenceIfDetected(from: outbound)
            // Learn partner/daughter/family support context from plain language.
            applySupportContextIfDetected(from: outbound)

            let aria = try await AriaService.shared.sendMessage(
                outbound,
                store: self,
                localGenerator: responseGenerator,
                voiceMode: ariaVoiceMode
            )

            lastSuggestedActions = aria.suggestedActions ?? []

            // If ARIA built a session, surface it as today's plan.
            if let card = aria.toRichCardData(), card.type == .workoutPlan {
                adoptWorkoutFromRichCard(card)
            }

            // Harvest durable facts from this exchange (goal language, injuries, etc.).
            harvestDurableMemory(userText: text, ariaText: aria.message)

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
            beginStreamingReveal(for: trainerMessage.id, fullLength: trainerMessage.content.count)
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
        persistChatHistory()
    }

    /// Lightweight durable-memory extraction — production-minded, no LLM required.
    private func harvestDurableMemory(userText: String, ariaText: String) {
        let lower = userText.lowercased()
        let patterns: [(String, String)] = [
            ("i want to", "User goal: "),
            ("my goal is", "User goal: "),
            ("i'm training for", "User goal: "),
            ("im training for", "User goal: "),
            ("i have a", "User note: "),
            ("i'm dealing with", "User note: "),
            ("im dealing with", "User note: "),
            ("injury", "Injury context: "),
            ("hurt my", "Injury context: "),
            ("prefer", "Preference: "),
            ("don't like", "Preference: "),
            ("do not like", "Preference: "),
        ]
        for (needle, prefix) in patterns {
            guard lower.contains(needle) else { continue }
            let snippet = String(userText.prefix(140))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            rememberDurable(prefix + snippet)
            break
        }
        // Confidence tags from ARIA that look like standing truths.
        if ariaText.lowercased().contains("i'll remember") || ariaText.lowercased().contains("noted:") {
            rememberDurable("ARIA noted: " + String(ariaText.prefix(120)))
        }
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

    /// Compresses pre-window history into a few "memory anchors" — what the user
    /// asked for, durable standing facts, live biometrics, and ARIA insights —
    /// instead of replaying the whole transcript on every turn.
    private func conversationMemoryAnchors() -> String? {
        var anchors: [String] = []

        // Always pin live biometrics so sleep/readiness/training stay tight.
        anchors.append(CrossZoneConsistency.memoryAnchorLine(for: CrossZoneConsistency.snapshot(from: self)))

        if !durableMemoryAnchors.isEmpty {
            anchors.append(
                "Durable memory: " + durableMemoryAnchors.prefix(6).joined(separator: " | ")
            )
        }

        let olderCount = max(0, chatMessages.count - Self.recentTurnWindow)
        if olderCount > 0 {
            let older = chatMessages.prefix(olderCount)
            let userThemes = older
                .filter { $0.role == .user }
                .suffix(3)
                .map { $0.content.prefix(110).trimmingCharacters(in: .whitespacesAndNewlines) }
            if !userThemes.isEmpty {
                anchors.append("Earlier the user asked about: " + userThemes.joined(separator: " | "))
            }
            anchors.append("\(olderCount) earlier turns omitted for brevity.")
        }

        let insights = AriaContextStore.shared.context.lastInsights.prefix(3)
        if !insights.isEmpty {
            anchors.append("Standing insights: " + insights.joined(separator: " | "))
        }

        return anchors.isEmpty ? nil : anchors.joined(separator: "\n")
    }

    /// The conversational slice that rides along with every remote ARIA call:
    /// recent turns verbatim, everything older compressed into anchors.
    func conversationContextPayload() -> ARIAContextPayload.ConversationDomain {
        let recent = chatMessages.suffix(Self.recentTurnWindow).map {
            ARIAContextPayload.ConversationDomain.Turn(
                role: $0.role.rawValue,
                content: String($0.content.prefix(600))
            )
        }
        return .init(
            recentTurns: Array(recent),
            summary: conversationMemoryAnchors(),
            totalTurns: chatMessages.count
        )
    }

    /// Legacy method for backward compatibility - converts to async
    /// Builds a full `TrainerContext` including living ARIA tags/constraints + cycle.
    func makeTrainerContext() -> TrainerContext {
        let ctx = AriaContextStore.shared.context
        let cycleStore = MenstrualHealthStore.shared
        // Read-only by design: this is called from SwiftUI computed properties, and
        // mutating published cycle state from inside a view update is not allowed.
        // The cycle store is refreshed on launch, on Home's task, and after every log.
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
            conversationHistory: Array(chatMessages.suffix(Self.recentTurnWindow)),
            totalMessageCount: chatMessages.count,
            conversationSummary: conversationMemoryAnchors(),
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

        if authorized {
            await hk.refreshHydration()
        }
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
        await flushPendingWidgetWater()
        publishHomeWidgets()
        objectWillChange.send()
    }

    /// Widget taps enqueue milliliters. Write them to HealthKit now that we
    /// are in the app process that actually holds the entitlement.
    func flushPendingWidgetWater() async {
        let pending = PendingWaterLog.drain()
        guard pending > 0 else { return }
        try? await HealthKitManager.shared.logWater(milliliters: pending)
        await HealthKitManager.shared.refreshHydration()
    }

    func publishHomeWidgets() {
        let nights = sleepData.compactMap { entry -> CircadianRhythm.Night? in
            guard let onset = entry.onset, let wake = entry.wake, wake > onset else { return nil }
            return CircadianRhythm.Night(onset: onset, wake: wake, asleepHours: entry.totalHours)
        }.sorted { $0.wake < $1.wake }
        let phase = CircadianRhythm.phase(from: nights)
        let nowHour = CircadianRhythm.hourOfDay(Date())
        let windowTitle = phase.map { CircadianRhythm.window(atHour: nowHour, phase: $0).title }

        let cycle = MenstrualHealthStore.shared
        let waterMl = HealthKitManager.shared.todayWaterMilliliters
        let waterTarget = HydrationEngine.targetMilliliters(
            weightKilograms: userProfile.weight,
            activeCalories: Double(dailyMetrics.activeCalories),
            cycle: {
                guard cycle.settings.enabled else { return .none }
                switch cycle.snapshot.phase {
                case .menstruation: return .menstruation
                case .luteal: return .luteal
                default: return .none
                }
            }()
        )

        HomeWidgetSnapshotStore.save(
            HomeWidgetSnapshot(
                readiness: readiness.overall,
                readinessLabel: ReadinessBand(score: readiness.overall).label,
                sleepHours: sleepData.first?.totalHours ?? Double(dailyMetrics.totalSleep) / 60,
                sleepScore: sleepData.first?.score,
                sleepWindowTitle: windowTitle,
                hydrationMl: waterMl,
                hydrationTargetMl: waterTarget,
                cyclePhase: cycle.settings.enabled ? cycle.snapshot.phase.rawValue : nil,
                cycleDay: cycle.settings.enabled ? cycle.snapshot.dayInCycle : nil,
                qol: LifestyleWidgetBridge.currentQOL(),
                topRecommendation: LifestyleWidgetBridge.currentRecommendation(),
                workoutName: todayWorkout?.name
            )
        )
    }

    func openChat(with prompt: String, voice: Bool = false, isProactive: Bool = false) {
        if quietMode, !voice, isProactive { return }
        ariaPendingChatPrompt = prompt
        ariaVoiceMode = voice
        activeTab = .chat
    }

    /// Deep-link into Home Cycle Health full-screen (optional Support pane).
    func openCycleHealth(pane: String? = nil, sharing: Bool = false) {
        pendingCyclePane = pane
        pendingCycleSharingOpen = sharing
        // Shell-level fullScreenCover hosts Cycle Health — no need to switch tabs.
        pendingCycleHealthOpen = true
    }

    func openHydration() {
        pendingHydrationOpen = true
    }

    func logGlassFromWidget() async {
        try? await HealthKitManager.shared.logWater(
            milliliters: HydrationEngine.glassMilliliters
        )
        await HealthKitManager.shared.refreshHydration()
        publishHomeWidgets()
    }

    /// Route a `forge://` URL. Returns false for anything unrecognised so the
    /// caller can leave the app where it was rather than guessing.
    @discardableResult
    func handleDeepLink(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "forge" else { return false }
        // forge://cycle/sharing  →  host "cycle", first path component "sharing"
        let segments = ([url.host] + url.pathComponents.filter { $0 != "/" })
            .compactMap { $0?.lowercased() }
        switch segments.first {
        case "cycle":
            let leaf = segments.dropFirst().first
            openCycleHealth(pane: leaf == "support" ? "partner" : "me",
                            sharing: leaf == "sharing")
            return true
        case "hydration", "water":
            if segments.dropFirst().first == "log" {
                Task { await logGlassFromWidget() }
            }
            openHydration()
            return true
        case "home":
            activeTab = .home
            return true
        case "sleep":
            activeTab = .sleep
            return true
        case "workout", "train":
            activeTab = .workout
            return true
        case "lifestyle":
            activeTab = .lifestyle
            return true
        case "aria":
            if segments.dropFirst().first == "weekly" {
                WeeklyAriaReviewStore.shared.showSheet = true
            } else {
                activeTab = .chat
            }
            return true
        default:
            return false
        }
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
        heightCm: Double? = nil,
        gender: Gender? = nil,
        biologicalSex: BiologicalSex? = nil,
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
        if let heightCm { userProfile.height = heightCm }
        if let gender { userProfile.gender = gender }
        if let biologicalSex {
            userProfile.biologicalSex = biologicalSex
            MenstrualHealthStore.shared.enableForBiologicalSexIfNeeded(biologicalSex)
        }
        if let interestTags { userProfile.interestTags = interestTags }
        if let trainingTheme {
            setTrainingTheme(trainingTheme, source: "profile")
            return
        }
        objectWillChange.send()
    }

    func connectHealthDevice(_ id: String) {
        var ids = HealthDeviceCatalog.migrateStoredIDs(userProfile.connectedDevices)
        if !ids.contains(id) { ids.append(id) }
        userProfile.connectedDevices = ids
    }

    func disconnectHealthDevice(_ id: String) {
        var ids = HealthDeviceCatalog.migrateStoredIDs(userProfile.connectedDevices)
        ids.removeAll { $0 == id }
        userProfile.connectedDevices = ids
    }

    /// Stores a new profile photo on disk and records its filename on the profile.
    /// Returns false when the image could not be written.
    @discardableResult
    func setProfilePhoto(_ image: UIImage) -> Bool {
        guard let fileName = ProfileAvatarStore.shared.save(
            image,
            replacing: userProfile.avatarFileName
        ) else { return false }
        userProfile.avatarFileName = fileName
        objectWillChange.send()
        return true
    }

    func removeProfilePhoto() {
        ProfileAvatarStore.shared.delete(userProfile.avatarFileName)
        userProfile.avatarFileName = nil
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
