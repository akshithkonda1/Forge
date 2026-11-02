import XCTest
import ForgeCore

/// Tess: run on Mac / Xcode. Locks BH-15 — completion after refresh work,
/// exactly once when work throws. Linux CI cannot execute XCTest here.
final class HealthKitObserverCompletionTests: XCTestCase {

    override func setUp() {
        super.setUp()
        HealthKitObserverGate.resetTestState()
    }

    func testCompletionRunsAfterRefresh() async {
        var order: [String] = []
        await HealthKitObserverGate.run(
            observerError: nil,
            work: {
                try await Task.sleep(nanoseconds: 10_000_000)
                order.append("refresh")
            },
            completion: { order.append("completion") }
        )
        XCTAssertEqual(order, ["refresh", "completion"])
    }

    func testCompletionRunsExactlyOnceOnThrow() async {
        enum Probe: Error { case boom }
        var count = 0
        await HealthKitObserverGate.run(
            observerError: nil,
            work: { throw Probe.boom },
            completion: { count += 1 }
        )
        XCTAssertEqual(count, 1)
    }
}
