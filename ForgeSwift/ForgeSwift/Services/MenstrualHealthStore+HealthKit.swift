import Foundation
import Combine
import HealthKit
import ActivityKit
import ForgeCore

extension MenstrualHealthStore {

    func syncFromHealthKit(days: Int = 400) async {
        // Two concurrent syncs (toolbar tap while the onAppear sync is in flight) both
        // merged into `logs` and both wrote, so the slower one clobbered the newer merge.
        guard settings.enabled, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let storedAnchor = defaults.data(forKey: Self.flowAnchorKey)
        let bundle = await HealthKitManager.shared.fetchMenstrualHealthBundle(
            days: days,
            flowAnchor: storedAnchor
        )
        mergeHealthKit(bundle)
        if let anchor = bundle.newFlowAnchor {
            defaults.set(anchor, forKey: Self.flowAnchorKey)
        }
        lastSyncAt = Date()
        defaults.set(Date().timeIntervalSince1970, forKey: quietSyncKey)
        recompute()
        pushAriaTags()
    }

    /// Quiet weekly HealthKit menstrual sync. Runs full sync if never run, >7 days, or forced (e.g. HealthKit offline).
    func quietWeeklyHealthKitSync(force: Bool = false) async {
        guard settings.enabled else { return }
        let last = defaults.double(forKey: quietSyncKey)
        let week: TimeInterval = 7 * 24 * 60 * 60
        let stale = last <= 0 || (Date().timeIntervalSince1970 - last) >= week
        guard force || stale || lastSyncAt == nil else {
            // Still refresh engine from local logs.
            recompute()
            return
        }
        await syncFromHealthKit()
    }

    private func mergeHealthKit(_ bundle: MenstrualHealthKitBundle) {
        let currentHealthDays = Set(bundle.flowSamples.map { CycleDayKey.key(for: $0.date) })
        let windowStart = CycleDayKey.addDays(CycleDayKey.key(), -400)
        let staleHealthDays = Set(logs.compactMap { log -> String? in
            guard log.source == "healthkit", log.flow.isBleeding else { return nil }
            if let windowStart, log.dayKey < windowStart { return nil }
            return currentHealthDays.contains(log.dayKey) ? nil : log.dayKey
        })
        logs = CycleHealthKitSync.merge(
            logs: logs,
            flowSamples: bundle.flowSamples.map {
                CycleHealthKitSync.FlowSample(date: $0.date, flow: $0.flow, updatedAt: $0.updatedAt)
            },
            bbtSamples: bundle.bbtSamples,
            ovulationTests: bundle.ovulationTests,
            mucusSamples: bundle.mucusSamples,
            deletedFlowDayKeys: Set(bundle.deletedFlowDayKeys).union(staleHealthDays),
            maxRetainedLogs: Self.maxRetainedLogs
        )
        persistLogs()
    }

    func writeFlowToHealthKitIfNeeded(_ log: CycleDayLog) async {
        await writeCycleDayToAppleHealth(log)
    }

    /// Apple Cycle Tracking is the on-device ledger. Forge writes, then later
    /// reads the same samples to template a clinician report. Nothing is posted
    /// to a Forge database. Raw cycle archives stay encrypted on-device (Cycle Vault);
    /// the encryption key stays in the URL fragment and S3 only receives ciphertext
    /// via a pre-signed KMS-encrypted upload.
    ///
    /// Cycle context is shared with ARIA only when the user turns on “ARIA reads
    /// cycle on this iPhone” (and with supporters only per person, opt-in), via
    /// AriaContextStore.
    func writeCycleDayToAppleHealth(_ log: CycleDayLog) async {
        guard log.source == "manual" || log.source == "merged" else { return }
        let hk = HealthKitManager.shared
        if log.flow == .none {
            await hk.deleteMenstrualFlow(dayKey: log.dayKey)
            await hk.deleteIntermenstrualBleeding(dayKey: log.dayKey)
        } else if log.flow == .spotting {
            // Spotting is not menstrual flow. Writing it as `.light` used to
            // come back as a real period start. Prefer HK intermenstrual bleeding;
            // if that type is unavailable, keep spotting local only.
            await hk.deleteMenstrualFlow(dayKey: log.dayKey)
            await hk.saveIntermenstrualBleeding(dayKey: log.dayKey)
        } else if CycleHealthKitSync.writesAsMenstrualFlow(log.flow) {
            let isEpisodeStart = MenstrualCycleEngine.buildPeriodEpisodes(from: logs)
                .contains { $0.startDayKey == log.dayKey }
            await hk.deleteIntermenstrualBleeding(dayKey: log.dayKey)
            await hk.saveMenstrualFlow(
                dayKey: log.dayKey,
                flow: log.flow,
                isCycleStart: isEpisodeStart
            )
        }
        if let bbt = log.bbtCelsius {
            await hk.saveBasalBodyTemperature(dayKey: log.dayKey, celsius: bbt)
        }
        if let opk = log.ovulationTest {
            await hk.saveOvulationTest(dayKey: log.dayKey, result: opk)
        }
        if let mucus = log.mucus {
            await hk.saveCervicalMucus(dayKey: log.dayKey, quality: mucus)
        }
    }

    // MARK: ARIA bridge
}
