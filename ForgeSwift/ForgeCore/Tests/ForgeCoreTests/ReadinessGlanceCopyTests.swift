import XCTest
@testable import ForgeCore

final class ReadinessGlanceCopyTests: XCTestCase {

    func testEveningPrefersTomorrow() {
        let line = ReadinessGlanceCopy.complicationLine(
            today: 82,
            tomorrow: 61,
            postureRaw: "protect",
            hour: 20
        )
        XCTAssertEqual(line, "Tomorrow 61 · Protect")
        XCTAssertTrue(ReadinessGlanceCopy.accessibilityLine(
            today: 82, tomorrow: 61, postureRaw: "protect", hour: 20
        ).contains("tomorrow"))
    }

    func testMorningKeepsToday() {
        let line = ReadinessGlanceCopy.complicationLine(
            today: 82,
            tomorrow: 61,
            postureRaw: "protect",
            hour: 9
        )
        XCTAssertEqual(line, "Readiness 82")
    }

    func testEmptyIsHonest() {
        XCTAssertEqual(
            ReadinessGlanceCopy.complicationLine(today: nil, tomorrow: nil, postureRaw: nil, hour: 9),
            "Readiness syncing…"
        )
        XCTAssertNil(ReadinessGlanceCopy.homeTomorrowLine(score: nil, postureRaw: "rest"))
        XCTAssertEqual(
            ReadinessGlanceCopy.homeTomorrowLine(score: 54, postureRaw: "rest"),
            "Tomorrow 54 · Rest"
        )
    }

    func testLateNightCountsAsEvening() {
        XCTAssertTrue(ReadinessGlanceCopy.isEvening(hour: 2))
        XCTAssertTrue(ReadinessGlanceCopy.isEvening(hour: 18))
        XCTAssertFalse(ReadinessGlanceCopy.isEvening(hour: 17))
    }

    func testWatchSnapshotKeepsTomorrowFields() throws {
        var snap = WatchSnapshot()
        snap.readinessOverall = 74
        snap.tomorrowPredictedScore = 61
        snap.tomorrowPosture = ReadinessForecastEngine.Posture.protect.rawValue
        let data = try JSONEncoder().encode(snap)
        let loaded = try JSONDecoder().decode(WatchSnapshot.self, from: data)
        XCTAssertEqual(loaded.tomorrowPredictedScore, 61)
        XCTAssertEqual(loaded.tomorrowPosture, "protect")
        XCTAssertEqual(
            ReadinessGlanceCopy.homeTomorrowLine(
                score: loaded.tomorrowPredictedScore,
                postureRaw: loaded.tomorrowPosture
            ),
            "Tomorrow 61 · Protect"
        )
    }
}

final class AriaDayBriefTests: XCTestCase {

    func testDayBriefNamesTomorrowWhenPresent() {
        var context = WatchARIAContext()
        context.readinessOverall = 74
        context.readinessConfidence = 0.8
        context.sleepQualityScore = 82
        context.tomorrowPredictedScore = 58
        context.tomorrowPosture = "protect"
        let line = AriaDayBrief.line(for: context, recommendation: nil)
        XCTAssertTrue(line.contains("Readiness 74"))
        XCTAssertTrue(line.contains("Tomorrow 58"))
        XCTAssertTrue(line.contains("Protect"))
    }

    func testDayBriefOmitsTomorrowWhenUnknown() {
        var context = WatchARIAContext()
        context.readinessOverall = 74
        context.readinessConfidence = 0.8
        let line = AriaDayBrief.line(for: context, recommendation: nil)
        XCTAssertFalse(line.contains("Tomorrow"))
    }
}
