import XCTest
@testable import ForgeCore

final class SleepModelsTests: XCTestCase {

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = day
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components)!
    }

    private func segment(_ day: Int, _ startHour: Int, _ startMinute: Int, minutes: Double, _ stage: SleepStage) -> SleepStageSegment {
        let start = date(day, startHour, startMinute)
        return SleepStageSegment(start: start, end: start.addingTimeInterval(minutes * 60), stage: stage)
    }

    func testAggregatesDeriveFromSegments() {
        let night = SleepNight(segments: [
            segment(1, 23, 0, minutes: 60, .core),
            segment(2, 0, 0, minutes: 70, .deep),
            segment(2, 1, 10, minutes: 90, .rem),
            segment(2, 2, 40, minutes: 20, .awake),
            segment(2, 3, 0, minutes: 180, .core),
        ])
        XCTAssertEqual(night.deepMinutes, 70)
        XCTAssertEqual(night.remMinutes, 90)
        XCTAssertEqual(night.coreMinutes, 240)
        XCTAssertEqual(night.awakeMinutes, 20)
        // Awake time is not asleep time.
        XCTAssertEqual(night.totalMinutes, 400)
        XCTAssertEqual(night.start, date(1, 23, 0))
        XCTAssertEqual(night.durationLabel, "6h 40m")
    }

    func testGroupIntoNightsKeepsPostMidnightSleepTogether() {
        let segments = [
            // Night of July 1 (crosses midnight)
            segment(1, 23, 30, minutes: 120, .core),
            segment(2, 1, 30, minutes: 60, .deep),
            // Night of July 2
            segment(2, 23, 0, minutes: 300, .core),
        ]
        let nights = SleepNight.groupIntoNights(segments: segments)
        XCTAssertEqual(nights.count, 2)
        XCTAssertEqual(nights[0].totalMinutes, 180, "23:30 + 01:30 segments belong to one night")
        XCTAssertEqual(nights[1].totalMinutes, 300)
    }
}

final class WindDownPredictorTests: XCTestCase {

    private func onset(day: Int, hour: Int, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = day
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components)!
    }

    private var now: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 4
        components.hour = 15
        return Calendar.current.date(from: components)!
    }

    func testFewerThanThreeOnsetsIsHonestNil() {
        let plan = WindDownPredictor.plan(
            recentOnsets: [onset(day: 1, hour: 23), onset(day: 2, hour: 23)],
            recentSleepMinutes: [420, 430],
            now: now
        )
        XCTAssertNil(plan, "must not invent a bedtime from two nights")
    }

    func testWellSleptKeepsMedianOnset() {
        let plan = WindDownPredictor.plan(
            recentOnsets: [onset(day: 1, hour: 23, minute: 0), onset(day: 2, hour: 23, minute: 30), onset(day: 3, hour: 23, minute: 15)],
            recentSleepMinutes: [480, 490, 500], // no debt
            now: now
        )!
        let hour = Calendar.current.component(.hour, from: plan.bedtimeWindowStart)
        let minute = Calendar.current.component(.minute, from: plan.bedtimeWindowStart)
        XCTAssertEqual(hour, 23)
        XCTAssertEqual(minute, 15, "median of 23:00/23:15/23:30 is 23:15")
        // Wind-down leads the window by 20 minutes.
        XCTAssertEqual(
            plan.bedtimeWindowStart.timeIntervalSince(plan.windDownStart),
            WindDownPredictor.windDownLeadMinutes * 60
        )
    }

    func testSleepDebtPullsEarlierButCapped() {
        let onsets = [onset(day: 1, hour: 23), onset(day: 2, hour: 23), onset(day: 3, hour: 23)]
        let mildDebt = WindDownPredictor.plan(
            recentOnsets: onsets,
            recentSleepMinutes: [420, 420, 420], // 60 min short → shift 30
            now: now
        )!
        let mildHour = Calendar.current.component(.hour, from: mildDebt.bedtimeWindowStart)
        let mildMinute = Calendar.current.component(.minute, from: mildDebt.bedtimeWindowStart)
        XCTAssertEqual(mildHour, 22)
        XCTAssertEqual(mildMinute, 30)

        let heavyDebt = WindDownPredictor.plan(
            recentOnsets: onsets,
            recentSleepMinutes: [180, 180, 180], // catastrophic debt → cap at 45
            now: now
        )!
        let heavyHour = Calendar.current.component(.hour, from: heavyDebt.bedtimeWindowStart)
        let heavyMinute = Calendar.current.component(.minute, from: heavyDebt.bedtimeWindowStart)
        XCTAssertEqual(heavyHour, 22)
        XCTAssertEqual(heavyMinute, 15, "shift is capped at 45 minutes — no drastic prescriptions")
    }

    func testMidnightCrossingOnsetsProduceSaneMedian() {
        let plan = WindDownPredictor.plan(
            recentOnsets: [
                onset(day: 1, hour: 23, minute: 45),
                onset(day: 3, hour: 0, minute: 30),  // after midnight
                onset(day: 4, hour: 0, minute: 5),
            ],
            recentSleepMinutes: [480, 480, 480],
            now: now
        )!
        let hour = Calendar.current.component(.hour, from: plan.bedtimeWindowStart)
        XCTAssertEqual(hour, 0, "median of 23:45 / 00:05 / 00:30 is 00:05")
    }
}

final class SleepStoryEngineTests: XCTestCase {

    private func night(totalHours: Double, deepMinutes: Double = 60, awakeMinutes: Double = 10) -> SleepNight {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        var segments: [SleepStageSegment] = []
        var cursor = start
        func add(_ minutes: Double, _ stage: SleepStage) {
            guard minutes > 0 else { return }
            segments.append(SleepStageSegment(start: cursor, end: cursor.addingTimeInterval(minutes * 60), stage: stage))
            cursor = cursor.addingTimeInterval(minutes * 60)
        }
        add(deepMinutes, .deep)
        add(awakeMinutes, .awake)
        add(totalHours * 60 - deepMinutes, .core)
        return SleepNight(segments: segments)
    }

    func testNoDataStoryIsHonest() {
        let story = SleepStoryEngine.story(night: nil, readiness: nil)
        XCTAssertTrue(story.contains("No sleep data"), "must not invent a night")
    }

    func testShortNightIsKindAndLinksReadiness() {
        let readiness = ReadinessScore(overall: 52, sleepQuality: 40, recovery: 60, confidence: 0.8)
        let story = SleepStoryEngine.story(night: night(totalHours: 4.5), readiness: readiness)
        XCTAssertTrue(story.contains("52"), "story should link to today's readiness")
        for banned in ["bad night", "failed", "only", "should have"] {
            XCTAssertFalse(story.lowercased().contains(banned), "guilt language: \(story)")
        }
    }

    func testFactorNoteIsWovenIn() {
        let story = SleepStoryEngine.story(night: night(totalHours: 7.5), readiness: nil, factors: [.lateCaffeine])
        XCTAssertTrue(story.contains("Caffeine"), "logged factor should appear as context")
    }

    func testTonightPlanWithoutPredictionAdmitsLearning() {
        let plan = SleepStoryEngine.tonightPlan(plan: nil, night: nil)
        XCTAssertTrue(plan.contains("still learning"))
    }

    func testTonightPlanMentionsWindDownTime() {
        let windDown = WindDownPlan(
            windDownStart: Date(timeIntervalSince1970: 1_750_000_000),
            bedtimeWindowStart: Date(timeIntervalSince1970: 1_750_001_200),
            bedtimeWindowEnd: Date(timeIntervalSince1970: 1_750_003_900)
        )
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        let expected = formatter.string(from: windDown.windDownStart)
        let plan = SleepStoryEngine.tonightPlan(plan: windDown, night: night(totalHours: 7.5))
        XCTAssertTrue(plan.contains(expected), "plan should name the wind-down time: \(plan)")
    }
}
