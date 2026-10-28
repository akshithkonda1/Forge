import XCTest
@testable import ForgeCore

final class ForgeConditionSafetyTests: XCTestCase {

    func testEmptyDeclarationNeverGuesses() {
        let decision = ForgeConditionSafety.decide(
            .init(
                declared: [],
                sleepHours: 4.8,
                heatRisk: true,
                moveNames: ["Open Water Swim", "Rock Climbing"]
            )
        )
        XCTAssertEqual(decision, .none)
        XCTAssertFalse(decision.applied)
    }

    func testEpilepsyBlocksSoloSwimAndClimbWithoutNamingTheCondition() {
        let decision = ForgeConditionSafety.decide(
            .init(
                declared: [.epilepsy],
                sleepHours: 7.4,
                heatRisk: false,
                moveNames: ["Open Water Swim", "Rock Climbing", "Goblet Squat"]
            )
        )
        XCTAssertTrue(decision.applied)
        XCTAssertTrue(decision.blockedMoves.contains("Open Water Swim"))
        XCTAssertTrue(decision.blockedMoves.contains("Rock Climbing"))
        XCTAssertTrue(decision.keptMoves.contains("Goblet Squat"))
        XCTAssertTrue(decision.replacements.contains { $0.lowercased().contains("pool-side") })
        XCTAssertTrue(decision.replacements.contains { $0.lowercased().contains("floor") })
        XCTAssertTrue(decision.changeNote.lowercased().contains("safety rule"))
        XCTAssertFalse(ForgeConditionSafety.containsBannedSpeech(decision.changeNote))
        XCTAssertFalse(AriaCoachSpeechGuard.containsBanned(decision.changeNote))
        for line in decision.replacements {
            XCTAssertFalse(ForgeConditionSafety.containsBannedSpeech(line), line)
        }
    }

    func testSleepLossAndHeatFlagsStayPlain() {
        let decision = ForgeConditionSafety.decide(
            .init(
                declared: [.epilepsy],
                sleepHours: 5.2,
                heatRisk: true,
                moveNames: ["Push-Up"]
            )
        )
        XCTAssertEqual(Set(decision.flags), [.sleepLoss, .heat])
        XCTAssertTrue(decision.changeNote.lowercased().contains("short"))
        XCTAssertTrue(decision.changeNote.lowercased().contains("heat"))
        XCTAssertFalse(decision.changeNote.lowercased().contains("seizure"))
        XCTAssertFalse(decision.changeNote.lowercased().contains("medication"))
        XCTAssertEqual(
            ForgeConditionSafety.flagLine(.sleepLoss),
            "Last night ran short — keep intensity grounded."
        )
    }

    func testSeizuresDeclarationUsesSameRulesWithoutSayingSeizures() {
        let decision = ForgeConditionSafety.decide(
            .init(declared: [.seizures], moveNames: ["Swimming", "Hang Clean"])
        )
        XCTAssertTrue(decision.blockedMoves.contains("Swimming"))
        XCTAssertTrue(decision.blockedMoves.contains("Hang Clean"))
        XCTAssertFalse(ForgeConditionSafety.containsBannedSpeech(decision.changeNote))
        let line = ForgeConditionSafety.trainingLine([.epilepsy])
        XCTAssertTrue(line.lowercased().contains("swimming"))
        XCTAssertTrue(line.lowercased().contains("climbing"))
        XCTAssertFalse(ForgeConditionSafety.containsBannedSpeech(line))
        XCTAssertFalse(line.lowercased().contains("recovery"))
    }

    func testSanitizeStripsBannedCoachTokens() {
        let raw = "Seizure-aware plan with medication notes"
        let clean = ForgeConditionSafety.sanitize(raw)
        XCTAssertFalse(ForgeConditionSafety.containsBannedSpeech(clean))
        XCTAssertFalse(clean.lowercased().contains("seizure"))
        XCTAssertFalse(clean.lowercased().contains("medication"))
    }
}
