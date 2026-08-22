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

        let bundle = await HealthKitManager.shared.fetchMenstrualHealthBundle(days: days)
        mergeHealthKit(bundle)
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
        // `Dictionary(uniqueKeysWithValues:)` traps at runtime on a duplicate key. A single
        // duplicated dayKey — from an interrupted migration, a restored backup, or two
        // writers racing — would crash the app on every HealthKit sync. Keep the newest.
        var byDay = Dictionary(logs.map { ($0.dayKey, $0) }) { older, newer in
            newer.updatedAt >= older.updatedAt ? newer : older
        }

        /// Manual entries are the user's own words about their body — HealthKit never
        /// silently overwrites them, and merging never downgrades a "manual" log to a
        /// weaker precedence tier.
        func mergedSource(_ existing: String) -> String {
            existing == "manual" || existing == "merged" ? "merged" : "healthkit"
        }

        for sample in bundle.flowSamples {
            let key = CycleDayKey.key(for: sample.date)
            var log = byDay[key] ?? CycleDayLog(dayKey: key, flow: .none, source: "healthkit")
            let manualIsAuthoritative = (log.source == "manual" || log.source == "merged")
                && log.updatedAt > sample.date
            if !manualIsAuthoritative {
                log.flow = sample.flow
                log.source = mergedSource(log.source)
                log.updatedAt = max(log.updatedAt, sample.date)
            }
            byDay[key] = log
        }

        for bbt in bundle.bbtSamples {
            let key = CycleDayKey.key(for: bbt.date)
            var log = byDay[key] ?? CycleDayLog(dayKey: key, source: "healthkit")
            if log.bbtCelsius == nil || log.source == "healthkit" {
                log.bbtCelsius = bbt.celsius
                log.source = mergedSource(log.source)
            }
            byDay[key] = log
        }

        for opk in bundle.ovulationTests {
            let key = CycleDayKey.key(for: opk.date)
            var log = byDay[key] ?? CycleDayLog(dayKey: key, source: "healthkit")
            if log.ovulationTest == nil || log.source == "healthkit" {
                log.ovulationTest = opk.result
                log.source = mergedSource(log.source)
            }
            byDay[key] = log
        }

        for mucus in bundle.mucusSamples {
            let key = CycleDayKey.key(for: mucus.date)
            var log = byDay[key] ?? CycleDayLog(dayKey: key, source: "healthkit")
            if log.mucus == nil || log.source == "healthkit" {
                log.mucus = mucus.quality
                log.source = mergedSource(log.source)
            }
            byDay[key] = log
        }

        var merged = byDay.values.sorted { $0.dayKey < $1.dayKey }
        if merged.count > Self.maxRetainedLogs {
            merged = Array(merged.suffix(Self.maxRetainedLogs))
        }
        logs = merged
        persistLogs()
    }

    func writeFlowToHealthKitIfNeeded(_ log: CycleDayLog) async {
        guard log.flow.isBleeding, log.source == "manual" || log.source == "merged" else { return }
        // Only the first bleeding day of an episode is a cycle *start*. Tagging every
        // bleeding day as a start told Apple Health each day began a new cycle.
        let isEpisodeStart = MenstrualCycleEngine.buildPeriodEpisodes(from: logs)
            .contains { $0.startDayKey == log.dayKey }
        await HealthKitManager.shared.saveMenstrualFlow(
            dayKey: log.dayKey,
            flow: log.flow,
            isCycleStart: isEpisodeStart
        )
    }

    // MARK: ARIA bridge
}
