import Foundation

/// On-device ARIA for previews, simulators and Device Hub.
/// Full local coach (plans, library muscles, specialists) with a companion
/// voice — testers get the same functionality as live ARIA, no cloud.
@MainActor
enum AriaDummyOrchestrator {

    static func reply(
        text: String,
        store: AppStore,
        agent: AriaCoachAgent
    ) async -> AriaResponse {
        let context = store.makeTrainerContext()
        let life = context.lifeRead
        let trimmedName = store.userProfile.name.split(separator: " ").first.map(String.init) ?? ""
        let you = trimmedName.isEmpty ? "" : "\(trimmedName) — "

        // 1) Identity — warm, same as production briefing, no source line.
        if AriaFirstHealthBriefing.isIdentityQuestion(text) {
            let body = AriaFirstHealthBriefing.identityBody()
            let msg = trimmedName.isEmpty
                ? "I'm ARIA.\n\n\(body)\n\nAsk me how you slept, what to train, or how to show up — I'll bring the right specialist."
                : "\(you)I'm ARIA.\n\n\(body)\n\nAsk me anything real and I'll meet you where you are."
            return AriaResponse(
                confidenceReason: "Grounded in your recent patterns",
                proseSummary: msg,
                message: msg,
                suggestedActions: AriaFirstHealthBriefing.suggestedActions,
                confidence: 0.88
            )
        }

        // 2) Emotional need first — always human before metric. This is the companion layer.
        if let reading = AriaEmotionalSupportCoach.detect(in: text, context: context),
           AriaEmotionalSupportCoach.isEmotionalSupportQuery(text, context: context) {
            let resp = AriaEmotionalSupportCoach.respond(reading: reading, context: context, input: text)
            // Strip any clinical disclaimer footers that feel institutional in dummy — keep warm core.
            return AriaResponse(
                confidenceReason: "Learning first",
                proseSummary: resp.content,
                message: resp.content,
                suggestedActions: resp.suggestedActions,
                confidence: resp.confidence
            )
        }

        // 3) Build facts without ever naming the source — numbers are just known.
        var facts = AriaSpeechFacts()
        if let night = store.sleepData.first {
            facts.sleepHours = night.totalHours
            facts.deepMinutes = night.deepMinutes
            facts.sleepAvg = Int(store.dailyMetrics.totalSleep > 0 ? Double(store.dailyMetrics.totalSleep) / 60.0 : night.totalHours)
            facts.sleepBand = night.score >= 80 ? .strong : (night.score < 55 ? .weak : .ok)
        } else if store.dailyMetrics.totalSleep > 0 {
            facts.sleepHours = Double(store.dailyMetrics.totalSleep) / 60.0
            facts.sleepBand = .unknown
        }

        let readiness = store.readiness.overall
        let intent = intentFor(agent: agent, text: text)

        // 4) Training plans + body-map muscle asks — same plan engine as live ARIA.
        if agent == .workout || AriaThemeResolver.isPlanRequest(text) || TargetMuscle.mentioned(in: text) != nil {
            let plan = AriaPlanEngine.evaluate(input: text, context: context)
            if plan.shouldPersistTheme {
                store.setTrainingTheme(plan.theme, source: "chat")
            }
            store.todayWorkout = plan.workoutPlan
            facts.sessionTitle = plan.workoutPlan.name
            facts.sessionDuration = plan.workoutPlan.duration
            facts.sessionIntensity = plan.workoutPlan.intensity.label
            facts.themeJustLocked = plan.shouldPersistTheme
            facts.themeLabel = plan.theme.label

            var voiceFacts = facts
            voiceFacts.sessionFlavor = plan.richCard.workoutName
            let voice = AriaVoiceEngine.speak(intent: .trainingPlan, context: context, input: text, facts: voiceFacts)

            let woven = weaveStory(voice.count > 40 ? voice : plan.narrative, life: life)
            return AriaResponse(
                confidenceReason: companionReason(readiness: readiness, hasSleep: facts.sleepHours != nil),
                proseSummary: woven,
                message: woven,
                richCard: AriaService.payload(from: plan.richCard),
                suggestedActions: plan.suggestedActions,
                confidence: 0.88
            )
        }

        // 5) Sleep / recovery keep the companion voice. Every other specialist
        // falls through to the full local coach so testers get real cycle,
        // lifestyle, progress, and archetype answers — not a one-liner.
        switch agent {
        case .recovery, .sleep:
            let raw = AriaVoiceEngine.speak(intent: .sleep, context: context, input: text, facts: facts)
            let prose = humanizeRecover(raw, you: you, facts: facts, readiness: readiness, coaching: context.userProfile.coachingStyle, life: life)
            return AriaResponse(
                confidenceReason: companionReason(readiness: readiness, hasSleep: facts.sleepHours != nil),
                proseSummary: prose,
                message: prose,
                suggestedActions: agent == .sleep
                    ? ["How did I sleep?", "Tell me about last night", "Keep it light"]
                    : ["How did I sleep?", "What should I train today?", "Keep it light today"],
                confidence: 0.84
            )
        case .lifestyle, .progress, .cycle, .aria, .workout:
            break
        }

        // 6) Full local coach — testers get the same rule-based specialists as
        // live ARIA (cycle, progress, archetypes, pain, nutrition). Voice stays
        // human: soften HUD leftovers and weave the pack story.
        if let local = try? await RuleBasedResponseGenerator().generateResponse(for: text, context: context) {
            if let card = local.richCard, card.type == .workoutPlan {
                let plan = AriaPlanEngine.evaluate(input: text, context: context)
                if plan.shouldPersistTheme {
                    store.setTrainingTheme(plan.theme, source: "chat")
                }
                store.todayWorkout = plan.workoutPlan
            }
            let prose = weaveStory(softenMetrics(local.content), life: life)
            return AriaResponse(
                confidenceReason: companionReason(readiness: readiness, hasSleep: facts.sleepHours != nil),
                proseSummary: prose,
                message: prose,
                richCard: local.richCard.flatMap(AriaService.payload(from:)),
                suggestedActions: local.suggestedActions ?? AriaFirstHealthBriefing.suggestedActions,
                confidence: local.confidence
            )
        }

        let generalProse: String = {
            if intent == .sleep {
                return AriaVoiceEngine.speak(intent: .sleep, context: context, input: text, facts: facts)
            }
            if intent == .lowEnergy {
                return AriaVoiceEngine.speak(intent: .lowEnergy, context: context, input: text, facts: facts)
            }
            if intent == .greeting || text.lowercased().contains("how are you") || text.count < 20 {
                return AriaVoiceEngine.speak(intent: .greeting, context: context, input: text, facts: facts)
            }
            let fallback = AriaVoiceEngine.speak(intent: intent, context: context, input: text, facts: facts)
            if fallback.trimmingCharacters(in: .whitespacesAndNewlines).count > 30 {
                return fallback
            }
            return humanFallback(you: you, readiness: readiness, facts: facts, coaching: context.userProfile.coachingStyle, life: life)
        }()

        return AriaResponse(
            confidenceReason: companionReason(readiness: readiness, hasSleep: facts.sleepHours != nil),
            proseSummary: generalProse,
            message: generalProse,
            suggestedActions: AriaFirstHealthBriefing.suggestedActions,
            confidence: 0.82
        )
    }

    // MARK: - Helpers

    private static func intentFor(agent: AriaCoachAgent, text: String) -> AriaSpeechIntent {
        let lower = text.lowercased()
        switch agent {
        case .recovery: return .sleep
        case .sleep: return .sleep
        case .workout: return .trainingPlan
        case .lifestyle: return .checkIn
        case .progress: return .progress
        case .cycle: return .checkIn
        case .aria:
            if lower.contains("sleep") || lower.contains("slept") || lower.contains("deep") { return .sleep }
            if lower.contains("sore") || lower.contains("pain") || lower.contains("hurt") { return .pain }
            if lower.contains("tired") || lower.contains("exhausted") || lower.contains("wiped") || lower.contains("drained") { return .lowEnergy }
            if lower.contains("progress") || lower.contains("trending") || lower.contains("pr ") { return .progress }
            if lower.contains("thank") { return .gratitude }
            if lower.contains("hype") || lower.contains("motivat") { return .motivation }
            if AriaThemeResolver.isPlanRequest(text) { return .trainingPlan }
            return .fallback
        }
    }

    private static func companionReason(readiness: Int, hasSleep: Bool) -> String {
        if readiness > 0 && hasSleep { return "Grounded in your sleep and readiness lately" }
        if readiness > 0 { return "Grounded in how ready you're feeling" }
        if hasSleep { return "Grounded in your recent sleep" }
        return "Grounded in your patterns"
    }

    // MARK: - Lane humanizers — strip DIE metric tables into companion speech

    private static func humanizeRecover(_ raw: String, you: String, facts: AriaSpeechFacts, readiness: Int, coaching: CoachingStyle, life: AriaLifeRead) -> String {
        // If voice engine already sounds human (contains "I hear" or contraction + empathy), keep it.
        let lower = raw.lowercased()
        let alreadyHuman = lower.contains("i hear") || lower.contains("makes sense") || lower.contains("of course")
        if alreadyHuman && raw.count > 40 { return weaveStory(softenMetrics(raw), life: life) }

        let name = you.replacingOccurrences(of: " — ", with: "").trimmingCharacters(in: .whitespaces)
        var rng = AriaSeededRNG(seed: UInt64(abs((name + "\(readiness)" + (life.story ?? "")).hashValue)))
        let weak = facts.sleepBand == .weak || life.felt == "thin" || life.felt == "spent" || life.lastNightLate
        let opener = name.isEmpty ? "" : rng.pick(["Hey \(name) — ", "\(name), ", "Hey \(name), "])
        let plot = life.spokenLine(rng: &rng)
        let empathy = plot ?? (weak
            ? rng.pick(["Last night was on the short side —", "Sleep was thin last night —", "The rebuild didn't quite land —"])
            : rng.pick(["You actually got to rebuild last night —", "Last night gave you something to work with —", "Sleep did its job —"]))
        let body = weak
            ? rng.pick([
                "so if today feels a little heavier, that makes sense. Let's not chase a hero day.",
                "so your body didn't get its full reset. Let's keep today kind.",
                "so no wonder energy feels a bit low. We'll protect tomorrow instead.",
              ])
            : rng.pick([
                "let's use it well, not waste it.",
                "good ground to do something that counts.",
                "we've got something to build on.",
              ])
        let invite = readiness < 55
            ? rng.pick(["Want a gentle reset or just a check-in? Your call.", "Want breathing + light movement, or just rest?"])
            : rng.pick(["Want a light, honest session or full rest? You choose.", "Want me to map something light, or keep it to a walk?"])
        return "\(opener)\(empathy) \(body) \(invite)".replacingOccurrences(of: "  ", with: " ")
    }

    private static func softenMetrics(_ s: String) -> String {
        var out = s
        // Drop the clinical HUD sentence if the voice engine still emitted one.
        if let range = out.range(of: #"Readiness \d+/100 · HRV \d+ ms · RHR \d+ bpm[^.]*\."#, options: .regularExpression) {
            out.replaceSubrange(range, with: "I already looked — here's the read.")
        }
        out = out.replacingOccurrences(
            of: #"Readiness \d+, HRV \d+, resting heart \d+\."#,
            with: "",
            options: .regularExpression
        )
        return out
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func weaveStory(_ raw: String, life: AriaLifeRead) -> String {
        guard let story = life.story, !story.isEmpty else { return raw }
        if raw.localizedCaseInsensitiveContains(story) { return raw }
        return "\(story) \(raw)"
    }

    private static func humanFallback(you: String, readiness: Int, facts: AriaSpeechFacts, coaching: CoachingStyle, life: AriaLifeRead) -> String {
        let name = you.replacingOccurrences(of: " — ", with: "").trimmingCharacters(in: .whitespaces)
        var rng = AriaSeededRNG(seed: UInt64(abs((name + "\(readiness)" + "\(facts.sleepHours ?? 0)" + (life.story ?? "")).hashValue)))

        // Sleep — spoken like a friend who noticed, not a sensor
        let cite = coaching == .dataDriven
        let sleepBit: String = {
            if let plot = life.spokenLine(rng: &rng) { return plot }
            guard facts.sleepHours != nil else { return "" }
            switch facts.sleepBand {
            case .weak:
                return rng.pick([
                    "Last night was on the short side — if today feels heavy, that tracks.",
                    "Sleep came up short, so your body didn't get its full reset.",
                    "The rebuild didn't quite land. Makes sense you're feeling it.",
                ])
            case .strong:
                return rng.pick([
                    "You actually got a night you can spend — that's real fuel.",
                    "Last night did its job. Nice — that's your rebuild.",
                    "You earned that sleep. Let's not waste it.",
                ])
            case .ok:
                return rng.pick([
                    "Sleep was decent — not perfect, not empty. We'll work with it.",
                    "Last night was middle-ground. Enough to build on if we're smart.",
                    "Nothing broken, nothing extra to spend. That's still a day.",
                ])
            case .unknown:
                return rng.pick([
                    "Last night is in — we'll roll with it.",
                    "We've got enough of a night to make today count.",
                ])
            }
        }()

        let readinessBit: String = {
            switch readiness {
            case 0:
                return rng.pick([
                    "I'm here. Let's just pick one small, kind next step together.",
                    "No pressure to have it figured out — one gentle move is enough.",
                ])
            case 1..<50:
                return cite
                    ? rng.pick([
                        "Around \(readiness) today — that's your body asking for care, not a lecture. We protect tomorrow.",
                        "Low tank today. Of course everything feels heavier — let's not add weight.",
                    ])
                    : rng.pick([
                        "You're running on fumes — not failing. Let's keep today soft.",
                        "Low tank today. Of course everything feels heavier — let's not add weight.",
                    ])
            case 50..<60:
                return rng.pick([
                    "Tender middle — you could push, but you shouldn't have to.",
                    "Not your strongest day, not your emptiest. Perfect for something light and honest.",
                ])
            case 60..<75:
                return rng.pick([
                    "Steady, workable ground. One honest effort will count.",
                    "You've got enough to move, not enough to burn. That's actually a sweet spot.",
                ])
            case 75..<85:
                return rng.pick([
                    "You've got good energy to use. Not to waste, to use.",
                    "Body's willing today — let's give it something worth doing.",
                ])
            case 85...:
                return rng.pick([
                    "You're lit today. Big window, but we still go clean, not reckless.",
                    "Rare air — let's spend it on something that matters.",
                ])
            default:
                return rng.pick(["Steady ground today. One good choice is enough.", "We're good — one next move, together."])
            }
        }()

        let invite: String = {
            switch coaching {
            case .pushHard:
                return rng.pick([
                    "Want the sharp version or the scaled one? Your call.",
                    "I can write you the hard block or the smart pull-back — which serves you right now?",
                ])
            case .patient:
                return rng.pick([
                    "Want something light, or do you just need to be heard for a minute?",
                    "We can move a little or just talk — what would feel kinder?",
                ])
            case .dataDriven:
                return rng.pick([
                    "Want the why behind it, or just the next move?",
                    "I can show the reasoning or keep it simple — you choose.",
                ])
            case .ultraElite:
                return rng.pick([
                    "You want precision or just the play?",
                    "Clean execution today — want the full plan laid out?",
                ])
            default:
                return rng.pick([
                    "What would help most — train, recover, or just talk it through?",
                    "Your call — we can train, reset, or just check in. What feels right?",
                    "Want me to map something, or just sit with what's here?",
                ])
            }
        }()

        // Warm opener — like a companion who remembers you, not a system booting
        let opener: String = {
            if !name.isEmpty {
                return rng.pick([
                    "Hey \(name) —",
                    "\(name),",
                    "Hey \(name),",
                ])
            }
            return rng.pick(["Hey —", "Hey,", ""])
        }()

        let body = [sleepBit, readinessBit].filter { !$0.isEmpty }.joined(separator: " ")
        if opener.isEmpty { return "\(body) \(invite)" }
        return "\(opener) \(body) \(invite)".replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
    }
}
