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
}
