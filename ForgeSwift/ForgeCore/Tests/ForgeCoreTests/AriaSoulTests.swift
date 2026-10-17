import XCTest
@testable import ForgeCore

final class AriaSoulTests: XCTestCase {

    func testEveryPersonalityAndBlendKeepsRails() {
        XCTAssertEqual(
            AriaSoul.Personality.allCases.map(\.label),
            ["Coach", "Friend", "Drill Sergeant"]
        )
        let configs = AriaSoul.Personality.allCases.map { AriaSoul.Config(blend: blend($0)) } + [
            AriaSoul.Config(blend: AriaSoul.fuse(
                experience: "beginner", goals: [], engagement: 0.2, override: nil
            )),
            AriaSoul.Config(blend: AriaSoul.fuse(
                experience: "elite", goals: ["competition"], engagement: 0.8, override: nil
            )),
        ]
        let attempted = "You failed. Shame on you. Time for recovery. I diagnose this. Push through the pain."
        for config in configs {
            let directive = AriaSoul.directive(config)
            XCTAssertTrue(directive.lowercased().contains("not a doctor"), config.blend.dominant.label)
            XCTAssertTrue(directive.lowercased().contains("never say recovery"))
            XCTAssertTrue(directive.lowercased().contains("never shame"))
            XCTAssertTrue(directive.lowercased().contains("never push past comfort"))
            XCTAssertFalse(AriaSoul.containsRailBreak(directive), config.blend.dominant.label)
            XCTAssertFalse(ForgeReinforcement.containsBlame(directive))
            let spoken = AriaSoul.speak(attempted, config: config)
            XCTAssertFalse(AriaSoul.containsRailBreak(spoken), "\(config.blend.dominant.label): \(spoken)")
            XCTAssertFalse(spoken.lowercased().contains("recovery"))
            XCTAssertFalse(spoken.lowercased().contains("diagnos"))
            XCTAssertFalse(spoken.lowercased().contains("shame on you"))
            XCTAssertFalse(spoken.lowercased().contains("push through the pain"))
            XCTAssertFalse(ForgeReinforcement.containsBlame(spoken))
        }
        XCTAssertTrue(AriaSoul.containsRailBreak("You failed. Time for recovery."))
        XCTAssertEqual(AriaSoul.sanitize("You failed").lowercased().contains("failed"), false)
    }

    private func blend(_ personality: AriaSoul.Personality) -> AriaSoul.Blend {
        switch personality {
        case .coach: return .coach
        case .friend: return .friend
        case .drillSergeant: return .drillSergeant
        }
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

    func testBeginnerFusesCoachWithFriendWarmth() {
        let blend = AriaSoul.fuse(experience: "beginner", goals: [], engagement: 0, override: nil)
        XCTAssertGreaterThan(blend.coach, blend.friend)
        XCTAssertGreaterThan(blend.friend, 0)
        XCTAssertEqual(blend.drillSergeant, 0)
        XCTAssertNil(blend.anchor)
        let line = AriaSoul.directive(AriaSoul.Config(blend: blend))
        XCTAssertTrue(line.contains("Blend Coach"))
        XCTAssertTrue(line.contains("Friend"))
        XCTAssertFalse(AriaSoul.containsRailBreak(line))
    }

    func testPRFusesDrillSergeantWithCoachStructure() {
        let blend = AriaSoul.fuse(
            experience: "elite",
            goals: ["competition", "athletic-performance"],
            engagement: 0.8,
            override: nil
        )
        XCTAssertGreaterThan(blend.drillSergeant, 0)
        XCTAssertGreaterThan(blend.coach, 0)
        XCTAssertEqual(blend.dominant, .drillSergeant)
        let line = AriaSoul.directive(AriaSoul.Config(blend: blend))
        XCTAssertTrue(line.contains("Drill Sergeant"))
        XCTAssertTrue(line.contains("Coach"))
        XCTAssertFalse(AriaSoul.containsRailBreak(line))
        XCTAssertFalse(ForgeReinforcement.containsBlame(line))
    }

    func testEngagementRaisesDrillAndOverrideWins() {
        let low = AriaSoul.fuse(experience: "intermediate", goals: [], engagement: 0, override: nil)
        let high = AriaSoul.fuse(experience: "intermediate", goals: [], engagement: 1, override: nil)
        XCTAssertGreaterThan(high.drillSergeant, low.drillSergeant)
        let anchored = AriaSoul.fuse(
            experience: "beginner", goals: [], engagement: 1, override: .friend
        )
        XCTAssertEqual(anchored.anchor, .friend)
        XCTAssertEqual(anchored.dominant, .friend)
        XCTAssertEqual(anchored.friend, 1)
    }

    func testOverrideAnchorsAndMidConversationSwitchIsPerReply() {
        let fused = AriaSoul.fuse(experience: "beginner", goals: [], engagement: 0, override: nil)
        XCTAssertEqual(fused.dominant, .coach)
        XCTAssertGreaterThan(fused.friend, 0)
        var live = AriaSoul.Config(blend: fused)
        let first = AriaSoul.nextReply(draft: "Next move is easy.", config: live)
        XCTAssertTrue(first.soul.contains("Coach"))
        live = AriaSoul.Config(blend: AriaSoul.fuse(
            experience: "beginner", goals: [], engagement: 0, override: .drillSergeant
        ))
        let second = AriaSoul.nextReply(draft: "Next move is easy.", config: live)
        XCTAssertEqual(live.blend.anchor, .drillSergeant)
        XCTAssertNotEqual(first.soul, second.soul)
        XCTAssertTrue(second.soul.contains("Drill Sergeant"))
        XCTAssertTrue(second.soul.lowercased().contains("snarky"))
        XCTAssertFalse(AriaSoul.containsRailBreak(second.spoken))
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
        XCTAssertTrue(ForgeReinforcement.containsBlame("you did it wrong"))
        XCTAssertTrue(ForgeReinforcement.containsBlame("you skipped again"))
        XCTAssertTrue(ForgeReinforcement.containsBlame("you broke the streak"))
        XCTAssertFalse(ForgeReinforcement.reframe(whatHappened: "The set didn't finish.").lowercased().contains("you failed"))
        XCTAssertTrue(ForgeReinforcement.skippedWorkout.lowercased().contains("help and solve"))
        XCTAssertTrue(ForgeReinforcement.missedSet.lowercased().contains("help and solve"))
        XCTAssertTrue(ForgeReinforcement.brokenStreak.lowercased().contains("help and solve"))
        XCTAssertFalse(ForgeReinforcement.containsBlame(ForgeReinforcement.errorLine))
        XCTAssertEqual(ForgeReinforcement.speak("You failed the set"), ForgeReinforcement.reframe(whatHappened: ""))
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
