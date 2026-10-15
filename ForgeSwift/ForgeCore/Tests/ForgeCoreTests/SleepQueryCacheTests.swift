import XCTest
@testable import ForgeCore

final class SleepQueryCacheTests: XCTestCase {

    func testFingerprintSkipsUnchangedSessions() {
        let a = SleepQueryFingerprint.sessions([
            (date: "2026-10-13", hours: 7.4, wakeEpoch: 100),
        ])
        let b = SleepQueryFingerprint.sessions([
            (date: "2026-10-13", hours: 7.4, wakeEpoch: 100),
        ])
        let c = SleepQueryFingerprint.sessions([
            (date: "2026-10-14", hours: 7.4, wakeEpoch: 200),
        ])
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
        let cache = SleepQueryCache()
        let night = SleepNight(segments: [])
        cache.store(fingerprint: a, nights: [night], lastNight: night)
        XCTAssertEqual(cache.nightsIfUnchanged(b)?.count, 1)
        XCTAssertNil(cache.nightsIfUnchanged(c))
    }

#if canImport(HealthKit)
    func testSharedSleepCacheLookbackIsSixteenDays() {
        XCTAssertEqual(ForgeHealthQueries.sleepCacheLookbackDays, 16)
    }
#endif
}
