import XCTest
import HealthKit
@testable import ForgeSwift

@MainActor
final class FakeCycleHealthKitClient: CycleHealthKitWriting {
    var savedFlow: [(dayKey: String, flow: MenstrualFlowLevel, isCycleStart: Bool)] = []
    var deletedFlow: [String] = []
    var savedSpotting: [String] = []
    var deletedSpotting: [String] = []

    func saveMenstrualFlow(dayKey: String, flow: MenstrualFlowLevel, isCycleStart: Bool) async {
        savedFlow.append((dayKey, flow, isCycleStart))
    }

    func deleteMenstrualFlow(dayKey: String) async {
        deletedFlow.append(dayKey)
    }

    func saveIntermenstrualBleeding(dayKey: String) async {
        savedSpotting.append(dayKey)
    }

    func deleteIntermenstrualBleeding(dayKey: String) async {
        deletedSpotting.append(dayKey)
    }
}

final class CycleHealthKitPolicyTests: XCTestCase {

    private func noon(_ key: String) -> Date {
        CycleDayKey.date(from: key)!
    }

    private func emptyBundle(
        flow: [(Date, MenstrualFlowLevel)] = [],
        deleted: Set<String> = [],
        succeeded: Bool = true
    ) -> MenstrualHealthKitBundle {
        MenstrualHealthKitBundle(
            flowSamples: flow.map { (date: $0.0, flow: $0.1) },
            bbtSamples: [],
            ovulationTests: [],
            mucusSamples: [],
            deletedFlowDayKeys: deleted,
            sampleQuerySucceeded: succeeded
        )
    }

    // MARK: Spotting must never be menstrual flow

    func testSpottingIsNeverAMenstrualFlowHealthKitValue() {
        XCTAssertNil(CycleHealthKitPolicy.menstrualFlowHealthKitValue(.spotting))
        XCTAssertNil(CycleHealthKitPolicy.menstrualFlowHealthKitValue(.none))
        XCTAssertEqual(CycleHealthKitPolicy.menstrualFlowHealthKitValue(.light), .light)
        XCTAssertEqual(CycleHealthKitPolicy.menstrualFlowHealthKitValue(.medium), .medium)
        XCTAssertEqual(CycleHealthKitPolicy.menstrualFlowHealthKitValue(.heavy), .heavy)
    }

    func testIncomingVaginalBleedingNeverBecomesSpotting() {
        XCTAssertNil(CycleHealthKitPolicy.importedMenstrualFlow(.none))
        XCTAssertEqual(CycleHealthKitPolicy.importedMenstrualFlow(.light), .light)
        XCTAssertEqual(CycleHealthKitPolicy.importedMenstrualFlow(.medium), .medium)
        XCTAssertEqual(CycleHealthKitPolicy.importedMenstrualFlow(.heavy), .heavy)
        XCTAssertEqual(CycleHealthKitPolicy.importedMenstrualFlow(.unspecified), .unspecified)
        XCTAssertNotEqual(CycleHealthKitPolicy.importedMenstrualFlow(.light), .spotting)
    }

    func testSpottingOutboundWritesIntermenstrualAndDeletesLeftoverFlow() {
        let actions = CycleHealthKitPolicy.outboundActions(
            flow: .spotting,
            isCycleStart: false,
            intermenstrualBleedingAvailable: true
        )
        XCTAssertEqual(actions, [.deleteMenstrualFlow, .saveIntermenstrualBleeding])
        XCTAssertFalse(actions.contains { if case .saveMenstrualFlow = $0 { return true }; return false })
    }

    func testSpottingStaysLocalWhenIntermenstrualTypeIsUnavailable() {
        let actions = CycleHealthKitPolicy.outboundActions(
            flow: .spotting,
            isCycleStart: false,
            intermenstrualBleedingAvailable: false
        )
        XCTAssertEqual(actions, [.deleteMenstrualFlow, .skipKeepLocal])
    }

    func testClearingADayDeletesHealthKitFlowAndSpotting() {
        XCTAssertEqual(
            CycleHealthKitPolicy.outboundActions(flow: .none, isCycleStart: false),
            [.deleteMenstrualFlow, .deleteIntermenstrualBleeding]
        )
    }

    func testSpottingWriteThroughTheClientNeverSavesMenstrualFlow() async {
        let client = await MainActor.run { FakeCycleHealthKitClient() }
        await CycleHealthKitPolicy.perform(
            CycleHealthKitPolicy.outboundActions(
                flow: .spotting,
                isCycleStart: false,
                intermenstrualBleedingAvailable: true
            ),
            dayKey: "2026-03-11",
            client: client
        )
        let saved = await MainActor.run { client.savedFlow }
        let spotting = await MainActor.run { client.savedSpotting }
        let deleted = await MainActor.run { client.deletedFlow }
        XCTAssertTrue(saved.isEmpty, "spotting must not land as menstrual flow")
        XCTAssertEqual(spotting, ["2026-03-11"])
        XCTAssertEqual(deleted, ["2026-03-11"])
    }

    func testReadBackOfSpottingDoesNotCreateFlow() {
        // Spotting is intermenstrual — it is not in flowSamples. A local
        // spotting log must stay spotting, not become light / a period.
        let existing = [CycleDayLog(dayKey: "2026-03-11", flow: .spotting, source: "manual")]
        let merged = CycleHealthKitPolicy.merge(existing: existing, bundle: emptyBundle())
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].flow, .spotting)
        XCTAssertTrue(MenstrualCycleEngine.buildPeriodEpisodes(from: merged).isEmpty)
    }

    // MARK: Bidirectional deletions + precedence

    func testHealthDeletionRemovesHealthKitSourcedFlow() {
        let existing = [
            CycleDayLog(dayKey: "2026-03-04", flow: .medium, source: "healthkit"),
            CycleDayLog(dayKey: "2026-03-05", flow: .light, source: "healthkit"),
        ]
        // Live query still has the 5th — only the 4th was deleted in Health.
        // An empty successful fetch would infer *every* Health-sourced bleed gone.
        let merged = CycleHealthKitPolicy.merge(
            existing: existing,
            bundle: emptyBundle(
                flow: [(noon("2026-03-05"), .light)],
                deleted: ["2026-03-04"]
            )
        )
        XCTAssertFalse(merged.contains { $0.dayKey == "2026-03-04" })
        XCTAssertTrue(merged.contains { $0.dayKey == "2026-03-05" && $0.flow == .light })
    }

    func testHealthDeletionDoesNotWipeAManualEntry() {
        let existing = [
            CycleDayLog(dayKey: "2026-03-04", flow: .heavy, source: "manual"),
        ]
        let merged = CycleHealthKitPolicy.merge(
            existing: existing,
            bundle: emptyBundle(deleted: ["2026-03-04"])
        )
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].flow, .heavy)
        XCTAssertEqual(merged[0].source, "manual")
    }

    func testHealthDeletionDoesNotWipeAMergedEntry() {
        let existing = [
            CycleDayLog(dayKey: "2026-03-04", flow: .medium, source: "merged"),
        ]
        let merged = CycleHealthKitPolicy.merge(
            existing: existing,
            bundle: emptyBundle(deleted: ["2026-03-04"])
        )
        XCTAssertEqual(merged[0].flow, .medium)
        XCTAssertEqual(merged[0].source, "merged")
    }

    func testInferredDeletionWhenHealthSampleIsGoneAndSourceIsNotManual() {
        let existing = [
            CycleDayLog(dayKey: "2026-03-04", flow: .medium, source: "healthkit"),
        ]
        // Live query succeeded and returned no flow samples for that day.
        let merged = CycleHealthKitPolicy.merge(
            existing: existing,
            bundle: emptyBundle(flow: [], deleted: [], succeeded: true)
        )
        XCTAssertTrue(merged.isEmpty, "a period deleted in Health is removed from Forge")
    }

    func testFailedHealthQueryDoesNotSweepHealthKitLogs() {
        let existing = [
            CycleDayLog(dayKey: "2026-03-04", flow: .medium, source: "healthkit"),
        ]
        let merged = CycleHealthKitPolicy.merge(
            existing: existing,
            bundle: emptyBundle(flow: [], deleted: [], succeeded: false)
        )
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].flow, .medium)
    }

    func testManualWinsOverIncomingHealthFlow() {
        let existing = [
            CycleDayLog(
                dayKey: "2026-03-04",
                flow: .spotting,
                source: "manual",
                updatedAt: Date().addingTimeInterval(60)
            ),
        ]
        let merged = CycleHealthKitPolicy.merge(
            existing: existing,
            bundle: emptyBundle(flow: [(noon("2026-03-04"), .heavy)])
        )
        XCTAssertEqual(merged[0].flow, .spotting, "a later manual log must not become Health flow")
        XCTAssertTrue(merged[0].source == "manual" || merged[0].source == "merged")
    }

    func testHealthKitFlowStillImportsWhenThereIsNoManualEntry() {
        let merged = CycleHealthKitPolicy.merge(
            existing: [],
            bundle: emptyBundle(flow: [(noon("2026-03-04"), .medium)])
        )
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].flow, .medium)
        XCTAssertEqual(merged[0].source, "healthkit")
        XCTAssertEqual(merged[0].flow, .medium)
        XCTAssertNotEqual(merged[0].flow, .spotting)
    }

    func testDeleteLogActionsAskTheClientToRemoveBothSampleTypes() async {
        let client = await MainActor.run { FakeCycleHealthKitClient() }
        await CycleHealthKitPolicy.perform(
            [.deleteMenstrualFlow, .deleteIntermenstrualBleeding],
            dayKey: "2026-03-04",
            client: client
        )
        let flow = await MainActor.run { client.deletedFlow }
        let spotting = await MainActor.run { client.deletedSpotting }
        XCTAssertEqual(flow, ["2026-03-04"])
        XCTAssertEqual(spotting, ["2026-03-04"])
    }

    func testFlowSyncIdentifierRoundTrips() {
        let id = CycleHealthKitPolicy.menstrualFlowSyncIdentifier(dayKey: "2026-03-04")
        XCTAssertEqual(id, "forge.cycle.flow.2026-03-04")
        XCTAssertEqual(CycleHealthKitPolicy.dayKey(fromFlowSyncIdentifier: id), "2026-03-04")
        XCTAssertNil(CycleHealthKitPolicy.dayKey(fromFlowSyncIdentifier: "other.2026-03-04"))
    }

    func testHealthDeletionKeepsOtherSignalsOnAHealthKitDay() {
        let existing = [
            CycleDayLog(
                dayKey: "2026-03-04",
                flow: .medium,
                bbtCelsius: 36.4,
                source: "healthkit"
            ),
        ]
        let merged = CycleHealthKitPolicy.merge(
            existing: existing,
            bundle: emptyBundle(deleted: ["2026-03-04"])
        )
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].flow, .none)
        XCTAssertEqual(merged[0].bbtCelsius, 36.4)
    }
}
