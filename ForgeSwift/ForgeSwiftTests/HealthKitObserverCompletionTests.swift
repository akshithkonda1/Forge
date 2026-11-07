import XCTest
import ForgeCore
@testable import ForgeSwift

/// BH-15 call-site test. Must fail on main if HealthKitManager still calls
/// `completion()` before `scheduleLiveRefresh` (~:695 on 0d1426ca).
/// Exercising only HealthKitObserverGate is not enough — reverting the
/// `startBidirectionalSync` handler must fail this class.
final class HealthKitObserverCompletionTests: XCTestCase {

    override func setUp() {
        super.setUp()
        HealthKitObserverGate.resetTestState()
    }

    func testHealthKitManagerCallSiteDoesNotCompleteBeforeRefresh() throws {
        let source = try HealthKitObserverCallSite.loadHealthKitManagerSource()
        XCTAssertTrue(
            HealthKitObserverCallSite.usesCompletionGate(source),
            "startBidirectionalSync must await handleObserverDelivery / HealthKitObserverGate.run"
        )
        XCTAssertFalse(
            HealthKitObserverCallSite.completesBeforeRefresh(source),
            "completion() before scheduleLiveRefresh is the BH-15 bug on main"
        )
        let body = HealthKitObserverCallSite.startBidirectionalSyncBody(source)
        XCTAssertTrue(
            body.contains("handleObserverDelivery"),
            "observer query must call HealthKitManager.handleObserverDelivery"
        )
        XCTAssertFalse(
            body.contains("scheduleLiveRefresh()"),
            "fire-and-forget scheduleLiveRefresh + completion() is the main bug"
        )
    }

    func testManagerDeliveryRunsCompletionAfterRefresh() async {
        var order: [String] = []
        await HealthKitManager.shared.handleObserverDelivery(
            error: nil,
            completion: { order.append("completion") },
            refresh: {
                try await Task.sleep(nanoseconds: 15_000_000)
                order.append("refresh")
            }
        )
        XCTAssertEqual(order, ["refresh", "completion"])
    }

    func testManagerDeliveryRunsCompletionExactlyOnceWhenWorkThrows() async {
        enum Probe: Error { case boom }
        var count = 0
        await HealthKitManager.shared.handleObserverDelivery(
            error: nil,
            completion: { count += 1 },
            refresh: { throw Probe.boom }
        )
        XCTAssertEqual(count, 1)
    }
}
