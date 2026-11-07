import Foundation
import HealthKit

/// Pure HealthKit cycle I/O policy — write/delete decisions and merge
/// precedence. Kept off `HealthKitManager` so tests can exercise it without a
/// store, and so spotting / deletion rules live in one place.
///
/// Deletion precedence (documented for the PR):
/// 1. Clearing or deleting a day in Forge always deletes the matching Health
///    sample (`forge.cycle.flow.<day>` / `forge.cycle.spotting.<day>`).
/// 2. A Health deletion removes the Forge log only when that log has **no
///    manual source** (`source != "manual"` and `source != "merged"`).
/// 3. A manual / merged entry is never silently wiped because Apple Health
///    deleted a sample. The user typed it in Forge; Health cannot un-say it.
/// 4. An empty or failed Health query does **not** count as a deletion sweep
///    (`sampleQuerySucceeded == false`) — otherwise going offline would
///    erase every Health-sourced day.
enum CycleHealthKitPolicy {

    static let flowSyncPrefix = "forge.cycle.flow."
    static let spottingSyncPrefix = "forge.cycle.spotting."

    static func menstrualFlowSyncIdentifier(dayKey: String) -> String {
        flowSyncPrefix + dayKey
    }

    static func spottingSyncIdentifier(dayKey: String) -> String {
        spottingSyncPrefix + dayKey
    }

    static func dayKey(fromFlowSyncIdentifier identifier: String) -> String? {
        guard identifier.hasPrefix(flowSyncPrefix) else { return nil }
        let key = String(identifier.dropFirst(flowSyncPrefix.count))
        return CycleDayKey.date(from: key) == nil ? nil : key
    }

    /// Intermenstrual bleeding exists on the iOS 27 deployment target (added
    /// in iOS 14). Still gated so a write can skip rather than invent a flow.
    static var intermenstrualBleedingAvailable: Bool {
        HKObjectType.categoryType(forIdentifier: .intermenstrualBleeding) != nil
    }

    // MARK: Outbound writes

    enum OutboundAction: Equatable {
        case saveMenstrualFlow(MenstrualFlowLevel, isCycleStart: Bool)
        case saveIntermenstrualBleeding
        case deleteMenstrualFlow
        case deleteIntermenstrualBleeding
        case skipKeepLocal
    }

    /// Spotting is never a menstrual-flow sample. Writing it as `.light`
    /// used to come back as real flow, open a false period, and reset the
    /// cycle day.
    static func outboundActions(
        flow: MenstrualFlowLevel,
        isCycleStart: Bool,
        intermenstrualBleedingAvailable: Bool = intermenstrualBleedingAvailable
    ) -> [OutboundAction] {
        switch flow {
        case .spotting:
            var actions: [OutboundAction] = [.deleteMenstrualFlow]
            if intermenstrualBleedingAvailable {
                actions.append(.saveIntermenstrualBleeding)
            } else {
                actions.append(.skipKeepLocal)
            }
            return actions
        case .light, .medium, .heavy, .unspecified:
            return [.saveMenstrualFlow(flow, isCycleStart: isCycleStart)]
        case .none:
            return [.deleteMenstrualFlow, .deleteIntermenstrualBleeding]
        }
    }

    /// `nil` means "do not write a menstrual-flow sample" — spotting and a
    /// cleared day never become `HKCategoryValueVaginalBleeding.light`.
    static func menstrualFlowHealthKitValue(_ flow: MenstrualFlowLevel) -> HKCategoryValueVaginalBleeding? {
        switch flow {
        case .none, .spotting: return nil
        case .light: return .light
        case .medium: return .medium
        case .heavy: return .heavy
        case .unspecified: return .unspecified
        }
    }

    /// Incoming menstrual-flow samples never become `.spotting`. Spotting is
    /// intermenstrual bleeding, which is not in this mapping.
    static func importedMenstrualFlow(_ value: HKCategoryValueVaginalBleeding) -> MenstrualFlowLevel? {
        switch value {
        case .none: return nil
        case .light: return .light
        case .medium: return .medium
        case .heavy: return .heavy
        case .unspecified: return .unspecified
        @unknown default: return .unspecified
        }
    }

    // MARK: Merge + deletions

    static func merge(
        existing: [CycleDayLog],
        bundle: MenstrualHealthKitBundle,
        maxRetainedLogs: Int = MenstrualHealthStore.maxRetainedLogs
    ) -> [CycleDayLog] {
        // Deletions first, then live samples. A day Health still has must be
        // able to come back after a stale deletion token; applying deletes
        // after the add would drop it.
        let deleted = effectiveDeletedFlowDayKeys(existing: existing, bundle: bundle)
        let surviving = applyingFlowDeletions(existing, deletedDayKeys: deleted)

        var byDay = Dictionary(surviving.map { ($0.dayKey, $0) }) { older, newer in
            newer.updatedAt >= older.updatedAt ? newer : older
        }

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
        if merged.count > maxRetainedLogs {
            merged = Array(merged.suffix(maxRetainedLogs))
        }
        return merged
    }

    /// Anchored-query deletions plus, when the live sample query succeeded,
    /// Health-sourced bleeding days that are no longer in Health.
    static func effectiveDeletedFlowDayKeys(
        existing: [CycleDayLog],
        bundle: MenstrualHealthKitBundle
    ) -> Set<String> {
        var deleted = bundle.deletedFlowDayKeys
        guard bundle.sampleQuerySucceeded else { return deleted }
        let currentFlowDays = Set(bundle.flowSamples.map { CycleDayKey.key(for: $0.date) })
        for log in existing {
            guard log.source == "healthkit", log.flow.isBleeding else { continue }
            if !currentFlowDays.contains(log.dayKey) {
                deleted.insert(log.dayKey)
            }
        }
        return deleted
    }

    static func applyingFlowDeletions(
        _ logs: [CycleDayLog],
        deletedDayKeys: Set<String>
    ) -> [CycleDayLog] {
        logs.compactMap { log in
            guard deletedDayKeys.contains(log.dayKey) else { return log }
            // Manual / merged: the user said this in Forge. Health cannot un-say it.
            if log.source == "manual" || log.source == "merged" {
                return log
            }
            var cleared = log
            cleared.flow = .none
            let hasOtherSignals = cleared.bbtCelsius != nil
                || cleared.ovulationTest != nil
                || cleared.mucus != nil
                || !(cleared.notes ?? "").isEmpty
                || !cleared.symptoms.isEmpty
                || cleared.painScale != nil
            return hasOtherSignals ? cleared : nil
        }
    }

    static func perform(
        _ actions: [OutboundAction],
        dayKey: String,
        client: CycleHealthKitWriting
    ) async {
        for action in actions {
            switch action {
            case .saveMenstrualFlow(let flow, let isCycleStart):
                await client.saveMenstrualFlow(dayKey: dayKey, flow: flow, isCycleStart: isCycleStart)
            case .saveIntermenstrualBleeding:
                await client.saveIntermenstrualBleeding(dayKey: dayKey)
            case .deleteMenstrualFlow:
                await client.deleteMenstrualFlow(dayKey: dayKey)
            case .deleteIntermenstrualBleeding:
                await client.deleteIntermenstrualBleeding(dayKey: dayKey)
            case .skipKeepLocal:
                break
            }
        }
    }
}

/// Narrow HealthKit surface for cycle flow writes and deletes. The real
/// `HealthKitManager` conforms; tests use an in-memory fake.
@MainActor
protocol CycleHealthKitWriting: AnyObject {
    func saveMenstrualFlow(dayKey: String, flow: MenstrualFlowLevel, isCycleStart: Bool) async
    func deleteMenstrualFlow(dayKey: String) async
    func saveIntermenstrualBleeding(dayKey: String) async
    func deleteIntermenstrualBleeding(dayKey: String) async
}
