import XCTest
@testable import ForgeCore

/// The gate is what stops "republish whenever the cycle recomputes" from turning
/// into a CloudKit write on every app foreground. Its whole value is in the
/// skips, so that is what these test.
final class PublishGateTests: XCTestCase {

    private struct Payload: Codable, Equatable {
        var phase: String
        var asOf: String
    }

    private var suiteName = ""
    private var defaults: UserDefaults!
    private var gate: PublishGate<Payload>!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "forge.tests.publishGate.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        gate = PublishGate<Payload>(key: "test", minimumInterval: 60, defaults: defaults)
    }

    override func tearDownWithError() throws {
        UserDefaults().removePersistentDomain(forName: suiteName)
        try super.tearDownWithError()
    }

    // MARK: - The common path

    func testFirstPublishAlwaysGoes() {
        XCTAssertEqual(gate.decide(Payload(phase: "bleeding", asOf: "2026-08-03")), .publish)
    }

    func testIdenticalValueIsSkipped() {
        let value = Payload(phase: "bleeding", asOf: "2026-08-03")
        gate.recordPublished(value)
        // This is the case that fires dozens of times a day: recompute ran, the
        // redacted digest did not move.
        XCTAssertEqual(gate.decide(value), .skipUnchanged)
    }

    func testUnchangedSkipIgnoresTheInterval() {
        // Order matters. An unchanged value must report `.skipUnchanged`, not
        // `.skipTooSoon` — a caller that schedules a retry on `.skipTooSoon`
        // would otherwise wake up repeatedly to publish nothing.
        let value = Payload(phase: "winding", asOf: "2026-08-03")
        gate.recordPublished(value, at: Date())
        XCTAssertEqual(gate.decide(value), .skipUnchanged)
    }

    func testANewDayPublishesEvenWhenTheStateIsIdentical() {
        // Freshness falls out of equality: the digest stamps its own day, so a
        // new day is a different value and needs no separate staleness timer.
        let yesterday = Payload(phase: "winding", asOf: "2026-08-02")
        gate.recordPublished(yesterday, at: Date().addingTimeInterval(-86_400))
        let today = Payload(phase: "winding", asOf: "2026-08-03")
        XCTAssertEqual(gate.decide(today), .publish)
    }

    // MARK: - Throttling

    func testChangedValueTooSoonIsHeldWithARetryHint() {
        gate.recordPublished(Payload(phase: "bleeding", asOf: "2026-08-03"),
                             at: Date().addingTimeInterval(-10))
        let decision = gate.decide(Payload(phase: "rebuilding", asOf: "2026-08-03"))
        guard case .skipTooSoon(let retryAfter) = decision else {
            return XCTFail("expected skipTooSoon, got \(decision)")
        }
        XCTAssertEqual(retryAfter, 50, accuracy: 1)
    }

    func testChangedValuePublishesOnceTheIntervalPasses() {
        gate.recordPublished(Payload(phase: "bleeding", asOf: "2026-08-03"),
                             at: Date().addingTimeInterval(-120))
        XCTAssertEqual(gate.decide(Payload(phase: "rebuilding", asOf: "2026-08-03")), .publish)
    }

    func testAClockThatMovedBackwardsDoesNotLockTheGate() {
        // Timezone change or a manual clock set. Without the guard, a watermark
        // in the future would hold the gate shut for however far ahead it sits —
        // and sharing would quietly stop updating with nothing to show for it.
        gate.recordPublished(Payload(phase: "bleeding", asOf: "2026-08-03"),
                             at: Date().addingTimeInterval(86_400))
        XCTAssertEqual(gate.decide(Payload(phase: "rebuilding", asOf: "2026-08-03")), .publish)
    }

    // MARK: - Failure handling

    func testAFailedPublishLeavesTheGateOpen() {
        // The contract that makes this safe: recordPublished is only called on
        // success. If a write fails and nothing is recorded, the very next
        // attempt must still go — otherwise the change is lost until the value
        // happens to move again, which for a cycle digest could be a full day.
        let value = Payload(phase: "bleeding", asOf: "2026-08-03")
        XCTAssertEqual(gate.decide(value), .publish)
        // ... publish throws, nothing recorded ...
        XCTAssertEqual(gate.decide(value), .publish)
    }

    // MARK: - Lifecycle

    func testResetForcesTheNextPublish() {
        let value = Payload(phase: "bleeding", asOf: "2026-08-03")
        gate.recordPublished(value)
        XCTAssertEqual(gate.decide(value), .skipUnchanged)

        // Revoking deletes the zone, so the record the watermark refers to is
        // gone. Re-sharing must write again rather than trust a stale match.
        gate.reset()
        XCTAssertEqual(gate.decide(value), .publish)
        XCTAssertNil(gate.lastPublishedAt)
    }

    func testWatermarkSurvivesANewGateInstance() {
        let value = Payload(phase: "bleeding", asOf: "2026-08-03")
        gate.recordPublished(value)
        // Relaunching the app must not re-upload identical content.
        let fresh = PublishGate<Payload>(key: "test", minimumInterval: 60, defaults: defaults)
        XCTAssertEqual(fresh.decide(value), .skipUnchanged)
        XCTAssertNotNil(fresh.lastPublishedAt)
    }

    func testTwoGatesWithDifferentKeysDoNotSeeEachOther() {
        let other = PublishGate<Payload>(key: "other", minimumInterval: 60, defaults: defaults)
        let value = Payload(phase: "bleeding", asOf: "2026-08-03")
        gate.recordPublished(value)
        XCTAssertEqual(other.decide(value), .publish)
    }

    func testNoStorageFallsOpenRatherThanShut() {
        // Publishing twice is recoverable; never publishing is a feature that
        // silently does nothing.
        let unbacked = PublishGate<Payload>(key: "test", minimumInterval: 60, defaults: nil)
        let value = Payload(phase: "bleeding", asOf: "2026-08-03")
        unbacked.recordPublished(value)
        XCTAssertEqual(unbacked.decide(value), .publish)
    }
}
