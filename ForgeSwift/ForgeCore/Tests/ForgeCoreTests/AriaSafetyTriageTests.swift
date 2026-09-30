import XCTest
@testable import ForgeCore

/// `shared/aria-safety-corpus.json`, row for row — the same file the Python
/// suite (`backend/tests/test_safety_triage.py`) asserts against guidance.py.
final class AriaSafetyTriageTests: XCTestCase {

    private struct Corpus: Decodable {
        struct Row: Decodable {
            let text: String
            let band: String
            let prose: String?
            let phase: String?
            let topic: String?
            let subject: String?
            let voice: String?
            let replyTopic: String?

            enum CodingKeys: String, CodingKey {
                case text, band, prose, phase, topic, subject, voice
                case replyTopic = "reply_topic"
            }
        }

        struct CheckIn: Decodable {
            let outcome: String
            let subject: String
            let selfHarm: Bool
            let relationshipLevel: Int
            let message: String

            enum CodingKeys: String, CodingKey {
                case outcome, subject, message
                case selfHarm = "self_harm"
                case relationshipLevel = "relationship_level"
            }
        }

        let turns: [Row]
        let answers: [Row]
        let checkIns: [CheckIn]

        enum CodingKeys: String, CodingKey {
            case turns, answers
            case checkIns = "check_ins"
        }
    }

    private static func loadCorpus() throws -> Corpus {
        // ForgeSwift/ForgeCore/Tests/ForgeCoreTests/<this file> -> repo root.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared")
            .appendingPathComponent("aria-safety-corpus.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Corpus.self, from: data)
    }

    private func assertRow(
        _ decision: AriaSafetyDecision?,
        _ row: Corpus.Row,
        expectReplyTopic: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let label = "«\(row.text)»"
        if row.band == AriaSafetyBand.coach {
            XCTAssertNil(decision, label, file: file, line: line)
            return
        }
        guard let decision else {
            XCTFail("\(label) expected \(row.band), got coach", file: file, line: line)
            return
        }
        XCTAssertEqual(decision.band, row.band, label, file: file, line: line)
        XCTAssertEqual(decision.prose, row.prose, label, file: file, line: line)
        XCTAssertEqual(decision.safety?.phase, row.phase, label, file: file, line: line)
        XCTAssertEqual(decision.safety?.topic, row.topic, label, file: file, line: line)
        XCTAssertEqual(decision.safety?.subject, row.subject, label, file: file, line: line)
        XCTAssertEqual(decision.safety?.voice, row.voice, label, file: file, line: line)
        if expectReplyTopic {
            XCTAssertEqual(decision.safety?.replyTopic, row.replyTopic, label, file: file, line: line)
        }
    }

    func testEveryLexiconPatternCompilesInICU() {
        XCTAssertGreaterThan(AriaSafetyLexicon.allPatterns.count, 30)
        for pattern in AriaSafetyLexicon.allPatterns {
            XCTAssertNoThrow(try NSRegularExpression(pattern: pattern), pattern)
        }
    }

    func testFirstTurnsMatchSharedCorpus() throws {
        let corpus = try Self.loadCorpus()
        XCTAssertGreaterThanOrEqual(corpus.turns.count, 80)
        for row in corpus.turns {
            XCTAssertEqual(AriaSafetyTriage.classifyBand(row.text), row.band, "«\(row.text)»")
            assertRow(AriaSafetyTriage.assess(row.text), row, expectReplyTopic: row.band == AriaSafetyBand.triage)
        }
    }

    func testTriageAnswersMatchSharedCorpus() throws {
        let corpus = try Self.loadCorpus()
        XCTAssertGreaterThanOrEqual(corpus.answers.count, 20)
        for row in corpus.answers {
            let decision = AriaSafetyTriage.assess(row.text, triageTopic: row.replyTopic)
            assertRow(decision, row, expectReplyTopic: false)
        }
    }

    func testCheckInsMatchSharedCorpus() throws {
        let corpus = try Self.loadCorpus()
        for row in corpus.checkIns {
            XCTAssertEqual(
                AriaSafetyTriage.checkInMessage(
                    outcome: row.outcome,
                    subject: row.subject,
                    relationshipLevel: row.relationshipLevel,
                    selfHarm: row.selfHarm
                ),
                row.message
            )
        }
    }

    func testGuidancePolicySpeaksTheSafetyCopyOn911AndTriageTurns() throws {
        let corpus = try Self.loadCorpus()
        let rows = corpus.turns.filter {
            $0.band == AriaSafetyBand.emergency || $0.band == AriaSafetyBand.triage
        }
        XCTAssertGreaterThan(rows.count, 40)
        for row in rows {
            let decision = AriaGuidancePolicy.decide(text: row.text)
            XCTAssertEqual(decision.band, .referOut, "«\(row.text)»")
            XCTAssertEqual(decision.line, row.prose, "«\(row.text)»")
            XCTAssertEqual(decision.safety?.phase, row.phase, "«\(row.text)»")
        }
    }

    func testVoiceTurnsOnForTriageAndOffAfterResolution() throws {
        let triage = try XCTUnwrap(AriaSafetyTriage.assess("I have chest pain"))
        XCTAssertEqual(triage.safety?.wantsVoice, true)
        XCTAssertEqual(triage.safety?.replyTopic, "chest_pain.self")
        XCTAssertNil(triage.safety?.checkIn)

        let resolved = try XCTUnwrap(AriaSafetyTriage.assess("no", triageTopic: "chest_pain.self"))
        XCTAssertEqual(resolved.safety?.isResolved, true)
        XCTAssertEqual(resolved.safety?.wantsVoice, false)
        XCTAssertEqual(resolved.safety?.checkIn?.after, "resolution")

        let escalated = try XCTUnwrap(AriaSafetyTriage.assess("yes", triageTopic: "chest_pain.self"))
        XCTAssertEqual(escalated.band, AriaSafetyBand.emergency)
        XCTAssertTrue(escalated.wantsEscalation)
        XCTAssertEqual(escalated.safety?.checkIn?.after, "escalation")
    }

    func testCheckInFollowsTheRelationship() {
        XCTAssertEqual(
            AriaSafetyTriage.checkInMessage(outcome: AriaSafetyBand.emergency, relationshipLevel: 1),
            "You were in an emergency. How are you feeling now?"
        )
        let bond = AriaSafetyTriage.checkInMessage(outcome: AriaSafetyBand.emergency, relationshipLevel: 8)
        XCTAssertTrue(bond.hasPrefix("Hey."))
        XCTAssertTrue(bond.contains("How are you feeling"))
    }

    func testSmartApostrophesAreFolded() {
        XCTAssertEqual(AriaSafetyTriage.classifyBand("I don\u{2019}t want to live anymore"), AriaSafetyBand.emergency)
        XCTAssertEqual(AriaSafetyTriage.normalize("He\u{2019}s CHOKING"), "he's choking")
    }

    func testTriageTopicWhitelist() {
        XCTAssertEqual(AriaSafetyTriage.parseTriageTopic("chest_pain.self")?.topic, "chest_pain")
        XCTAssertEqual(AriaSafetyTriage.parseTriageTopic("FAINT.other")?.subject, "other")
        XCTAssertEqual(AriaSafetyTriage.parseTriageTopic("ingestion")?.subject, "self")
        for bad in [nil, "", "bogus.self", "faint.them", "faint.self.extra", String(repeating: "x", count: 40)] {
            XCTAssertNil(AriaSafetyTriage.parseTriageTopic(bad), String(describing: bad))
        }
    }

    func testSessionDecodesTheBackendContract() throws {
        let json = """
        {"schema": 1, "phase": "resolved", "topic": "faint", "subject": "self", "voice": "off",
         "outcome": "coach_with_care",
         "check_in": {"after": "resolution", "message": "That could have been an emergency. How are you feeling now?"}}
        """
        let session = try JSONDecoder().decode(AriaSafetySession.self, from: Data(json.utf8))
        XCTAssertTrue(session.isResolved)
        XCTAssertFalse(session.wantsVoice)
        XCTAssertNil(session.replyTopic)
        XCTAssertEqual(session.checkIn?.after, "resolution")

        let triage = """
        {"schema": 1, "phase": "triage", "topic": "chest_pain", "subject": "self", "voice": "on",
         "outcome": null, "questions": ["Q1?", "Q2?"], "reply_topic": "chest_pain.self", "check_in": null}
        """
        let open = try JSONDecoder().decode(AriaSafetySession.self, from: Data(triage.utf8))
        XCTAssertEqual(open.replyTopic, "chest_pain.self")
        XCTAssertEqual(open.questions?.count, 2)
        XCTAssertNil(open.checkIn)
    }
}
