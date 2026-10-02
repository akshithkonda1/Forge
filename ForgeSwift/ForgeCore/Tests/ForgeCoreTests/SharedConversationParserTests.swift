import XCTest
@testable import ForgeCore

final class SharedConversationParserTests: XCTestCase {

    private let key = LifeContextHashKey(bytes: Data(repeating: 3, count: 32))!
    private let sharedAt = Date(timeIntervalSince1970: 1_790_000_000)

    private var parser: SharedConversationParser { SharedConversationParser(hashKey: key) }

    func testSpeakerLinesBecomeTurns() {
        let turns = parser.parse("Sam: Dinner Friday at 7?\nMe: Yes! See you then", sharedAt: sharedAt)
        XCTAssertEqual(turns.count, 2)
        XCTAssertEqual(turns[0].sender, .them(ContactID(hashing: "Sam", key: key)))
        XCTAssertEqual(turns[0].text, "Dinner Friday at 7?")
        XCTAssertEqual(turns[1].sender, .me)
        XCTAssertEqual(turns[1].text, "Yes! See you then")
        XCTAssertEqual(turns[0].timestamp, sharedAt)
        XCTAssertEqual(turns[1].timestamp, sharedAt.addingTimeInterval(1), "order survives without timestamps")
    }

    func testNamesNeverSurviveIntoATurn() {
        let turns = parser.parse("Jordan Rivera: running late\nJordan Rivera: 10 min", sharedAt: sharedAt)
        XCTAssertEqual(turns.count, 2)
        for turn in turns {
            guard case .them(let id) = turn.sender else { return XCTFail("expected the other person") }
            XCTAssertFalse(id.value.lowercased().contains("jordan"))
            XCTAssertFalse(turn.text.contains("Jordan"))
        }
        XCTAssertEqual(turns[0].sender, turns[1].sender, "the same speaker hashes the same")
    }

    func testWhatsAppExportFormats() {
        let text = """
        [10/2/26, 7:41:03 PM] Sam: Dinner Friday?
        [10/2/26, 7:42:10 PM] Me: Sounds good
        10/2/26, 7:43 PM - Sam: 7pm at the usual place
        """
        let turns = parser.parse(text, sharedAt: sharedAt)
        XCTAssertEqual(turns.map(\.text), ["Dinner Friday?", "Sounds good", "7pm at the usual place"])
        XCTAssertEqual(turns.map(\.isFromMe), [false, true, false])
    }

    func testContinuationLinesJoinThePreviousMessage() {
        let turns = parser.parse("Sam: Are we still on\nfor tomorrow?\nMe: yes", sharedAt: sharedAt)
        XCTAssertEqual(turns.count, 2)
        XCTAssertEqual(turns[0].text, "Are we still on\nfor tomorrow?")
    }

    func testTextWithNoSpeakersIsOneMessageFromSomeoneElse() {
        let turns = parser.parse("dinner friday at 7?\nsounds good", sharedAt: sharedAt)
        XCTAssertEqual(turns.count, 1)
        XCTAssertFalse(turns[0].isFromMe, "unlabeled text is never treated as the user's own words")
    }

    func testLabelsThatAreNotPeople() {
        let turns = parser.parse("Note: buy milk\nPS: call later", sharedAt: sharedAt)
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns[0].text, "Note: buy milk\nPS: call later")
    }

    func testSystemLinesAreSkipped() {
        let text = """
        [10/2/26, 7:40:00 PM] Messages and calls are end-to-end encrypted.
        [10/2/26, 7:41:03 PM] Sam: <Media omitted>
        [10/2/26, 7:41:30 PM] Sam: Dinner Friday?
        """
        let turns = parser.parse(text, sharedAt: sharedAt)
        XCTAssertEqual(turns.map(\.text), ["Dinner Friday?"])
    }

    func testPhoneNumbersAreRemovedOnTheWayIn() {
        let turns = parser.parse("Sam: call me on 415-555-0132", sharedAt: sharedAt)
        XCTAssertEqual(turns.count, 1)
        XCTAssertFalse(turns[0].text.contains("555"))
    }

    func testSelfAliasesAreConfigurable() {
        let custom = SharedConversationParser(hashKey: key, selfAliases: ["Ava"])
        let turns = custom.parse("Ava: on my way\nSam: ok", sharedAt: sharedAt)
        XCTAssertEqual(turns.map(\.isFromMe), [true, false])
    }

    func testBoundsCapWork() {
        let bounded = SharedConversationParser(hashKey: key, maxTurns: 3)
        let text = (0..<10).map { "Sam: message \($0)" }.joined(separator: "\n")
        XCTAssertEqual(bounded.parse(text, sharedAt: sharedAt).count, 3)
    }

    func testParsedConversationFeedsTheEngine() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let tuesday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: 10))!
        let turns = parser.parse("Sam: Want to grab dinner Friday at 7?\nMe: Yes! See you then", sharedAt: tuesday)
        let facts = MessageContextEngine(hashKey: key, configuration: .init(calendar: calendar)).extract(from: turns)
        XCTAssertEqual(facts.map(\.summary), ["Dinner with a friend Friday 7pm"])
    }
}
