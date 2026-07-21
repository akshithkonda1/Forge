import Foundation
import Combine
import HealthKit

/// Persists cycle logs, syncs HealthKit menstrual signals, exposes engine snapshot.
@MainActor
final class MenstrualHealthStore: ObservableObject {
    static let shared = MenstrualHealthStore()

    @Published private(set) var settings: MenstrualTrackingSettings
    @Published private(set) var logs: [CycleDayLog]
    @Published private(set) var snapshot: MenstrualCycleSnapshot
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var isSyncing = false

    private let defaults = UserDefaults.standard
    private let settingsKey = "forge.menstrual.settings.v1"
    private let logsKey = "forge.menstrual.logs.v1"

    private init() {
        if let data = defaults.data(forKey: settingsKey),
           let s = try? JSONDecoder().decode(MenstrualTrackingSettings.self, from: data) {
            settings = s
        } else {
            settings = .default
        }
        if let data = defaults.data(forKey: logsKey),
           let l = try? JSONDecoder().decode([CycleDayLog].self, from: data) {
            logs = l
        } else {
            logs = []
        }
        snapshot = .empty
        recompute()
    }

    // MARK: Settings

    func updateSettings(_ mutate: (inout MenstrualTrackingSettings) -> Void) {
        var s = settings
        mutate(&s)
        settings = s
        persistSettings()
        recompute()
        pushAriaTags()
    }

    func enableForFemaleProfileIfNeeded(gender: Gender) {
        guard gender == .female else { return }
        if !settings.enabled {
            updateSettings {
                $0.enabled = true
                $0.shareWithAria = true
            }
        }
    }

    // MARK: Logging

    func upsertLog(_ log: CycleDayLog) {
        if let idx = logs.firstIndex(where: { $0.dayKey == log.dayKey }) {
            var merged = logs[idx]
            merged.flow = log.flow
            merged.symptoms = log.symptoms
            if let bbt = log.bbtCelsius { merged.bbtCelsius = bbt }
            if let o = log.ovulationTest { merged.ovulationTest = o }
            if let m = log.mucus { merged.mucus = m }
            if let n = log.notes { merged.notes = n }
            merged.source = log.source
            merged.updatedAt = Date()
            logs[idx] = merged
        } else {
            logs.append(log)
        }
        logs.sort { $0.dayKey < $1.dayKey }
        // Cap retention ~24 months of daily logs
        if logs.count > 800 {
            logs = Array(logs.suffix(800))
        }
        persistLogs()
        recompute()
        pushAriaTags()
        Task { await writeFlowToHealthKitIfNeeded(log) }
    }

    func logPeriodStart(on dayKey: String = CycleDayKey.key(), flow: MenstrualFlowLevel = .medium) {
        upsertLog(CycleDayLog(dayKey: dayKey, flow: flow, source: "manual"))
    }

    func logToday(
        flow: MenstrualFlowLevel? = nil,
        symptoms: [CycleSymptom]? = nil,
        bbtCelsius: Double? = nil,
        ovulationTest: OvulationTestResult? = nil,
        mucus: CervicalMucusQuality? = nil,
        notes: String? = nil
    ) {
        let key = CycleDayKey.key()
        var existing = logs.first(where: { $0.dayKey == key }) ?? CycleDayLog(dayKey: key)
        if let flow { existing.flow = flow }
        if let symptoms { existing.symptoms = symptoms }
        if let bbtCelsius { existing.bbtCelsius = bbtCelsius }
        if let ovulationTest { existing.ovulationTest = ovulationTest }
        if let mucus { existing.mucus = mucus }
        if let notes { existing.notes = notes }
        existing.source = "manual"
        existing.updatedAt = Date()
        upsertLog(existing)
    }

    // MARK: Engine

    func recompute(readinessHRV: Int? = nil, baselineHRV: Int? = nil, restingHR: Int? = nil) {
        snapshot = MenstrualCycleEngine.evaluate(
            logs: logs,
            settings: settings,
            recentHRV: readinessHRV,
            baselineHRV: baselineHRV,
            restingHR: restingHR
        )
    }

    func refresh(from store: AppStore) {
        recompute(
            readinessHRV: store.dailyMetrics.hrv,
            baselineHRV: max(store.dailyMetrics.hrv, 40),
            restingHR: store.dailyMetrics.restingHR
        )
        if settings.enabled, settings.shareWithAria {
            pushAriaTags()
        }
    }

    // MARK: HealthKit

    func syncFromHealthKit(days: Int = 400) async {
        guard settings.enabled else { return }
        isSyncing = true
        defer { isSyncing = false }

        let bundle = await HealthKitManager.shared.fetchMenstrualHealthBundle(days: days)
        mergeHealthKit(bundle)
        lastSyncAt = Date()
        recompute()
        pushAriaTags()
    }

    private func mergeHealthKit(_ bundle: MenstrualHealthKitBundle) {
        var byDay = Dictionary(uniqueKeysWithValues: logs.map { ($0.dayKey, $0) })

        for sample in bundle.flowSamples {
            let key = CycleDayKey.key(for: sample.date)
            var log = byDay[key] ?? CycleDayLog(dayKey: key, source: "healthkit")
            // Manual wins on conflict if newer
            if log.source == "manual", log.updatedAt > sample.date { /* keep manual flow */ }
            else {
                log.flow = sample.flow
                if log.source != "manual" { log.source = "healthkit" }
                else { log.source = "merged" }
            }
            log.updatedAt = max(log.updatedAt, sample.date)
            byDay[key] = log
        }

        for bbt in bundle.bbtSamples {
            let key = CycleDayKey.key(for: bbt.date)
            var log = byDay[key] ?? CycleDayLog(dayKey: key, source: "healthkit")
            if log.bbtCelsius == nil || log.source != "manual" {
                log.bbtCelsius = bbt.celsius
            }
            byDay[key] = log
        }

        for opk in bundle.ovulationTests {
            let key = CycleDayKey.key(for: opk.date)
            var log = byDay[key] ?? CycleDayLog(dayKey: key, source: "healthkit")
            log.ovulationTest = opk.result
            byDay[key] = log
        }

        for mucus in bundle.mucusSamples {
            let key = CycleDayKey.key(for: mucus.date)
            var log = byDay[key] ?? CycleDayLog(dayKey: key, source: "healthkit")
            log.mucus = mucus.quality
            byDay[key] = log
        }

        logs = byDay.values.sorted { $0.dayKey < $1.dayKey }
        persistLogs()
    }

    private func writeFlowToHealthKitIfNeeded(_ log: CycleDayLog) async {
        guard log.flow.isBleeding, log.source == "manual" || log.source == "merged" else { return }
        await HealthKitManager.shared.saveMenstrualFlow(dayKey: log.dayKey, flow: log.flow)
    }

    // MARK: ARIA bridge

    func pushAriaTags() {
        guard settings.enabled, settings.shareWithAria else {
            AriaContextStore.shared.clearCycleTags()
            return
        }
        AriaContextStore.shared.applyCycleSnapshot(snapshot)
    }

    func ariaContextLines() -> [String] {
        guard settings.enabled, settings.shareWithAria else { return [] }
        var lines: [String] = []
        lines.append("Cycle phase: \(snapshot.phase.label)")
        if let d = snapshot.dayInCycle {
            lines.append("Day in cycle: \(d)")
        }
        lines.append("Confidence: \(Int(snapshot.confidence * 100))% (\(snapshot.dataQuality))")
        lines.append(snapshot.trainingNote)
        lines.append(snapshot.readinessNote)
        if let next = snapshot.nextPeriod {
            lines.append("Next period window: \(next.earliestDayKey) → \(next.latestDayKey) (median \(next.medianDayKey))")
        }
        lines.append(snapshot.disclaimer)
        return lines
    }

    // MARK: Persist

    private func persistSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: settingsKey)
        }
    }

    private func persistLogs() {
        if let data = try? JSONEncoder().encode(logs) {
            defaults.set(data, forKey: logsKey)
        }
    }
}

// MARK: - HealthKit DTO

struct MenstrualHealthKitBundle {
    var flowSamples: [(date: Date, flow: MenstrualFlowLevel)]
    var bbtSamples: [(date: Date, celsius: Double)]
    var ovulationTests: [(date: Date, result: OvulationTestResult)]
    var mucusSamples: [(date: Date, quality: CervicalMucusQuality)]
}
