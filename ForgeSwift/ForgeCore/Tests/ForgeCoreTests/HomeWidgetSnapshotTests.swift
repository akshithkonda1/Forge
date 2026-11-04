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
        UserDefaults(suiteName: HomeWidgetSnapshotStore.appGroupID)?
            .removeObject(forKey: StandByMetricsStore.key)
        UserDefaults(suiteName: WatchSnapshotStore.appGroupID)?
            .removeObject(forKey: WatchSnapshotStore.key)
        super.tearDown()
    }

    func testSnapshotRoundTripsThroughTheAppGroup() {
        let snap = HomeWidgetSnapshot.preview
        HomeWidgetSnapshotStore.save(snap, reloadWidgets: false)
        let loaded = HomeWidgetSnapshotStore.load()
        XCTAssertEqual(loaded?.readiness, 84)
        XCTAssertEqual(loaded?.hydrationMl, 1_420)
        XCTAssertEqual(loaded?.cyclePhase, "follicular")
        XCTAssertNil(loaded?.tonightWindDown)
    }

    func testTonightWindDownRoundTrips() {
        var snap = HomeWidgetSnapshot.preview
        snap.tonightWindDown = Date(timeIntervalSince1970: 1_800_000_000)
        HomeWidgetSnapshotStore.save(snap, reloadWidgets: false)
        XCTAssertEqual(
            HomeWidgetSnapshotStore.load()?.tonightWindDown,
            Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    func testWatchSnapshotSaveSkipsWhenContentIsEqual() {
        var first = WatchSnapshot()
        first.sleepMinutes = 420
        first.tonightWindDown = Date(timeIntervalSince1970: 50)
        first.updatedAt = Date(timeIntervalSince1970: 1)
        WatchSnapshotStore.save(first, reloadWidgets: false)
        var second = first
        second.updatedAt = Date(timeIntervalSince1970: 99)
        WatchSnapshotStore.save(second, reloadWidgets: false)
        XCTAssertEqual(WatchSnapshotStore.load()?.updatedAt, Date(timeIntervalSince1970: 99))
        XCTAssertTrue(first.hasSameWidgetContent(as: second))
        XCTAssertTrue(WatchSnapshotStore.watchWidgetKinds.contains("SleepQualityComplication"))
        XCTAssertFalse(WatchSnapshotStore.watchWidgetKinds.contains(where: { $0.isEmpty }))
    }

    func testSaveSkipsWhenContentIsEqual() {
        var first = HomeWidgetSnapshot.preview
        first.updatedAt = Date(timeIntervalSince1970: 1)
        HomeWidgetSnapshotStore.save(first, reloadWidgets: false)
        var second = first
        second.updatedAt = Date(timeIntervalSince1970: 99)
        HomeWidgetSnapshotStore.save(second, reloadWidgets: false)
        let loaded = HomeWidgetSnapshotStore.load()
        XCTAssertEqual(loaded?.updatedAt, Date(timeIntervalSince1970: 1))
        XCTAssertTrue(first.hasSameWidgetContent(as: second))
        XCTAssertGreaterThanOrEqual(HomeWidgetSnapshotStore.reloadDebounceSeconds, 2)
        XCTAssertLessThanOrEqual(HomeWidgetSnapshotStore.reloadDebounceSeconds, 5)
        XCTAssertFalse(HomeWidgetSnapshotStore.homeWidgetKinds.contains(where: { $0.isEmpty }))
        XCTAssertTrue(HomeWidgetSnapshotStore.homeWidgetKinds.contains("ReadinessWidget"))
        XCTAssertFalse(HomeWidgetSnapshotStore.homeWidgetKinds.contains("LifestyleWidget"))
    }

    func testYesterdaysSnapshotDoesNotShowAsToday() {
        let calendar = Calendar(identifier: .gregorian)
        let morning = Date(timeIntervalSince1970: 1_800_000_000)
        var snap = HomeWidgetSnapshot.preview
        snap.updatedAt = morning
        // Same day: unchanged.
        XCTAssertEqual(snap.asOf(morning.addingTimeInterval(3_600), calendar: calendar), snap)
        // Next day: readiness, sleep and water drop; slow fields stay.
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: morning)!
        let rolled = snap.asOf(tomorrow, calendar: calendar)
        XCTAssertFalse(rolled.hasReadiness)
        XCTAssertEqual(rolled.readinessLabel, "—")
        XCTAssertEqual(rolled.hydrationMl, 0)
        XCTAssertEqual(rolled.sleepHours, 0)
        XCTAssertNil(rolled.sleepScore)
        XCTAssertEqual(rolled.cyclePhase, snap.cyclePhase)
        XCTAssertEqual(rolled.hydrationTargetMl, snap.hydrationTargetMl)
    }

    /// StandByNestProvider maps each timeline date through `asOf`, the same
    /// way Home widgets do. A snapshot written yesterday keeps last night
    /// until midnight, then readiness and sleep empty.
    func testStandByTimelineRollsOverAtMidnight() {
        let calendar = Calendar(identifier: .gregorian)
        let yesterdayEvening = Date(timeIntervalSince1970: 1_800_000_000)
        var snap = HomeWidgetSnapshot.preview
        snap.updatedAt = yesterdayEvening

        let sameDay = snap.asOf(yesterdayEvening, calendar: calendar)
        XCTAssertEqual(sameDay.readiness, snap.readiness)
        XCTAssertEqual(sameDay.sleepHours, snap.sleepHours)
        XCTAssertEqual(sameDay.sleepScore, snap.sleepScore)

        let midnight = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: yesterdayEvening)
        )!
        XCTAssertFalse(calendar.isDate(yesterdayEvening, inSameDayAs: midnight))

        // Same mapping StandByNestProvider.getTimeline uses: one entry per date.
        let dates = [yesterdayEvening, midnight]
        let entries = dates.map { (date: $0, snapshot: snap.asOf($0, calendar: calendar)) }
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].snapshot.readiness, 84)
        XCTAssertEqual(entries[0].snapshot.sleepHours, 7.4)
        XCTAssertEqual(entries[0].snapshot.sleepScore, 88)
        XCTAssertFalse(entries[1].snapshot.hasReadiness)
        XCTAssertEqual(entries[1].snapshot.sleepHours, 0)
        XCTAssertNil(entries[1].snapshot.sleepScore)
        XCTAssertEqual(entries[1].snapshot.cyclePhase, snap.cyclePhase)
    }

    func testSameContentOnANewDayStillRefreshesUpdatedAt() {
        var first = HomeWidgetSnapshot.preview
        first.updatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        HomeWidgetSnapshotStore.save(first, reloadWidgets: false)
        var second = first
        second.updatedAt = first.updatedAt.addingTimeInterval(3 * 86_400)
        HomeWidgetSnapshotStore.save(second, reloadWidgets: false)
        XCTAssertEqual(HomeWidgetSnapshotStore.load()?.updatedAt, second.updatedAt)
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

    func testStandByMetricsDefaultWhenNeverSaved() {
        // Explicit clear rather than relying solely on tearDown from
        // whichever test ran before this one — XCTest doesn't guarantee
        // declaration order between test methods.
        UserDefaults(suiteName: HomeWidgetSnapshotStore.appGroupID)?
            .removeObject(forKey: StandByMetricsStore.key)
        XCTAssertEqual(StandByMetricsStore.load(), StandByMetricKind.defaultSelection)
    }

    func testStandByMetricsRoundTripsAndReorders() {
        StandByMetricsStore.save([.hydration, .sleep], reloadWidgets: false)
        XCTAssertEqual(StandByMetricsStore.load(), [.hydration, .sleep])
    }

    func testStandByMetricsEmptySelectionIsIntentionalNotFallback() {
        // Unlike the Home board, "just Readiness and the clock" is a real
        // choice — an explicit empty save must not bounce back to defaults.
        StandByMetricsStore.save([], reloadWidgets: false)
        XCTAssertEqual(StandByMetricsStore.load(), [])
    }

    func testStandByMetricsDedupsOnLoad() {
        let defaults = UserDefaults(suiteName: HomeWidgetSnapshotStore.appGroupID)
        let data = try? JSONEncoder().encode([
            StandByMetricKind.sleep,
            .sleep,
            .hydration,
        ])
        defaults?.set(data, forKey: StandByMetricsStore.key)
        XCTAssertEqual(StandByMetricsStore.load(), [.sleep, .hydration])
    }

    func testLifestyleWidgetMissingSnapshotIsEmptyNotZeroQOL() {
        XCTAssertEqual(LifestyleWidgetContent.decode(nil), .empty)
        XCTAssertNil(LifestyleWidgetContent.decode(nil).snapshot)
    }

    func testLifestyleWidgetDecodeFailureIsEmptyNotZeroQOL() {
        let garbage = Data("{not-json".utf8)
        XCTAssertEqual(LifestyleWidgetContent.decode(garbage), .empty)
        XCTAssertNil(LifestyleWidgetContent.decode(garbage).snapshot)
    }

    func testLifestyleWidgetValidSnapshotLoadsQOL() {
        let snap = LifestyleWidgetSnapshot.preview
        let data = try? JSONEncoder().encode(snap)
        let content = LifestyleWidgetContent.decode(data)
        XCTAssertEqual(content.snapshot?.qol, snap.qol)
        XCTAssertEqual(content.snapshot?.topTitle, snap.topTitle)
    }
}
