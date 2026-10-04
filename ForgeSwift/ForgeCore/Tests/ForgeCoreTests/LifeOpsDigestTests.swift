import XCTest
@testable import ForgeCore

final class LifeOpsDigestTests: XCTestCase {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 15))!
    }

    private func day(_ offset: Int, hour: Int = 10) -> Date {
        let start = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: offset, to: start)!
            .addingTimeInterval(TimeInterval(hour * 3600))
    }

    private func asset(
        kind: FakeCalendarEvent.Kind,
        days: Int,
        title: String,
        isInterview: Bool = false
    ) -> LifestyleAsset {
        let start = day(days)
        return LifestyleAsset(
            kind: kind,
            start: start,
            end: start.addingTimeInterval(3600),
            isAllDay: false,
            daysUntil: days,
            source: .memory,
            title: title,
            placeName: "Secret venue that must never leak",
            isInterview: isInterview
        )
    }

    func testFarTripIsKnownWithoutMakingLoadHeavy() throws {
        let assets = [asset(kind: .travel, days: 60, title: "Stay at citizenM Chicago Downtown")]
        let digest = LifeOpsDigest.build(
            assets: assets,
            reminders: nil,
            busyToday: 0,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(digest.travelDaysUntil, 60)
        XCTAssertEqual(digest.load, .quiet)
        XCTAssertFalse(digest.isQuiet)
        XCTAssertEqual(digest.ariaTags, ["life_ops:load:quiet", "life_ops:travel:d60"])
        let spoken = try XCTUnwrap(digest.spokenLine)
        XCTAssertTrue(spoken.contains("60 days"))
        XCTAssertTrue(spoken.localizedCaseInsensitiveContains("no need to change"))
        XCTAssertFalse(spoken.localizedCaseInsensitiveContains("citizenM"))
        XCTAssertFalse(spoken.localizedCaseInsensitiveContains("Chicago"))
        XCTAssertFalse(digest.summaryLine.localizedCaseInsensitiveContains("citizenM"))
        XCTAssertNil(digest.trainingPlan)
    }

    func testInterviewHoldsThisWeekCountWithoutTitles() throws {
        let assets = [
            asset(kind: .work, days: 2, title: "SRE interview at Cisco", isInterview: true),
            asset(kind: .work, days: 1, title: "Standup"),
        ]
        let digest = LifeOpsDigest.build(
            assets: assets,
            reminders: nil,
            busyToday: 1,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(digest.interviewCount, 1)
        XCTAssertEqual(digest.workHoldCount, 2)
        XCTAssertEqual(digest.load, .moderate)
        XCTAssertTrue(digest.ariaTags.contains("life_ops:interview:1"))
        let spoken = try XCTUnwrap(digest.spokenLine)
        XCTAssertTrue(spoken.localizedCaseInsensitiveContains("interview"))
        XCTAssertFalse(spoken.localizedCaseInsensitiveContains("Cisco"))
        XCTAssertFalse(spoken.localizedCaseInsensitiveContains("Standup"))
        XCTAssertEqual(digest.trainingPlan?.reduceVolume, true)
        XCTAssertEqual(digest.trainingPlan?.keepLight, false)
    }

    func testOverdueRemindersPlusInterviewsAreHeavy() throws {
        let assets = [asset(kind: .work, days: 0, title: "Phone screen with recruiter", isInterview: true)]
        let reminders = RemindersWorkload(
            overdueCount: 2,
            dueTodayCount: 1,
            dueTomorrowCount: 0,
            highPriorityCount: 1,
            kindCounts: ["work": 2]
        )
        let digest = LifeOpsDigest.build(
            assets: assets,
            reminders: reminders,
            busyToday: 4,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(digest.load, .heavy)
        XCTAssertEqual(digest.trainingPlan?.keepLight, true)
        let spoken = try XCTUnwrap(digest.spokenLine)
        XCTAssertTrue(spoken.localizedCaseInsensitiveContains("heavy"))
        XCTAssertTrue(spoken.localizedCaseInsensitiveContains("kind"))
        XCTAssertFalse(spoken.localizedCaseInsensitiveContains("recruiter"))
    }

    func testEmptyBoardIsClear() {
        let digest = LifeOpsDigest.build(
            assets: [],
            reminders: RemindersWorkload.empty,
            busyToday: 0,
            now: now,
            calendar: calendar
        )
        XCTAssertTrue(digest.isQuiet)
        XCTAssertEqual(digest.ariaTags, ["life_ops:clear"])
        XCTAssertNil(digest.spokenLine)
        XCTAssertNil(digest.trainingPlan)
    }

    func testTravelDayKeepsTheSessionMovable() throws {
        let digest = LifeOpsDigest.build(
            assets: [asset(kind: .flight, days: 0, title: "AA 1842 to ORD")],
            reminders: nil,
            busyToday: 0,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(digest.travelDaysUntil, 0)
        XCTAssertEqual(digest.load, .moderate)
        XCTAssertEqual(digest.trainingPlan?.keepLight, true)
        XCTAssertEqual(digest.trainingPlan?.reduceVolume, true)
        let spoken = try XCTUnwrap(digest.spokenLine)
        XCTAssertTrue(spoken.localizedCaseInsensitiveContains("travel is here"))
        XCTAssertFalse(spoken.localizedCaseInsensitiveContains("ORD"))
        XCTAssertFalse(spoken.localizedCaseInsensitiveContains("AA 1842"))
        XCTAssertFalse(digest.ariaTags.contains { $0.localizedCaseInsensitiveContains("ORD") })
    }
}
