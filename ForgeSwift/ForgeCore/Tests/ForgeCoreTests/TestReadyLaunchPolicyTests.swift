import XCTest
@testable import ForgeCore

final class TestReadyLaunchPolicyTests: XCTestCase {

    func testHomeMustNotWaitOnHeavyIngest() {
        XCTAssertFalse(TestReadyLaunchPolicy.homeWaitsForHealthKitPackWrite)
        XCTAssertFalse(TestReadyLaunchPolicy.homeWaitsForCalendarYearWrite)
        XCTAssertFalse(TestReadyLaunchPolicy.homeWaitsForMedicationCatalog)
        XCTAssertFalse(TestReadyLaunchPolicy.homeWaitsForRemoteDashboard)
        XCTAssertFalse(TestReadyLaunchPolicy.homeWaitsForThirtyDayHealthQueries)
        XCTAssertFalse(TestReadyLaunchPolicy.homeWaitsForHealthKitAuthorizationSheet)
        XCTAssertFalse(TestReadyLaunchPolicy.calendarYearWriteRunsOnMainActor)
        XCTAssertEqual(TestReadyLaunchPolicy.seedDefaultsKey, "forge.testReady.sessionSeed.v2")
        XCTAssertEqual(TestReadyLaunchPolicy.healthKitInstalledSeedKey, "forge.testReady.healthKit.installedSeed.v1")
        XCTAssertEqual(TestReadyLaunchPolicy.calendarInstalledSeedKey, "forge.testReady.calendar.installedSeed.v1")
    }

    func testRewriteSkippedWhenInstalledSeedMatches() {
        XCTAssertFalse(TestReadyLaunchPolicy.shouldRewrite(installedSeed: 7, sessionSeed: 7))
        XCTAssertTrue(TestReadyLaunchPolicy.shouldRewrite(installedSeed: nil, sessionSeed: 7))
        XCTAssertTrue(TestReadyLaunchPolicy.shouldRewrite(installedSeed: 1, sessionSeed: 7))
    }

    func testSessionSeedIsStableWithinAProcess() {
        let suite = "forge.testReady.launch.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        var generated = 0
        let now = Date()
        let token = "process-a"
        let first = TestReadyLaunchPolicy.sessionSeed(
            now: now,
            defaults: defaults,
            processToken: token
        ) {
            generated += 1
            return 42
        }
        let second = TestReadyLaunchPolicy.sessionSeed(
            now: now,
            defaults: defaults,
            processToken: token
        ) {
            generated += 1
            return 99
        }
        XCTAssertEqual(first, 42)
        XCTAssertEqual(second, 42)
        XCTAssertEqual(generated, 1, "the same process must not mint a new seed")
        defaults.removePersistentDomain(forName: suite)
    }

    func testSessionSeedMintsForANewProcess() {
        let suite = "forge.testReady.launch.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let now = Date()
        let first = TestReadyLaunchPolicy.sessionSeed(
            now: now,
            defaults: defaults,
            processToken: "process-a"
        ) { 11 }
        let second = TestReadyLaunchPolicy.sessionSeed(
            now: now,
            defaults: defaults,
            processToken: "process-b"
        ) { 22 }
        XCTAssertEqual(first, 11)
        XCTAssertEqual(second, 22)
        defaults.removePersistentDomain(forName: suite)
    }

    func testStoredSeedRoundTrip() {
        let suite = "forge.testReady.store.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        XCTAssertNil(
            TestReadyLaunchPolicy.storedSeed(
                defaults,
                key: TestReadyLaunchPolicy.healthKitInstalledSeedKey
            )
        )
        TestReadyLaunchPolicy.storeSeed(
            88,
            defaults: defaults,
            key: TestReadyLaunchPolicy.healthKitInstalledSeedKey
        )
        XCTAssertEqual(
            TestReadyLaunchPolicy.storedSeed(
                defaults,
                key: TestReadyLaunchPolicy.healthKitInstalledSeedKey
            ),
            88
        )
        TestReadyLaunchPolicy.storeSeed(
            nil,
            defaults: defaults,
            key: TestReadyLaunchPolicy.healthKitInstalledSeedKey
        )
        XCTAssertNil(
            TestReadyLaunchPolicy.storedSeed(
                defaults,
                key: TestReadyLaunchPolicy.healthKitInstalledSeedKey
            )
        )
        defaults.removePersistentDomain(forName: suite)
    }
}
