import XCTest
@testable import ForgeSwift

final class CycleHealthKitSyncTests: XCTestCase {

    private func day(_ key: String, hour: Int = 12) -> Date {
        var comps = DateComponents()
        let parts = key.split(separator: "-").compactMap { Int($0) }
        comps.year = parts[0]
        comps.month = parts[1]
        comps.day = parts[2]
        comps.hour = hour
        return Calendar.current.date(from: comps) ?? Date()
    }

    func testSpottingIsNeverWrittenAsMenstrualFlow() {
        XCTAssertFalse(CycleHealthKitSync.writesAsMenstrualFlow(.spotting))
        XCTAssertFalse(CycleHealthKitSync.writesAsMenstrualFlow(.none))
        XCTAssertTrue(CycleHealthKitSync.writesAsMenstrualFlow(.light))
        XCTAssertTrue(CycleHealthKitSync.writesAsMenstrualFlow(.medium))
        XCTAssertTrue(CycleHealthKitSync.writesAsMenstrualFlow(.heavy))
    }

    func testHealthLightFlowNeverBecomesSpottingOnReadBack() {
        let sample = CycleHealthKitSync.FlowSample(
            date: day("2026-03-04"),
            flow: .light,
            updatedAt: day("2026-03-04", hour: 18)
        )
        let merged = CycleHealthKitSync.merge(
            logs: [],
            flowSamples: [sample],
            bbtSamples: [],
            ovulationTests: [],
            mucusSamples: [],
            maxRetainedLogs: 800
        )
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].flow, .light)
        XCTAssertNotEqual(merged[0].flow, .spotting)
        XCTAssertEqual(merged[0].source, "healthkit")
    }

    func testHeaviestFlowWinsSameDayConflicts() {
        let lightFirst = CycleHealthKitSync.FlowSample(
            date: day("2026-03-04", hour: 8),
            flow: .light,
            updatedAt: day("2026-03-04", hour: 20)
        )
        let heavyOlder = CycleHealthKitSync.FlowSample(
            date: day("2026-03-04", hour: 10),
            flow: .heavy,
            updatedAt: day("2026-03-04", hour: 11)
        )
        let resolved = CycleHealthKitSync.resolveSameDayFlow([lightFirst, heavyOlder])
        XCTAssertEqual(resolved["2026-03-04"]?.flow, .heavy,
                       "heaviest wins even when a lighter sample is newer")
    }

    func testSameDayTieBreaksByNewestSample() {
        let earlier = CycleHealthKitSync.FlowSample(
            date: day("2026-03-04", hour: 8),
            flow: .medium,
            updatedAt: day("2026-03-04", hour: 9)
        )
        let later = CycleHealthKitSync.FlowSample(
            date: day("2026-03-04", hour: 14),
            flow: .medium,
            updatedAt: day("2026-03-04", hour: 16)
        )
        let resolved = CycleHealthKitSync.resolveSameDayFlow([earlier, later])
        XCTAssertEqual(resolved["2026-03-04"]?.updatedAt, later.updatedAt)
    }

    func testHealthDeletionClearsHealthkitLogButKeepsManual() {
        let health = CycleDayLog(dayKey: "2026-03-04", flow: .medium, source: "healthkit")
        let manual = CycleDayLog(dayKey: "2026-03-05", flow: .heavy, source: "manual")
        let merged = CycleDayLog(dayKey: "2026-03-06", flow: .light, source: "merged")
        let result = CycleHealthKitSync.applyHealthFlowDeletions(
            logs: [health, manual, merged],
            deletedDayKeys: ["2026-03-04", "2026-03-05", "2026-03-06"]
        )
        XCTAssertFalse(result.contains { $0.dayKey == "2026-03-04" },
                       "a Health-only day is removed when Health deletes the sample")
        XCTAssertEqual(result.first { $0.dayKey == "2026-03-05" }?.flow, .heavy,
                       "manual never yields to a Health deletion")
        XCTAssertEqual(result.first { $0.dayKey == "2026-03-06" }?.flow, .light,
                       "merged has a manual side — keep it")
    }

    func testHealthDeletionKeepsHealthkitDayWhenOtherSignalsRemain() {
        var log = CycleDayLog(dayKey: "2026-03-04", flow: .medium, source: "healthkit")
        log.bbtCelsius = 36.4
        let result = CycleHealthKitSync.applyHealthFlowDeletions(
            logs: [log],
            deletedDayKeys: ["2026-03-04"]
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].flow, .none)
        XCTAssertEqual(result[0].bbtCelsius, 36.4)
    }

    func testMergeAppliesHeaviestThenDeletions() {
        let existing = [
            CycleDayLog(dayKey: "2026-03-04", flow: .light, source: "healthkit"),
            CycleDayLog(dayKey: "2026-03-05", flow: .medium, source: "manual"),
        ]
        let samples = [
            CycleHealthKitSync.FlowSample(date: day("2026-03-04", hour: 8), flow: .light, updatedAt: day("2026-03-04", hour: 8)),
            CycleHealthKitSync.FlowSample(date: day("2026-03-04", hour: 12), flow: .heavy, updatedAt: day("2026-03-04", hour: 9)),
        ]
        let merged = CycleHealthKitSync.merge(
            logs: existing,
            flowSamples: samples,
            bbtSamples: [],
            ovulationTests: [],
            mucusSamples: [],
            deletedFlowDayKeys: ["2026-03-04"],
            maxRetainedLogs: 800
        )
        XCTAssertEqual(merged.first { $0.dayKey == "2026-03-04" }?.flow, .heavy,
                       "a live Health sample on the same day wins over a stale deletion")
        XCTAssertEqual(merged.first { $0.dayKey == "2026-03-05" }?.flow, .medium)
    }

    func testMergeDeletesHealthkitDayWhenHealthHasNoReplacement() {
        let existing = [CycleDayLog(dayKey: "2026-03-04", flow: .medium, source: "healthkit")]
        let merged = CycleHealthKitSync.merge(
            logs: existing,
            flowSamples: [],
            bbtSamples: [],
            ovulationTests: [],
            mucusSamples: [],
            deletedFlowDayKeys: ["2026-03-04"],
            maxRetainedLogs: 800
        )
        XCTAssertTrue(merged.isEmpty)
    }

    func testSyncIdentifiersAreStable() {
        XCTAssertEqual(CycleHealthKitSync.syncIdentifier(forFlowDayKey: "2026-03-04"), "forge.cycle.flow.2026-03-04")
        XCTAssertEqual(CycleHealthKitSync.syncIdentifier(forSpottingDayKey: "2026-03-04"), "forge.cycle.spotting.2026-03-04")
        XCTAssertEqual(CycleHealthKitSync.dayKey(fromFlowSyncIdentifier: "forge.cycle.flow.2026-03-04"), "2026-03-04")
        XCTAssertNil(CycleHealthKitSync.dayKey(fromFlowSyncIdentifier: "forge.cycle.spotting.2026-03-04"))
        XCTAssertNil(CycleHealthKitSync.dayKey(fromFlowSyncIdentifier: "other.2026-03-04"))
    }
}
