import XCTest
@testable import ForgeCore

final class SleepMorningSummaryTests: XCTestCase {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        cal.locale = Locale(identifier: "en_US_POSIX")
        return cal
    }

    func testNeedPartsClampAndWhy() {
        let parts = SleepNeedParts.make(
            estimatedBaseline: 10,
            loadHours: 20,
            debtHours: 8,
            napHours: 0.5
        )
        XCTAssertEqual(parts.baselineHours, 9.0, accuracy: 0.01)
        XCTAssertLessThanOrEqual(parts.totalHours, SleepNeedParts.clampMax)
        XCTAssertGreaterThanOrEqual(parts.totalHours, SleepNeedParts.clampMin)
        XCTAssertTrue(parts.whyLines.contains(where: { $0.contains("Baseline") }))
        XCTAssertTrue(parts.whyLines.contains(where: { $0.contains("Load") }))
        XCTAssertTrue(parts.whyLines.contains(where: { $0.contains("Short stretch") }))
        XCTAssertTrue(parts.whyLines.contains(where: { $0.contains("Naps") }))
        for line in parts.whyLines {
            XCTAssertNil(SleepCoachCopy.containsBannedPhrase(line), line)
        }
    }

    func testUserOverrideBaselineWins() {
        let parts = SleepNeedParts.make(estimatedBaseline: 8.4, overrideBaseline: 7.5)
        XCTAssertTrue(parts.userOverride)
        XCTAssertEqual(parts.baselineHours, 7.5, accuracy: 0.01)
        XCTAssertTrue(parts.whyLines.contains(where: { $0.contains("You set the baseline") }))
    }

    func testPublishedWeightsAreAppleShape() {
        XCTAssertEqual(SleepPublishedScore.durationWeight, 0.5, accuracy: 0.001)
        XCTAssertEqual(SleepPublishedScore.consistencyWeight, 0.3, accuracy: 0.001)
        XCTAssertEqual(SleepPublishedScore.interruptionWeight, 0.2, accuracy: 0.001)
        let breakdown = SleepPublishedScore.breakdown(
            asleepHours: 8,
            needHours: 8,
            consistency: 100,
            awakeMinutes: 0
        )
        XCTAssertEqual(breakdown.total, 100)
        XCTAssertEqual(breakdown.parts.count, 3)
    }

    func testNoScoreUntilSevenNights() {
        let need = SleepNeedParts.make(estimatedBaseline: 8)
        let learning = SleepMorningSummary.make(
            lastNightHours: 7.2,
            scoredNightCount: 3,
            bedtimeLabel: "10:30 PM",
            need: need
        )
        XCTAssertNil(learning.visibleScore)
        if case .learning(let n, let needNights) = learning.calibration {
            XCTAssertEqual(n, 3)
            XCTAssertEqual(needNights, 7)
        } else {
            XCTFail("expected learning")
        }
        XCTAssertTrue(learning.contextLine.localizedCaseInsensitiveContains("still learning"))
        XCTAssertTrue(learning.nextStep.contains("10:30"))
        XCTAssertNil(SleepCoachCopy.containsBannedPhrase(learning.contextLine))
        XCTAssertNil(SleepCoachCopy.containsBannedPhrase(learning.nextStep))

        let ready = SleepMorningSummary.make(
            lastNightHours: 7.2,
            scoredNightCount: 7,
            bedtimeLabel: "10:30 PM",
            need: need
        )
        XCTAssertNotNil(ready.visibleScore)
        XCTAssertEqual(ready.calibration, .ready)
    }

    func testShortNightCopyMatchesTheBar() {
        let need = SleepNeedParts.make(estimatedBaseline: 8)
        let summary = SleepMorningSummary.make(
            lastNightHours: 5.5,
            scoredNightCount: 8,
            bedtimeLabel: "10:15 PM",
            need: need
        )
        XCTAssertEqual(summary.contextLine, "Short night. Keep today easy and get to bed a bit earlier.")
        XCTAssertEqual(summary.nextStep, "Tonight, lights out at 10:15 PM.")
        XCTAssertFalse(summary.contextLine.localizedCaseInsensitiveContains("owe"))
        XCTAssertFalse(summary.contextLine.localizedCaseInsensitiveContains("guilt"))
        XCTAssertNil(SleepCoachCopy.containsBannedPhrase(summary.contextLine))
        XCTAssertFalse(summary.contextLine.contains("52"))
        XCTAssertFalse(summary.contextLine.localizedCaseInsensitiveContains("hrv"))
    }

    func testDebtMeterMissesAndPaybackCap() {
        let iso = DateFormatter()
        iso.calendar = calendar
        iso.locale = Locale(identifier: "en_US_POSIX")
        iso.timeZone = calendar.timeZone
        iso.dateFormat = "yyyy-MM-dd"
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14))!
        var nights: [String: Double] = [:]
        var hours: [Double] = []
        for offset in (0..<14).reversed() {
            let day = calendar.date(byAdding: .day, value: -offset, to: now)!
            let h = offset == 0 ? 5.0 : 6.0
            nights[iso.string(from: day)] = h
            hours.append(h)
        }
        let meter = SleepDebtMeter.make(
            nightsByDate: nights,
            needHours: 8,
            asleepHoursOldestFirst: hours,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(meter.days.count, 7)
        XCTAssertTrue(meter.days.contains(where: \.missed))
        XCTAssertGreaterThan(meter.stretchHours, 0)
        XCTAssertLessThanOrEqual(meter.paybackMinutes, Int(SleepDebtMeter.paybackCapMinutes))
        XCTAssertTrue(meter.detail.localizedCaseInsensitiveContains("short stretch"))
        XCTAssertFalse(meter.detail.localizedCaseInsensitiveContains("owe"))
        XCTAssertFalse(meter.headline.localizedCaseInsensitiveContains("deficit"))
        XCTAssertNil(SleepCoachCopy.containsBannedPhrase(meter.headline))
        XCTAssertNil(SleepCoachCopy.containsBannedPhrase(meter.detail))
    }

    func testDebtMeterLearningHidesTheCall() {
        let meter = SleepDebtMeter.make(
            nightsByDate: ["2026-10-13": 7.0],
            needHours: 8,
            asleepHoursOldestFirst: [7.0],
            now: calendar.date(from: DateComponents(year: 2026, month: 10, day: 14))!,
            calendar: calendar
        )
        XCTAssertTrue(meter.isLearning)
        XCTAssertEqual(meter.stretchHours, 0, accuracy: 0.01)
        XCTAssertTrue(meter.detail.localizedCaseInsensitiveContains("nights on file"))
    }

    func testFeelingStoreRoundTrip() {
        let suite = "forge.feeling.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertNil(SleepFeelingStore.feeling(on: "2026-10-14", defaults: defaults))
        SleepFeelingStore.save(.groggy, on: "2026-10-14", defaults: defaults)
        XCTAssertEqual(SleepFeelingStore.feeling(on: "2026-10-14", defaults: defaults), .groggy)
        XCTAssertEqual(SleepFeeling.allCases.count, 3)
    }

