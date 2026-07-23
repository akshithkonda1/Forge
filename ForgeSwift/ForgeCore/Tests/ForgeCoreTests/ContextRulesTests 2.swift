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
}
