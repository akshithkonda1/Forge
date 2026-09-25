import XCTest
@testable import ForgeCore

final class HomeReduceMotionTests: XCTestCase {

    func testReduceMotionFreezesRingFieldAndChart() {
        XCTAssertTrue(HomeTrendMath.isFrozen(reduceMotion: true, minimal: false))
        XCTAssertTrue(HomeTrendMath.isFrozen(reduceMotion: false, minimal: true))
        XCTAssertTrue(HomeTrendMath.isFrozen(reduceMotion: true, minimal: true))
        XCTAssertFalse(HomeTrendMath.isFrozen(reduceMotion: false, minimal: false))

        XCTAssertEqual(HomeTrendMath.plottedScore(70, grown: false, reduceMotion: true), 70)
        XCTAssertEqual(HomeTrendMath.plottedScore(30, grown: false, reduceMotion: true), 30)
        XCTAssertEqual(HomeTrendMath.plottedScore(70, grown: false, reduceMotion: false), 0)
        XCTAssertEqual(HomeTrendMath.plottedScore(70, grown: true, reduceMotion: false), 70)
        XCTAssertEqual(HomeTrendMath.plottedScore(70, grown: true, reduceMotion: true), 70)
    }

    func testHomeTrendChartRuleMarkUsesRawAverage() {
        let raw = [10, 90, 100]
        XCTAssertEqual(HomeTrendMath.clampedPlotScore(10), 30, "the 10 bar still plots at the 30 floor")
        XCTAssertEqual(raw.map(HomeTrendMath.clampedPlotScore), [30, 90, 100])
        XCTAssertEqual(HomeTrendMath.ruleMarkY(raw), 66)
        XCTAssertNotEqual(HomeTrendMath.ruleMarkY(raw), 73)
        let flooredAverage = raw.map(HomeTrendMath.clampedPlotScore).reduce(0, +) / raw.count
        XCTAssertEqual(flooredAverage, 73)
        XCTAssertNotEqual(HomeTrendMath.ruleMarkY(raw), flooredAverage)
    }

    func testHomeTrendPointLabelsNameWeekdayFriToThu() {
        var chicago = Calendar(identifier: .gregorian)
        chicago.timeZone = TimeZone(identifier: "America/Chicago")!
        let locale = Locale(identifier: "en_US_POSIX")
        let days = (18...24).map { day -> Date in
            chicago.date(from: DateComponents(year: 2026, month: 9, day: day))!
        }
        let weekdays = days.map { HomeTrendMath.weekdayLabel(for: $0, calendar: chicago, locale: locale) }
        XCTAssertEqual(weekdays, ["Fri", "Sat", "Sun", "Mon", "Tue", "Wed", "Thu"])
    }
}
