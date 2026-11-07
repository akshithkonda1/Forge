import XCTest
@testable import ForgeCore

final class AriaPersonalPatternEngineTests: XCTestCase {

    private var calendar: Calendar!
    private var day0: Date!

    override func setUp() {
        super.setUp()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar = cal
        day0 = cal.date(from: DateComponents(year: 2026, month: 3, day: 2))!
    }

    func testLateCaffeineNeedsMinimumDataAndConfidence() throws {
        var snap = AriaPersonalPatternEngine.Snapshot(userId: "u1")
        for i in 0..<4 {
            snap = AriaPersonalPatternEngine.ingest(
                snap,
                observation: obs(day: i, sleep: 5.2, caffeineHour: 16),
                now: day0,
                calendar: calendar
            )
        }
        XCTAssertTrue(snap.visible.isEmpty, "four nights is under the bar")

        snap = AriaPersonalPatternEngine.ingest(
            snap,
            observation: obs(day: 4, sleep: 5.0, caffeineHour: 17),
            now: day0,
            calendar: calendar
        )
        let pattern = try XCTUnwrap(snap.visible.first { $0.kind == .lateCaffeineShortSleep })
        XCTAssertGreaterThanOrEqual(pattern.confidence, AriaPersonalPatternEngine.minConfidence)
        XCTAssertEqual(pattern.sampleCount, 5)
        XCTAssertTrue(pattern.title.lowercased().contains("late caffeine"))
        XCTAssertTrue(pattern.evidence.lowercased().contains("3 pm") || pattern.evidence.lowercased().contains("after"))
        XCTAssertTrue(pattern.changed.lowercased().contains("1 pm"))
        XCTAssertFalse(AriaPersonalPatternEngine.containsBannedSpeech(pattern.title))
        XCTAssertFalse(AriaPersonalPatternEngine.containsBannedSpeech(pattern.evidence))
        XCTAssertFalse(AriaPersonalPatternEngine.containsBannedSpeech(pattern.changed))
    }

    func testMixedCaffeineStaysBelowConfidence() {
        var snap = AriaPersonalPatternEngine.Snapshot(userId: "u1")
        for i in 0..<5 {
            let short = i < 2
            snap = AriaPersonalPatternEngine.ingest(
                snap,
                observation: obs(day: i, sleep: short ? 5.1 : 7.8, caffeineHour: 16),
                now: day0,
                calendar: calendar
            )
        }
        XCTAssertNil(snap.visible.first { $0.kind == .lateCaffeineShortSleep })
    }

    func testConfirmCorrectExpire() throws {
        var snap = seededLateCaffeine()
        let id = try XCTUnwrap(snap.visible.first?.id)
        snap = AriaPersonalPatternEngine.confirm(snap, id: id, now: day0)
        XCTAssertEqual(snap.patterns.first?.status, .confirmed)
        XCTAssertEqual(snap.visible.count, 1)

        snap = AriaPersonalPatternEngine.correct(snap, id: id, note: "Tea after dinner is fine", now: day0)
        XCTAssertTrue(snap.visible.isEmpty)
        XCTAssertEqual(snap.patterns.first?.status, .corrected)
        XCTAssertEqual(snap.patterns.first?.correction, "Tea after dinner is fine")

        snap = seededLateCaffeine()
        let other = try XCTUnwrap(snap.visible.first?.id)
        snap = AriaPersonalPatternEngine.expire(snap, id: other, now: day0)
        XCTAssertEqual(snap.patterns.first?.status, .expired)
        XCTAssertTrue(snap.visible.isEmpty)
    }

    func testShortSleepThenTrainingAndCalendarHabits() {
        var snap = AriaPersonalPatternEngine.Snapshot(userId: "u1")
        for i in 0..<6 {
            let day = calendar.date(byAdding: .day, value: i, to: day0)!
            snap = AriaPersonalPatternEngine.ingest(
                snap,
                observation: AriaPersonalPatternEngine.Observation(
                    day: day,
                    sleepHours: 5.4,
                    trainingWentWell: i == 0 ? true : false,
                    calendarBusyHours: 5,
                    habitCompletion: 0.2,
                    weekday: 2,
                    calendar: calendar
                ),
                now: day0,
                calendar: calendar
            )
        }
        XCTAssertNotNil(snap.visible.first { $0.kind == .shortSleepThenTraining })
        XCTAssertNotNil(snap.visible.first { $0.kind == .heavyCalendarHabitSlip })
        XCTAssertFalse(snap.activeChanges.contains { AriaCoachSpeechGuard.containsBanned($0) })
    }

    func testRemoteFactsAreFlagsNotRawHealth() {
        let snap = seededLateCaffeine()
        let facts = AriaPersonalPatternEngine.remoteFacts(snap)
        XCTAssertFalse(facts.isEmpty)
        for fact in facts {
            XCTAssertTrue(fact.hasPrefix("pattern:"))
            XCTAssertFalse(fact.contains("5.0"))
            XCTAssertFalse(AriaPersonalPatternEngine.containsBannedSpeech(fact))
        }
    }

    func testStoreRoundTrip() {
        let defaults = UserDefaults(suiteName: "forge.pattern.\(UUID().uuidString)")!
        var snap = seededLateCaffeine()
        snap.userId = "person-1"
        AriaPersonalPatternEngine.Store.save(snap, defaults: defaults)
        let loaded = AriaPersonalPatternEngine.Store.load(defaults: defaults)
        XCTAssertEqual(loaded.userId, "person-1")
        XCTAssertEqual(loaded.visible.count, snap.visible.count)
    }

    private func seededLateCaffeine() -> AriaPersonalPatternEngine.Snapshot {
        var snap = AriaPersonalPatternEngine.Snapshot(userId: "u1")
        for i in 0..<5 {
            snap = AriaPersonalPatternEngine.ingest(
                snap,
                observation: obs(day: i, sleep: 5.1, caffeineHour: 16),
                now: day0,
                calendar: calendar
            )
        }
        return snap
    }

    private func obs(day: Int, sleep: Double, caffeineHour: Int) -> AriaPersonalPatternEngine.Observation {
        let date = calendar.date(byAdding: .day, value: day, to: day0)!
        return AriaPersonalPatternEngine.Observation(
            day: date,
            sleepHours: sleep,
            caffeineHour: caffeineHour,
            calendar: calendar
        )
    }
}
