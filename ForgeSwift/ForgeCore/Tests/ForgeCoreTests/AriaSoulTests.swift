import XCTest
@testable import ForgeCore

final class AriaSoulTests: XCTestCase {

    func testEveryPersonalityAndBlendKeepsRails() {
        let configs = [
            AriaSoul.Config(blend: .coach),
            AriaSoul.Config(blend: .friend),
            AriaSoul.Config(blend: .drillSergeant),
            AriaSoul.Config(blend: AriaSoul.fuse(
                experience: "beginner", goals: [], engagement: 0.2, override: nil
            )),
            AriaSoul.Config(blend: AriaSoul.fuse(
                experience: "elite", goals: ["competition"], engagement: 0.8, override: nil
            )),
        ]
        for config in configs {
            let directive = AriaSoul.directive(config)
            XCTAssertTrue(directive.lowercased().contains("not a doctor"), config.blend.dominant.label)
            XCTAssertTrue(directive.lowercased().contains("never say recovery"))
            XCTAssertFalse(AriaSoul.containsRailBreak(directive))
            XCTAssertFalse(ForgeReinforcement.containsBlame(directive))
        }
        XCTAssertTrue(AriaSoul.containsRailBreak("You failed. Time for recovery."))
        XCTAssertEqual(AriaSoul.sanitize("You failed").lowercased().contains("failed"), false)
    }

    func testSnarkySoulCannotBreakRails() {
        XCTAssertTrue(AriaSoul.Personality.drillSergeant.flavor.lowercased().contains("snarky"))
        let attempted = "You failed the set. Shame on you. Time for recovery. I diagnose overtraining and prescribe rest."
        let spoken = AriaSoul.speak(attempted, config: AriaSoul.Config(blend: .drillSergeant))
        XCTAssertFalse(AriaSoul.containsRailBreak(spoken), spoken)
        XCTAssertFalse(spoken.lowercased().contains("recovery"))
        XCTAssertFalse(spoken.lowercased().contains("you failed"))
        XCTAssertFalse(spoken.lowercased().contains("shame on you"))
        XCTAssertFalse(spoken.lowercased().contains("diagnos"))
        XCTAssertFalse(spoken.lowercased().contains("prescribe"))
        XCTAssertEqual(AriaSoul.version, "1")
        XCTAssertTrue(AriaSoul.rails.contains { $0.lowercased().contains("not a doctor") })
        XCTAssertTrue(AriaSoul.bedrockOff)
    }

    func testOverrideAnchorsAndMidConversationSwitchIsPerReply() {
        let fused = AriaSoul.fuse(experience: "beginner", goals: [], engagement: 0, override: nil)
        XCTAssertEqual(fused.dominant, .coach)
        XCTAssertGreaterThan(fused.friend, 0)
        let first = AriaSoul.directive(AriaSoul.Config(blend: fused))
        let switched = AriaSoul.fuse(
            experience: "beginner", goals: [], engagement: 0, override: .drillSergeant
        )
        XCTAssertEqual(switched.anchor, .drillSergeant)
        let second = AriaSoul.directive(AriaSoul.Config(blend: switched))
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(second.contains("Drill Sergeant"))
    }

    func testHealthFilterSkipsJobHuntingUnlessStressOrSleep() {
        if case .skip = AriaHealthFilter.decide("I'm looking for a job") {
            // expected
        } else {
            XCTFail("job hunting should not be stored")
        }
        if case .storeHealthAngle(_, let excerpt) = AriaHealthFilter.decide(
            "I'm looking for a job and it's wrecking my sleep"
        ) {
            XCTAssertTrue(excerpt.lowercased().contains("sleep"))
            XCTAssertFalse(excerpt.lowercased().contains("looking for a job"))
        } else {
            XCTFail("sleep-framed job stress should keep the health angle")
        }
    }

    func testPausedDetects503() {
        XCTAssertTrue(AriaPaused.isPaused(status: 503, code: "aria_paused"))
        XCTAssertTrue(AriaPaused.isPaused(status: 503, code: nil))
        XCTAssertFalse(AriaPaused.isPaused(status: 200, code: "aria_paused"))
        XCTAssertTrue(AriaPaused.line.lowercased().contains("taking a break"))
    }

    func testReinforcementBlocksBlame() {
        XCTAssertTrue(ForgeReinforcement.containsBlame("You failed the set"))
        XCTAssertFalse(ForgeReinforcement.reframe(whatHappened: "The set didn't finish.").lowercased().contains("you failed"))
    }

    func testIngestSkipsJobHuntingAndStoresHealthAngle() {
        let empty = AriaContextMemory.Snapshot()
        let skipped = AriaContextMemory.ingest(empty, text: "I'm looking for a job", source: "chat")
        XCTAssertTrue(skipped.items.isEmpty)

        let kept = AriaContextMemory.ingest(
            empty,
            text: "I'm looking for a job and it's wrecking my sleep",
            source: "chat"
        )
        XCTAssertFalse(kept.items.isEmpty)
        XCTAssertTrue(kept.items.contains { $0.text.lowercased().contains("sleep") })
        XCTAssertFalse(kept.items.contains { $0.text.lowercased().contains("looking for a job") })
    }
}
