import XCTest
import ForgeCore
@testable import ForgeSwift

final class AriaCoachAgentRouterTests: XCTestCase {

    func testPinnedAgentWins() {
        let ctx = AriaCoachAgentRouter.Context(pinned: .lifestyle, cycleAvailable: false)
        XCTAssertEqual(
            AriaCoachAgentRouter.resolve(message: "what should I train today?", context: ctx),
            .lifestyle
        )
    }

    func testRecoveryQuestionRoutesToRecovery() {
        // Recovery has no page of its own (folded into the Lifestyle tab's
        // UI) but stays a full pinnable/tracked mode -- that's a UI-placement
        // decision, not a routing demotion.
        let ctx = AriaCoachAgentRouter.Context(pinned: nil, cycleAvailable: false)
        XCTAssertEqual(
            AriaCoachAgentRouter.resolve(message: "my HRV is tanked, I'm exhausted", context: ctx),
            .recovery
        )
    }

    func testSleepQuestionRoutesToSleep() {
        let ctx = AriaCoachAgentRouter.Context(pinned: nil, cycleAvailable: false)
        XCTAssertEqual(
            AriaCoachAgentRouter.resolve(message: "How did I sleep last night?", context: ctx),
            .sleep
        )
    }

    func testProgressQuestionRoutesToProgress() {
        let ctx = AriaCoachAgentRouter.Context(pinned: nil, cycleAvailable: false)
        XCTAssertEqual(
            AriaCoachAgentRouter.resolve(message: "Am I making progress with my streak?", context: ctx),
            .progress
        )
    }

    func testNutritionQuestionRoutesToLifestyle() {
        // Fuel folded into Lifestyle -- nutrition vocabulary should route there now.
        let ctx = AriaCoachAgentRouter.Context(pinned: nil, cycleAvailable: false)
        XCTAssertEqual(
            AriaCoachAgentRouter.resolve(message: "What should I eat for breakfast?", context: ctx),
            .lifestyle
        )
    }

    func testWorkoutQuestionRoutesToWorkout() {
        let ctx = AriaCoachAgentRouter.Context(pinned: nil, cycleAvailable: false)
        XCTAssertEqual(
            AriaCoachAgentRouter.resolve(message: "What should I train today?", context: ctx),
            .workout
        )
    }

    func testTabHintBiasesAmbiguousMessage() {
        // No pin, no keyword match: an ambiguous "hey" should fall back to
        // the tab the user is actually on rather than the bare generalist.
        let ctx = AriaCoachAgentRouter.Context(pinned: nil, cycleAvailable: false, tabHint: .sleep)
        XCTAssertEqual(
            AriaCoachAgentRouter.resolve(message: "hey", context: ctx),
            .sleep
        )
    }

    func testExplicitPinBeatsTabHint() {
        // Pinning stays sacrosanct: navigating to Sleep must not silently
        // override a Progress pin.
        let ctx = AriaCoachAgentRouter.Context(pinned: .progress, cycleAvailable: false, tabHint: .sleep)
        XCTAssertEqual(
            AriaCoachAgentRouter.resolve(message: "hey", context: ctx),
            .progress
        )
    }

    func testKeywordMatchBeatsTabHint() {
        // A clear keyword hit stays authoritative over the soft tab fallback.
        let ctx = AriaCoachAgentRouter.Context(pinned: nil, cycleAvailable: false, tabHint: .lifestyle)
        XCTAssertEqual(
            AriaCoachAgentRouter.resolve(message: "How did I sleep last night?", context: ctx),
            .sleep
        )
    }

    func testCycleRouteRequiresAvailability() {
        let hidden = AriaCoachAgentRouter.Context(pinned: nil, cycleAvailable: false)
        XCTAssertEqual(
            AriaCoachAgentRouter.resolve(message: "my period started", context: hidden),
            .aria
        )
        let open = AriaCoachAgentRouter.Context(pinned: nil, cycleAvailable: true)
        XCTAssertEqual(
            AriaCoachAgentRouter.resolve(message: "my period started", context: open),
            .cycle
        )
    }

    func testPinnedCycleFallsBackWhenNotShared() {
        let ctx = AriaCoachAgentRouter.Context(pinned: .cycle, cycleAvailable: false)
        XCTAssertEqual(
            AriaCoachAgentRouter.resolve(message: "hello", context: ctx),
            .aria
        )
    }

    func testCycleDirectiveForbidsFertility() {
        let law = AriaCoachAgent.cycle.localDirective.lowercased()
        XCTAssertTrue(law.contains("never invent fertility"))
        XCTAssertTrue(law.contains("not medical"))
    }

    func testMultiIntentSpawnsEveryMatchingAgent() {
        let ctx = AriaCoachAgentRouter.Context(pinned: nil, cycleAvailable: false)
        let plan = AriaCoachAgentRouter.plan(
            message: "I slept badly — what should I train and eat?",
            context: ctx
        )
        let kinds = Set(plan.workers.map(\.kind))
        // "slept" now routes to the dedicated Sleep specialist rather than
        // Recovery, and "eat" routes to Lifestyle now that Fuel folded into it.
        XCTAssertTrue(kinds.contains(.sleep))
        XCTAssertTrue(kinds.contains(.workout))
        XCTAssertTrue(kinds.contains(.lifestyle))
        XCTAssertEqual(plan.workers.filter(\.isPrimary).count, 1)
    }

    func testCycleSpawnsOneWorkerPerPerson() {
        let ctx = AriaCoachAgentRouter.Context(
            pinned: nil,
            cycleAvailable: true,
            cycleSubjects: ["Sam", "Maya"]
        )
        let plan = AriaCoachAgentRouter.plan(
            message: "how do I show up for them this week",
            context: ctx
        )
        let cycleWorkers = plan.workers.filter { $0.kind == .cycle }
        XCTAssertEqual(cycleWorkers.map(\.subject), ["Sam", "Maya"])
        XCTAssertEqual(cycleWorkers.filter(\.isPrimary).count, 1)
    }

    func testPinLeadsButDoesNotBlockOthers() {
        let ctx = AriaCoachAgentRouter.Context(pinned: .progress, cycleAvailable: false)
        let plan = AriaCoachAgentRouter.plan(
            message: "what should I train after I eat",
            context: ctx
        )
        XCTAssertEqual(plan.primary.kind, .progress)
        XCTAssertTrue(plan.kinds.contains(.workout))
        XCTAssertTrue(plan.kinds.contains(.lifestyle))
        XCTAssertTrue(plan.kinds.contains(.progress))
    }
}

final class AriaFirstHealthBriefingTests: XCTestCase {

    func testIdentityQuestions() {
        XCTAssertTrue(AriaFirstHealthBriefing.isIdentityQuestion("Who are you?"))
        XCTAssertTrue(AriaFirstHealthBriefing.isIdentityQuestion("what can you do"))
        XCTAssertTrue(AriaFirstHealthBriefing.isIdentityQuestion("What is ARIA?"))
        XCTAssertFalse(AriaFirstHealthBriefing.isIdentityQuestion("How did I sleep?"))
    }

    func testWelcomeCitesHealthAndSpecialists() {
        let snap = AriaFirstHealthBriefing.Snapshot(
            sleepHours: 7.2,
            sleepScore: 88,
            hrvMs: 52,
            restingHR: 58,
            readiness: 78,
            steps: 8400,
            lastWorkoutName: "Lower Body Strength",
            fromHealthKit: true
        )
        let result = AriaFirstHealthBriefing.welcome(
            name: "Ada",
            healthConnected: true,
            snapshot: snap
        )
        XCTAssertTrue(result.message.contains("Ada"))
        XCTAssertTrue(result.message.contains("Apple Health"))
        XCTAssertTrue(result.message.contains("7.2"))
        XCTAssertTrue(result.message.contains("HRV 52"))
        XCTAssertTrue(result.message.contains("Workout"))
        XCTAssertTrue(result.message.contains("Recovery"))
        XCTAssertTrue(result.actions.contains("Who are you?"))
        XCTAssertTrue(result.actions.contains("What should I train?"))
    }

    func testOnboardingLineIsFirstIntegration() {
        let snap = AriaFirstHealthBriefing.Snapshot(
            sleepHours: 7.2, sleepScore: 88, hrvMs: 52,
            restingHR: nil, readiness: nil, steps: nil,
            lastWorkoutName: nil, fromHealthKit: true
        )
        let line = AriaFirstHealthBriefing.onboardingConnectedLine(snapshot: snap)
        XCTAssertTrue(line.contains("first time"))
        XCTAssertTrue(line.contains("7.2"))
    }

    func testLearnInsightsComeFromHealthKit() {
        let empty = AriaFirstHealthBriefing.Snapshot(
            sleepHours: nil, sleepScore: nil, hrvMs: nil,
            restingHR: nil, readiness: nil, steps: nil,
            lastWorkoutName: nil, fromHealthKit: false
        )
        XCTAssertTrue(AriaFirstHealthBriefing.learnInsights(snapshot: empty).isEmpty)

        let live = AriaFirstHealthBriefing.Snapshot(
            sleepHours: 7.2, sleepScore: 88, hrvMs: 52,
            restingHR: nil, readiness: 78, steps: nil,
            lastWorkoutName: nil, fromHealthKit: true
        )
        let insights = AriaFirstHealthBriefing.learnInsights(snapshot: live)
        XCTAssertTrue(insights.contains { $0.contains("first connect") })
        XCTAssertTrue(insights.contains { $0.contains("HRV 52") })
    }
}

final class AriaFirstBondTests: XCTestCase {

    private var snap: AriaFirstHealthBriefing.Snapshot {
        AriaFirstHealthBriefing.Snapshot(
            sleepHours: 7.2, sleepScore: 88, hrvMs: 52,
            restingHR: 58, readiness: 78, steps: nil,
            lastWorkoutName: nil, fromHealthKit: true
        )
    }

    private func ctx(cycle: Bool = false) -> AriaFirstBond.Context {
        AriaFirstBond.Context(name: "Ada", snapshot: snap, goal: "Build muscle", cycleAvailable: cycle)
    }

    func testOpeningIsPersonalAndAsksToStay() {
        let turn = AriaFirstBond.start(ctx())
        XCTAssertTrue(turn.message.contains("Ada"))
        XCTAssertTrue(turn.message.contains("ARIA"))
        XCTAssertTrue(turn.message.contains("7.2"))
        XCTAssertTrue(turn.message.contains("Build muscle") || turn.message.contains("build muscle"))
        XCTAssertTrue(turn.replies.contains("I’m here."))
        XCTAssertEqual(turn.next, .opening)
        XCTAssertFalse(turn.finishes)
    }

    func testYesNoChecksAreSequentialAndDynamic() {
        let context = ctx(cycle: true)
        var turn = AriaFirstBond.advance(beat: .opening, userText: "I’m here.", context: context)
        XCTAssertTrue(turn.message.contains("not a doctor"))
        XCTAssertEqual(turn.replies, AriaFirstBond.yesNo)
        XCTAssertEqual(turn.next, .notDoctor)

        turn = AriaFirstBond.advance(beat: .notDoctor, userText: "Yes.", context: context)
        XCTAssertTrue(turn.message.contains("Apple Health"))
        XCTAssertEqual(turn.next, .health)

        turn = AriaFirstBond.advance(beat: .health, userText: "No.", context: context)
        XCTAssertTrue(turn.message.lowercased().contains("invent") || turn.message.contains("missing"))
        XCTAssertTrue(turn.message.contains("game") || turn.message.contains("XP"))
        XCTAssertEqual(turn.next, .notGame)

        turn = AriaFirstBond.advance(beat: .notGame, userText: "Not sure.", context: context)
        XCTAssertTrue(turn.message.contains("Cycle"))
        XCTAssertEqual(turn.next, .specialists)
    }

    func testCycleStaysOutWhenNotShared() {
        let turn = AriaFirstBond.advance(beat: .notGame, userText: "Yes.", context: ctx(cycle: false))
        XCTAssertTrue(turn.message.contains("Cycle stays out"))
    }

    func testWrongAnswerCorrectsThenContinues() {
        let turn = AriaFirstBond.advance(beat: .notDoctor, userText: "No.", context: ctx())
        XCTAssertTrue(turn.message.contains("won’t diagnose") || turn.message.contains("won't diagnose")
                      || turn.message.contains("not medical"))
        XCTAssertEqual(turn.next, .health)
    }

    func testLeaveEndsTheBond() {
        let turn = AriaFirstBond.advance(beat: .opening, userText: "Not now.", context: ctx())
        XCTAssertTrue(turn.finishes)
        XCTAssertTrue(turn.message.contains("ours"))
    }

    func testRealQuestionHandoffAfterChecks() {
        XCTAssertTrue(AriaFirstBond.shouldHandoffToCoach("How did I sleep?"))
        XCTAssertFalse(AriaFirstBond.shouldHandoffToCoach("Yes."))
        let turn = AriaFirstBond.advance(beat: .invite, userText: "How did I sleep?", context: ctx())
        XCTAssertTrue(turn.finishes)
        XCTAssertTrue(turn.message.isEmpty)
    }
}

final class ARIAChatHandoffTests: XCTestCase {

    func testTextPromptAutoSendsWithoutVoice() {
        let result = ARIAChatHandoff.consume(
            .init(pendingPrompt: "  How did I sleep?  ", voiceLaunch: false)
        )
        XCTAssertEqual(result.prompt, "How did I sleep?")
        XCTAssertFalse(result.startVoice)
        XCTAssertTrue(result.autoSend)
    }

    func testVoiceLaunchDoesNotAutoSend() {
        let result = ARIAChatHandoff.consume(
            .init(pendingPrompt: "Continue from today's briefing.", voiceLaunch: true)
        )
        XCTAssertEqual(result.prompt, "Continue from today's briefing.")
        XCTAssertTrue(result.startVoice)
        XCTAssertFalse(result.autoSend)
    }

    func testVoiceOnlyLaunchHasNoPrompt() {
        let result = ARIAChatHandoff.consume(.init(pendingPrompt: nil, voiceLaunch: true))
        XCTAssertNil(result.prompt)
        XCTAssertTrue(result.startVoice)
        XCTAssertFalse(result.autoSend)
    }

    func testBlankPromptIsIgnored() {
        let result = ARIAChatHandoff.consume(.init(pendingPrompt: "   ", voiceLaunch: false))
        XCTAssertNil(result.prompt)
        XCTAssertFalse(result.startVoice)
        XCTAssertFalse(result.autoSend)
    }

    func testLifeReadParsesPackTagsWithoutAFieldDump() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 8
        parts.day = 25
        parts.hour = 15
        let now = calendar.date(from: parts)!
        let pack = FakeHealthPack.generate(now: now, calendar: calendar, seed: 41, persona: "stressed")
        let tags = AppStore.lifestyleTags(from: pack)
        XCTAssertTrue(tags.contains("persona:stressed"))
        XCTAssertTrue(tags.contains { $0.hasPrefix("felt:") })
        XCTAssertTrue(tags.contains { $0.hasPrefix("story:") })

        let read = AriaLifeRead.from(tags: tags)
        XCTAssertEqual(read.persona, "stressed")
        XCTAssertEqual(read.felt, pack.today?.felt)
        XCTAssertEqual(read.story, pack.today?.storyLine)
        XCTAssertFalse(read.story?.contains("HRV") ?? true)
        var rng = AriaSeededRNG(seed: 7)
        XCTAssertEqual(read.spokenLine(rng: &rng), pack.today?.storyLine)
    }

    func testLifeReadLastNightFlags() {
        let read = AriaLifeRead.from(tags: [
            "lastnight:drinks",
            "lastnight:drinks:4",
            "lastnight:late",
            "story:Drinks with mates ran late — the night after is still paying for it.",
        ])
        XCTAssertEqual(read.lastNightKind, "drinks")
        XCTAssertEqual(read.lastNightDrinks, 4)
        XCTAssertTrue(read.lastNightLate)
        XCTAssertTrue(read.hasEvening)
        XCTAssertTrue(read.story?.contains("Drinks with mates") ?? false)
    }
}
