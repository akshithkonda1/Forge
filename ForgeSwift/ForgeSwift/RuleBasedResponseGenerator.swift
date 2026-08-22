import Foundation
import ForgeCore
#if canImport(FoundationModels)
import FoundationModels
#endif

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
