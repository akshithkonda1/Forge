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
/// never an off-device LLM. Curated web lookup, when it happens, goes
/// through `AriaWebResearch` in its own file.
///
/// Instantaneous grounding: each turn reads `AriaLiveGroundingHub` (fed by
/// HealthKit hydrate + AppStore) so Dummy coaches from stored life signals
/// instead of inventing sleep / readiness numbers.
@MainActor
enum AriaDummyOrchestrator {

    static let usesOffDeviceLLM = AriaDummyTurn.usesOffDeviceLLM
    static let writesCalendarEvents = AriaDummyTurn.writesCalendarEvents

    /// Last side effects applied — tests inspect this instead of EventKit.
    static var lastAppliedActions: [AriaDummyAction] = []
    /// Last Swarm picture — tests inspect the dataset pass without a model.
    static var lastSwarmPicture: AriaSwarmPicture?
    /// Last live grounding snapshot consumed this turn — tests prove stream use.
    static var lastGroundingSnapshot: AriaLiveGroundingSnapshot?

    static func reply(
        text: String,
        store: AppStore,
        agent: AriaCoachAgent,
        agents: [String]? = nil
    ) async -> AriaResponse {
        AriaContextStore.shared.fileSpoken(text)
        // Prefer the live stream (just hydrated by AriaService) over a stale
        // copy; fall back to building from AppStore when the hub is empty.
        let grounding = consumeLiveGrounding(store: store)
        lastGroundingSnapshot = grounding
        var context = store.makeTrainerContext(query: text)
        let life = context.lifeRead
        let trimmedName = store.userProfile.name.split(separator: " ").first.map(String.init) ?? ""
        let you = trimmedName.isEmpty ? "" : "\(trimmedName) — "
        let facts = speechFacts(from: store, grounding: grounding)
        let readiness = grounding.readiness > 0 ? grounding.readiness : store.readiness.overall

        let swarmPicture = runSwarm(store: store)
        lastSwarmPicture = swarmPicture

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

        let occurrence = AriaReplyVariety.beginTurn(prompt: text)
        context.totalMessageCount = max(context.totalMessageCount, occurrence)

        let follow = AriaDummyTurn.followUp(in: text)
        if follow != .none, let followed = handleFollowUp(
            follow,
            text: text,
            store: store,
            context: context,
            facts: facts,
            name: trimmedName
        ) {
            return publish(followed, prompt: text, store: store)
        }

        let personal = personalRead(store: store, swarm: swarmPicture, grounding: grounding)
        let sleepWeak = personal.sleepWeak
            || facts.sleepBand == .weak
            || (facts.sleepHours.map { $0 < 6.5 } ?? false)
            || text.lowercased().contains("slept badly")
            || text.lowercased().contains("slept 5")
        var interpretation = AriaDummyTurn.interpret(
            text: text,
            agent: agent,
            agents: routed,
            signals: store.intentSignals(for: text),
            sleepWeak: sleepWeak,
            readinessLow: readiness > 0 && readiness < 55
        )
        if QualityOfLifeLivingStore.isQuestion(text),
           !interpretation.domains.contains(.lifestyle),
           !interpretation.domains.contains(.nutrition) {
            interpretation.domains.append(.lifestyle)
        }
        if QualityOfLifeLivingStore.isCharacterQuestion(text),
           !interpretation.domains.contains(.lifestyle) {
            interpretation.domains.append(.lifestyle)
        }
        interpretation.domains = AriaPromptCorrelation.filterDomains(
            interpretation.domains,
            toPrompt: text
        )
        let calendarOutcome = FakeCalendarPack.outcome(fromTags: life.calendarIngestPayload())
        if calendarOutcome.keepLight, AriaPromptCorrelation.trainingAsk(text.lowercased()) {
            interpretation.keepLight = true
        }
        if AriaPromptCorrelation.trainingAsk(text.lowercased()),
           let qolPlan = QualityOfLifeTrainingPolicy.plan(fromTags: AriaContextStore.shared.context.lifestyleTags),
           qolPlan.keepLight {
            interpretation.keepLight = true
        }
        if personal.keepLight, AriaPromptCorrelation.trainingAsk(text.lowercased()) {
            interpretation.keepLight = true
        }
        let adaptation = AriaIntentResolver.adapt(store.intentSignals(for: text))
        if adaptation.keepLight, AriaPromptCorrelation.trainingAsk(text.lowercased()) {
            interpretation.keepLight = true
        }
        let asked = AriaPromptCorrelation.askedDomains(in: text)
        for spec in adaptation.specialists {
            let domain: AriaIntentDomain?
            switch spec {
            case "sleep": domain = .sleep
            case "recovery": domain = .readiness
            case "workout": domain = .training
            case "lifestyle": domain = .lifestyle
            case "progress": domain = .progress
            case "cycle": domain = .cycle
            default: domain = nil
            }
            if let domain, asked.contains(domain), !interpretation.domains.contains(domain) {
                interpretation.domains.append(domain)
            }
        }
        if calendarOutcome.shorten, asked.contains(.training) {
            interpretation.constrainedPlanInput += ". short session that still fits this week's calendar"
        }

        let emotional = AriaEmotionalSupportCoach.isEmotionalSupportQuery(text, context: context)
        let hasSystems = interpretation.domains.contains(where: {
            $0 == .training || $0 == .nutrition || $0 == .sleep || $0 == .cycle
        })
        if emotional, !hasSystems,
           let reading = AriaEmotionalSupportCoach.detect(in: text, context: context) {
            let resp = AriaEmotionalSupportCoach.respond(reading: reading, context: context, input: text)
            return publish(
                AriaResponse(
                    confidenceReason: "Local fill-in — companion",
                    proseSummary: resp.content,
                    message: resp.content,
                    suggestedActions: resp.suggestedActions,
                    confidence: resp.confidence
                ),
                prompt: text,
                store: store
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
        if beats.contains(where: { $0.domain == .training }),
           !beats.contains(where: { $0.domain == .lifestyle }),
           asked.contains(.training) || AriaPromptCorrelation.calendarAsk(text.lowercased()),
           let fit = life.sessionFitLine() {
            beats.append(
                AriaDummyBeat(
                    domain: .lifestyle,
                    prose: fit,
                    suggestedActions: ["What's on my calendar?"]
                )
            )
        }

        if beats.isEmpty {
            let intent = intentFor(agent: interpretation.primaryAgent, text: text)
            let fallback = AriaVoiceEngine.speak(intent: intent, context: context, input: text, facts: facts)
            let prose = AriaPromptCorrelation.grounded(
                prompt: text,
                draft: fallback.count > 30
                    ? fallback
                    : humanFallback(you: you, readiness: readiness, facts: facts, coaching: context.userProfile.coachingStyle, life: life)
            )
            return publish(
                AriaResponse(
                    confidenceReason: reason(
                        for: interpretation,
                        readiness: readiness,
                        hasSleep: facts.sleepHours != nil,
                        grounding: grounding
                    ),
                    proseSummary: prose,
                    message: prose,
                    suggestedActions: AriaFirstHealthBriefing.suggestedActions,
                    contextUpdates: ["relationship_level": min(10, 1 + store.chatMessages.count / 3)],
                    confidence: 0.82
                ),
                prompt: text,
                store: store
            )
        }

        var actions = beats.flatMap(\.actions)
        if let reminder = interpretation.reminder { actions.append(reminder) }
        for joint in interpretation.joints {
            actions.append(.rememberFact("Injury context: \(joint)"))
        }
        apply(actions, store: store)
        lastAppliedActions = actions

        let seed = AriaReplyVariety.salt(
            prompt: text,
            occurrence: occurrence,
            extra: UInt64(store.chatMessages.count)
        )
        let skeleton = AriaDummyTurn.compose(
            beats: beats,
            interpretation: interpretation,
            name: trimmedName,
            seed: seed,
            prompt: text
        )
        let required = requiredTokens(from: interpretation, beats: beats, prompt: text)
        let woven = AriaPromptCorrelation.allowsUnpromptedLifeStory(text)
            ? weaveStory(softenMetrics(skeleton), life: life)
            : softenMetrics(skeleton)
        var grounded = woven
        if let ground = personal.spokenGround,
           !grounded.localizedCaseInsensitiveContains(String(ground.prefix(24))) {
            grounded = "\(ground) \(grounded)"
        }
        var message = await polishIfOnDevice(skeleton: grounded, context: context, required: required, prompt: text)
        message = AriaPromptCorrelation.grounded(prompt: text, draft: message)
        if NSClassFromString("XCTestCase") == nil,
           AriaWebResearch.isDummyResearchWorthy(text: text),
           let web = await AriaWebResearch.lookUp(
            question: text,
            domainRawValue: interpretation.domains.first?.rawValue ?? "lifestyle",
            salt: seed
           ) {
            message = "\(web)\n\n\(message)"
        }

        let card = beats.compactMap(\.card).first
        var suggestions = beats.flatMap(\.suggestedActions)
        if suggestions.isEmpty { suggestions = AriaFirstHealthBriefing.suggestedActions }
        // The suggestion box opts out: its chip row is the interface.
        if !beats.contains(where: \.allowsManySuggestions), suggestions.count > 4 {
            suggestions = Array(suggestions.prefix(4))
        }

        return publish(
            AriaResponse(
                confidenceReason: reason(
                    for: interpretation,
                    readiness: readiness,
                    hasSleep: facts.sleepHours != nil,
                    grounding: grounding
                ),
                proseSummary: message,
                message: message,
                richCard: card,
                suggestedActions: suggestions,
                contextUpdates: ["relationship_level": min(10, 1 + store.chatMessages.count / 3)],
                confidence: 0.88
            ),
            prompt: text,
            store: store
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
            if let goal = ScheduleGoalParser.parse(text) {
                ScheduleGoalStore.save(goal)
                AriaKnowledgeLedgerStore.file(AriaKnowledgeFact(
                    category: .weSpokeAbout,
                    kind: "schedule_goal",
                    summary: "Wake target is \(ScheduleCorrector.clockLabel(goal.targetWakeHour)).",
                    source: "aria-dummy"
                ))
                let nights = SleepCircadianBridge.nights(from: store.sleepData)
                let step = ScheduleCorrector.tonight(goal: goal, nights: nights)
                let target = ScheduleCorrector.clockLabel(goal.targetWakeHour)
                let prose = step?.coachingReply
                    ?? "I'll get you up at \(target). A few more nights of sleep and I'll ratchet bedtime toward it."
                return AriaDummyBeat(
                    domain: .sleep,
                    prose: prose,
                    suggestedActions: ["How did I sleep?", "Keep it light today"]
                )
            }
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
            // The suggestion box: who owns this session? Delegation ("take
            // charge") hands ARIA the wheel; an explicit choice is recorded
            // and learned; otherwise ARIA predicts from habit — or asks.
            var planInput = interpretation.constrainedPlanInput
            var predictedNote: String? = nil
            var sportAltFocus: TrainingFocus? = nil
            switch Self.trainingDecision(text: text, interpretation: interpretation, store: store) {
            case .beat(let beat):
                return beat
            case .forceFocus(let focus):
                let weekday = TrainingHabits.weekdayIndex(for: Date())
                var habits = store.trainingHabits
                habits.record(.focus(focus), weekday: weekday)
                store.trainingHabits = habits
                planInput += " " + focus.planKeyword
                sportAltFocus = focus
                predictedNote = "\(TrainingHabits.weekdayName(for: weekday))s are usually \(focus.chipLabel.lowercased()) for you — that's what's on the board."
            case .forceSport(let name):
                var habits = store.trainingHabits
                habits.record(.sport(name), weekday: TrainingHabits.weekdayIndex(for: Date()))
                store.trainingHabits = habits
                let predictedPlan = ExerciseLibrary.sportSession(named: name, minutes: 45, completed: false)
                let predictedProse = AriaReplyVariety.pick([
                    "You usually play your way through the week — \(name), 45 minutes, on the board.",
                    "\(name), 45 minutes — on the board. The pattern talked, I listened.",
                ], prompt: text) + exerciseLedger(predictedPlan)
                return AriaDummyBeat(
                    domain: .training,
                    prose: predictedProse,
                    card: workoutCard(predictedPlan),
                    suggestedActions: ["What's on my board?", "Something else"],
                    actions: [.recordSport(name: name, minutes: 45, completed: false)]
                )
            case .proceed(let altFocus, let note):
                sportAltFocus = altFocus
                predictedNote = note
            }
            if let sport = interpretation.recordedSport {
                // A chosen sport is a choice: learn it.
                var habits = store.trainingHabits
                habits.record(.sport(sport.name), weekday: TrainingHabits.weekdayIndex(for: Date()))
                store.trainingHabits = habits
                let plan = ExerciseLibrary.sportSession(
                    named: sport.name,
                    minutes: sport.minutes,
                    completed: sport.completed
                )
                let verb = sport.completed ? "logged" : "put on the board"
                let prose = AriaReplyVariety.pick([
                    "I \(verb) \(sport.name) as \(sport.minutes) minutes of training — it counts as part of the session.",
                    "\(sport.name), \(sport.minutes) minutes — \(verb), and it counts toward the session.",
                    "Done: \(sport.name) \(verb) (\(sport.minutes) min). That's session credit.",
                ], prompt: text) + exerciseLedger(plan)
                return AriaDummyBeat(
                    domain: .training,
                    prose: prose,
                    card: workoutCard(plan),
                    suggestedActions: ["What's on my board?", "Give me a calisthenics session"],
                    actions: [.recordSport(name: sport.name, minutes: sport.minutes, completed: sport.completed)]
                )
            }
            let workout: WorkoutPlan
            var actions: [AriaDummyAction] = [.persistWorkout]
            if interpretation.preferCalisthenics {
                workout = constrainedWorkout(
                    ExerciseLibrary.calisthenicsPlan(
                        keepLight: interpretation.keepLight,
                        skipLegs: interpretation.skipLegs
                    ),
                    interpretation: interpretation,
                    life: life
                )
                store.todayWorkout = workout
                var line = AriaReplyVariety.pick([
                    "I pulled this from the calisthenics library. \(workout.name) is on the board for about \(workout.duration) minutes — \(workout.intensity.label.lowercased()) intensity.",
                    "Calisthenics library built this one — \(workout.name), about \(workout.duration) minutes at \(workout.intensity.label.lowercased()) intensity.",
                    "\(workout.name): bodyweight-only from the calisthenics library, roughly \(workout.duration) minutes, \(workout.intensity.label.lowercased()).",
                    "No gear needed — \(workout.name) from the calisthenics library, \(workout.duration) minutes, \(workout.intensity.label.lowercased()) intensity.",
                ], prompt: text) + exerciseLedger(workout)
                if let reason = eventReason(interpretation: interpretation, life: life) {
                    line = "\(reason) \(line)"
                }
                return AriaDummyBeat(
                    domain: .training,
                    prose: line,
                    card: workoutCard(workout),
                    suggestedActions: ["Make it easier", "ARIA, show me how"],
                    actions: actions
                )
            }
            let plan = AriaPlanEngine.evaluate(input: planInput, context: context)
            workout = constrainedWorkout(
                plan.workoutPlan,
                interpretation: interpretation,
                life: life
            )
            if plan.shouldPersistTheme {
                store.setTrainingTheme(plan.theme, source: "chat")
            }
            store.todayWorkout = workout
            var voiceFacts = facts
            voiceFacts.sessionTitle = workout.name
            voiceFacts.sessionDuration = workout.duration
            voiceFacts.sessionIntensity = workout.intensity.label
            let voice = AriaVoiceEngine.speak(intent: .trainingPlan, context: context, input: text, facts: voiceFacts)
            var line = AriaReplyVariety.pick([
                "\(workout.name) is on the board for about \(workout.duration) minutes — \(workout.intensity.label.lowercased()) intensity.",
                "Board's set: \(workout.name), about \(workout.duration) minutes at \(workout.intensity.label.lowercased()) intensity.",
                "\(workout.name) — \(workout.duration) minutes, \(workout.intensity.label.lowercased()). It's on the board.",
                "Today's session is \(workout.name): roughly \(workout.duration) minutes, \(workout.intensity.label.lowercased()) intensity.",
            ], prompt: text)
            if let reason = eventReason(interpretation: interpretation, life: life) {
                line = "\(reason) \(line)"
            }
            let ledger = exerciseLedger(workout)
            let prose: String
            if voice.count > 60 {
                if let reason = eventReason(interpretation: interpretation, life: life) {
                    prose = "\(reason) \(voice)" + ledger
                } else {
                    prose = voice + ledger
                }
            } else {
                prose = line + ledger
            }
            if plan.shouldPersistTheme { actions.append(.persistTheme) }
            // Predicted sessions say so up front; every muscle plan also names
            // a sport that trains the same tissue — the sports person stays
            // in the conversation.
            var finalProse = prose
            if let note = predictedNote { finalProse = "\(note) \(finalProse)" }
            if let focus = sportAltFocus,
               let alt = Self.sportAlternativeLine(for: focus, store: store) {
                finalProse += alt
            }
            return AriaDummyBeat(
                domain: .training,
                prose: finalProse,
                card: workoutCard(workout),
                suggestedActions: plan.suggestedActions,
                actions: actions
            )
        case .nutrition, .lifestyle:
            if let ml = interpretation.logWaterMl {
                let ounces = Int((ml / 29.5735).rounded())
                return AriaDummyBeat(
                    domain: .nutrition,
                    prose: "Logged. That’s about \(ounces) ounces of water on the board.",
                    suggestedActions: ["What's on my board?", "Remind me to drink water"],
                    actions: [.logWater(milliliters: ml)]
                )
            }
            if let note = interpretation.noteToWrite {
                return AriaDummyBeat(
                    domain: .lifestyle,
                    prose: "Wrote it down: \(note)",
                    suggestedActions: ["What's on my board?", "Remember that"],
                    actions: [.writeNote(note)]
                )
            }
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
            if interpretation.readCalendar {
                let inventory = LifestyleAssetIndex.spokenInventory(CalendarManager.shared.lifestyleAssets)
                let line = inventory
                    ?? life.contextualizeCalendarLine()
                    ?? life.spokenCalendarLine()
                    ?? "I don't have this week's calendar in yet. Connect it and I'll read this week — kinds and busy windows, never titles."
                return AriaDummyBeat(
                    domain: .lifestyle,
                    prose: line,
                    suggestedActions: ["What should I train today?", "What's on my board?"]
                )
            }
            if AriaReferenceCatalog.questionSuggestsEventPrep(text) {
                var line = AriaReplyVariety.pick([
                    "I don't shop the web — a wedding tux or dark suit should fit you, not chase a trend. Classic black tie, shoes you can stand in.",
                    "Skip the shopping tab. A classic tuxedo or dark suit that actually fits beats a trendy rental — shoes you can stand in.",
                    "For the wedding: tux or dark suit, fitted, nothing flashy. I don't shop the web; I care that you can stand in those shoes.",
                    "Wear a tux or a dark suit that fits your body, not a catalog. Black tie stays classic; comfort is the rest of the night.",
                ], prompt: text)
                if let reason = eventReason(interpretation: interpretation, life: life) {
                    line = "\(reason) \(line)"
                }
                return AriaDummyBeat(
                    domain: .lifestyle,
                    prose: line,
                    suggestedActions: ["What should I train today?", "What's my quality of life?"]
                )
            }
            if QualityOfLifeLivingStore.isQuestion(text) {
                return AriaDummyBeat(
                    domain: .lifestyle,
                    prose: QualityOfLifeLivingStore.coachingLine(
                        variety: AriaReplyVariety.occurrence(for: text)
                    ),
                    suggestedActions: ["Open Lifestyle", "What should I change?"]
                )
            }
            if QualityOfLifeLivingStore.isCharacterQuestion(text) {
                return AriaDummyBeat(
                    domain: .lifestyle,
                    prose: QualityOfLifeLivingStore.characterLine(
                        variety: AriaReplyVariety.occurrence(for: text)
                    ),
                    suggestedActions: ["What's my quality of life?", "What should I train today?"]
                )
            }
            if text.lowercased().contains("eat") || text.lowercased().contains("food")
                || text.lowercased().contains("protein") || text.lowercased().contains("meal")
                || domain == .nutrition {
                return AriaDummyBeat(
                    domain: .nutrition,
                    prose: AriaReplyVariety.pick([
                        "Keep food simple — protein and something you will actually eat.",
                        "Eat something you'll actually finish — protein first, nothing fancy.",
                        "Food stays simple: protein plus a plate you will eat.",
                        "Don't overthink the plate — protein and a meal you'll finish.",
                    ], prompt: text),
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
            if interpretation.readBoard {
                return AriaDummyBeat(
                    domain: .progress,
                    prose: boardReading(store: store, facts: facts, prompt: text),
                    suggestedActions: ["Write that down", "How did I sleep?"]
                )
            }
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
            let locked = AriaReplyVariety.pick([
                "Locked. \(workout.name) stays on the board.",
                "It's set — \(workout.name) stays on the board.",
                "Done. \(workout.name) is locked in.",
            ], prompt: text) + exerciseLedger(workout)
            return confirm(locked, store: store, card: workoutCard(workout))
        case .decline:
            store.todayWorkout = nil
            lastAppliedActions = [.cancelWorkout]
            let scratched = AriaReplyVariety.pick([
                "Scratched. Nothing on the board until you want it.",
                "Gone — the board's clear until you want something on it.",
                "Cleared. Say the word when you want a session.",
            ], prompt: text)
            return confirm(scratched, store: store, card: nil)
        case .easier:
            guard var workout = store.todayWorkout else { return nil }
            workout.intensity = AriaDummyTurn.stepDown(workout.intensity)
            store.todayWorkout = workout
            lastAppliedActions = [.scaleEasier]
            let scaled = AriaReplyVariety.pick([
                "Scaled it. \(workout.name) is now \(workout.intensity.label.lowercased()), about \(workout.duration) minutes.",
                "Turned it down — \(workout.name) is \(workout.intensity.label.lowercased()) now, about \(workout.duration) minutes.",
                "Easier it is: \(workout.name) at \(workout.intensity.label.lowercased()) intensity, \(workout.duration) minutes.",
            ], prompt: text) + exerciseLedger(workout)
            return confirm(scaled, store: store, card: workoutCard(workout))
        case .shorter:
            guard var workout = store.todayWorkout else { return nil }
            workout.duration = max(15, Int(Double(workout.duration) * 0.7))
            store.todayWorkout = workout
            lastAppliedActions = [.scaleShorter]
            let cut = AriaReplyVariety.pick([
                "Cut it down. \(workout.name) is about \(workout.duration) minutes now.",
                "Shorter session — \(workout.name), about \(workout.duration) minutes.",
                "Trimmed to \(workout.duration) minutes. \(workout.name), same intent, less clock.",
            ], prompt: text) + exerciseLedger(workout)
            return confirm(cut, store: store, card: workoutCard(workout))
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
            let workout = constrainedWorkout(
                plan.workoutPlan,
                interpretation: interpretation,
                life: context.lifeRead
            )
            store.todayWorkout = workout
            lastAppliedActions = [.skipLegs, .persistWorkout]
            let noLegs = AriaReplyVariety.pick([
                "Legs off. \(workout.name) is on the board instead.",
                "Skipped legs — \(workout.name) is the session now.",
                "No leg work today. \(workout.name) takes its place.",
            ], prompt: text) + exerciseLedger(workout)
            return confirm(noLegs, store: store, card: workoutCard(workout))
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

    private static func constrainedWorkout(
        _ workout: WorkoutPlan,
        interpretation: AriaDummyInterpretation,
        life: AriaLifeRead
    ) -> WorkoutPlan {
        constrain(
            workout,
            interpretation: interpretation,
            outcome: FakeCalendarPack.outcome(fromTags: life.calendarIngestPayload()),
            eventTags: eventTags(interpretation: interpretation, life: life)
        )
    }

    // MARK: - Train suggestion box

    /// The pre-plan decision: who owns this session and what should ARIA do
    /// about it. Explicit delegation and explicit choices always win; a
    /// confident habit predicts; otherwise the box asks.
    private enum TrainingDecision {
        case beat(AriaDummyBeat)
        case forceFocus(TrainingFocus)
        case forceSport(String)
        case proceed(altFocus: TrainingFocus?, note: String? = nil)
    }

    private static func trainingDecision(
        text: String,
        interpretation: AriaDummyInterpretation,
        store: AppStore
    ) -> TrainingDecision {
        let lower = text.lowercased()
        let weekday = TrainingHabits.weekdayIndex(for: Date())

        // "Take charge" — the user delegates; ARIA owns the plan from here.
        if TrainingHabits.isTakeChargePhrase(in: lower) {
            var habits = store.trainingHabits
            habits.setMode(.ariaLeads)
            store.trainingHabits = habits
            return .proceed(altFocus: nil, note: "Say the word — I've got the week.")
        }
        // "I'll pick" — the user keeps the wheel; open the box.
        if TrainingHabits.isUserLedPhrase(in: lower) {
            var habits = store.trainingHabits
            habits.setMode(.userLeads)
            store.trainingHabits = habits
            return .beat(suggestionBoxBeat(
                prompt: text,
                opener: "You're driving — what are we training?"
            ))
        }
        // An explicit body part is a choice: record it, learn it, build it.
        if let focus = TrainingFocus.from(text: text) {
            var habits = store.trainingHabits
            habits.record(.focus(focus), weekday: weekday)
            store.trainingHabits = habits
            return .proceed(altFocus: focus)
        }
        // Bare "sports" — open the sport picker, not a muscle box.
        if interpretation.recordedSport == nil,
           TrainingHabits.isSportPickerRequest(in: lower) {
            return .beat(sportPickerBeat(prompt: text, store: store))
        }
        // "Something else" (from the sport picker) — back to the muscle box.
        if lower.trimmingCharacters(in: .whitespacesAndNewlines) == "something else" {
            return .beat(suggestionBoxBeat(prompt: text, opener: nil))
        }
        // Vague request, user still owns the week: predict or ask.
        if store.trainingHabits.mode == .userLeads,
           interpretation.recordedSport == nil,
           !interpretation.preferCalisthenics {
            if let suggestion = store.trainingHabits.suggestion(forWeekday: weekday) {
                switch suggestion.choice {
                case .focus(let focus): return .forceFocus(focus)
                case .sport(let name): return .forceSport(name)
                }
            }
            return .beat(suggestionBoxBeat(prompt: text, opener: nil))
        }
        return .proceed(altFocus: nil)
    }

    /// "What part of the body today?" — every catalog focus plus sports plus
    /// handing ARIA the wheel. Chips, not a paragraph: least resistance.
    private static func suggestionBoxBeat(prompt: String, opener: String?) -> AriaDummyBeat {
        let line = opener ?? AriaReplyVariety.pick([
            "What part of the body are we training today?",
            "Where's the work going today — pick a lane and I'll build it.",
            "What's the target today?",
        ], prompt: prompt)
        var chips = TrainingFocus.allCases.map(\.chipLabel)
        chips.append("Sports")
        chips.append("You pick")
        return AriaDummyBeat(
            domain: .training,
            prose: line,
            suggestedActions: chips,
            allowsManySuggestions: true
        )
    }

    /// The sports shelf: favorites first (learned), catalog fallbacks after.
    /// Tapping a sport flows through the normal sport path — one row, real plan.
    private static func sportPickerBeat(prompt: String, store: AppStore) -> AriaDummyBeat {
        var chips = Array(store.trainingHabits.favoriteSports.prefix(3))
        for fallback in ["Swimming", "Tennis", "Basketball", "Boxing", "Soccer", "Hiking"] {
            if chips.count >= 4 { break }
            if !chips.contains(where: { $0.caseInsensitiveCompare(fallback) == .orderedSame }) {
                chips.append(fallback)
            }
        }
        chips.append("Something else")
        let line = AriaReplyVariety.pick([
            "What are we playing?",
            "Pick your sport — I'll put the session on the board.",
        ], prompt: prompt)
        return AriaDummyBeat(
            domain: .training,
            prose: line,
            suggestedActions: chips,
            allowsManySuggestions: true
        )
    }

    /// Every muscle plan names a sport that trains the same tissue, so the
    /// sports-only person is always one tap from their version of the session.
    private static func sportAlternativeLine(for focus: TrainingFocus, store: AppStore) -> String? {
        let matches = ExerciseLibrary.sportsFor(muscles: focus.muscles)
        guard !matches.isEmpty else { return nil }
        let favorites = store.trainingHabits.favoriteSports
        let pick = matches.first(where: { def in
            favorites.contains { $0.caseInsensitiveCompare(def.name) == .orderedSame }
        }) ?? matches[0]
        return "\n\nOr make it play: \(pick.name) hits the same muscles — it counts toward the session."
    }

    private static func eventTags(
        interpretation: AriaDummyInterpretation,
        life: AriaLifeRead
    ) -> [String] {
        var tags = life.calendarIngestPayload()
        if let days = SpokenEventParser.daysUntilWedding(in: interpretation.constrainedPlanInput) {
            tags.append("calendar:horizon:wedding:\(days)")
        }
        return tags
    }

    private static func eventReason(
        interpretation: AriaDummyInterpretation,
        life: AriaLifeRead
    ) -> String? {
        if let event = EventTrainingPolicy.plan(fromTags: eventTags(interpretation: interpretation, life: life)) {
            return event.reason
        }
        return QualityOfLifeTrainingPolicy.plan(fromTags: AriaContextStore.shared.context.lifestyleTags)?.reason
    }

    private static func constrain(
        _ workout: WorkoutPlan,
        interpretation: AriaDummyInterpretation,
        outcome: AriaCalendarOutcome = .ordinary,
        eventTags: [String] = []
    ) -> WorkoutPlan {
        var next = workout
        if interpretation.keepLight || outcome.keepLight {
            if next.intensity == .max || next.intensity == .high {
                next.intensity = .moderate
            }
        }
        if outcome.shorten {
            next.duration = min(next.duration, max(15, outcome.maxMinutes))
        }
        if interpretation.skipLegs {
            let kept = next.exercises.filter { !AriaDummyTurn.isLegMove($0.name) }
            if kept.count >= 2 { next.exercises = kept }
            if !next.name.lowercased().contains("upper") && !next.name.lowercased().contains("pull") {
                next.name = "Upper " + next.name
            }
        }
        var tags = eventTags
        if let days = SpokenEventParser.daysUntilWedding(in: interpretation.constrainedPlanInput) {
            tags.append("calendar:horizon:wedding:\(days)")
        }
        if let event = EventTrainingPolicy.plan(fromTags: tags) {
            if event.reduceVolume {
                next.duration = min(next.duration, max(25, event.keepLight ? 30 : 40))
            }
            if event.keepLight, next.intensity == .max || next.intensity == .high {
                next.intensity = .moderate
            }
            if event.progressive, !next.name.lowercased().contains("progressive") {
                next.name = "Progressive " + next.name
            }
        }
        if let qol = QualityOfLifeTrainingPolicy.plan(fromTags: AriaContextStore.shared.context.lifestyleTags) {
            if qol.reduceVolume {
                next.duration = min(next.duration, max(20, qol.maxDuration))
            }
            if qol.keepLight, next.intensity == .max || next.intensity == .high {
                next.intensity = .moderate
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
            case .logWater(let milliliters):
                store.rememberDurable("Logged \(Int(milliliters)) ml of water")
                AriaContextStore.shared.addInsight("Logged water — \(Int(milliliters)) ml")
                Task { try? await HealthKitManager.shared.logWater(milliliters: milliliters) }
            case .writeNote(let note):
                store.rememberDurable(note)
                AriaContextStore.shared.addInsight(note)
            case .recordSport(let name, let minutes, let completed):
                store.recordSportSession(name: name, minutes: minutes, completed: completed)
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

    private static func personalRead(
        store: AppStore,
        swarm: AriaSwarmPicture?,
        grounding: AriaLiveGroundingSnapshot
    ) -> AriaPersonalRead {
        let night = store.sleepData.first
        let nightHours = grounding.sleepHours
            ?? night?.totalHours
            ?? (store.dailyMetrics.totalSleep > 0 ? Double(store.dailyMetrics.totalSleep) / 60.0 : nil)
        let hrv = grounding.hrvMs.map(Double.init)
            ?? (store.dailyMetrics.hrv > 0 ? Double(store.dailyMetrics.hrv) : nil)
        let rhr = grounding.restingHR.map(Double.init)
            ?? (store.dailyMetrics.restingHR > 0 ? Double(store.dailyMetrics.restingHR) : nil)
        return AriaPersonalRead.evaluate(
            nightHours: nightHours,
            deepMinutes: grounding.deepMinutes.map(Double.init)
                ?? night.map { Double($0.deepMinutes) },
            remMinutes: night.map { Double($0.remMinutes) },
            awakeMinutes: night.map { Double($0.awakeMinutes) },
            hrvMs: hrv,
            readiness: grounding.readiness > 0 ? grounding.readiness : store.readiness.overall,
            chronologicalAge: store.userProfile.age.map(Double.init).flatMap { $0 > 12 ? $0 : nil },
            vo2Max: nil,
            restingHR: rhr,
            swarm: swarm
        )
    }

    private static func speechFacts(
        from store: AppStore,
        grounding: AriaLiveGroundingSnapshot
    ) -> AriaSpeechFacts {
        var facts = AriaSpeechFacts()
        let personal = personalRead(store: store, swarm: lastSwarmPicture, grounding: grounding)
        // Prefer live-stream scalars — only cite what the hub / store actually holds.
        if let hours = grounding.sleepHours, hours > 0 {
            facts.sleepHours = hours
            facts.deepMinutes = grounding.deepMinutes
            facts.sleepAvg = Int(hours.rounded())
        } else if let night = store.sleepData.first, night.totalHours > 0 {
            facts.sleepHours = night.totalHours
            facts.deepMinutes = night.deepMinutes
            facts.sleepAvg = Int(store.dailyMetrics.totalSleep > 0
                ? Double(store.dailyMetrics.totalSleep) / 60.0
                : night.totalHours)
        } else if store.dailyMetrics.totalSleep > 0 {
            facts.sleepHours = Double(store.dailyMetrics.totalSleep) / 60.0
        }
        switch personal.sleepBand {
        case "strong": facts.sleepBand = .strong
        case "weak": facts.sleepBand = .weak
        case "ok": facts.sleepBand = .ok
        default: facts.sleepBand = facts.sleepHours == nil ? .unknown : .ok
        }
        return facts
    }

    private static func consumeLiveGrounding(store: AppStore) -> AriaLiveGroundingSnapshot {
        let hub = AriaLiveGroundingHub.shared
        if hub.latest.hasLifeSignal {
            return hub.latest
        }
        let built = AriaLiveGroundingSnapshot.from(store: store)
        hub.publish(built, force: true)
        return built
    }

    private static func reason(
        for interpretation: AriaDummyInterpretation,
        readiness: Int,
        hasSleep: Bool,
        grounding: AriaLiveGroundingSnapshot
    ) -> String {
        let names = interpretation.domains.map(\.rawValue).joined(separator: " + ")
        let groundingLine = companionReason(readiness: readiness, hasSleep: hasSleep)
        let swarm = lastSwarmPicture.map { picture in
            let labels = picture.sources.filter(\.present).map(\.label)
            if labels.isEmpty { return "swarm" }
            return "swarm · \(labels.joined(separator: ", "))"
        } ?? "swarm"
        let stream = grounding.reasonTag
        if names.isEmpty { return "Local fill-in — \(swarm) · \(stream) · \(groundingLine)" }
        return "Local fill-in — \(names) · \(swarm) · on-device · \(stream) · \(groundingLine)"
    }

    @discardableResult
    private static func runSwarm(store: AppStore) -> AriaSwarmPicture {
        let picture = AriaSwarm.run(snapshot: .from(store: store))
        AriaSwarm.file(picture)
        return picture
    }

    private static func requiredTokens(
        from interpretation: AriaDummyInterpretation,
        beats: [AriaDummyBeat],
        prompt: String
    ) -> [String] {
        var tokens: [String] = AriaPromptCorrelation.requiredMentions(in: prompt)
        if interpretation.domains.contains(.sleep) { tokens.append("sleep") }
        if interpretation.domains.contains(.training) { tokens.append("minute") }
        if interpretation.recordedSport != nil { tokens.append("train") }
        if interpretation.logWaterMl != nil { tokens.append("water") }
        if interpretation.domains.contains(.nutrition), interpretation.logWaterMl == nil { tokens.append("eat") }
        if interpretation.skipLegs { tokens.append("leg") }
        if beats.contains(where: { $0.prose.localizedCaseInsensitiveContains("Lifestyle QoL") }),
           let snap = QualityOfLifeLivingStore.load() {
            tokens.append("\(snap.overall)/100")
        }
        var unique: [String] = []
        for token in tokens where !unique.contains(where: { $0.caseInsensitiveCompare(token) == .orderedSame }) {
            unique.append(token)
        }
        return unique
    }

    private static func polishIfOnDevice(
        skeleton: String,
        context: TrainerContext,
        required: [String],
        prompt: String
    ) async -> String {
        // Simulator has no model catalog — see FoundationModelsResponseGenerator's
        // own init comment and AppStore's identical guard.
        #if canImport(FoundationModels) && !targetEnvironment(simulator)
        guard #available(iOS 26.0, *) else { return skeleton }
        let gen = FoundationModelsResponseGenerator()
        guard gen.isAvailable else { return skeleton }
        let rewrite = """
        Rewrite this as one natural ARIA coaching turn that answers THIS user message — do not change the topic:
        \(prompt)

        Keep every fact. Do not add medical claims. Do not say you are a dummy, local, or fill-in.
        If they already asked this, rephrase — never reprint the last reply.

        \(skeleton)
        """
        guard let out = try? await gen.generateResponse(for: rewrite, context: context) else {
            return skeleton
        }
        let lower = out.content.lowercased()
        let kept = required.allSatisfy { token in
            lower.contains(token.lowercased())
        }
        if kept, AriaPromptCorrelation.correlates(reply: out.content, toPrompt: prompt), out.content.count > 40 {
            return out.content
        }
        return skeleton
        #else
        return skeleton
        #endif
    }

    private static func publish(_ response: AriaResponse, prompt: String, store: AppStore) -> AriaResponse {
        var out = response
        var message = bridgeNightIfNeeded(out.message, prompt: prompt, store: store)
        message = AriaReplyVariety.distinct(prompt: prompt, draft: message)
        // Last gate, after on-device polish — same order as Python Dummy
        // `friend_speak` / `_scrub_fused_speak` (vitals + cheer after generate).
        message = sanitizeSpeak(message)
        out.message = message
        out.proseSummary = message
        let takeaway = String(message.split(separator: ".").first ?? Substring(message))
        if takeaway.count > 12 {
            AriaKnowledgeLedgerStore.file(AriaKnowledgeFact(
                category: .weSpokeAbout,
                kind: "turn",
                summary: String(takeaway.prefix(140)),
                source: "aria-dummy"
            ))
        }
        return out
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
            durationMinutes: workout.duration,
            exercises: workout.exercises.map {
                CloudRichCardExercise(name: $0.name, sets: $0.sets, reps: $0.reps)
            }
        )
    }

    /// The auditable record: the exact exercises ARIA put on the board, in the
    /// chat message itself — never just the card. Names come from the Train
    /// library through the plan engine, so the list can only name moves the
    /// library actually has. Built from the *constrained* plan so the ledger
    /// always matches what `store.todayWorkout` holds.
    private static func exerciseLedger(_ workout: WorkoutPlan) -> String {
        guard !workout.exercises.isEmpty else { return "" }
        let rows = workout.exercises.map { ex in
            "• \(ex.name) — \(ex.sets) × \(ex.reps)"
        }
        return "\n\nOn the board:\n" + rows.joined(separator: "\n")
    }

    private static func clockLabel(_ hour: Int) -> String {
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        let suffix = hour >= 12 ? "pm" : "am"
        return "at \(h12)\(suffix)"
    }

    private static func boardReading(store: AppStore, facts: AriaSpeechFacts, prompt: String) -> String {
        var parts = [AriaReplyVariety.pick([
            "I already read your board.",
            "Board's read — here's where things stand.",
            "Got the board in front of me.",
        ], prompt: prompt)]
        if let hours = facts.sleepHours {
            parts.append("Last night was about \(String(format: "%.1f", hours)) hours.")
        }
        if let today = store.todayWorkout {
            parts.append("\(today.name) is on today's session.")
        }
        if let last = store.workoutHistory.first {
            parts.append("Last logged session was \(last.name).")
        }
        let life = store.makeTrainerContext().lifeRead
        if let inventory = LifestyleAssetIndex.spokenInventory(CalendarManager.shared.lifestyleAssets) {
            parts.append(inventory)
        } else if let spoken = life.spokenCalendarLine() {
            parts.append(spoken)
        } else {
            let busy = CalendarManager.shared.busyWindowsToday
            if busy > 0 {
                parts.append("Calendar shows \(busy) busy window\(busy == 1 ? "" : "s") today — I don't read the titles.")
            }
        }
        let notes = store.durableMemoryAnchors.prefix(4)
        if notes.isEmpty {
            parts.append("Nothing durable yet — tell me to write it down and I will.")
        } else {
            parts.append("I wrote down: " + notes.joined(separator: "; ") + ".")
        }
        return parts.joined(separator: " ")
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

    /// Fused Dummy `_VITALS_SPEAK` (`aria_engine` + Dummy orchestrator).
    /// Sleep-stage % is stripped first (`stripSleepStagePct`); these patterns
    /// are the remaining fail-and-fallback tokens, not a "min deep" HUD ban.
    private static let vitalsSpeak = try! NSRegularExpression(
        pattern: #"\b(hrv|bpm|ms|mmhg|vo2|spo2|recovery score|sleep[- ]?debt)\b|%\s*(?:below|above|under|over)\s+baseline|\b(?:deep|rem|light)\s+sleep\s+at\s+\d+(?:\.\d+)?\s*%|\brem\s+is\s+light\s+at\s+\d+(?:\.\d+)?\s*%"#,
        options: [.caseInsensitive]
    )

    /// Iris `_SLEEP_STAGE_PCT` — strip at speak, keep the rest of the sentence.
    private static let sleepStagePct = try! NSRegularExpression(
        pattern: #"\b(?:deep|rem|light)\s+sleep\s+at\s+\d+(?:\.\d+)?\s*%|\brem\s+is\s+light\s+at\s+\d+(?:\.\d+)?\s*%"#,
        options: [.caseInsensitive]
    )

    /// Python Dummy `_CHEER_SLUDGE` — empty praise Dummy fused speak already strips.
    private static let cheerSludge = try! NSRegularExpression(
        pattern: #"\b(crushing it|you['’]re killing it|you got this|you['’]ve got this|so proud of you|amazing work|great job|keep slaying|beast mode|you['’]re a machine|keep up the great|so inspiring)\b"#,
        options: [.caseInsensitive]
    )

    private static let speakFallback =
        "I'm with you. Let's pick one next step that respects today rather than performing it."

    /// Last user-visible gate. Mirrors `friend_speak` + `_speak_without_vitals`.
    /// Tests call this on known-bad fixtures; live Dummy chat runs it in `publish`.
    static func sanitizeSpeak(_ text: String) -> String {
        var out = cheerSludge.stringByReplacingMatches(
            in: text,
            options: [],
            range: NSRange(text.startIndex..<text.endIndex, in: text),
            withTemplate: "that's real work"
        )
        // Same order as fused Dummy: cheer (`friend_speak`) then
        // `_strip_sleep_stage_pct` then `_speak_without_vitals`.
        out = stripSleepStagePct(out)
        out = stripVitalsHUD(out)
        if dumpsVitals(out) {
            out = dropVitalsSentences(out)
        }
        out = out
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if out.isEmpty || dumpsVitals(out) {
            return speakFallback
        }
        return out
    }

    /// Port of `services.aria_engine._strip_sleep_stage_pct`.
    private static func stripSleepStagePct(_ text: String) -> String {
        var cleaned = sleepStagePct.stringByReplacingMatches(
            in: text,
            options: [],
            range: NSRange(text.startIndex..<text.endIndex, in: text),
            withTemplate: ""
        )
        cleaned = replaceRegex(cleaned, pattern: #"\s*is in a healthy band"#, with: "")
        cleaned = replaceRegex(cleaned, pattern: #"\bsleep:\s*;\s*"#, with: "")
        cleaned = replaceRegex(cleaned, pattern: #"\s{2,}"#, with: " ")
        cleaned = replaceRegex(cleaned, pattern: #"\s+([,.;:])"#, with: "$1")
        cleaned = replaceRegex(cleaned, pattern: #"\s*[—–-]\s*([,.;])"#, with: "$1")
        cleaned = replaceRegex(cleaned, pattern: #"\s*[—–-]\s*$"#, with: "")
        return cleaned.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:—–-"))
    }

    private static func replaceRegex(_ text: String, pattern: String, with template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        return re.stringByReplacingMatches(
            in: text,
            options: [],
            range: NSRange(text.startIndex..<text.endIndex, in: text),
            withTemplate: template
        )
    }

    private static func dumpsVitals(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return vitalsSpeak.firstMatch(in: text, options: [], range: range) != nil
    }

    private static func stripVitalsHUD(_ s: String) -> String {
        var out = s
        let hud = [
            #"Readiness \d+/100 · HRV \d+ ms · RHR \d+ bpm[^.]*\."#,
            #"Readiness \d+, HRV \d+, resting heart \d+\."#,
            #"Player status \d+/100 · HRV \d+[^.]*\."#,
        ]
        for pattern in hud {
            if let range = out.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                out.replaceSubrange(range, with: "I already looked — here's the read.")
            }
        }
        return out
    }

    private static func dropVitalsSentences(_ text: String) -> String {
        guard let sentenceRe = try? NSRegularExpression(pattern: #"[^.!?]+[.!?]?"#, options: []) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var kept: [String] = []
        sentenceRe.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let match, let swiftRange = Range(match.range, in: text) else { return }
            let sentence = String(text[swiftRange])
            if !dumpsVitals(sentence) {
                kept.append(sentence.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return kept.filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Sleep → train continuity. Python `_callback` / `_bridge_fused_memory`
    /// plus `memory_hole_hits`: a later training ask must still name the night.
    /// Short discourse moves (`make it easier`) do not have to re-narrate it.
    private static func bridgeNightIfNeeded(_ message: String, prompt: String, store: AppStore) -> String {
        if AriaDummyTurn.followUp(in: prompt) != .none { return message }
        let prior = priorUserPrompts(store: store, current: prompt)
        guard let last = prior.last else { return message }
        let promptLow = prompt.lowercased()
        let lastLow = last.lowercased()
        let sleepCues = ["sleep", "slept", "last night", "insomnia"]
        let trainCues = ["train", "workout", "session", "gym"]
        let nightAck = ["night", "sleep", "slept", "rest"]
        let hadSleep = sleepCues.contains { lastLow.contains($0) }
        let askingTrain = trainCues.contains { promptLow.contains($0) }
        guard hadSleep, askingTrain else { return message }
        let msgLow = message.lowercased()
        if nightAck.contains(where: { msgLow.contains($0) }) { return message }
        let opener = AriaReplyVariety.pick([
            "Yeah — about that night, ",
            "You were asking about the night — ",
            "Picking up from last night: ",
            "Still thinking about the sleep piece — ",
            "Right, the night you mentioned — ",
        ], prompt: prompt)
        var body = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if (opener.hasSuffix("— ") || opener.hasSuffix(": ")),
           let first = body.first,
           first.isUppercase,
           !body.hasPrefix("I "),
           !body.hasPrefix("I'm "),
           !body.hasPrefix("I’ll "),
           !body.hasPrefix("I'll ") {
            body = first.lowercased() + body.dropFirst()
        }
        return opener + body
    }

    private static func priorUserPrompts(store: AppStore, current: String) -> [String] {
        let users = store.chatMessages
            .filter { $0.role == .user }
            .map(\.content)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if let last = users.last,
           last.caseInsensitiveCompare(current) == .orderedSame {
            return Array(users.dropLast())
        }
        return users
    }

    private static func humanizeRecover(_ raw: String, you: String, facts: AriaSpeechFacts, readiness: Int, coaching: CoachingStyle, life: AriaLifeRead) -> String {
        // If voice engine already sounds human (contains "I hear" or contraction + empathy), keep it.
        let lower = raw.lowercased()
        let alreadyHuman = lower.contains("i hear") || lower.contains("makes sense") || lower.contains("of course")
        if alreadyHuman && raw.count > 40 { return weaveStory(softenMetrics(raw), life: life) }

        let name = you.replacingOccurrences(of: " — ", with: "").trimmingCharacters(in: .whitespaces)
        var rng = AriaSeededRNG(seed: UInt64(abs((name + "\(readiness)" + (life.story ?? "")).hashValue)))
        let hasSleep = facts.sleepHours != nil && facts.sleepBand != .unknown
        let weak = hasSleep && (
            facts.sleepBand == .weak || life.felt == "thin" || life.felt == "spent" || life.lastNightLate
        )
        let opener = name.isEmpty ? "" : rng.pick(["Hey \(name) — ", "\(name), ", "Hey \(name), "])
        let plot = life.spokenLine(rng: &rng)
        let empathy: String = {
            if let plot { return plot }
            guard hasSleep else {
                return rng.pick([
                    "I'm working from what's on your board —",
                    "I've got the signals we have —",
                    "Using what's already here —",
                ])
            }
            return weak
                ? rng.pick(["Last night was on the short side —", "Sleep was thin last night —", "The rebuild didn't quite land —"])
                : rng.pick(["You actually got to rebuild last night —", "Last night gave you something to work with —", "Sleep did its job —"])
        }()
        let body: String = {
            guard hasSleep else {
                return rng.pick([
                    "no inventing last night when it isn't here. Tell me how you feel and we'll pick one next step.",
                    "if last night isn't on the board yet, say how you feel and we'll coach from that.",
                    "we'll stay honest about missing sleep data and still pick something kind.",
                ])
            }
            return weak
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
        }()
        let invite = readiness < 55
            ? rng.pick([
                "Want a gentle reset or just a check-in? Your call.",
                "Want breathing + light movement, or just rest?",
                "Soft day or just a check-in — you pick.",
                "We can keep it tiny. Reset, or just talk?",
              ])
            : rng.pick([
                "Want a light, honest session or full rest? You choose.",
                "Want me to map something light, or keep it to a walk?",
                "Light work or a walk — either is a clean call.",
                "I can sketch a short session, or we leave it at easy movement.",
              ])
        return "\(opener)\(empathy) \(body) \(invite)".replacingOccurrences(of: "  ", with: " ")
    }

    private static func softenMetrics(_ s: String) -> String {
        sanitizeSpeak(s)
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
