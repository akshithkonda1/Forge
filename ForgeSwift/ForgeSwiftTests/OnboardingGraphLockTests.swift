import XCTest
import ForgeCore
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
        XCTAssertEqual(coordinator.progressStepIndex, 6)
        XCTAssertEqual(coordinator.progressStepCount, 6)

        // App-side interview still lists the leftover cases; the header counts
        // the six friend-first beats from OnboardingGraph.activeSteps.
        XCTAssertEqual(AriaInterviewStep.allCases.count, 13)
        XCTAssertEqual(OnboardingGraph.activeSteps.count, 6)

        coordinator.step = .intro
        XCTAssertEqual(coordinator.progress, 0)
        XCTAssertEqual(coordinator.progressStepIndex, 1)

        coordinator.step = .freeTime
        XCTAssertEqual(coordinator.progressStepIndex, 4)
        XCTAssertEqual(coordinator.progressStepCount, 6)

        let active: [AriaInterviewStep] = [
            .intro, .name, .health, .freeTime, .coaching, .ready,
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
            "terms alone are not enough — preferred name is still required"
        )
        coordinator.profile.name = "Maya"
        XCTAssertTrue(coordinator.canFinish)
    }

    @MainActor
    func testGoBackWalksActiveStepsWithoutReenteringIntro() {
        let coordinator = OnboardingCoordinator()
        coordinator.step = .name
        XCTAssertFalse(coordinator.canGoBack)

        coordinator.step = .health
        XCTAssertTrue(coordinator.canGoBack)
        coordinator.goBack()
        XCTAssertEqual(coordinator.step, .name)

        coordinator.step = .sleep
        coordinator.goBack()
        XCTAssertEqual(coordinator.step, .health)

        coordinator.step = .ready
        coordinator.goBack()
        XCTAssertEqual(coordinator.step, .coaching)

        coordinator.step = .coaching
        coordinator.goBack()
        XCTAssertEqual(coordinator.step, .freeTime)

        coordinator.step = .freeTime
        coordinator.goBack()
        XCTAssertEqual(coordinator.step, .health)

        coordinator.isCompleting = true
        coordinator.step = .ready
        XCTAssertFalse(coordinator.canGoBack)
        coordinator.goBack()
        XCTAssertEqual(coordinator.step, .ready)

        coordinator.isCompleting = false
        coordinator.isPrepping = true
        coordinator.isCompleting = true
        XCTAssertFalse(coordinator.canFinish)
        XCTAssertFalse(coordinator.canGoBack)
    }

    func testWelcomeHookSaysARIANotListening() {
        XCTAssertEqual(AriaOnboardingGuide.welcomeTitle, "Hey — I'm ARIA.")
        XCTAssertFalse(AriaOnboardingGuide.welcomeTitle.localizedCaseInsensitiveContains("listening"))
        XCTAssertTrue(AriaOnboardingGuide.welcomeSpokenLine.contains("ARIA"))
        XCTAssertFalse(AriaOnboardingGuide.welcomeSpokenLine.contains("I'm Aria"))
        XCTAssertFalse(AriaOnboardingGuide.welcomeSpokenLine.isEmpty)
    }
}
