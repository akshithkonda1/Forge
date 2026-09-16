import XCTest
@testable import ForgeCore

final class AriaSwarmTests: XCTestCase {

    func testRRAAndWatchAliases() {
        XCTAssertEqual(AriaSwarm.canonicalSource("RRA"), "oura")
        XCTAssertEqual(AriaSwarm.canonicalSource("Apple Watch"), "apple-watch")
        XCTAssertEqual(AriaSwarm.canonicalSource("apple-health"), "apple-watch")
        XCTAssertEqual(AriaSwarm.canonicalSource("WHOOP"), "whoop")
        XCTAssertNil(AriaSwarm.canonicalSource("simrunner"))
    }

    func testContextSplitsAcrossWhoopWatchOura() {
        let picture = AriaSwarm.run(snapshot: AriaSwarmSnapshot(
            sleepHours: 5.0,
            hrvMs: 40,
            readiness: 40,
            workoutLogged: true
        ))
        XCTAssertEqual(picture.name, "swarm")
        XCTAssertEqual(picture.slotName, "Grok")
        XCTAssertTrue(picture.agentic)
        XCTAssertEqual(picture.stages, ["read", "evaluate", "write"])
        let present = Set(picture.sources.filter(\.present).map(\.id))
        XCTAssertTrue(present.contains("whoop"))
        XCTAssertTrue(present.contains("oura"))
        XCTAssertTrue(present.contains("apple-watch"))
        XCTAssertEqual(picture.stance, "protect")
        XCTAssertFalse(picture.headline.isEmpty)
        XCTAssertFalse(picture.writes.isEmpty)
        XCTAssertFalse(picture.headline.contains("HRV"))
        XCTAssertFalse(picture.headline.contains("ms"))
    }

    func testMissingWearablesStayHonest() {
        let picture = AriaSwarm.run(snapshot: AriaSwarmSnapshot())
        XCTAssertEqual(picture.stance, "clarify")
        XCTAssertTrue(picture.headline.lowercased().contains("won't pretend")
                      || picture.headline.lowercased().contains("no wearable"))
        XCTAssertTrue(picture.agents.allSatisfy { $0.stance == "missing" })
        XCTAssertTrue(picture.agents.allSatisfy { $0.ops == AriaSwarm.stages })
    }

    func testUntaggedSamplesAreAttributed() {
        let picture = AriaSwarm.run(snapshot: AriaSwarmSnapshot(
            sleepHours: 5.0,
            hrvMs: 42,
            readiness: 40,
            samples: [
                AriaSwarmSample(type: "sleep", source: "simrunner"),
                AriaSwarmSample(type: "hrv", source: "simrunner"),
                AriaSwarmSample(type: "steps", source: nil),
            ]
        ))
        let present = Set(picture.sources.filter(\.present).map(\.id))
        XCTAssertTrue(present.contains("oura"))
        XCTAssertTrue(present.contains("whoop"))
        XCTAssertTrue(present.contains("apple-watch"))
    }

    func testFileWritesInferences() {
        let defaults = UserDefaults(suiteName: "aria-swarm-tests")!
        defaults.removePersistentDomain(forName: "aria-swarm-tests")
        let picture = AriaSwarm.run(snapshot: AriaSwarmSnapshot(
            sleepHours: 5.0, hrvMs: 40, readiness: 38
        ))
        let ledger = AriaSwarm.file(picture, defaults: defaults)
        XCTAssertFalse(ledger.facts(in: .inferences).isEmpty)
        XCTAssertEqual(ledger.latestSummary(kind: "swarm_picture"), picture.headline)
    }
}
