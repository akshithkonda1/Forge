import XCTest
@testable import ForgeCore

final class AriaMorningCardTests: XCTestCase {

    func testEmptyCardWhenNothingMeasured() {
        let card = AriaMorningCardBuilder.build(
            .init(numbers: .init(), hasLifeSignal: false)
        )
        XCTAssertTrue(card.empty)
        XCTAssertFalse(card.speak)
        XCTAssertTrue(card.reason.lowercased().contains("need"))
        XCTAssertLessThanOrEqual(AriaMorningCardBuilder.wordCount(card.reason), 25)
        XCTAssertFalse(AriaCoachSpeechGuard.containsBanned(card.call))
        XCTAssertFalse(AriaCoachSpeechGuard.containsBanned(card.reason))
    }

    func testReasonUsesNumbersAndStaysUnderTwentyFiveWords() {
        let card = AriaMorningCardBuilder.build(
            .init(
                numbers: .init(sleepHours: 5.4, readiness: 48, calendarBusyHours: 5, habitCompletion: 0.4),
                gymLabel: "Home gym",
                patternChanges: ["Coffee moves before 1 PM today"],
                safetyChange: "A safety rule swapped swimming for a pool-side session.",
                safetyFlags: [.sleepLoss]
            )
        )
        XCTAssertFalse(card.empty)
        XCTAssertEqual(card.call, "Easy session")
        XCTAssertEqual(card.actions.count, 3)
        XCTAssertTrue(card.actions.contains("Coffee moves before 1 PM today"))
        XCTAssertTrue(card.reason.contains("5.4"))
        XCTAssertTrue(card.reason.contains("48"))
        XCTAssertLessThanOrEqual(AriaMorningCardBuilder.wordCount(card.reason), AriaMorningCardBuilder.maxReasonWords)
        XCTAssertEqual(card.ruleLine.lowercased().contains("safety rule"), true)
        XCTAssertFalse(AriaCoachSpeechGuard.containsBanned(card.call))
        XCTAssertFalse(AriaCoachSpeechGuard.containsBanned(card.reason))
        XCTAssertFalse(card.actions.contains { AriaCoachSpeechGuard.containsBanned($0) })
    }

    func testSpeaksOnlyWhenANumberMovedAndDialAllows() {
        let previous = AriaMorningCardBuilder.Numbers(sleepHours: 7.4, readiness: 72)
        let current = AriaMorningCardBuilder.Numbers(sleepHours: 5.4, readiness: 48)
        XCTAssertTrue(AriaMorningCardBuilder.numberMoved(previous: previous, current: current))

        let quiet = AriaMorningCardBuilder.build(
            .init(numbers: current, previous: previous, talkativeness: .quiet)
        )
        XCTAssertFalse(quiet.speak)
        XCTAssertTrue(quiet.spokenLine.isEmpty)

        let balanced = AriaMorningCardBuilder.build(
            .init(numbers: current, previous: previous, talkativeness: .balanced)
        )
        XCTAssertTrue(balanced.speak)
        XCTAssertTrue(balanced.spokenLine.contains(balanced.call))

        let muted = AriaMorningCardBuilder.build(
            .init(numbers: current, previous: previous, talkativeness: .chatty, quietMode: true)
        )
        XCTAssertFalse(muted.speak)

        let still = AriaMorningCardBuilder.build(
            .init(numbers: current, previous: current, talkativeness: .chatty)
        )
        XCTAssertFalse(still.speak)

        XCTAssertTrue(
            AriaMorningCardBuilder.shouldSpeak(moved: true, talkativeness: .chatty, quietMode: false)
        )
        XCTAssertFalse(
            AriaMorningCardBuilder.shouldSpeak(moved: true, talkativeness: .quiet, quietMode: false)
        )
    }

    func testHeatCallStaysGrounded() {
        let card = AriaMorningCardBuilder.build(
            .init(
                numbers: .init(sleepHours: 7.2, readiness: 80),
                gymLabel: "Commercial gym",
                safetyFlags: [.heat]
            )
        )
        XCTAssertEqual(card.call, "Keep it cool and short")
        XCTAssertTrue(card.actions.contains { $0.lowercased().contains("cooler") })
        XCTAssertFalse(AriaCoachSpeechGuard.containsBanned(card.call))
    }
}
