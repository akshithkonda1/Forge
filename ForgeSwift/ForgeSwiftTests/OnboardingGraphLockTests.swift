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

        // The app-side trainingTheme/lifeContext legacy cases are gone (deleted
        // with their now-unreachable interview screens), so allCases and the
        // graph's activeSteps agree on count. OnboardingGraph.Step (ForgeCore)
        // still carries the two legacy cases for migration -- see
        // OnboardingGraphTests.swift for that half of the lock.
        XCTAssertEqual(AriaInterviewStep.allCases.count, 12)

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

    @MainActor
    func testGoBackWalksActiveStepsWithoutReenteringIntro() {
        let coordinator = OnboardingCoordinator()
        coordinator.step = .name
        XCTAssertFalse(coordinator.canGoBack)

        coordinator.step = .health
        XCTAssertTrue(coordinator.canGoBack)
        coordinator.goBack()
        XCTAssertEqual(coordinator.step, .name)

        coordinator.step = .ready
        coordinator.goBack()
        XCTAssertEqual(coordinator.step, .conditions)

        coordinator.step = .coaching
        coordinator.goBack()
        XCTAssertEqual(coordinator.step, .freeTime)

        coordinator.isCompleting = true
        coordinator.step = .ready
        XCTAssertFalse(coordinator.canGoBack)
        coordinator.goBack()
        XCTAssertEqual(coordinator.step, .ready)
    }

    func testOnboardingBotSaysOneLinePerTurn() {
        var profile = OnboardingProfile()
        profile.name = "Sam"
        profile.fitnessGoals = [.buildMuscle]
        profile.experienceLevel = .intermediate
        profile.coachingStyle = .balanced

        let bot = OnboardingAriaBot()
        let opening = bot.opening(profile: profile, health: nil, healthConnected: false)
        XCTAssertEqual(opening.messages.count, 1)
        XCTAssertTrue(opening.messages[0].contains("Sam"))
        XCTAssertFalse(opening.messages[0].contains("VO₂"))
        XCTAssertFalse(opening.messages[0].contains("HRV"))

        let days = bot.reply(step: 0, input: "4–5 days", answers: [], profile: profile)
        XCTAssertEqual(days.messages.count, 1)
        XCTAssertEqual(days.tags, ["weekly_days:4–5_days"])

        let energy = bot.reply(step: 1, input: "Mornings", answers: ["4–5 days"], profile: profile)
        XCTAssertEqual(energy.messages.count, 1)

        let done = bot.reply(step: 2, input: "Time", answers: ["4–5 days", "Mornings"], profile: profile)
        XCTAssertTrue(done.finished)
        XCTAssertEqual(done.messages.count, 1)
        XCTAssertTrue(done.messages[0].contains("tight"))
    }

    func testWelcomeHookSaysLearningNotListening() {
        XCTAssertEqual(AriaOnboardingGuide.welcomeTitle, "ARIA is already learning.")
        XCTAssertFalse(AriaOnboardingGuide.welcomeTitle.localizedCaseInsensitiveContains("listening"))
    }
}
