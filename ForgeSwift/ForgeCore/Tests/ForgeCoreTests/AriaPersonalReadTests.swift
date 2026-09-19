import XCTest
@testable import ForgeCore

final class AriaPersonalReadTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "forge.tests.personalRead.\(UUID().uuidString)")
    }

    override func tearDown() {
        if let suite = defaults?.dictionaryRepresentation().keys {
            suite.forEach { defaults.removeObject(forKey: $0) }
        }
        defaults = nil
        super.tearDown()
    }

    func testShortNightIsWeakAndKeepLight() {
        let read = AriaPersonalRead.evaluate(
            nightHours: 5.2,
            deepMinutes: 40,
            remMinutes: 30,
            awakeMinutes: 40,
            hrvMs: 40,
            readiness: 48,
            chronologicalAge: 33,
            vo2Max: nil,
            restingHR: 62,
            defaults: defaults
        )
        XCTAssertTrue(read.sleepWeak)
        XCTAssertTrue(read.keepLight)
        XCTAssertEqual(read.sleepBand, "weak")
    }

    func testPersonalHRVBelowBaselineKeepsLight() {
        var baselines = BodyModelHRVBaselines()
        for i in 0..<8 {
            baselines.ingest(HRVObservation(statistic: .sdnn, milliseconds: 70, timestamp: Date().addingTimeInterval(Double(-i) * 86400)))
        }
        BodyModelHRVBaselineStore.save(baselines, defaults: defaults)
        let read = AriaPersonalRead.evaluate(
            nightHours: 7.5,
            deepMinutes: 90,
            remMinutes: 80,
            awakeMinutes: 20,
            hrvMs: 48,
            readiness: 72,
            chronologicalAge: 33,
            vo2Max: nil,
            restingHR: 55,
            defaults: defaults
        )
        XCTAssertTrue(read.hrvBelowPersonal)
        XCTAssertTrue(read.keepLight)
        XCTAssertNotNil(read.hrvBaselineMs)
    }

    func testCompanionLineComesFromLedger() {
        AriaKnowledgeLedgerStore.file(
            AriaKnowledgeFact(
                category: .weSpokeAbout,
                kind: "goal",
                summary: "Training for a first 10k",
                source: "test"
            ),
            defaults: defaults
        )
        let read = AriaPersonalRead.evaluate(
            nightHours: 7.4,
            deepMinutes: 80,
            remMinutes: 70,
            awakeMinutes: 15,
            hrvMs: 60,
            readiness: 80,
            chronologicalAge: nil,
            vo2Max: nil,
            restingHR: nil,
            defaults: defaults
        )
        XCTAssertEqual(read.companionLine, "Training for a first 10k")
        XCTAssertEqual(read.spokenGround, "Training for a first 10k")
    }

    func testSwarmProtectForcesEasyDay() {
        let picture = AriaSwarmPicture(
            name: "swarm",
            slotName: "Grok",
            agentic: true,
            stages: ["read", "evaluate", "write"],
            sources: [],
            agents: [],
            headline: "Protect today — recovery is asking.",
            stance: "protect",
            actions: [],
            writes: []
        )
        let read = AriaPersonalRead.evaluate(
            nightHours: 7.8,
            deepMinutes: 95,
            remMinutes: 90,
            awakeMinutes: 10,
            hrvMs: 62,
            readiness: 78,
            chronologicalAge: 30,
            vo2Max: 48,
            restingHR: 52,
            swarm: picture,
            defaults: defaults
        )
        XCTAssertTrue(read.swarmProtect)
        XCTAssertTrue(read.keepLight)
        XCTAssertEqual(read.swarmLine, "Protect today — recovery is asking.")
    }
}
