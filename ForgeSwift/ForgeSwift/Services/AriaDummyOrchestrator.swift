import Foundation
import ForgeCore

/// On-device fill-in for ARIA while the live backend is still incomplete.
///
/// Device Hub / tester builds must feel like a connected backend so we can
/// tune day-to-day coaching (multi-causal turns, events, follow-ups) before
/// the real API lands. After that, this path is what performance and
/// day-in-the-life tests compare against.
///
/// Local compute only: rule conductor + seeded voice banks, and Apple
/// Intelligence when the phone has it. Never URLSession, never Bedrock,
/// never an off-device LLM.
@MainActor
enum AriaDummyOrchestrator {

    static let usesOffDeviceLLM = AriaDummyTurn.usesOffDeviceLLM
    static let writesCalendarEvents = AriaDummyTurn.writesCalendarEvents

    /// Last side effects applied — tests inspect this instead of EventKit.
    static var lastAppliedActions: [AriaDummyAction] = []

    static func reply(
        text: String,
        store: AppStore,
        agent: AriaCoachAgent,
        agents: [String]? = nil
    ) async -> AriaResponse {
        lastAppliedActions = []
        let context = store.makeTrainerContext()
        let life = context.lifeRead
        let trimmedName = store.userProfile.name.split(separator: " ").first.map(String.init) ?? ""
        let you = trimmedName.isEmpty ? "" : "\(trimmedName) — "
        let facts = speechFacts(from: store)
        let readiness = store.readiness.overall

        let guidance = AriaGuidancePolicy.decide(text: text)
        if guidance.band == .referOut, let line = guidance.line {
            return AriaResponse(
                confidenceReason: "Local fill-in — outside coaching scope, referred out.",
                proseSummary: line,
                message: line,
                suggestedActions: nil,
                confidence: 1.0
            )
        }

        let routed = (agents ?? []).compactMap { AriaCoachAgent(rawValue: $0) }
        let identityOnly = AriaFirstHealthBriefing.isIdentityQuestion(text)
            && AriaDummyTurn.clauses(in: text).count <= 1
            && !AriaThemeResolver.isPlanRequest(text)
        if identityOnly {
            let body = AriaFirstHealthBriefing.identityBody()
            let msg = trimmedName.isEmpty
                ? "I'm ARIA.\n\n\(body)\n\nAsk me how you slept, what to train, or how to show up — I'll bring the right specialist."
                : "\(you)I'm ARIA.\n\n\(body)\n\nAsk me anything real and I'll meet you where you are."
            return AriaResponse(
                confidenceReason: "Local fill-in — identity",
                proseSummary: msg,
                message: msg,
                suggestedActions: AriaFirstHealthBriefing.suggestedActions,
                confidence: 0.88
            )
        }

        let follow = AriaDummyTurn.followUp(in: text)
        if follow != .none, let followed = handleFollowUp(
            follow,
            text: text,
            store: store,
            context: context,
            facts: facts,
            name: trimmedName
        ) {
            return followed
        }

        let sleepWeak = facts.sleepBand == .weak
            || (facts.sleepHours ?? 9) < 6.5
            || text.lowercased().contains("slept badly")
            || text.lowercased().contains("slept 5")
        let interpretation = AriaDummyTurn.interpret(
            text: text,
            agent: agent,
            agents: routed,
            signals: store.intentSignals(for: text),
            sleepWeak: sleepWeak,
            readinessLow: readiness > 0 && readiness < 55
        )

        let emotional = AriaEmotionalSupportCoach.isEmotionalSupportQuery(text, context: context)
        let hasSystems = interpretation.domains.contains(where: {
            $0 == .training || $0 == .nutrition || $0 == .sleep || $0 == .cycle
        })
        if emotional, !hasSystems,
           let reading = AriaEmotionalSupportCoach.detect(in: text, context: context) {
            let resp = AriaEmotionalSupportCoach.respond(reading: reading, context: context, input: text)
            return AriaResponse(
                confidenceReason: "Local fill-in — companion",
                proseSummary: resp.content,
                message: resp.content,
                suggestedActions: resp.suggestedActions,
                confidence: resp.confidence
            )
        }

        var beats: [AriaDummyBeat] = []
        for domain in interpretation.domains {
            if let beat = await worker(
                domain: domain,
                text: text,
                interpretation: interpretation,
                store: store,
                context: context,
                facts: facts,
                you: you,
                life: life
            ) {
                beats.append(beat)
            }
        }

        if beats.isEmpty {
            let intent = intentFor(agent: interpretation.primaryAgent, text: text)
            let fallback = AriaVoiceEngine.speak(intent: intent, context: context, input: text, facts: facts)
            let prose = fallback.count > 30
                ? fallback
                : humanFallback(you: you, readiness: readiness, facts: facts, coaching: context.userProfile.coachingStyle, life: life)
            return AriaResponse(
                confidenceReason: reason(for: interpretation, readiness: readiness, hasSleep: facts.sleepHours != nil),
                proseSummary: prose,
                message: prose,
                suggestedActions: AriaFirstHealthBriefing.suggestedActions,
                contextUpdates: ["relationship_level": min(10, 1 + store.chatMessages.count / 3)],
                confidence: 0.82
            )
        }

        var actions = beats.flatMap(\.actions)
        if let reminder = interpretation.reminder { actions.append(reminder) }
        for joint in interpretation.joints {
            actions.append(.rememberFact("Injury context: \(joint)"))
        }
        apply(actions, store: store)
        lastAppliedActions = actions

        let seed = UInt64(truncatingIfNeeded: text.utf8.reduce(0) { ($0 &* 33) &+ UInt64($1) })
            &+ UInt64(store.chatMessages.count)
        let skeleton = AriaDummyTurn.compose(
            beats: beats,
            interpretation: interpretation,
            name: trimmedName,
            seed: seed
        )
        let required = requiredTokens(from: interpretation, beats: beats)
        let woven = weaveStory(softenMetrics(skeleton), life: life)
        let message = await polishIfOnDevice(skeleton: woven, context: context, required: required)

        let card = beats.compactMap(\.card).first
        var suggestions = beats.flatMap(\.suggestedActions)
        if suggestions.isEmpty { suggestions = AriaFirstHealthBriefing.suggestedActions }
        if suggestions.count > 4 { suggestions = Array(suggestions.prefix(4)) }

        return AriaResponse(
            confidenceReason: reason(for: interpretation, readiness: readiness, hasSleep: facts.sleepHours != nil),
            proseSummary: message,
            message: message,
            richCard: card,
            suggestedActions: suggestions,
            contextUpdates: ["relationship_level": min(10, 1 + store.chatMessages.count / 3)],
            confidence: 0.88
        )
    }

    // MARK: - Workers

    private static func worker(
        domain: AriaIntentDomain,
        text: String,
        interpretation: AriaDummyInterpretation,
        store: AppStore,
        context: TrainerContext,
        facts: AriaSpeechFacts,
        you: String,
        life: AriaLifeRead
    ) async -> AriaDummyBeat? {
        switch domain {
        case .sleep, .readiness:
            let raw = AriaVoiceEngine.speak(
                intent: domain == .readiness ? .lowEnergy : .sleep,
                context: context,
                input: text,
                facts: facts
            )
            let prose = humanizeRecover(
                raw,
                you: you,
                facts: facts,
                readiness: store.readiness.overall,
                coaching: context.userProfile.coachingStyle,
                life: life
            )
            return AriaDummyBeat(
                domain: domain,
                prose: prose,
                suggestedActions: ["How did I sleep?", "Keep it light today"]
            )
        case .training:
            let plan = AriaPlanEngine.evaluate(input: interpretation.constrainedPlanInput, context: context)
            let workout = constrain(plan.workoutPlan, interpretation: interpretation)
            if plan.shouldPersistTheme {
                store.setTrainingTheme(plan.theme, source: "chat")
            }
            store.todayWorkout = workout
            var voiceFacts = facts
            voiceFacts.sessionTitle = workout.name
            voiceFacts.sessionDuration = workout.duration
            voiceFacts.sessionIntensity = workout.intensity.label
            let voice = AriaVoiceEngine.speak(intent: .trainingPlan, context: context, input: text, facts: voiceFacts)
            let line = "\(workout.name) is on the board for about \(workout.duration) minutes — \(workout.intensity.label.lowercased()) intensity."
            let prose = voice.count > 60 ? voice : line
            var actions: [AriaDummyAction] = [.persistWorkout]
            if plan.shouldPersistTheme { actions.append(.persistTheme) }
            return AriaDummyBeat(
                domain: .training,
                prose: prose,
                card: AriaService.payload(from: plan.richCard),
                suggestedActions: plan.suggestedActions,
                actions: actions
            )
        case .nutrition, .lifestyle:
            if let reminder = interpretation.reminder,
               case .scheduleReminder(let kind, let hour) = reminder {
                let clock = clockLabel(hour ?? (kind == .sleep ? 21 : 13))
                let target: String
                switch kind {
                case .hydration: target = "water"
                case .meal: target = "food"
                case .sleep: target = "wind-down"
                case .workout: target = "the session"
                }
                return AriaDummyBeat(
                    domain: .nutrition,
                    prose: "I'll nudge you \(clock) about \(target) so you actually eat.",
                    suggestedActions: ["What should I eat?", "Remind me later"],
                    actions: [reminder]
                )
            }
            if text.lowercased().contains("eat") || text.lowercased().contains("food")
                || text.lowercased().contains("protein") || text.lowercased().contains("meal")
                || domain == .nutrition {
                return AriaDummyBeat(
                    domain: .nutrition,
                    prose: "Keep food simple — protein and something you will actually eat.",
                    suggestedActions: ["What should I eat?", "Protein ideas"]
                )
            }
            if domain == .lifestyle,
               let local = try? await RuleBasedResponseGenerator().generateResponse(for: text, context: context) {
                return AriaDummyBeat(
                    domain: .lifestyle,
                    prose: softenMetrics(local.content),
                    card: local.richCard.flatMap(AriaService.payload(from:)),
                    suggestedActions: local.suggestedActions ?? []
                )
            }
            return nil
        case .body:
            let joint = interpretation.joints.first ?? "that joint"
            return AriaDummyBeat(
                domain: .body,
                prose: "I'll keep load off the \(joint).",
                suggestedActions: ["Work around it", "Keep it light"],
                actions: [.rememberFact("Injury context: \(joint)")]
            )
        case .cycle:
            guard let note = AriaCycleTools.run(text: text) else { return nil }
            return AriaDummyBeat(domain: .cycle, prose: note)
        case .progress:
            let raw = AriaVoiceEngine.speak(intent: .progress, context: context, input: text, facts: facts)
            return AriaDummyBeat(
                domain: .progress,
                prose: softenMetrics(raw),
                suggestedActions: ["How am I progressing?"]
            )
        }
    }

    private static func handleFollowUp(
        _ follow: AriaDummyFollowUp,
        text: String,
        store: AppStore,
        context: TrainerContext,
        facts: AriaSpeechFacts,
        name: String
    ) -> AriaResponse? {
        switch follow {
        case .none:
            return nil
        case .accept:
            guard let workout = store.todayWorkout else { return nil }
            lastAppliedActions = [.persistWorkout]
            return confirm("Locked. \(workout.name) stays on the board.", store: store, card: workoutCard(workout))
        case .decline:
            store.todayWorkout = nil
            lastAppliedActions = [.cancelWorkout]
            return confirm("Scratched. Nothing on the board until you want it.", store: store, card: nil)
        case .easier:
            guard var workout = store.todayWorkout else { return nil }
            workout.intensity = AriaDummyTurn.stepDown(workout.intensity)
            store.todayWorkout = workout
            lastAppliedActions = [.scaleEasier]
            return confirm(
                "Scaled it. \(workout.name) is now \(workout.intensity.label.lowercased()), about \(workout.duration) minutes.",
                store: store,
                card: workoutCard(workout)
            )
        case .shorter:
            guard var workout = store.todayWorkout else { return nil }
            workout.duration = max(15, Int(Double(workout.duration) * 0.7))
            store.todayWorkout = workout
            lastAppliedActions = [.scaleShorter]
            return confirm(
                "Cut it down. \(workout.name) is about \(workout.duration) minutes now.",
                store: store,
                card: workoutCard(workout)
            )
        case .lessLegs:
            guard store.todayWorkout != nil else { return nil }
            let interpretation = AriaDummyTurn.interpret(
                text: "\(text) skip legs",
                agent: .workout,
                agents: [.workout],
                signals: store.intentSignals(for: text),
                sleepWeak: facts.sleepBand == .weak,
                readinessLow: store.readiness.overall > 0 && store.readiness.overall < 55
            )
            let plan = AriaPlanEngine.evaluate(input: interpretation.constrainedPlanInput, context: context)
            let workout = constrain(plan.workoutPlan, interpretation: interpretation)
            store.todayWorkout = workout
            lastAppliedActions = [.skipLegs, .persistWorkout]
            return confirm("Legs off. \(workout.name) is on the board instead.", store: store, card: AriaService.payload(from: plan.richCard))
        case .askSleep:
            let raw = AriaVoiceEngine.speak(intent: .sleep, context: context, input: text, facts: facts)
            let sleep = humanizeRecover(
                raw,
                you: name.isEmpty ? "" : "\(name) — ",
                facts: facts,
                readiness: store.readiness.overall,
                coaching: context.userProfile.coachingStyle,
                life: context.lifeRead
            )
            if let workout = store.todayWorkout {
                return confirm(
                    "\(sleep) \(workout.name) can stay — we already built it around the night.",
                    store: store,
                    card: workoutCard(workout)
                )
            }
            return confirm(sleep, store: store, card: nil)
        }
    }

    private static func constrain(
        _ workout: WorkoutPlan,
        interpretation: AriaDummyInterpretation
    ) -> WorkoutPlan {
        var next = workout
        if interpretation.keepLight {
            if next.intensity == .max || next.intensity == .high {
                next.intensity = .moderate
            }
        }
        if interpretation.skipLegs {
            let kept = next.exercises.filter { !AriaDummyTurn.isLegMove($0.name) }
            if kept.count >= 2 { next.exercises = kept }
            if !next.name.lowercased().contains("upper") && !next.name.lowercased().contains("pull") {
                next.name = "Upper " + next.name
            }
        }
        return next
    }

    private static func apply(_ actions: [AriaDummyAction], store: AppStore) {
        for action in actions {
            switch action {
            case .persistWorkout, .persistTheme, .scaleEasier, .scaleShorter, .cancelWorkout, .skipLegs:
                break
            case .rememberFact(let fact):
                store.rememberDurable(fact)
            case .scheduleReminder(let kind, let hour):
                var comps = DateComponents()
                comps.hour = hour ?? (kind == .sleep ? 21 : 13)
                comps.minute = 0
                let reminder = SmartReminder(
                    id: "aria.dummy.\(kind.rawValue)",
                    type: AriaDummyTurn.reminderType(for: kind),
                    time: comps,
                    enabled: true
                )
                SmartNotificationManager.shared.scheduledReminders.removeAll { $0.id == reminder.id }
                SmartNotificationManager.shared.scheduledReminders.append(reminder)
            }
        }
    }

    private static func speechFacts(from store: AppStore) -> AriaSpeechFacts {
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
        return facts
    }

    private static func reason(
        for interpretation: AriaDummyInterpretation,
        readiness: Int,
        hasSleep: Bool
    ) -> String {
        let names = interpretation.domains.map(\.rawValue).joined(separator: " + ")
        let grounding = companionReason(readiness: readiness, hasSleep: hasSleep)
        if names.isEmpty { return "Local fill-in — \(grounding)" }
        return "Local fill-in — \(names) · on-device · \(grounding)"
    }

    private static func requiredTokens(
        from interpretation: AriaDummyInterpretation,
        beats _: [AriaDummyBeat]
    ) -> [String] {
        var tokens: [String] = []
        if interpretation.domains.contains(.sleep) { tokens.append("sleep") }
        if interpretation.domains.contains(.training) { tokens.append("minute") }
        if interpretation.domains.contains(.nutrition) { tokens.append("eat") }
        if interpretation.skipLegs { tokens.append("leg") }
        return tokens
    }

    private static func polishIfOnDevice(
        skeleton: String,
        context: TrainerContext,
        required: [String]
    ) async -> String {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return skeleton }
        let gen = FoundationModelsResponseGenerator()
        guard gen.isAvailable else { return skeleton }
        let prompt = """
        Rewrite this as one natural ARIA coaching turn. Keep every fact. Do not add medical claims. \
        Do not say you are a dummy, local, or fill-in.

        \(skeleton)
        """
        guard let out = try? await gen.generateResponse(for: prompt, context: context) else {
            return skeleton
        }
        let lower = out.content.lowercased()
        let kept = required.allSatisfy { token in
            lower.contains(token.lowercased())
        }
        if kept, out.content.count > 40 { return out.content }
        return skeleton
        #else
        return skeleton
        #endif
    }

    private static func confirm(_ message: String, store: AppStore, card: RichCardPayload?) -> AriaResponse {
        AriaResponse(
            confidenceReason: "Local fill-in — follow-up · on-device",
            proseSummary: message,
            message: message,
            richCard: card,
            suggestedActions: ["Make it easier", "What should I train today?"],
            contextUpdates: ["relationship_level": min(10, 1 + store.chatMessages.count / 3)],
            confidence: 0.9
        )
    }

    private static func workoutCard(_ workout: WorkoutPlan) -> RichCardPayload {
        RichCardPayload(
            type: "workout_plan",
            title: workout.name,
            workoutName: workout.name,
            durationMinutes: workout.duration
        )
    }

    private static func clockLabel(_ hour: Int) -> String {
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        let suffix = hour >= 12 ? "pm" : "am"
        return "at \(h12)\(suffix)"
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
