import Foundation

/// On-device ARIA for previews, simulators and Device Hub.
/// Sounds like a companion, not a data dump — the user never needs to know
/// where a number came from. No HealthKit / simulator / "Test-Ready" / cloud mentions.
@MainActor
enum AriaDummyOrchestrator {

    static func reply(
        text: String,
        store: AppStore,
        agent: AriaCoachAgent
    ) -> AriaResponse {
        let context = store.makeTrainerContext()
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
                confidenceReason: "Listening first",
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

        // 4) Training plans — use the real plan engine, but voice it like a companion.
        if agent == .workout || AriaThemeResolver.isPlanRequest(text) {
            let plan = AriaPlanEngine.evaluate(input: text, context: context)
            // Keep the workout for the UI, but don't announce it as a system artifact.
            store.todayWorkout = plan.workoutPlan
            facts.sessionTitle = plan.workoutPlan.name
            facts.sessionDuration = plan.workoutPlan.duration
            facts.sessionIntensity = plan.workoutPlan.intensity.label
            facts.themeJustLocked = plan.shouldPersistTheme
            facts.themeLabel = plan.theme.label

            // Let the voice engine wrap the plan fact in human speech (seeded, style-aware).
            var voiceFacts = facts
            voiceFacts.sessionFlavor = plan.richCard.workoutName
            let voice = AriaVoiceEngine.speak(intent: .trainingPlan, context: context, input: text, facts: voiceFacts)

            // Prefer voice when it feels human; fall back to plan narrative without source notes.
            let prose = voice.count > 40 ? voice : plan.narrative
            return AriaResponse(
                confidenceReason: companionReason(readiness: readiness, hasSleep: facts.sleepHours != nil),
                proseSummary: prose,
                message: prose,
                suggestedActions: plan.suggestedActions,
                confidence: 0.88
            )
        }

        // 5) Warm, human-first per lane — maps to current AriaCoachAgent cases.
        switch agent {
        case .recovery:
            let raw = AriaVoiceEngine.speak(intent: .sleep, context: context, input: text, facts: facts)
            let prose = humanizeRecover(raw, you: you, facts: facts, readiness: readiness, coaching: context.userProfile.coachingStyle)
            return AriaResponse(
                confidenceReason: companionReason(readiness: readiness, hasSleep: facts.sleepHours != nil),
                proseSummary: prose,
                message: prose,
                suggestedActions: ["How did I sleep?", "What should I train today?", "Keep it light today"],
                confidence: 0.84
            )
        case .sleep:
            let raw = AriaVoiceEngine.speak(intent: .sleep, context: context, input: text, facts: facts)
            let prose = humanizeRecover(raw, you: you, facts: facts, readiness: readiness, coaching: context.userProfile.coachingStyle)
            return AriaResponse(
                confidenceReason: companionReason(readiness: readiness, hasSleep: facts.sleepHours != nil),
                proseSummary: prose,
                message: prose,
                suggestedActions: ["How did I sleep?", "Tell me about last night", "Keep it light"],
                confidence: 0.84
            )
        case .lifestyle:
            // Lifestyle covers fuel + life — keep it warm and practical, not a diet plan.
            let raw = AriaVoiceEngine.speak(intent: .checkIn, context: context, input: text, facts: facts)
            // If the question is explicitly about food, use fuel humanizer; otherwise life.
            let lower = text.lowercased()
            let isFood = lower.contains("eat") || lower.contains("food") || lower.contains("protein") || lower.contains("meal") || lower.contains("water") || lower.contains("hydrat")
            let prose = isFood ? humanizeFuel(raw, you: you) : humanizeLife(raw, you: you)
            return AriaResponse(
                confidenceReason: isFood ? "Grounded in your recent patterns" : "Fitting training into the life you already have",
                proseSummary: prose,
                message: prose,
                suggestedActions: isFood ? ["What should I eat next?", "How's my recovery?", "Make it simple"] : ["Fit this into today", "What should I train?", "Keep it light"],
                confidence: 0.84
            )
        case .progress:
            let raw = AriaVoiceEngine.speak(intent: .progress, context: context, input: text, facts: facts)
            return AriaResponse(
                confidenceReason: "Grounded in your trends",
                proseSummary: raw,
                message: raw,
                suggestedActions: ["Show my trends", "Any new PRs?", "What should I train?"],
                confidence: 0.82
            )
        case .cycle:
            let raw = AriaVoiceEngine.speak(intent: .checkIn, context: context, input: text, facts: facts)
            let prose = humanizeCycle(raw, you: you)
            return AriaResponse(
                confidenceReason: "Private coaching — only what you shared",
                proseSummary: prose,
                message: prose,
                suggestedActions: ["How to show up today?", "What helps for recovery?", "Keep it simple"],
                confidence: 0.82
            )
        case .aria, .workout:
            break
        }

        // 6) General ARIA — companion-first check-in grounded in readiness + sleep, no source.
        let generalProse: String = {
            // Use the voice engine's greeting/briefing beats — they already vary by coaching style, hour, relationship.
            if intent == .sleep {
                return AriaVoiceEngine.speak(intent: .sleep, context: context, input: text, facts: facts)
            }
            if intent == .lowEnergy {
                return AriaVoiceEngine.speak(intent: .lowEnergy, context: context, input: text, facts: facts)
            }
            if intent == .greeting || text.lowercased().contains("how are you") || text.count < 20 {
                return AriaVoiceEngine.speak(intent: .greeting, context: context, input: text, facts: facts)
            }
            // Default: warm, grounded check-in — not a metric table.
            let fallback = AriaVoiceEngine.speak(intent: intent, context: context, input: text, facts: facts)
            if fallback.trimmingCharacters(in: .whitespacesAndNewlines).count > 30 {
                return fallback
            }
            // Last-resort human line — still no source, one metric at most, plus choice.
            return humanFallback(you: you, readiness: readiness, facts: facts, coaching: context.userProfile.coachingStyle)
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

    private static func humanizeRecover(_ raw: String, you: String, facts: AriaSpeechFacts, readiness: Int, coaching: CoachingStyle) -> String {
        // If voice engine already sounds human (contains "I hear" or contraction + empathy), keep it.
        let lower = raw.lowercased()
        let alreadyHuman = lower.contains("i hear") || lower.contains("makes sense") || lower.contains("of course")
        if alreadyHuman && raw.count > 40 { return softenMetrics(raw) }

        let name = you.replacingOccurrences(of: " — ", with: "").trimmingCharacters(in: .whitespaces)
        var rng = AriaSeededRNG(seed: UInt64(abs((name + "\(readiness)").hashValue)))
        let sleep = facts.sleepHours.map { String(format: "%.1f", $0) } ?? ""
        let weak = facts.sleepBand == .weak
        let opener = name.isEmpty ? "" : rng.pick(["Hey \(name) — ", "\(name), ", "Hey \(name), "])
        let empathy = weak
            ? rng.pick(["I see last night was light on deep sleep —", "Last night was on the short side —", "Sleep was thin last night —"])
            : rng.pick(["You got some solid sleep —", "Nice — you actually got to rebuild last night —", "Last night gave you something to work with —"])
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
        let sleepPart = sleep.isEmpty ? "" : "\(sleep)h. "
        return "\(opener)\(empathy) \(sleepPart)\(body) \(invite)".replacingOccurrences(of: "  ", with: " ")
    }

    private static func humanizeFuel(_ raw: String, you: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("protein") && lower.contains("water") && lower.contains("not a diet") { return raw }
        let name = you.replacingOccurrences(of: " — ", with: "").trimmingCharacters(in: .whitespaces)
        var rng = AriaSeededRNG(seed: UInt64(abs(name.hashValue &+ 7)))
        let opener = name.isEmpty ? "" : rng.pick(["\(name) — ", "Hey \(name) — "])
        return "\(opener)\(rng.pick(["For fuel — just protein and water with your next meal is enough.", "Next meal: protein, water, something you actually like. That's it.", "No diet math. Just eat enough to support the work, then move on."])) \(rng.pick(["Not a diet, just care.", "Simple beats perfect here.", "Keep it kind, not precise."]))"
    }

    private static func humanizeLife(_ raw: String, you: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("life you already have") || lower.contains("fit training into") { return softenMetrics(raw) }
        let name = you.replacingOccurrences(of: " — ", with: "").trimmingCharacters(in: .whitespaces)
        var rng = AriaSeededRNG(seed: UInt64(abs(name.hashValue &+ 13)))
        let opener = name.isEmpty ? "" : "\(name) — "
        return "\(opener)\(rng.pick(["Training should fit your day, not replace it.", "We build inside the life you already have — work, people, rest.", "Your day comes first. Training just finds its corner."])) \(rng.pick(["What does today actually allow?", "Want me to shape something around what you've got?", "Tell me the window and I'll make it count."]))"
    }

    private static func humanizeCycle(_ raw: String, you: String) -> String {
        if !raw.isEmpty && !raw.lowercased().contains("no chart") { return softenMetrics(raw) }
        let name = you.replacingOccurrences(of: " — ", with: "").trimmingCharacters(in: .whitespaces)
        var rng = AriaSeededRNG(seed: UInt64(abs(name.hashValue &+ 21)))
        let opener = name.isEmpty ? "" : "\(name) — "
        return "\(opener)\(rng.pick(["Cycle support stays private here — just training, recovery, or how to show up as a human.", "This stays between you and who you support — no chart, no diagnosis, just care.", "Private by design. How you show up matters more than any calendar."])) \(rng.pick(["What would feel most helpful right now?", "Want a soft way to check in, or a plan that respects today?", "Tell me what they need and I'll keep it human."]))"
    }

    private static func softenMetrics(_ s: String) -> String {
        // Replace DIE-like "Readiness 72/100 · HRV 52 ms · RHR 58 bpm — band: ..." with human.
        var out = s
        out = out.replacingOccurrences(of: "Readiness ", with: "readiness ")
        // Collapse metric dumps that start a sentence — keep the empathy, not the table.
        if out.contains("HRV") && out.contains("RHR") && out.contains("Readiness") {
            // Move metric to a gentle parenthetical or drop it — human first.
            out = out.replacingOccurrences(of: " — band:", with: " —")
        }
        // Remove markdown bold that feels system-y in dummy if it dominates
        // Keep it for session titles only — voice's "**Title**" is fine.
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func humanFallback(you: String, readiness: Int, facts: AriaSpeechFacts, coaching: CoachingStyle) -> String {
        let name = you.replacingOccurrences(of: " — ", with: "").trimmingCharacters(in: .whitespaces)
        var rng = AriaSeededRNG(seed: UInt64(abs((name + "\(readiness)" + "\(facts.sleepHours ?? 0)").hashValue)))

        // Sleep — spoken like a friend who noticed, not a sensor
        let sleepBit: String = {
            guard let h = facts.sleepHours else { return "" }
            let hrs = String(format: "%.1f", h)
            switch facts.sleepBand {
            case .weak:
                return rng.pick([
                    "Last night was just \(hrs)h — and deep sleep was light, so if today feels heavy, that tracks.",
                    "You got about \(hrs) hours — deep sleep came up short, so your body didn't get its full reset.",
                    "\(hrs)h last night, but not much of that deep, restorative kind. Makes sense you're feeling it.",
                ])
            case .strong:
                return rng.pick([
                    "You got a solid \(hrs)h last night — that's real fuel.",
                    "\(hrs)h and you actually caught some deep sleep. Nice — that's your rebuild.",
                    "Last night was \(hrs)h of good sleep. You earned that.",
                ])
            case .ok:
                return rng.pick([
                    "Slept about \(hrs)h — not perfect, not empty. We'll work with it.",
                    "\(hrs)h last night — decent. Enough to build on if we're smart about today.",
                    "About \(hrs) hours. Middle ground — nothing broken, nothing extra to spend.",
                ])
            case .unknown:
                return rng.pick([
                    "About \(hrs)h last night — we'll roll with it.",
                    "Roughly \(hrs)h. Good enough to make today count.",
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
                return rng.pick([
                    "That \(readiness) I'm seeing? It just means you're running on fumes — not that you're failing. Let's keep today soft.",
                    "Around \(readiness) today — yeah, that's your body asking for care, not a lecture. We protect tomorrow.",
                    "Low tank today. Of course everything feels heavier — let's not add weight.",
                ])
            case 50..<60:
                return rng.pick([
                    "Sitting around \(readiness) — in that tender middle where you could push, but you shouldn't have to.",
                    "About \(readiness). Not your strongest day, not your emptiest. Perfect for something light and honest.",
                ])
            case 60..<75:
                return rng.pick([
                    "Around \(readiness) — steady, workable ground. One honest effort will count.",
                    "Mid-\(readiness)s — you've got enough to move, not enough to burn. That's actually a sweet spot.",
                ])
            case 75..<85:
                return rng.pick([
                    "High \(readiness)s — you've got good energy to use. Not to waste, to use.",
                    "Around \(readiness). Body's willing today — let's give it something worth doing.",
                ])
            case 85...:
                return rng.pick([
                    "\(readiness) — you're lit today. Big window, but we still go clean, not reckless.",
                    "High \(readiness)s. Rare air — let's spend it on something that matters.",
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
