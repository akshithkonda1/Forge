import Foundation

/// Pure HealthKit merge rules for cycle logs. No HK types — tests can exercise
/// same-day conflicts, spotting isolation, and deletion precedence without a store.
enum CycleHealthKitSync {

    struct FlowSample: Equatable {
        var date: Date
        var flow: MenstrualFlowLevel
        var updatedAt: Date

        var dayKey: String { CycleDayKey.key(for: date) }
    }

    /// Spotting is intermenstrual bleeding, not menstrual flow. Writing it as
    /// `.light` flow used to come back as a real period start.
    static func writesAsMenstrualFlow(_ flow: MenstrualFlowLevel) -> Bool {
        switch flow {
        case .light, .medium, .heavy, .unspecified: return true
        case .none, .spotting: return false
        }
    }

    /// Heaviest flow wins; ties break by newest `updatedAt`.
    static func resolveSameDayFlow(_ samples: [FlowSample]) -> [String: FlowSample] {
        var best: [String: FlowSample] = [:]
        for sample in samples {
            let key = sample.dayKey
            guard let existing = best[key] else {
                best[key] = sample
                continue
            }
            if sample.flow.sortWeight > existing.flow.sortWeight {
                best[key] = sample
            } else if sample.flow.sortWeight == existing.flow.sortWeight,
                      sample.updatedAt >= existing.updatedAt {
                best[key] = sample
            }
        }
        return best
    }

    /// Whether an inbound Health deletion may clear flow on this Forge log.
    ///
    /// Precedence:
    /// - `manual` never yields to a Health deletion. The user typed this.
    /// - `merged` has a manual side — keep it.
    /// - `healthkit` clears when the Health sample is gone.
    /// - A deletion that originated in Forge already removed the local log
    ///   before Health is asked to delete, so it never reaches this path.
    static func healthDeletionMayClear(_ log: CycleDayLog) -> Bool {
        log.source == "healthkit"
    }

    static func applyHealthFlowDeletions(
        logs: [CycleDayLog],
        deletedDayKeys: Set<String>
    ) -> [CycleDayLog] {
        guard !deletedDayKeys.isEmpty else { return logs }
        return logs.compactMap { log in
            guard deletedDayKeys.contains(log.dayKey), healthDeletionMayClear(log) else {
                return log
            }
            var cleared = log
            cleared.flow = .none
            cleared.updatedAt = Date()
            let hasOther = cleared.bbtCelsius != nil
                || cleared.ovulationTest != nil
                || cleared.mucus != nil
                || cleared.notes?.isEmpty == false
                || !cleared.symptoms.isEmpty
                || (cleared.painScale ?? 0) > 0
            return hasOther ? cleared : nil
        }
    }

    static func merge(
        logs: [CycleDayLog],
        flowSamples: [FlowSample],
        bbtSamples: [(date: Date, celsius: Double)],
        ovulationTests: [(date: Date, result: OvulationTestResult)],
        mucusSamples: [(date: Date, quality: CervicalMucusQuality)],
        deletedFlowDayKeys: Set<String> = [],
        maxRetainedLogs: Int
    ) -> [CycleDayLog] {
        var byDay = Dictionary(logs.map { ($0.dayKey, $0) }) { older, newer in
            newer.updatedAt >= older.updatedAt ? newer : older
        }

        func mergedSource(_ existing: String) -> String {
            existing == "manual" || existing == "merged" ? "merged" : "healthkit"
        }

        let resolvedFlow = resolveSameDayFlow(flowSamples)
        let liveHealthDays = Set(resolvedFlow.keys)
        for (key, sample) in resolvedFlow {
            var log = byDay[key] ?? CycleDayLog(dayKey: key, flow: .none, source: "healthkit")
            let manualIsAuthoritative = (log.source == "manual" || log.source == "merged")
                && log.updatedAt > sample.updatedAt
            if !manualIsAuthoritative {
                log.flow = sample.flow
                log.source = mergedSource(log.source)
                log.updatedAt = max(log.updatedAt, sample.updatedAt)
            }
            byDay[key] = log
        }

        for bbt in bbtSamples {
            let key = CycleDayKey.key(for: bbt.date)
            var log = byDay[key] ?? CycleDayLog(dayKey: key, source: "healthkit")
            if log.bbtCelsius == nil || log.source == "healthkit" {
                log.bbtCelsius = bbt.celsius
                log.source = mergedSource(log.source)
            }
            byDay[key] = log
        }

        for opk in ovulationTests {
            let key = CycleDayKey.key(for: opk.date)
            var log = byDay[key] ?? CycleDayLog(dayKey: key, source: "healthkit")
            if log.ovulationTest == nil || log.source == "healthkit" {
                log.ovulationTest = opk.result
                log.source = mergedSource(log.source)
            }
            byDay[key] = log
        }

        for mucus in mucusSamples {
            let key = CycleDayKey.key(for: mucus.date)
            var log = byDay[key] ?? CycleDayLog(dayKey: key, source: "healthkit")
            if log.mucus == nil || log.source == "healthkit" {
                log.mucus = mucus.quality
                log.source = mergedSource(log.source)
            }
            byDay[key] = log
        }

        let afterAdds = byDay.values.sorted { $0.dayKey < $1.dayKey }
        let deletions = deletedFlowDayKeys.subtracting(liveHealthDays)
        var merged = applyHealthFlowDeletions(logs: afterAdds, deletedDayKeys: deletions)
        if merged.count > maxRetainedLogs {
            merged = Array(merged.suffix(maxRetainedLogs))
        }
        return merged
    }

    static func syncIdentifier(forFlowDayKey dayKey: String) -> String {
        "forge.cycle.flow.\(dayKey)"
    }

    static func syncIdentifier(forSpottingDayKey dayKey: String) -> String {
        "forge.cycle.spotting.\(dayKey)"
    }

    static func dayKey(fromFlowSyncIdentifier identifier: String) -> String? {
        let prefix = "forge.cycle.flow."
        guard identifier.hasPrefix(prefix) else { return nil }
        let key = String(identifier.dropFirst(prefix.count))
        return CycleDayKey.date(from: key) == nil ? nil : key
    }
}
