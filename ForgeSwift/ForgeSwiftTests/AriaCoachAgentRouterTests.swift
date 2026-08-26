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
