import XCTest
@testable import ForgeCore

/// Widgets cannot tell "no night" from a real zero because `sleepHours` is a
/// non-optional Double. These tests pin the empty-vs-hours rule so Sleep and
/// Today never print `"0.0h"` after onboarding writes the empty sentinel.
final class HomeWidgetSleepDisplayTests: XCTestCase {

    func testEmptySentinelHasNothingToShow() {
        XCTAssertFalse(HomeWidgetSleepDisplay.hasHoursToShow(0))
        XCTAssertFalse(HomeWidgetSleepDisplay.hasSleepToShow(sleepHours: 0, sleepScore: nil))
        XCTAssertFalse(HomeWidgetSleepDisplay.hasSleepToShow(HomeWidgetSnapshot()))
    }

    func testNegativeHoursAreNotANight() {
        XCTAssertFalse(HomeWidgetSleepDisplay.hasHoursToShow(-1))
        XCTAssertFalse(HomeWidgetSleepDisplay.hasSleepToShow(sleepHours: -0.4, sleepScore: nil))
    }

    func testPositiveHoursCountAsANightEvenWithoutScore() {
        XCTAssertTrue(HomeWidgetSleepDisplay.hasHoursToShow(7.4))
        XCTAssertTrue(HomeWidgetSleepDisplay.hasSleepToShow(sleepHours: 7.4, sleepScore: nil))
        XCTAssertTrue(HomeWidgetSleepDisplay.hasHoursToShow(0.1))
    }

    func testScoreOnlyIsANightButDoesNotPrintZeroHours() {
        XCTAssertTrue(HomeWidgetSleepDisplay.hasSleepToShow(sleepHours: 0, sleepScore: 88))
        XCTAssertFalse(HomeWidgetSleepDisplay.hasHoursToShow(0))
        XCTAssertEqual(
            HomeWidgetSleepDisplay.hoursText(0, style: .compact),
            HomeWidgetSleepDisplay.emptyCopy
        )
    }

    func testPreviewSnapshotHasSleepToShow() {
        XCTAssertTrue(HomeWidgetSleepDisplay.hasSleepToShow(.preview))
        XCTAssertEqual(
            HomeWidgetSleepDisplay.hoursText(.preview, style: .compact),
            "7.4h"
        )
    }

    func testHoursStylesMatchWidgetFamilies() {
        XCTAssertEqual(HomeWidgetSleepDisplay.hoursText(7.4, style: .compact), "7.4h")
        XCTAssertEqual(HomeWidgetSleepDisplay.hoursText(7.4, style: .lastNight), "7.4 h last night")
        XCTAssertEqual(HomeWidgetSleepDisplay.hoursText(7.4, style: .number), "7.4")
        XCTAssertEqual(HomeWidgetSleepDisplay.hoursText(7.4, style: .hoursSleep), "7.4 h sleep")
    }

    func testEveryHoursStyleUsesEmptyCopyWhenHoursAreMissing() {
        for style: HomeWidgetSleepDisplay.HoursStyle in [.compact, .lastNight, .number, .hoursSleep] {
            XCTAssertEqual(
                HomeWidgetSleepDisplay.hoursText(0, style: style),
                "No sleep yet"
            )
        }
        XCTAssertEqual(HomeWidgetSleepDisplay.emptyCopy, "No sleep yet")
        let copy = HomeWidgetSleepDisplay.emptyCopy.lowercased()
        XCTAssertFalse(copy.contains("denied"))
        XCTAssertFalse(copy.contains("healthkit"))
        XCTAssertFalse(copy.contains("apnea"))
        XCTAssertFalse(copy.contains("insomnia"))
    }
}
