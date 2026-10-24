import XCTest
@testable import ForgeCore

final class HealthContinuityEnvelopeTests: XCTestCase {

    func testEnvelopeIsCloudKitPrivateNotForgeAPI() {
        var learner = HealthIngestLearner()
        learner.recordRecurringGap(source: "whoop", field: "hrv")
        let scout = HealthScout.inspect(
            samples: [],
            connectedSources: ["whoop"],
            expected: [.hrv],
            day: Date()
        )
        let envelope = HealthContinuityEnvelope.make(learner: learner, scout: scout)
        XCTAssertEqual(envelope.schemaVersion, 1)
        XCTAssertEqual(HealthContinuityEnvelope.cloudKitRecordType, "ForgeHealthContinuity")
        XCTAssertTrue(envelope.scoutTags.contains { $0.hasPrefix("scout_gap:") })
        XCTAssertFalse(HealthContinuityEnvelope.cloudKitZone.contains("forge.app"))
    }
}
