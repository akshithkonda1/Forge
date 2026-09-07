import XCTest
@testable import ForgeCore

final class AriaHealthRiskMonitorTests: XCTestCase {

    func testNormalReadingsProduceNoFindings() {
        let reading = AriaVitalReading(
            sampledAt: Date(),
            bodyTemperatureF: 98.2,
            wristTemperatureDeviationC: 0.1,
            restingHeartRate: 54,
            restingHeartRateBaseline: 55,
            hrvMs: 52,
            hrvBaselineMs: 50
        )
        XCTAssertTrue(AriaHealthRiskMonitor.evaluate(reading).isEmpty)
    }

    func testSlightlyHighTemperatureIsWatchNotDiagnosis() {
        let reading = AriaVitalReading(sampledAt: Date(), bodyTemperatureF: 99.7)
        let findings = AriaHealthRiskMonitor.evaluate(reading)
        XCTAssertEqual(findings.first?.kind, .elevatedTemperature)
        XCTAssertEqual(findings.first?.severity, .watch)
        XCTAssertFalse(findings.first?.body.lowercased().contains("you have") ?? true)
        XCTAssertTrue(findings.first?.chatOpener.contains("99.7") ?? false)
    }

    func testFeverRangeTemperatureIsConcernAndStillNotADiagnosis() {
        let reading = AriaVitalReading(sampledAt: Date(), bodyTemperatureF: 101.2)
        let finding = AriaHealthRiskMonitor.primary(AriaHealthRiskMonitor.evaluate(reading))
        XCTAssertEqual(finding?.severity, .concern)
        XCTAssertTrue(finding?.coachLine.lowercased().contains("clinician") ?? false)
        XCTAssertFalse(finding?.title.lowercased().contains("influenza") ?? true)
    }

    func testWristDeviationUsesWatchSleepingReading() {
        let reading = AriaVitalReading(sampledAt: Date(), wristTemperatureDeviationC: 0.85)
        let finding = AriaHealthRiskMonitor.primary(AriaHealthRiskMonitor.evaluate(reading))
        XCTAssertEqual(finding?.kind, .wristTemperatureRise)
        XCTAssertEqual(finding?.severity, .concern)
        XCTAssertTrue(finding?.body.lowercased().contains("wrist") ?? false)
    }

    func testRecentWorkoutDoesNotFlagBodyTemperature() {
        let reading = AriaVitalReading(
            sampledAt: Date(),
            bodyTemperatureF: 100.8,
            hoursSinceLastWorkout: 0.4
        )
        XCTAssertTrue(AriaHealthRiskMonitor.evaluate(reading).isEmpty)
    }

    func testRestingHeartRateSpikeAndHRVDrop() {
        let reading = AriaVitalReading(
            sampledAt: Date(),
            restingHeartRate: 72,
            restingHeartRateBaseline: 55,
            hrvMs: 28,
            hrvBaselineMs: 55
        )
        let kinds = Set(AriaHealthRiskMonitor.evaluate(reading).map(\.kind))
        XCTAssertTrue(kinds.contains(.restingHeartRateSpike))
        XCTAssertTrue(kinds.contains(.hrvDrop))
    }

    func testStaleSampleIsIgnored() {
        let reading = AriaVitalReading(
            sampledAt: Date().addingTimeInterval(-20 * 3600),
            bodyTemperatureF: 102
        )
        XCTAssertTrue(AriaHealthRiskMonitor.evaluate(reading).isEmpty)
    }

    func testCooldown() {
        XCTAssertTrue(AriaHealthRiskCooldown.shouldNotify(lastNotified: nil))
        XCTAssertFalse(
            AriaHealthRiskCooldown.shouldNotify(lastNotified: Date(), now: Date())
        )
        XCTAssertTrue(
            AriaHealthRiskCooldown.shouldNotify(
                lastNotified: Date().addingTimeInterval(-9 * 3600),
                now: Date()
            )
        )
    }

    func testChatSurfaceNeedles() {
        XCTAssertTrue(AriaHealthRiskMonitor.shouldSurfaceInChat(text: "why is my temperature high"))
        XCTAssertFalse(AriaHealthRiskMonitor.shouldSurfaceInChat(text: "what should I eat for dinner"))
    }

    func testVitalsPayloadRoundTripAndInbox() {
        let payload = WatchVitalsPayload(
            sampledAt: Date(timeIntervalSince1970: 1_700_000_000),
            bodyTemperatureF: 100.6,
            wristTemperatureDeviationC: 0.6,
            source: "watch"
        )
        let defaults = UserDefaults(suiteName: "forge.test.vitals.\(UUID().uuidString)")
        WatchVitalsInbox.save(payload, defaults: defaults)
        let loaded = WatchVitalsInbox.load(defaults: defaults)
        XCTAssertEqual(loaded?.bodyTemperatureF, 100.6)
        XCTAssertEqual(loaded?.source, "watch")
        XCTAssertEqual(loaded?.asReading().bodyTemperatureF, 100.6)
    }
}
