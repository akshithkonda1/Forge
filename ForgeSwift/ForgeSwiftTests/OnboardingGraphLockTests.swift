import XCTest
@testable import ForgeSwift

/// App-side lock for the #168 graph. Same shape as AriaCoachAgentRouterTests:
/// XCTest against the types the coordinator actually uses, no UI harness.
/// The Linux-runnable twin is ForgeCoreTests/OnboardingGraphTests.swift —
/// this target cannot compile on Linux (HealthKit / SwiftUI app).
final class OnboardingGraphLockTests: XCTestCase {

    func testSleepRhythmBandIsIrregularNotInconsistent() {
        XCTAssertEqual(
            Set(SleepRhythmBand.allCases.map(\.rawValue)),
            ["earlyBird", "average", "nightOwl", "irregular"]
        )
        XCTAssertNil(SleepRhythmBand(rawValue: "inconsistent"))
        XCTAssertNotNil(SleepRhythmBand(rawValue: "irregular"))
        XCTAssertEqual(SleepRhythmBand.irregular.rawValue, "irregular")
    }

    @MainActor
    func testHeaderProgressUsesActiveStepsNotAllCases() {
        let coordinator = OnboardingCoordinator()
        coordinator.step = .ready
        XCTAssertEqual(coordinator.progress, 1.0)
        XCTAssertEqual(coordinator.progressStepIndex, 12)
        XCTAssertEqual(coordinator.progressStepCount, 12)
        XCTAssertNotEqual(coordinator.progressStepCount, AriaInterviewStep.allCases.count)

        // allCases still lists trainingTheme + lifeContext, so Ready would be 11/13.
        let allCasesReady = Double(AriaInterviewStep.ready.rawValue)
            / Double(max(1, AriaInterviewStep.allCases.count - 1))
        XCTAssertNotEqual(coordinator.progress, allCasesReady)

        coordinator.step = .intro
        XCTAssertEqual(coordinator.progress, 0)
        XCTAssertEqual(coordinator.progressStepIndex, 1)

        coordinator.step = .freeTime
        XCTAssertEqual(coordinator.progressStepIndex, 9)
        XCTAssertEqual(coordinator.progressStepCount, 12)

        let active: [AriaInterviewStep] = [
            .intro, .name, .health, .details, .goals, .experience,
            .workouts, .sleep, .freeTime, .coaching, .conditions, .ready,
        ]
        var last = -1.0
        for step in active {
            coordinator.step = step
            XCTAssertGreaterThan(coordinator.progress, last)
            last = coordinator.progress
        }
        XCTAssertEqual(last, 1.0)
    }

    @MainActor
    func testCompleteIsNoOpUnlessCanFinishAndTerms() {
        let coordinator = OnboardingCoordinator()
        XCTAssertFalse(coordinator.hasAgreedToTerms)
        XCTAssertFalse(coordinator.canFinish)

        coordinator.hasAgreedToTerms = true
        XCTAssertFalse(
            coordinator.canFinish,
            "terms alone are not enough — name, details, goals, workouts still required"
        )
    }
}
