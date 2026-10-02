import XCTest
@testable import ForgeCore

/// Synthetic conversations in, structured facts out. Every case pins the
/// calendar (UTC, Gregorian) and anchors each message's timestamp, so the
/// expected dates hold on any runner, on any day.
final class MessageContextEngineTests: XCTestCase {

    // MARK: Fixtures

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private let key = LifeContextHashKey(bytes: Data(repeating: 7, count: 32))!

    private var engine: MessageContextEngine {
        MessageContextEngine(hashKey: key, configuration: .init(calendar: calendar))
    }

    private var sam: MessageTurn.Sender { .them(ContactID(hashing: "Sam", key: key)) }
    private var alex: MessageTurn.Sender { .them(ContactID(hashing: "+1 (415) 555-0132", key: key)) }

    /// Tuesday 29 September 2026, 10:00 UTC.
    private func at(_ day: Int = 29, month: Int = 9, hour: Int = 10, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private func turn(_ sender: MessageTurn.Sender, _ text: String, minute: Int) -> MessageTurn {
        MessageTurn(sender: sender, text: text, timestamp: at(minute: minute))
    }

    // MARK: Plans

    func testDinnerPlanWithDateAndConfirmation() {
        let facts = engine.extract(from: [
            turn(sam, "Want to grab dinner Friday at 7?", minute: 0),
            turn(.me, "Yes! See you then", minute: 5),
        ])
        XCTAssertEqual(facts.count, 1)
        let fact = facts[0]
        XCTAssertEqual(fact.kind, .plan)
        XCTAssertEqual(fact.label, "dinner")
        XCTAssertEqual(fact.summary, "Dinner with a friend Friday 7pm")
        XCTAssertEqual(fact.date, at(2, month: 10, hour: 19))
        XCTAssertEqual(fact.confidence, 0.95, accuracy: 0.001)
        XCTAssertEqual(fact.confidenceBand, .high)
        XCTAssertEqual(fact.observedAt, at(minute: 0))
    }

    func testPlanRoleComesFromRoleWordsNotNames() {
        let facts = engine.extract(from: [
            turn(.me, "Lunch with my sister Sarah tomorrow at noon", minute: 0),
        ])
        let plan = facts.first { $0.kind == .plan }
        XCTAssertEqual(plan?.summary, "Lunch with family Wednesday 12pm")
        XCTAssertFalse(plan?.summary.lowercased().contains("sarah") ?? true)
    }

    func testDeclinedPlanIsDropped() {
        let facts = engine.extract(from: [
            turn(sam, "Drinks Thursday?", minute: 0),
            turn(.me, "Can't this week, sorry", minute: 2),
        ])
        XCTAssertTrue(facts.filter { $0.kind == .plan }.isEmpty)
    }

    func testProposalAndAgreementCollapseToOnePlan() {
        let facts = engine.extract(from: [
            turn(sam, "Dinner Friday?", minute: 0),
            turn(.me, "Yes, dinner Friday works", minute: 1),
        ])
        let plans = facts.filter { $0.kind == .plan }
        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plans.first?.confidence ?? 0, 0.85, accuracy: 0.001)
        XCTAssertEqual(plans.first?.observedAt, at(minute: 0))
    }

    // MARK: Travel

    func testFlightMention() {
        let facts = engine.extract(from: [turn(.me, "My flight lands Thursday at 6pm", minute: 0)])
        XCTAssertEqual(facts.count, 1)
        XCTAssertEqual(facts.first?.kind, .travel)
        XCTAssertEqual(facts.first?.label, "flight")
        XCTAssertEqual(facts.first?.summary, "Flight Thursday 6pm")
        XCTAssertEqual(facts.first?.date, at(1, month: 10, hour: 18))
        XCTAssertGreaterThanOrEqual(facts.first?.confidence ?? 0, 0.75)
    }

    func testTripNextWeekKeepsWeekPrecision() {
        let facts = engine.extract(from: [turn(.me, "Flying to Denver next week for work", minute: 0)])
        let travel = facts.first { $0.kind == .travel }
        XCTAssertEqual(travel?.summary, "Flight next week")
        XCTAssertGreaterThanOrEqual(travel?.confidence ?? 0, 0.7)
        XCTAssertFalse(travel?.summary.contains("Denver") ?? true, "places move confidence, never text")
    }

    // MARK: Signals

    func testStressSignalIsTheUsersOwn() {
        let facts = engine.extract(from: [
            turn(sam, "I'm so stressed about my exams", minute: 0),
            turn(.me, "Work has been insane, I'm so overwhelmed and stressed", minute: 1),
        ])
        let stress = facts.filter { $0.kind == .stressSignal }
        XCTAssertEqual(stress.count, 1)
        XCTAssertEqual(stress.first?.summary, "Stress signal about work")
        XCTAssertEqual(stress.first?.observedAt, at(minute: 1))
        XCTAssertEqual(stress.first?.confidence ?? 0, 0.9, accuracy: 0.001)
        XCTAssertNil(stress.first?.date)
    }

    func testHealthSignalOnlyFromMe() {
        let facts = engine.extract(from: [
            turn(sam, "I'm sick too", minute: 0),
            turn(.me, "Ugh I'm so sick, fever all night", minute: 1),
        ])
        let health = facts.filter { $0.kind == .healthSignal }
        XCTAssertEqual(health.count, 1)
        XCTAssertEqual(health.first?.summary, "Feeling unwell")
        XCTAssertEqual(health.first?.observedAt, at(minute: 1))
    }

    func testCommitmentWithDeadline() {
        let facts = engine.extract(from: [turn(.me, "I'll send the report by Friday", minute: 0)])
        XCTAssertEqual(facts.map(\.summary), ["Work deadline Friday"])
        XCTAssertEqual(facts.first?.kind, .commitment)
    }

    func testCommitmentAgreedToARequest() {
        let facts = engine.extract(from: [
            turn(alex, "Can you send me the deck by Thursday?", minute: 0),
            turn(.me, "Yep, will do", minute: 3),
        ])
        let commitment = facts.first { $0.kind == .commitment }
        XCTAssertEqual(commitment?.summary, "Work deadline Thursday")
        XCTAssertEqual(commitment?.observedAt, at(minute: 3), "the commitment is made in the reply")
    }

    func testRelationshipUsesARoleNeverAName() {
        let facts = engine.extract(from: [
            turn(.me, "Love you mom, miss you", minute: 0),
            turn(sam, "Love you too sweetheart", minute: 1),
        ])
        let relationship = facts.filter { $0.kind == .relationship }
        XCTAssertEqual(relationship.count, 1)
        XCTAssertEqual(relationship.first?.summary, "Close connection with family")
    }

    // MARK: Thresholds (table)

    func testConfidenceThresholdTable() {
        let cases: [(text: String, kind: LifeContextFact.Kind, kept: Bool)] = [
            ("I'm stressed", .stressSignal, true),
            ("I'm exhausted", .stressSignal, false),
            ("Rough week, so exhausted and drained", .stressSignal, true),
            ("I'm not stressed anymore", .stressSignal, false),
            ("My knee is sore", .healthSignal, false),
            ("I sprained my ankle", .healthSignal, true),
            ("Feeling better, not sick anymore", .healthSignal, false),
            ("Dentist appointment Tuesday at 3pm", .healthSignal, true),
            ("The wedding is Saturday", .event, true),
            ("Weddings are expensive", .event, false),
            ("I'll call later", .commitment, false),
            ("I promise I'll call mom tonight", .commitment, true),
        ]
        for testCase in cases {
            let facts = engine.extract(from: [turn(.me, testCase.text, minute: 0)])
            let found = facts.contains { $0.kind == testCase.kind }
            XCTAssertEqual(found, testCase.kept, "\(testCase.text) → \(testCase.kind) kept=\(testCase.kept)")
        }
    }

    func testLowConfidencePlanIsDropped() {
        let facts = engine.extract(from: [
            turn(sam, "We should get coffee sometime", minute: 0),
            turn(.me, "maybe!", minute: 2),
        ])
        XCTAssertTrue(facts.isEmpty)
    }

    func testEveryKeptFactClearsTheThreshold() {
        for fact in engine.extract(from: broadConversation()) {
            XCTAssertGreaterThanOrEqual(fact.confidence, MessageContextEngine.defaultMinimumConfidence)
        }
    }

    // MARK: Dedup, cap, determinism

    func testSameInputSameFacts() {
        let turns = broadConversation()
        let first = engine.extract(from: turns)
        let second = engine.extract(from: turns)
        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first, engine.extract(from: turns.reversed()), "order of the input array does not matter")
    }

    func testMergeDedupesBySourceHash() {
        let facts = engine.extract(from: broadConversation())
        let merged = engine.merge(facts, into: facts)
        XCTAssertEqual(merged.count, facts.count)
        XCTAssertEqual(Set(merged.map(\.sourceHash)).count, merged.count)

        let original = facts[0]
        let weaker = LifeContextFact(
            kind: original.kind, label: original.label, summary: original.summary, date: original.date,
            confidence: 0.61, sourceHash: original.sourceHash, observedAt: original.observedAt
        )
        let kept = MessageContextEngine.merge([weaker], into: [original])
        XCTAssertEqual(kept, [original], "the more confident copy wins")
    }

    func testSharingTheSameConversationTwiceAddsNothing() {
        let turns = broadConversation()
        let once = engine.extract(from: turns)
        let twice = engine.merge(engine.extract(from: turns), into: once)
        XCTAssertEqual(once, twice)
    }

    func testMergeDropsBelowThreshold() {
        let low = LifeContextFact(
            kind: .plan, label: "coffee", summary: "Coffee with a friend", date: nil,
            confidence: 0.4, sourceHash: "aa", observedAt: at()
        )
        XCTAssertTrue(MessageContextEngine.merge([low], into: []).isEmpty)
    }

    func testCapIsTwoHundredWithOldestFirstEviction() {
        let facts = (0..<250).map { index in
            LifeContextFact(
                kind: .plan, label: "dinner", summary: "Dinner with a friend", date: nil, confidence: 0.8,
                sourceHash: "h\(1000 + index)", observedAt: at().addingTimeInterval(TimeInterval(index * 60))
            )
        }
        let kept = MessageContextEngine.merge(facts, into: [])
        XCTAssertEqual(kept.count, 200)
        XCTAssertEqual(kept.first?.sourceHash, "h1050", "the fifty oldest are evicted")
        XCTAssertEqual(kept.last?.sourceHash, "h1249")
    }

    func testExtractionAlsoCapsAtTwoHundred() {
        let start = at(1, month: 10)
        let turns = (0..<250).map { index -> MessageTurn in
            let day = calendar.date(byAdding: .day, value: index, to: start)!
            let parts = calendar.dateComponents([.month, .day], from: day)
            let month = ["January", "February", "March", "April", "May", "June", "July", "August",
                         "September", "October", "November", "December"][parts.month! - 1]
            return MessageTurn(
                sender: .me,
                text: "Dinner with my family on \(month) \(parts.day!)",
                timestamp: at().addingTimeInterval(TimeInterval(index))
            )
        }
        let facts = engine.extract(from: turns)
        XCTAssertEqual(facts.count, 200)
        XCTAssertEqual(facts.first?.observedAt, at().addingTimeInterval(50))
        XCTAssertEqual(Set(facts.map(\.sourceHash)).count, 200)
    }

    func testDifferentKeysGiveDifferentHashes() {
        let other = MessageContextEngine(
            hashKey: LifeContextHashKey(bytes: Data(repeating: 9, count: 32))!,
            configuration: .init(calendar: calendar)
        )
        let turns = [turn(.me, "I'm so stressed", minute: 0)]
        XCTAssertNotEqual(engine.extract(from: turns).first?.sourceHash, other.extract(from: turns).first?.sourceHash)
    }

    // MARK: Privacy

    func testNoVerbatimLeakage() {
        let turns = broadConversation()
        let facts = engine.extract(from: turns)
        XCTAssertGreaterThanOrEqual(facts.count, 6)
        for fact in facts {
            for field in [fact.summary, fact.label, fact.sourceHash, fact.kind.rawValue] {
                for source in turns {
                    XCTAssertNil(
                        Self.sharedRun(field, source.text, longerThan: 4),
                        "\(fact.kind) repeats input verbatim"
                    )
                }
            }
        }
    }

    func testSummaryThatWouldEchoTheInputIsCut() {
        let text = "Dinner with a friend Friday 7pm"
        let facts = engine.extract(from: [turn(.me, text, minute: 0)])
        XCTAssertEqual(facts.first?.summary, "Plan Friday 7pm")
        for fact in facts {
            XCTAssertNil(Self.sharedRun(fact.summary, text, longerThan: 4))
        }
    }

    func testPhoneNumbersAndEmailsNeverReachTheEngine() {
        let turn = MessageTurn(
            sender: .me,
            text: "Call me at 415-555-0132 or write sam.lee@example.com, card 4111 1111 1111 1111",
            timestamp: at()
        )
        XCTAssertFalse(turn.text.contains("555"))
        XCTAssertFalse(turn.text.contains("example.com"))
        XCTAssertFalse(turn.text.contains("4111"))
        XCTAssertFalse(String(describing: turn).contains("Call me"), "a turn never prints its text")
    }

    func testContactIDIsAHashNotAName() {
        let id = ContactID(hashing: "Sam", key: key)
        XCTAssertTrue(id.value.hasPrefix("c_"))
        XCTAssertFalse(id.value.lowercased().contains("sam"))
        XCTAssertEqual(id, ContactID(hashing: "  sam ", key: key))
        XCTAssertEqual(
            ContactID(hashing: "+1 (415) 555-0132", key: key),
            ContactID(hashing: "14155550132", key: key)
        )
    }

    // MARK: Brief

    func testContextBriefMatchesTheHandoffShape() {
        let now = at(minute: 30)
        let facts = [
            LifeContextFact(kind: .plan, label: "dinner", summary: "Dinner with a friend Friday 7pm",
                            date: at(2, month: 10, hour: 19), confidence: 0.95, sourceHash: "a", observedAt: at()),
            LifeContextFact(kind: .travel, label: "trip", summary: "Trip", date: nil, confidence: 0.7,
                            sourceHash: "b", observedAt: at(28)),
            LifeContextFact(kind: .travel, label: "flight", summary: "Flight Oct 20", date: at(20, month: 10),
                            confidence: 0.75, sourceHash: "c", observedAt: at(27)),
            LifeContextFact(kind: .stressSignal, label: "stress", summary: "Stress signal", date: nil,
                            confidence: 0.8, sourceHash: "d", observedAt: at()),
            LifeContextFact(kind: .stressSignal, label: "stress", summary: "Stress signal", date: nil,
                            confidence: 0.8, sourceHash: "e", observedAt: at(10)),
        ]
        XCTAssertEqual(
            LifeContextBrief.render(facts, now: now, calendar: calendar),
            "Friday: dinner plan, high confidence; this week: 2 travel mentions, 1 stress signal"
        )
        XCTAssertEqual(
            LifeContextBrief.ariaTags(facts, now: now, calendar: calendar),
            ["life_context:plan:dinner:d3", "life_context:week:travel:2", "life_context:week:stressSignal:1"]
        )
        XCTAssertNil(LifeContextBrief.render([], now: now, calendar: calendar))
    }

    func testBriefNeverEchoesAStoredLabelItDidNotWrite() {
        let tampered = LifeContextFact(kind: .plan, label: "Dinner with Sam at 555-0132", summary: "x",
                                       date: at(30), confidence: 0.9, sourceHash: "z", observedAt: at())
        let brief = LifeContextBrief.render([tampered], now: at(), calendar: calendar) ?? ""
        XCTAssertFalse(brief.contains("Sam"))
        XCTAssertEqual(brief, "Tomorrow: item plan, high confidence")
    }

    // MARK: Helpers

    /// A week of conversation touching every kind.
    private func broadConversation() -> [MessageTurn] {
        [
            turn(sam, "Want to grab dinner Friday at 7?", minute: 0),
            turn(.me, "Yes! See you then", minute: 1),
            turn(.me, "My flight lands Thursday at 6pm", minute: 2),
            turn(.me, "Work has been insane, I'm so overwhelmed and stressed", minute: 3),
            turn(sam, "My sister's wedding is Saturday, you're coming right?", minute: 4),
            turn(.me, "Definitely, can't wait", minute: 5),
            turn(.me, "I'll send the report by Friday", minute: 6),
            turn(.me, "Ugh I'm so sick, fever all night", minute: 7),
            turn(.me, "Love you mom, miss you", minute: 8),
            turn(sam, "Love you too sweetheart", minute: 9),
            turn(sam, "We should get coffee sometime", minute: 10),
            turn(.me, "maybe!", minute: 11),
        ]
    }

    /// The first run of more than `limit` consecutive words that `output`
    /// shares with `input`, or nil. Written independently of the engine's own
    /// guard so the test does not grade the code with itself.
    static func sharedRun(_ output: String, _ input: String, longerThan limit: Int) -> String? {
        func words(_ text: String) -> [String] {
            text.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        }
        let out = words(output)
        let source = words(input)
        let size = limit + 1
        guard out.count >= size, source.count >= size else { return nil }
        let outputRuns = Set((0...(out.count - size)).map { out[$0..<($0 + size)].joined(separator: " ") })
        for start in 0...(source.count - size) {
            let run = source[start..<(start + size)].joined(separator: " ")
            if outputRuns.contains(run) { return run }
        }
        return nil
    }
}
