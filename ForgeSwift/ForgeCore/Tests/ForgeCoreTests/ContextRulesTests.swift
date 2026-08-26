import XCTest
@testable import ForgeCore

final class ContextRulesTests: XCTestCase {

    // MARK: Desk-block nudge

    func testDeskNudgeFiresAt90MinutesOncePerBlock() {
        XCTAssertTrue(ContextRules.deskBlockNudgeDue(mode: .deskCoding, minutesInMode: 90, alreadyFiredThisBlock: false))
        XCTAssertTrue(ContextRules.deskBlockNudgeDue(mode: .deepFocus, minutesInMode: 120, alreadyFiredThisBlock: false))
        XCTAssertFalse(ContextRules.deskBlockNudgeDue(mode: .deskCoding, minutesInMode: 89, alreadyFiredThisBlock: false))
        XCTAssertFalse(ContextRules.deskBlockNudgeDue(mode: .deskCoding, minutesInMode: 200, alreadyFiredThisBlock: true), "one nudge per block")
        XCTAssertFalse(ContextRules.deskBlockNudgeDue(mode: .gym, minutesInMode: 200, alreadyFiredThisBlock: false))
        XCTAssertFalse(ContextRules.deskBlockNudgeDue(mode: nil, minutesInMode: 200, alreadyFiredThisBlock: false))
    }

    // MARK: Evening wind-down

    private func date(hour: Int, minute: Int = 0) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components)!
    }

    func testEveningFallsBackTo9PMWithoutPrediction() {
        XCTAssertFalse(ContextRules.eveningWindDownDue(now: date(hour: 20, minute: 59), predictedWindDown: nil, currentMode: nil, pendingSuggestion: nil))
        XCTAssertTrue(ContextRules.eveningWindDownDue(now: date(hour: 21), predictedWindDown: nil, currentMode: nil, pendingSuggestion: nil))
    }

    func testPredictedWindDownOverridesFixedHour() {
        let predicted = date(hour: 22, minute: 15)
        XCTAssertFalse(
            ContextRules.eveningWindDownDue(now: date(hour: 21, minute: 30), predictedWindDown: predicted, currentMode: nil, pendingSuggestion: nil),
            "9 PM must not fire when the predictor says 10:15"
        )
        XCTAssertTrue(
            ContextRules.eveningWindDownDue(now: date(hour: 22, minute: 20), predictedWindDown: predicted, currentMode: nil, pendingSuggestion: nil)
        )
    }

    func testNoWindDownSuggestionWhenAlreadyWindingDown() {
        XCTAssertFalse(ContextRules.eveningWindDownDue(now: date(hour: 23), predictedWindDown: nil, currentMode: .windDown, pendingSuggestion: nil))
        XCTAssertFalse(ContextRules.eveningWindDownDue(now: date(hour: 23), predictedWindDown: nil, currentMode: nil, pendingSuggestion: .windDown))
    }

    // MARK: Motion heuristic

    func testDeskModeLikelyOnlyDuringWorkHoursWhenUnset() {
        XCTAssertTrue(ContextRules.deskModeLikely(stationaryShare: 0.9, hour: 14, currentMode: nil, pendingSuggestion: nil))
        XCTAssertFalse(ContextRules.deskModeLikely(stationaryShare: 0.5, hour: 14, currentMode: nil, pendingSuggestion: nil))
        XCTAssertFalse(ContextRules.deskModeLikely(stationaryShare: 0.9, hour: 22, currentMode: nil, pendingSuggestion: nil))
        XCTAssertFalse(ContextRules.deskModeLikely(stationaryShare: 0.9, hour: 14, currentMode: .gym, pendingSuggestion: nil), "never override a chosen mode")
        XCTAssertFalse(ContextRules.deskModeLikely(stationaryShare: 0.9, hour: 14, currentMode: nil, pendingSuggestion: .windDown), "one suggestion at a time")
    }

    // MARK: Gym corroboration

    func testGymNeedsElevatedHeartRate() {
        XCTAssertFalse(ContextRules.gymSuggestionAllowed(recentHeartRate: nil), "no HR, no gym claim")
        XCTAssertFalse(ContextRules.gymSuggestionAllowed(recentHeartRate: 72))
        XCTAssertTrue(ContextRules.gymSuggestionAllowed(recentHeartRate: 112))
    }

    // MARK: Heart-rate freshness
    //
    // ContextEngine's five-minute loop has no HealthKit access; it remembers the
    // last reading HomeView handed it. Before this rule existed the loop passed nil
    // and gymSuggestionAllowed rejected it every time, so the known-place gym
    // signal only ever worked while Home was on screen.


    func testAFreshReadingIsUsable() {
        let now = Date()
        let reading = HeartRateReading(bpm: 128, takenAt: now.addingTimeInterval(-60))
        XCTAssertEqual(ContextRules.usableHeartRate(reading, now: now), 128)
    }

    func testAStaleReadingIsNot() {
        let now = Date()
        let reading = HeartRateReading(bpm: 128, takenAt: now.addingTimeInterval(-3 * 3600))
        XCTAssertNil(ContextRules.usableHeartRate(reading, now: now),
                     "an elevated heart rate three hours ago is a workout already finished")
    }

    func testTheBoundaryIsInclusive() {
        let now = Date()
        let edge = HeartRateReading(bpm: 110, takenAt: now.addingTimeInterval(-ContextRules.heartRateFreshness))
        XCTAssertEqual(ContextRules.usableHeartRate(edge, now: now), 110)

        let past = HeartRateReading(bpm: 110, takenAt: now.addingTimeInterval(-ContextRules.heartRateFreshness - 1))
        XCTAssertNil(ContextRules.usableHeartRate(past, now: now))
    }

    func testNoReadingIsNotUsable() {
        XCTAssertNil(ContextRules.usableHeartRate(nil))
    }

    func testAFutureDatedReadingIsNotTreatedAsInfinitelyFresh() {
        // A clock adjustment can stamp a reading ahead of now.
        let now = Date()
        let ahead = HeartRateReading(bpm: 140, takenAt: now.addingTimeInterval(3 * 3600))
        XCTAssertNil(ContextRules.usableHeartRate(ahead, now: now))
    }

    func testTheGymRuleFiresOnceTheLoopHasAFreshReading() {
        // The whole point: the background loop can now reach a true verdict.
        let now = Date()
        let training = HeartRateReading(bpm: 132, takenAt: now.addingTimeInterval(-120))
        XCTAssertTrue(
            ContextRules.gymSuggestionAllowed(
                recentHeartRate: ContextRules.usableHeartRate(training, now: now)
            )
        )

        let resting = HeartRateReading(bpm: 68, takenAt: now.addingTimeInterval(-120))
        XCTAssertFalse(
            ContextRules.gymSuggestionAllowed(
                recentHeartRate: ContextRules.usableHeartRate(resting, now: now)
            ),
            "near the gym at resting heart rate is the car park"
        )
    }
}
