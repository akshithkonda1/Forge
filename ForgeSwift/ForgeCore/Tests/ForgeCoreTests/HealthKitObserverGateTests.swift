import XCTest
@testable import ForgeCore

/// Would fail on the BH-15/BH-16 pattern: completion() before work, and a
/// swallowed throw that never called completion (or called it twice).
final class HealthKitObserverGateTests: XCTestCase {

    override func setUp() {
        super.setUp()
        HealthKitObserverGate.resetTestState()
    }

    func testCompletionRunsAfterRefreshWork() async {
        var order: [String] = []
        await HealthKitObserverGate.run(
            observerError: nil,
            work: {
                try await Task.sleep(nanoseconds: 20_000_000)
                order.append("refresh")
            },
            completion: { order.append("completion") }
        )
        XCTAssertEqual(order, ["refresh", "completion"])
    }

    func testCompletionRunsExactlyOnceWhenWorkThrows() async {
        enum Probe: Error { case boom }
        var count = 0
        var workStarted = false
        await HealthKitObserverGate.run(
            observerError: nil,
            work: {
                workStarted = true
                throw Probe.boom
            },
            completion: { count += 1 }
        )
        XCTAssertTrue(workStarted)
        XCTAssertEqual(count, 1)
    }

    func testObserverErrorIsRecordedAndCompletionStillRunsOnce() async {
        enum Probe: Error { case observer }
        var count = 0
        await HealthKitObserverGate.run(
            observerError: Probe.observer,
            work: { },
            completion: { count += 1 }
        )
        XCTAssertEqual(count, 1)
        XCTAssertEqual(HealthKitObserverGate.lastObserverErrorDescription, Probe.observer.localizedDescription)
    }

    func testBackgroundDeliveryFailureIsNotSwallowed() {
        enum Probe: Error { case delivery }
        HealthKitObserverGate.recordBackgroundDeliveryFailure(
            typeIdentifier: "HKQuantityTypeIdentifierHeartRateVariabilitySDNN",
            error: Probe.delivery
        )
        XCTAssertEqual(
            HealthKitObserverGate.lastBackgroundDeliveryErrorDescription,
            "HKQuantityTypeIdentifierHeartRateVariabilitySDNN: \(Probe.delivery.localizedDescription)"
        )
    }
}
