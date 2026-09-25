import XCTest
@testable import ForgeCore

final class AriaKnowledgeLedgerTests: XCTestCase {

    func testFoldersSortNewestFirstAndCap() {
        var ledger = AriaKnowledgeLedger()
        ledger.file(AriaKnowledgeFact(
            category: .weSpokeAbout, kind: "chat", summary: "older", source: "chat",
            createdAt: Date(timeIntervalSince1970: 1)
        ))
        ledger.file(AriaKnowledgeFact(
            category: .weSpokeAbout, kind: "chat", summary: "newer", source: "chat",
            createdAt: Date(timeIntervalSince1970: 2)
        ))
        let spoke = ledger.facts(in: .weSpokeAbout)
        XCTAssertEqual(spoke.first?.summary, "newer")
        XCTAssertEqual(spoke.count, 2)
        XCTAssertTrue(ledger.facts(in: .appleHealth).isEmpty)
    }

    func testReplaceKeepsWeSpokeAboutWhenHealthPackResets() {
        var ledger = AriaKnowledgeLedger()
        ledger.file(AriaKnowledgeFact(
            category: .weSpokeAbout, kind: "chat", summary: "wedding in 2 weeks", source: "chat"
        ))
        ledger.replace(
            category: .appleHealth,
            source: "test-ready-pack",
            with: [
                AriaKnowledgeFact(
                    category: .appleHealth, kind: "sleep", summary: "7.6h last night",
                    source: "test-ready-pack"
                )
            ]
        )
        XCTAssertEqual(ledger.facts(in: .weSpokeAbout).first?.summary, "wedding in 2 weeks")
        XCTAssertEqual(ledger.facts(in: .appleHealth).first?.kind, "sleep")
    }

    func testSpokenWeddingParser() {
        XCTAssertEqual(SpokenEventParser.daysUntilWedding(in: "I have a wedding in 2 weeks"), 14)
        XCTAssertEqual(SpokenEventParser.daysUntilWedding(in: "wedding in two weeks"), 14)
        XCTAssertEqual(SpokenEventParser.daysUntilWedding(in: "the wedding is tomorrow"), 1)
        XCTAssertNil(SpokenEventParser.daysUntilWedding(in: "I slept badly"))
    }

    func testWeeklyMoodRoundTrip() {
        var ledger = AriaKnowledgeLedger()
        ledger.file(AriaKnowledgeFact(
            category: .weSpokeAbout, kind: "weekly_mood", summary: "2", source: "weekly"
        ))
        XCTAssertEqual(ledger.latestWeeklyMood(), 2)
    }

    func testWeeklyMoodScaleReadsGollumAndHappy() {
        XCTAssertEqual(WeeklyMoodScale.score(from: "felt like Gollum all week"), 2)
        XCTAssertEqual(WeeklyMoodScale.score(from: "happy with family"), 8)
        XCTAssertNil(WeeklyMoodScale.score(from: "   "))
    }

    func testEmptyCalendarReplaceClearsOtherData() {
        var ledger = AriaKnowledgeLedger()
        ledger.file(AriaKnowledgeFact(
            category: .otherData, kind: "calendar_week", summary: "This week: wedding.", source: "calendar"
        ))
        ledger.file(AriaKnowledgeFact(
            category: .weSpokeAbout, kind: "chat", summary: "keep me", source: "chat"
        ))
        ledger.replace(category: .otherData, source: "calendar", with: [])
        XCTAssertTrue(ledger.facts(in: .otherData).isEmpty)
        XCTAssertEqual(ledger.facts(in: .weSpokeAbout).first?.summary, "keep me")
    }

    func testFakeHealthPackKnowledgeFactsStayAnonymous() {
        let pack = FakeHealthPack.generate(seed: 42)
        let facts = pack.knowledgeFacts(source: "test-ready-pack")
        XCTAssertFalse(facts.isEmpty)
        XCTAssertTrue(facts.allSatisfy { $0.category == .appleHealth })
        XCTAssertTrue(facts.allSatisfy { $0.source == "test-ready-pack" })
        let joined = facts.map(\.summary).joined(separator: " ")
        XCTAssertFalse(joined.lowercased().contains("street"))
        XCTAssertFalse(joined.lowercased().contains("@"))
        XCTAssertTrue(joined.contains(pack.personaLabel) || facts.contains { $0.kind == "persona" })
        XCTAssertNil(
            joined.range(of: #"\b(?:deep|rem|light)\s+sleep\s+at\s+\d"#, options: .regularExpression)
        )
    }

    func testSleepNightBodyNotesStayQualitative() {
        var ledger = AriaKnowledgeLedger()
        ledger.file(AriaKnowledgeFact(
            category: .appleHealth,
            kind: "sleep",
            summary: "Last night: deep sleep at 21%. REM is light at 12%. Keep it qualitative.",
            source: "apple-health"
        ))
        let summary = ledger.facts(in: .appleHealth).first?.summary ?? ""
        XCTAssertFalse(summary.lowercased().contains("sleep at"))
        XCTAssertFalse(summary.lowercased().contains("%"))
        XCTAssertTrue(summary.lowercased().contains("qualitative"))
        XCTAssertEqual(ledger.facts.first?.source, "apple-health")
    }
}
