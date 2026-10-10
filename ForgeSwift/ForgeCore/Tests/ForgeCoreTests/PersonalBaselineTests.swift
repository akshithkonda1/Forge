import XCTest
@testable import ForgeCore

final class PersonalBaselineTests: XCTestCase {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    /// Noon on 2026-10-10 UTC, minus `daysAgo`, at `hour`.
    private func at(daysAgo: Int, hour: Int) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: hour))!
        return calendar.date(byAdding: .day, value: -daysAgo, to: base)!
    }

    func testNeedsFiveRealDays() {
        XCTAssertNil(PersonalBaseline.fromDailyValues([50, 52, 0, 48], logScaled: true))
        XCTAssertNotNil(PersonalBaseline.fromDailyValues([40, 50, 60, 50, 50], logScaled: true))
    }

    func testLogScaledKeepsGeometricMeanAndLnSpread() {
        let base = PersonalBaseline.fromDailyValues([40, 50, 60, 50, 50], logScaled: true)!
        XCTAssertEqual(base.days, 5)
        XCTAssertLessThanOrEqual(base.mean, 50)
        XCTAssertGreaterThan(base.spread, 0)
        XCTAssertLessThan(base.spread, 1, "spread is in ln units, not ms")
    }

    func testLinearMatchesPython() {
        // Same vector as test_personal_baseline_linear in Python.
        let base = PersonalBaseline.fromDailyValues([54, 55, 56, 55, 55], logScaled: false)!
        XCTAssertEqual(base.mean, 55, accuracy: 1e-9)
        XCTAssertEqual(base.spread, (2.0 / 4.0).squareRoot(), accuracy: 1e-9)
    }

    func testBusyDayDoesNotOutvoteQuietDay() {
        var samples: [PersonalBaseline.Sample] = []
        // Day 1: twelve readings of 30. Days 2-5: one reading of 60 each.
        for i in 0..<12 { samples.append(.init(date: at(daysAgo: 1, hour: 1 + i % 6), value: 30)) }
        for d in 2...5 { samples.append(.init(date: at(daysAgo: d, hour: 3), value: 60)) }
        let base = PersonalBaseline.daily(samples: samples, logScaled: false, calendar: calendar)!
        XCTAssertEqual(base.days, 5)
        XCTAssertEqual(base.mean, (30 + 4 * 60) / 5.0, accuracy: 1e-9)
    }

    func testTodayIsLeftOut() {
        var samples: [PersonalBaseline.Sample] = []
        for d in 1...5 { samples.append(.init(date: at(daysAgo: d, hour: 3), value: 50)) }
        samples.append(.init(date: at(daysAgo: 0, hour: 3), value: 10))
        let base = PersonalBaseline.daily(
            samples: samples, logScaled: true, excluding: at(daysAgo: 0, hour: 12), calendar: calendar
        )!
        XCTAssertEqual(base.days, 5)
        XCTAssertEqual(base.mean, 50, accuracy: 1e-9)
    }

    func testPrefersOvernightReadingsWhenThereAreEnough() {
        var samples: [PersonalBaseline.Sample] = []
        for d in 1...6 {
            samples.append(.init(date: at(daysAgo: d, hour: 3), value: 60))   // night
            samples.append(.init(date: at(daysAgo: d, hour: 15), value: 30))  // afternoon
        }
        let night = PersonalBaseline.daily(samples: samples, logScaled: true, preferNight: true, calendar: calendar)!
        XCTAssertEqual(night.mean, 60, accuracy: 1e-9)
        let all = PersonalBaseline.daily(samples: samples, logScaled: true, preferNight: false, calendar: calendar)!
        XCTAssertLessThan(all.mean, 60)
    }

    func testLateEveningBelongsToNextMorning() {
        // 23:00 on day 2 and 03:00 on day 1 are the same night.
        let samples: [PersonalBaseline.Sample] = [
            .init(date: at(daysAgo: 2, hour: 23), value: 40),
            .init(date: at(daysAgo: 1, hour: 3), value: 40),
        ]
        let base = PersonalBaseline.daily(samples: samples, logScaled: false, minimumDays: 1, calendar: calendar)
        XCTAssertNil(base, "one night is one day; two are needed for a spread")
    }

    func testWindowMean() {
        let samples: [PersonalBaseline.Sample] = [
            .init(date: at(daysAgo: 0, hour: 1), value: 40),
            .init(date: at(daysAgo: 0, hour: 4), value: 90),
            .init(date: at(daysAgo: 0, hour: 15), value: 10),
        ]
        let window = DateInterval(start: at(daysAgo: 0, hour: 0), end: at(daysAgo: 0, hour: 7))
        let mean = PersonalBaseline.windowMean(samples: samples, in: window, logScaled: true)!
        XCTAssertEqual(mean, (40.0 * 90.0).squareRoot(), accuracy: 1e-9)
        let empty = DateInterval(start: at(daysAgo: 0, hour: 8), end: at(daysAgo: 0, hour: 9))
        XCTAssertNil(PersonalBaseline.windowMean(samples: samples, in: empty, logScaled: true))
    }

    func testZScoreClampsSpread() {
        let tight = PersonalBaseline(mean: 50, spread: 0.001, days: 10, logScaled: true)
        let z = tight.zScore(49, floor: 0.08, ceiling: 0.6)!
        XCTAssertEqual(z, log(49.0 / 50.0) / 0.08, accuracy: 1e-9)
        XCTAssertNil(tight.zScore(0, floor: 0.08, ceiling: 0.6))
    }
}
