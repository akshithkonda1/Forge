import XCTest
import HealthKit
@testable import ForgeSwift

/// `HealthKitManager.makeSleepNightSamples` used to bucket raw sleep-analysis
/// samples by `Calendar.current.startOfDay(for: sample.endDate)` with no
/// cross-midnight adjustment, so any night spanning midnight (nearly every
/// real night) fragmented into two partial `SleepNightSample`s. This locks
/// the fix: a -12h shift on `startDate` before bucketing, same technique as
/// `SleepNight.groupIntoNights` in ForgeCore's SleepModels.swift.
@MainActor
final class SleepNightGroupingTests: XCTestCase {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func sample(_ value: HKCategoryValueSleepAnalysis, start: Date, end: Date) -> HKCategorySample {
        HKCategorySample(type: HKCategoryType(.sleepAnalysis), value: value.rawValue, start: start, end: end)
    }

    func testMidnightCrossingNightIsNotFragmented() {
        let start1 = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 23))!
        let end1 = calendar.date(byAdding: .hour, value: 1, to: start1)!   // 23:00–00:00
        let start2 = calendar.date(from: DateComponents(year: 2026, month: 9, day: 11, hour: 0))!
        let end2 = calendar.date(byAdding: .hour, value: 7, to: start2)!   // 00:00–07:00

        let samples = [
            sample(.asleepCore, start: start1, end: end1),
            sample(.asleepDeep, start: start2, end: end2),
        ]
        let nights = HealthKitManager.makeSleepNightSamples(from: samples)
        XCTAssertEqual(nights.count, 1, "one continuous night spanning midnight must not fragment")
        XCTAssertEqual(nights.first?.totalHours ?? 0, 8, accuracy: 0.01)
    }

    func testTwoSeparateNightsStillProduceTwoEntries() {
        // Regression guard: the fix must not over-merge nights several days apart.
        let night1Start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 23))!
        let night1End = calendar.date(byAdding: .hour, value: 7, to: night1Start)!
        let night2Start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 23))!
        let night2End = calendar.date(byAdding: .hour, value: 7, to: night2Start)!

        let samples = [
            sample(.asleepCore, start: night1Start, end: night1End),
            sample(.asleepCore, start: night2Start, end: night2End),
        ]
        let nights = HealthKitManager.makeSleepNightSamples(from: samples)
        XCTAssertEqual(nights.count, 2, "nights several days apart must stay separate")
    }

    func testAwakeSegmentsCountTowardAwakeMinutesButNotOnsetOrWake() {
        let onset = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 23))!
        let wakeInterruption = calendar.date(byAdding: .hour, value: 3, to: onset)!
        let backToSleep = calendar.date(byAdding: .minute, value: 20, to: wakeInterruption)!
        let finalWake = calendar.date(byAdding: .hour, value: 4, to: backToSleep)!

        let samples = [
            sample(.asleepCore, start: onset, end: wakeInterruption),
            sample(.awake, start: wakeInterruption, end: backToSleep),
            sample(.asleepDeep, start: backToSleep, end: finalWake),
        ]
        let nights = HealthKitManager.makeSleepNightSamples(from: samples)
        XCTAssertEqual(nights.count, 1)
        XCTAssertEqual(nights.first?.awakeMinutes, 20)
        XCTAssertEqual(nights.first?.onset, onset, "onset must come from the first asleep sample, not the awake gap")
        XCTAssertEqual(nights.first?.wake, finalWake, "wake must come from the last asleep sample, not the awake gap")
    }

    func testEmptySamplesProduceNoNights() {
        XCTAssertTrue(HealthKitManager.makeSleepNightSamples(from: []).isEmpty)
    }
}
