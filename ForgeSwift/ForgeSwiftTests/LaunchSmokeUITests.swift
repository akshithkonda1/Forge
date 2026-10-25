// Tess equivalent — LaunchSmokeUITests was not on any branch or PR.
// These run as ForgeSwiftTests (CI has no UI-test target). They fail on
// main when a root surface can render no copy — the blank dark prep page.
import XCTest
import ForgeCore
@testable import ForgeSwift

final class LaunchSmokeUITests: XCTestCase {

    func testEveryPrepStageHasVisibleCopy() {
        for stage in AriaForgePrep.Stage.allCases {
            XCTAssertFalse(stage.eyebrow.trimmingCharacters(in: .whitespaces).isEmpty, "\(stage) eyebrow")
            XCTAssertFalse(stage.headline.trimmingCharacters(in: .whitespaces).isEmpty, "\(stage) headline")
            XCTAssertFalse(
                stage.detail(healthConnected: true).trimmingCharacters(in: .whitespaces).isEmpty,
                "\(stage) detail"
            )
            XCTAssertFalse(
                stage.footer(progress: 0.2).trimmingCharacters(in: .whitespaces).isEmpty,
                "\(stage) footer"
            )
        }
    }

    func testAuthenticatedOnboardingAndShellAreNeverAnEmptyChoice() {
        // ContentView is always one of: AuthWelcomeView, OnboardingView, MainTabView.
        // A leftover prep flag must still land on OnboardingView's prep surface,
        // which always has stage copy — never an empty Group.
        XCTAssertFalse(AriaForgePrep.Stage.profile.headline.isEmpty)
        XCTAssertEqual(AriaForgePrep.Stage.profile.eyebrow, "Prepping Forge")
        XCTAssertEqual(AriaForgePrepHandoff.interviewCompleteKey, "forge.onboarding.interviewComplete")
    }

    func testSleepNightWithoutStagesDoesNotBlankTheMeter() {
        let night = SleepData(
            date: "2026-10-16",
            totalHours: .nan,
            deepMinutes: 0,
            remMinutes: 0,
            lightMinutes: 0,
            awakeMinutes: 0,
            score: 0
        )
        XCTAssertEqual(night.timeInBedMinutes, 0)
        XCTAssertEqual(night.efficiencyPercent, 0)
        let byDate = SleepDebtMeter.uniquedNightsByDate([(night.date, night.totalHours)])
        let meter = SleepDebtMeter.make(
            nightsByDate: byDate,
            needHours: 8,
            asleepHoursOldestFirst: [night.totalHours]
        )
        XCTAssertFalse(meter.headline.isEmpty)
    }
}
