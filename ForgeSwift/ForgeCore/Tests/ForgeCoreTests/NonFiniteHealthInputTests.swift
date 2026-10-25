// Tess's draft NonFiniteHealthInputTests — compiled and run here.
// Int(Double) traps on NaN / ±inf / out-of-range. HealthKit and third-party
// sources feed these. A failing case here CRASHES the test host (no soft
// failure) — that is the signal.
//
// Dropped from the draft: `testCognitoSignUpRequestWithMalformedRegionThrowsNotTraps`.
// That case is out of scope for this sweep (auth URL construction, not
// HealthKit-derived Int(Double)), and Tess marked it UNCERTAIN on iOS 17+.
import XCTest
@testable import ForgeCore

final class NonFiniteHealthInputTests: XCTestCase {
    // SleepMorningSummary.swift:224-225 — guard catches NaN (NaN > 0.15 is false) but NOT +inf.
    func testPaybackWithInfiniteStretchDoesNotTrap() {
        let r = SleepDebtMeter.payback(stretchHours: .infinity)   // EXPECTED CRASH on main: Int(inf)
        XCTAssertGreaterThanOrEqual(r.nights, 1)
    }
    func testPaybackWithNaN() {
        XCTAssertEqual(SleepDebtMeter.payback(stretchHours: .nan).nights, 0)
    }
    // SleepPublishedScore.breakdown, SleepMorningSummary.swift:146-152 — clamp makes NaN→0 via max(0,NaN); expected pass.
    func testBreakdownWithNaNHours() {
        _ = SleepPublishedScore.breakdown(asleepHours: .nan, needHours: .nan, consistency: .nan, awakeMinutes: .nan)
    }
    // SleepMorningSummary.swift:209-213
    func testStretchHoursWithEmptyAndNaN() {
        XCTAssertEqual(SleepDebtMeter.stretchHours(asleepHoursOldestFirst: [], needHours: 8), 0)
        XCTAssertTrue(SleepDebtMeter.stretchHours(asleepHoursOldestFirst: [.nan], needHours: 8).isNaN == false,
                      "NaN night leaks into the stretch and later into Int(...)")
    }

    func testMinutesFromHoursRejectsNonFinite() {
        XCTAssertEqual(SleepDebtMeter.minutesFromHours(.nan), 0)
        XCTAssertEqual(SleepDebtMeter.minutesFromHours(.infinity), 0)
        XCTAssertEqual(SleepDebtMeter.minutesFromHours(-.infinity), 0)
        XCTAssertEqual(SleepDebtMeter.minutesFromHours(7.5), 450)
        XCTAssertEqual(SleepDebtMeter.hoursLabel(.nan), "0h")
        XCTAssertEqual(SleepDebtMeter.hoursLabel(.infinity), "0h")
    }
}
