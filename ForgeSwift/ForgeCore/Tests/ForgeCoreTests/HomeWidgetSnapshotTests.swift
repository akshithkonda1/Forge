import XCTest
@testable import ForgeCore

final class HomeWidgetSnapshotTests: XCTestCase {

    override func tearDown() {
        UserDefaults(suiteName: HomeWidgetSnapshotStore.appGroupID)?
            .removeObject(forKey: HomeWidgetSnapshotStore.key)
        UserDefaults(suiteName: HomeWidgetSnapshotStore.appGroupID)?
            .removeObject(forKey: PendingWaterLog.key)
        UserDefaults(suiteName: HomeWidgetSnapshotStore.appGroupID)?
            .removeObject(forKey: HomeWidgetBoardStore.key)
        super.tearDown()
    }

    func testSnapshotRoundTripsThroughTheAppGroup() {
        let snap = HomeWidgetSnapshot.preview
        HomeWidgetSnapshotStore.save(snap, reloadWidgets: false)
        let loaded = HomeWidgetSnapshotStore.load()
        XCTAssertEqual(loaded?.readiness, 84)
        XCTAssertEqual(loaded?.hydrationMl, 1_420)
        XCTAssertEqual(loaded?.cyclePhase, "follicular")
    }

    func testHydrationFractionClamps() {
        var snap = HomeWidgetSnapshot(hydrationMl: 3_000, hydrationTargetMl: 2_000)
        XCTAssertEqual(snap.hydrationFraction, 1, accuracy: 0.001)
        snap.hydrationMl = 500
        XCTAssertEqual(snap.hydrationFraction, 0.25, accuracy: 0.001)
        snap.hydrationTargetMl = 0
        XCTAssertEqual(snap.hydrationFraction, 0, accuracy: 0.001)
    }

    func testPendingWaterQueuesAndDrains() {
        PendingWaterLog.enqueue(250)
        PendingWaterLog.enqueue(250)
        XCTAssertEqual(PendingWaterLog.drain(), 500, accuracy: 0.1)
        XCTAssertEqual(PendingWaterLog.drain(), 0, accuracy: 0.1)
    }

    func testPendingWaterIgnoresNonPositive() {
        PendingWaterLog.enqueue(-10)
        PendingWaterLog.enqueue(0)
        XCTAssertEqual(PendingWaterLog.drain(), 0, accuracy: 0.1)
    }

    func testBoardDefaultsWhenEmpty() {
        XCTAssertEqual(HomeWidgetBoardStore.load(), HomePinnedWidgetKind.defaultPins)
    }

    func testBoardAddIsIdempotentAndRemoveWorks() {
        HomeWidgetBoardStore.save([.hydration])
        HomeWidgetBoardStore.add(.sleep)
        HomeWidgetBoardStore.add(.sleep)
        XCTAssertEqual(HomeWidgetBoardStore.load(), [.hydration, .sleep])
        HomeWidgetBoardStore.remove(.hydration)
        XCTAssertEqual(HomeWidgetBoardStore.load(), [.sleep])
    }

    func testBoardDedupsOnLoad() {
        let defaults = UserDefaults(suiteName: HomeWidgetSnapshotStore.appGroupID)
        let data = try? JSONEncoder().encode([
            HomePinnedWidgetKind.hydration,
            .hydration,
            .sleep,
        ])
        defaults?.set(data, forKey: HomeWidgetBoardStore.key)
        XCTAssertEqual(HomeWidgetBoardStore.load(), [.hydration, .sleep])
    }

    func testAvailableToAddOmitsPinned() {
        let available = HomeWidgetBoardStore.availableToAdd(from: [.hydration, .sleep])
        XCTAssertFalse(available.contains(.hydration))
        XCTAssertTrue(available.contains(.cycle))
        XCTAssertTrue(available.contains(.workout))
    }
}
