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

        let bundle = await HealthKitManager.shared.fetchMenstrualHealthBundle(
            days: days,
            flowAnchor: loadFlowAnchor()
        )
        persistFlowAnchor(bundle.newFlowAnchor)
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
        logs = CycleHealthKitPolicy.merge(
            existing: logs,
            bundle: bundle,
            maxRetainedLogs: Self.maxRetainedLogs
        )
        persistLogs()
    }

    private func loadFlowAnchor() -> HKQueryAnchor? {
        guard let data = defaults.data(forKey: flowAnchorKey) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private func persistFlowAnchor(_ anchor: HKQueryAnchor?) {
        guard let anchor,
              let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
        else { return }
        defaults.set(data, forKey: flowAnchorKey)
    }

    func writeFlowToHealthKitIfNeeded(_ log: CycleDayLog) async {
        await writeCycleDayToAppleHealth(log)
    }

    /// Apple Cycle Tracking is the on-device ledger. Forge writes, then later
    /// reads the same samples to template a clinician report. Nothing is posted
    /// to a Forge database. Raw cycle data is encrypted on-device; the key stays
    /// in the URL fragment, and optional clinician-report links send ciphertext
    /// only to S3 via a pre-signed KMS-encrypted upload. Cycle context is shared
    /// with ARIA only when the user turns on “share with ARIA”, and with
    /// supporters only per person (opt-in), through `AriaContextStore`.
    func writeCycleDayToAppleHealth(_ log: CycleDayLog) async {
        guard log.source == "manual" || log.source == "merged" else { return }
        let hk = HealthKitManager.shared
        let isEpisodeStart = MenstrualCycleEngine.buildPeriodEpisodes(from: logs)
            .contains { $0.startDayKey == log.dayKey }
        let actions = CycleHealthKitPolicy.outboundActions(
            flow: log.flow,
            isCycleStart: isEpisodeStart
        )
        await CycleHealthKitPolicy.perform(actions, dayKey: log.dayKey, client: hk)
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

/// Same-day Health flow samples: the heaviest flow wins; equal weight prefers
/// the newest sample date (`updatedAt` / HealthKit `endDate`).
enum HealthKitSameDayFlow {
    static func resolve(
        _ samples: [(flow: MenstrualFlowLevel, date: Date)]
    ) -> (flow: MenstrualFlowLevel, date: Date)? {
        samples.max { lhs, rhs in
            if lhs.flow.sortWeight != rhs.flow.sortWeight {
                return lhs.flow.sortWeight < rhs.flow.sortWeight
            }
            return lhs.date < rhs.date
        }
    }
}
