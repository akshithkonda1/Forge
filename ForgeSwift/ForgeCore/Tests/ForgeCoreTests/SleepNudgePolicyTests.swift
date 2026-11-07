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
        UserDefaults(suiteName: WatchSnapshotStore.appGroupID)?
            .removeObject(forKey: SleepNudgePolicy.phoneWindDownScheduledAtKey)
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
        XCTAssertNil(nested.phoneScheduledAt)

        let stamped = Date(timeIntervalSince1970: 1_800_000_000)
        let topLevel = SleepNudgePolicy.nudgeFlags(from: [
            SleepNudgePolicy.quietWeekDefaultsKey: false,
            SleepNudgePolicy.phoneWindDownScheduledKey: true,
            SleepNudgePolicy.phoneWindDownScheduledAtKey: stamped,
        ])
        XCTAssertEqual(topLevel.quietWeek, false)
        XCTAssertEqual(topLevel.phoneWindDownScheduled, true)
        XCTAssertEqual(topLevel.phoneScheduledAt, stamped)

        let missing = SleepNudgePolicy.nudgeFlags(from: [
            CompanionConfig.nestedKey: ["forge.aria.baseURL": "https://example.com"],
        ])
        XCTAssertNil(missing.quietWeek)
        XCTAssertNil(missing.phoneWindDownScheduled)
        XCTAssertNil(missing.phoneScheduledAt)
    }

    func testWatchMayFireWhenPhoneFlagMissing() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(
            SleepNudgePolicy.watchMayFire(
                windDownStart: now.addingTimeInterval(3_600),
                now: now,
                quietWeek: false,
                phoneWindDownScheduled: nil,
                phoneScheduledAt: nil
            )
        )
        XCTAssertTrue(
            SleepNudgePolicy.watchMayFire(
                windDownStart: now.addingTimeInterval(3_600),
                now: now,
                quietWeek: false,
                phoneWindDownScheduled: true,
                phoneScheduledAt: nil
            ),
            "a true flag without a timestamp is untrusted — Watch fail-opens"
        )
    }

    func testWatchMayFireWhenPhoneFlagStale() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(
            SleepNudgePolicy.watchMayFire(
                windDownStart: now.addingTimeInterval(3_600),
                now: now,
                quietWeek: false,
                phoneWindDownScheduled: true,
                phoneScheduledAt: now.addingTimeInterval(-(SleepNudgePolicy.maxPhoneScheduleAge + 1))
            )
        )
    }

    func testWatchMayFireSkipsWhenPhoneFlagFreshTrue() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertFalse(
            SleepNudgePolicy.watchMayFire(
                windDownStart: now.addingTimeInterval(3_600),
                now: now,
                quietWeek: false,
                phoneWindDownScheduled: true,
                phoneScheduledAt: now.addingTimeInterval(-60)
            )
        )
    }

    func testWatchMayFireSkipsDuringQuietWeek() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertFalse(
            SleepNudgePolicy.watchMayFire(
                windDownStart: now.addingTimeInterval(3_600),
                now: now,
                quietWeek: true,
                phoneWindDownScheduled: nil,
                phoneScheduledAt: nil
            )
        )
    }

    func testWatchMayFireSkipsPastWindDownStart() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertFalse(
            SleepNudgePolicy.watchMayFire(
                windDownStart: now.addingTimeInterval(-1),
                now: now,
                quietWeek: false,
                phoneWindDownScheduled: nil,
                phoneScheduledAt: nil
            )
        )
    }
}
