import XCTest
@testable import ForgeCore

final class SleepNudgePolicyTests: XCTestCase {

    private var injectedSuite = ""
    private var injected: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        injectedSuite = "forge.tests.nudge.\(UUID().uuidString)"
        injected = try XCTUnwrap(UserDefaults(suiteName: injectedSuite))
    }

    override func tearDownWithError() throws {
        UserDefaults().removePersistentDomain(forName: injectedSuite)
        UserDefaults(suiteName: WatchSnapshotStore.appGroupID)?
            .removeObject(forKey: SleepNudgePolicy.quietWeekDefaultsKey)
        UserDefaults(suiteName: WatchSnapshotStore.appGroupID)?
            .removeObject(forKey: SleepNudgePolicy.phoneWindDownScheduledKey)
        try super.tearDownWithError()
    }

    func testQuietWeekAllowsNothing() {
        let requested = SleepNudgePolicy.rankedIdentifiers
        XCTAssertEqual(SleepNudgePolicy.allowed(requested, quietWeek: true), [])
        XCTAssertEqual(
            SleepNudgePolicy.allowed(
                [
                    SleepWindDownNotice.phoneIdentifier,
                    SleepWindDownNotice.caffeineIdentifier,
                    SleepNudgePolicy.watchWindDownIdentifier,
                ],
                quietWeek: true
            ),
            []
        )
    }

    func testThreeRequestedReturnTwoInPriorityOrder() {
        let requested = [
            SleepNudgePolicy.watchWindDownIdentifier,
            SleepWindDownNotice.caffeineIdentifier,
            SleepWindDownNotice.phoneIdentifier,
        ]
        XCTAssertEqual(
            SleepNudgePolicy.allowed(requested, quietWeek: false),
            [
                SleepWindDownNotice.phoneIdentifier,
                SleepWindDownNotice.caffeineIdentifier,
            ]
        )
        XCTAssertEqual(
            SleepNudgePolicy.allowed(requested, quietWeek: false).count,
            SleepNudgePolicy.maxPerDay
        )
    }

    func testQuietWeekRoundTripsThroughInjectedAndAppGroupDefaults() {
        SleepNudgePolicy.setQuietWeek(true, defaults: injected)
        XCTAssertTrue(SleepNudgePolicy.isQuietWeek(defaults: injected))
        SleepNudgePolicy.setQuietWeek(false, defaults: injected)
        XCTAssertFalse(SleepNudgePolicy.isQuietWeek(defaults: injected))

        SleepNudgePolicy.setQuietWeek(true)
        XCTAssertTrue(SleepNudgePolicy.isQuietWeek())
        XCTAssertEqual(
            UserDefaults(suiteName: WatchSnapshotStore.appGroupID)?
                .bool(forKey: SleepNudgePolicy.quietWeekDefaultsKey),
            true
        )
        XCTAssertEqual(WatchSnapshotStore.appGroupID, "group.com.forge.ForgeSwift")
        SleepNudgePolicy.setQuietWeek(false)
        XCTAssertFalse(SleepNudgePolicy.isQuietWeek())
    }

    func testNudgeFlagsReadNestedStringsAndTopLevelBools() {
        let nested = SleepNudgePolicy.nudgeFlags(from: [
            CompanionConfig.nestedKey: [
                SleepNudgePolicy.quietWeekDefaultsKey: "true",
                SleepNudgePolicy.phoneWindDownScheduledKey: "false",
            ],
        ])
        XCTAssertEqual(nested.quietWeek, true)
        XCTAssertEqual(nested.phoneWindDownScheduled, false)

        let topLevel = SleepNudgePolicy.nudgeFlags(from: [
            SleepNudgePolicy.quietWeekDefaultsKey: false,
            SleepNudgePolicy.phoneWindDownScheduledKey: true,
        ])
        XCTAssertEqual(topLevel.quietWeek, false)
        XCTAssertEqual(topLevel.phoneWindDownScheduled, true)

        let missing = SleepNudgePolicy.nudgeFlags(from: [
            CompanionConfig.nestedKey: ["forge.aria.baseURL": "https://example.com"],
        ])
        XCTAssertNil(missing.quietWeek)
        XCTAssertNil(missing.phoneWindDownScheduled)
    }
}
