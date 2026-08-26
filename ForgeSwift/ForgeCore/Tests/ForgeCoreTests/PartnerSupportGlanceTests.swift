import XCTest
@testable import ForgeCore

/// Wrist and lock-screen copy is the easy place to undo digest redaction.
/// These tests fail if a glance starts naming a period, a phase, or fertility.
final class PartnerSupportGlanceTests: XCTestCase {

    func testLockScreenLineNeverNamesAPeriodEvenWhenHeadlineDoes() {
        let glance = PartnerSupportGlance(
            firstName: "Sam",
            extraThoughtfulnessHelps: true,
            headline: "On their period — comfort and a lighter load help most.",
            asOfDayKey: "2099-01-01",
            isPaused: false
        )
        let lock = glance.lockScreenLine.lowercased()
        XCTAssertEqual(glance.lockScreenLine, "A little extra care lands well today.")
        XCTAssertFalse(lock.contains("period"))
        XCTAssertFalse(lock.contains("cycle"))
        XCTAssertFalse(lock.contains("fertile"))
        XCTAssertFalse(lock.contains("day 2"))
        XCTAssertFalse(glance.circularLabel.lowercased().contains("period"))
    }

    func testQuietDayLockScreenLine() {
        let glance = PartnerSupportGlance(
            firstName: "Sam",
            extraThoughtfulnessHelps: false,
            headline: "Energy's building — a good stretch for plans.",
            asOfDayKey: "2099-01-01",
            isPaused: false
        )
        XCTAssertEqual(glance.lockScreenLine, "Everyday support is enough.")
        XCTAssertEqual(glance.circularLabel, "OK")
    }

    func testPausedGlanceDoesNotLookLive() {
        let glance = PartnerSupportGlance(
            firstName: "Sam",
            extraThoughtfulnessHelps: true,
            headline: "On their period — comfort and a lighter load help most.",
            asOfDayKey: "2099-01-01",
            isPaused: true
        )
        XCTAssertEqual(glance.lockScreenLine, "No recent update")
        XCTAssertEqual(glance.circularLabel, "—")
    }

    func testNotificationBodyStaysLockSafe() {
        let glance = PartnerSupportGlance(
            firstName: "Sam",
            extraThoughtfulnessHelps: true,
            headline: "Day 2. On their period — comfort and a lighter load help most.",
            asOfDayKey: "2099-01-01",
            isPaused: false
        )
        XCTAssertEqual(glance.notificationTitle, "How to show up for Sam")
        let body = glance.notificationBody.lowercased()
        XCTAssertFalse(body.contains("period"))
        XCTAssertFalse(body.contains("day 2"))
        XCTAssertTrue(body.contains("open forge"))
    }

    func testEncodedGlanceHasNoSnapshotSecrets() throws {
        let glance = PartnerSupportGlance.gallerySample
        let data = try JSONEncoder().encode(glance)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let forbidden = [
            "fertileScore", "ovulation", "cycleGoal", "flow", "symptoms",
            "bbt", "periodDay", "daysUntilNextPeriodApprox", "phase",
        ]
        for key in forbidden {
            XCTAssertNil(object[key], "glance leaked \(key)")
        }
        let allowed: Set<String> = [
            "firstName", "extraThoughtfulnessHelps", "headline",
            "asOfDayKey", "isPaused", "updatedAt",
        ]
        for key in object.keys {
            XCTAssertTrue(allowed.contains(key), "unexpected glance key \(key)")
        }
    }
}
