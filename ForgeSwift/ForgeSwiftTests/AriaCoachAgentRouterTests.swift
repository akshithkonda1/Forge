import XCTest
@testable import ForgeSwift

final class AriaCoachAgentRouterTests: XCTestCase {

    func testPinnedAgentWins() {
        let ctx = AriaCoachAgentRouter.Context(pinned: .fuel, cycleAvailable: false)
        XCTAssertEqual(
            AriaCoachAgentRouter.resolve(message: "what should I train today?", context: ctx),
            .fuel
        )
    }

    func testSleepQuestionRoutesToRecover() {
        let ctx = AriaCoachAgentRouter.Context(pinned: nil, cycleAvailable: false)
        XCTAssertEqual(
            AriaCoachAgentRouter.resolve(message: "How did I sleep last night?", context: ctx),
            .recover
        )
    }

    func testWorkoutQuestionRoutesToTrain() {
        let ctx = AriaCoachAgentRouter.Context(pinned: nil, cycleAvailable: false)
        XCTAssertEqual(
            AriaCoachAgentRouter.resolve(message: "What should I train today?", context: ctx),
            .train
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
        XCTAssertTrue(kinds.contains(.recover))
        XCTAssertTrue(kinds.contains(.train))
        XCTAssertTrue(kinds.contains(.fuel))
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
        let ctx = AriaCoachAgentRouter.Context(pinned: .fuel, cycleAvailable: false)
        let plan = AriaCoachAgentRouter.plan(
            message: "what should I train after I eat",
            context: ctx
        )
        XCTAssertEqual(plan.primary.kind, .fuel)
        XCTAssertTrue(plan.kinds.contains(.train))
        XCTAssertTrue(plan.kinds.contains(.fuel))
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
        XCTAssertTrue(result.message.contains("Train"))
        XCTAssertTrue(result.message.contains("Recover"))
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

final class AriaUseOnboardingTests: XCTestCase {

    func testGuideHasFiveStepsAndATryPrompt() {
        let snap = AriaFirstHealthBriefing.Snapshot(
            sleepHours: 7.2, sleepScore: 88, hrvMs: 52,
            restingHR: 58, readiness: 78, steps: nil,
            lastWorkoutName: nil, fromHealthKit: true
        )
        let pages = AriaUseOnboarding.pages(name: "Ada", snapshot: snap)
        XCTAssertEqual(pages.map(\.step), AriaUseOnboardingStep.allCases)
        XCTAssertTrue(pages[0].title.contains("Ada"))
        XCTAssertTrue(pages[1].body.contains("How did I sleep"))
        XCTAssertTrue(pages[2].body.contains("Train"))
        XCTAssertTrue(pages[3].body.contains("7.2"))
        XCTAssertEqual(pages.last?.step, .tryIt)
        XCTAssertTrue(AriaUseOnboarding.tryPrompts.contains("What should I train?"))
    }

    func testHealthPageWithoutSignalsStillTeachesConnect() {
        let snap = AriaFirstHealthBriefing.Snapshot(
            sleepHours: nil, sleepScore: nil, hrvMs: nil,
            restingHR: nil, readiness: nil, steps: nil,
            lastWorkoutName: nil, fromHealthKit: false
        )
        let health = AriaUseOnboarding.pages(name: "", snapshot: snap)
            .first { $0.step == .health }
        XCTAssertTrue(health?.body.contains("Connect Apple Health") == true)
    }
}
