import XCTest
@testable import ForgeCore

final class AriaDeviceEgressTests: XCTestCase {

    func testComputedFactsAreBandsNotSamples() {
        let facts = AriaDeviceEgress.computedFacts(
            sleepHours: 5.4,
            readiness: 48,
            gymLabel: "Home",
            patternFlags: ["lateCaffeineShortSleep"],
            safetyChanged: true
        )
        XCTAssertEqual(facts.sleepBand, "short")
        XCTAssertEqual(facts.readinessBand, "low")
        XCTAssertEqual(facts.asRemoteMap["sleep_band"], "short")
        XCTAssertNil(facts.asRemoteMap["sleep_hours"])
        XCTAssertEqual(facts.asRemoteMap["safety_changed"], "true")
        XCTAssertFalse(facts.summary.lowercased().contains("5.4"))
        XCTAssertFalse(facts.summary.lowercased().contains("hrv"))
        XCTAssertFalse(AriaDeviceEgress.containsRawHealth(facts.summary))
        XCTAssertFalse(ForgeConditionSafety.containsBannedSpeech(facts.summary))
    }

    func testTodayLogAndSanitization() {
        let defaults = UserDefaults(suiteName: "forge.egress.\(UUID().uuidString)")!
        var log = AriaDeviceEgress.Log.empty
        let now = Date()
        log = AriaDeviceEgress.record(
            log,
            kind: .chatFacts,
            summary: "sleep short, readiness low, gym Home",
            factKeys: ["sleep_band", "readiness_band", "gym"],
            now: now
        )
        log = AriaDeviceEgress.record(
            log,
            kind: .serverVoice,
            summary: "HRV 38 ms with seizure notes",
            factKeys: [],
            now: now
        )
        let today = AriaDeviceEgress.today(log, now: now)
        XCTAssertEqual(today.count, 2)
        XCTAssertEqual(today.last?.kind, .chatFacts)
        XCTAssertEqual(today.first?.summary, "Computed facts only")
        XCTAssertFalse(today.contains { AriaDeviceEgress.containsRawHealth($0.summary) && $0.summary != "Computed facts only" })

        AriaDeviceEgress.save(log, defaults: defaults)
        let loaded = AriaDeviceEgress.load(defaults: defaults)
        XCTAssertEqual(loaded.events.count, 2)
    }

    func testUnknownBandsWhenNothingMeasured() {
        let facts = AriaDeviceEgress.computedFacts(
            sleepHours: nil,
            readiness: nil,
            gymLabel: "",
            patternFlags: [],
            safetyChanged: false
        )
        XCTAssertEqual(facts.sleepBand, "unknown")
        XCTAssertEqual(facts.readinessBand, "unknown")
        XCTAssertFalse(facts.keys.contains("safety_changed"))
    }
}
