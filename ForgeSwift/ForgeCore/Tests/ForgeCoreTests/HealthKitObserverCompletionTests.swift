import XCTest
@testable import ForgeCore

/// BH-15: HealthKitManager wiring, not just the gate.
/// Fails on main/0d1426ca where `startBidirectionalSync` calls `completion()`
/// before `scheduleLiveRefresh` finishes. A revert of that call site must fail.
final class HealthKitObserverCompletionTests: XCTestCase {

    override func setUp() {
        super.setUp()
        HealthKitObserverGate.resetTestState()
    }

    func testHealthKitManagerCallSiteDoesNotCompleteBeforeRefresh() throws {
        let source = try HealthKitObserverCallSite.loadHealthKitManagerSource()
        XCTAssertFalse(
            source.isEmpty,
            "HealthKitManager.swift must be readable from ForgeCore tests"
        )
        XCTAssertFalse(
            HealthKitObserverCallSite.startBidirectionalSyncBody(source).isEmpty,
            "startBidirectionalSync() must exist in HealthKitManager.swift"
        )
        XCTAssertTrue(
            HealthKitObserverCallSite.usesCompletionGate(source),
            "startBidirectionalSync must use HealthKitObserverGate.run or handleObserverDelivery"
        )
        XCTAssertFalse(
            HealthKitObserverCallSite.completesBeforeRefresh(source),
            "HKObserverQuery must not call completion() before refresh (0d1426ca BH-15)"
        )
    }

    func testCompletionRunsAfterBackgroundRefresh() async {
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
        await HealthKitObserverGate.run(
            observerError: nil,
            work: { throw Probe.boom },
            completion: { count += 1 }
        )
        XCTAssertEqual(count, 1)
    }
}
