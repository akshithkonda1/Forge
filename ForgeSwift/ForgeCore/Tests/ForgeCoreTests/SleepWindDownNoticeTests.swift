import XCTest
@testable import ForgeCore

final class SleepWindDownNoticeTests: XCTestCase {

    func testFallbackIsNinePm() {
        let fire = SleepWindDownNotice.fireHourMinute(bedtimeHour: nil)
        XCTAssertEqual(fire.hour, 21)
        XCTAssertEqual(fire.minute, 0)
    }

    func testPersonalBedtimeMinusOneHour() {
        let fire = SleepWindDownNotice.fireHourMinute(bedtimeHour: 23.0)
        XCTAssertEqual(fire.hour, 22)
        XCTAssertEqual(fire.minute, 0)
    }

    func testMidnightWrap() {
        let fire = SleepWindDownNotice.fireHourMinute(bedtimeHour: 0.25)
        XCTAssertEqual(fire.hour, 23)
        XCTAssertEqual(fire.minute, 15)
    }

    func testInferredBedtimeFromWakeGoal() {
        let goal = ScheduleGoal(
            targetWakeHour: 6,
            cutoverStart: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let hour = SleepWindDownNotice.inferredBedtimeHour(goal: goal, needHours: 8)
        XCTAssertEqual(hour, 22.0, accuracy: 0.01)
    }

    func testRetiredIdsStayDistinctFromTheCanonicalOne() {
        XCTAssertFalse(SleepWindDownNotice.retiredPhoneIdentifiers.contains(SleepWindDownNotice.phoneIdentifier))
        XCTAssertTrue(SleepWindDownNotice.retiredPhoneIdentifiers.contains("sleep-wind-down"))
        XCTAssertTrue(SleepWindDownNotice.retiredPhoneIdentifiers.contains("forge.notification.lifestyle.sleep"))
    }
}
