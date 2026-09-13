import XCTest
@testable import ForgeCore

/// Locks the #168 onboarding graph. The app coordinator cannot compile here
/// (MainActor / HealthKit / SwiftUI); this is the piece Linux `swift test` runs.
final class OnboardingGraphTests: XCTestCase {

    func testConfirmInterestsGoesToCoaching() {
        XCTAssertEqual(OnboardingGraph.next(after: .confirmInterests), .coaching)
    }

    func testSelectCoachingStyleGoesToReady() {
        XCTAssertEqual(OnboardingGraph.next(after: .selectCoachingStyle), .ready)
        XCTAssertNotEqual(OnboardingGraph.next(after: .selectCoachingStyle), .conditions)
    }

    func testConfirmConditionsGoesToReadyNeverCoaching() {
        XCTAssertEqual(OnboardingGraph.next(after: .confirmConditions), .ready)
        XCTAssertNotEqual(OnboardingGraph.next(after: .confirmConditions), .coaching)
    }

    func testSleepBandIsIrregularNotInconsistent() {
        XCTAssertEqual(
            Set(OnboardingGraph.SleepBand.allCases.map(\.rawValue)),
            ["earlyBird", "average", "nightOwl", "irregular"]
        )
        XCTAssertNil(OnboardingGraph.SleepBand(rawValue: "inconsistent"))
        XCTAssertEqual(OnboardingGraph.SleepBand(rawValue: "irregular"), .irregular)
    }

    func testSleepVarianceSeedsNightOwlAndIrregularOnly() {
        XCTAssertTrue(OnboardingGraph.seedsSleepVariance(.nightOwl))
        XCTAssertTrue(OnboardingGraph.seedsSleepVariance(.irregular))
        XCTAssertTrue(OnboardingGraph.seedsSleepVariance(bandRawValue: "nightOwl"))
        XCTAssertTrue(OnboardingGraph.seedsSleepVariance(bandRawValue: "irregular"))
        XCTAssertFalse(OnboardingGraph.seedsSleepVariance(.earlyBird))
        XCTAssertFalse(OnboardingGraph.seedsSleepVariance(.average))
        XCTAssertFalse(OnboardingGraph.seedsSleepVariance(bandRawValue: "inconsistent"))
        XCTAssertEqual(OnboardingGraph.sleepVarianceHabitId, "sleep_variance")
    }

    func testCompleteIsNoOpUnlessCanFinishAndTerms() {
        XCTAssertTrue(OnboardingGraph.allowsFinish(canFinish: true, hasAgreedToTerms: true))
        XCTAssertFalse(OnboardingGraph.allowsFinish(canFinish: true, hasAgreedToTerms: false))
        XCTAssertFalse(OnboardingGraph.allowsFinish(canFinish: false, hasAgreedToTerms: true))
        XCTAssertFalse(OnboardingGraph.allowsFinish(canFinish: false, hasAgreedToTerms: false))
    }

    func testHeaderProgressUsesSixFriendBeats() {
        XCTAssertEqual(OnboardingGraph.activeSteps, [
            .intro, .name, .health, .freeTime, .coaching, .ready,
        ])
        XCTAssertEqual(OnboardingGraph.activeSteps.count, 6)
        XCTAssertEqual(OnboardingGraph.Step.allCases.count, 15)
        XCTAssertFalse(OnboardingGraph.activeSteps.contains(.trainingTheme))
        XCTAssertFalse(OnboardingGraph.activeSteps.contains(.lifeContext))
        XCTAssertFalse(OnboardingGraph.activeSteps.contains(.schedule))
        XCTAssertFalse(OnboardingGraph.activeSteps.contains(.conditions))
        XCTAssertEqual(OnboardingGraph.displayCount, OnboardingGraph.activeSteps.count)
        XCTAssertNotEqual(OnboardingGraph.displayCount, OnboardingGraph.Step.allCases.count)

        XCTAssertEqual(OnboardingGraph.progress(at: .intro), 0)
        XCTAssertEqual(OnboardingGraph.progress(at: .ready), 1)
        XCTAssertEqual(OnboardingGraph.displayIndex(for: .ready), 6)
        XCTAssertEqual(OnboardingGraph.displayIndex(for: .freeTime), 4)
        XCTAssertEqual(OnboardingGraph.displayIndex(for: .health), 3)
        XCTAssertEqual(OnboardingGraph.normalized(.schedule), .freeTime)
        XCTAssertEqual(OnboardingGraph.normalized(.details), .health)
        XCTAssertEqual(OnboardingGraph.normalized(.conditions), .coaching)
        XCTAssertEqual(OnboardingGraph.displayIndex(for: .schedule), 4)

        // allCases would leave Ready short of a full bar (legacy screens).
        let allCasesReady = Double(OnboardingGraph.Step.allCases.firstIndex(of: .ready)!)
            / Double(OnboardingGraph.Step.allCases.count - 1)
        XCTAssertNotEqual(OnboardingGraph.progress(at: .ready), allCasesReady)
    }

    func testPreviousWalksSixBeatsAndSkipsIntro() {
        XCTAssertNil(OnboardingGraph.previous(of: .intro))
        XCTAssertNil(OnboardingGraph.previous(of: .name))
        XCTAssertEqual(OnboardingGraph.previous(of: .health), .name)
        XCTAssertEqual(OnboardingGraph.previous(of: .freeTime), .health)
        XCTAssertEqual(OnboardingGraph.previous(of: .coaching), .freeTime)
        XCTAssertEqual(OnboardingGraph.previous(of: .ready), .coaching)
        XCTAssertEqual(OnboardingGraph.previous(of: .schedule), .health)
        XCTAssertEqual(OnboardingGraph.previous(of: .conditions), .freeTime)
        XCTAssertEqual(OnboardingGraph.previous(of: .trainingTheme), .health)
        XCTAssertEqual(OnboardingGraph.previous(of: .lifeContext), .health)
        XCTAssertEqual(OnboardingGraph.previous(of: .details), .name)
    }
}
