import Foundation
import Combine
import HealthKit

/// Persists cycle logs, syncs HealthKit menstrual signals, exposes engine snapshot.
/// Also holds an optional **partner** cycle (relationship sync) — never written to the user's HealthKit.
@MainActor
final class MenstrualHealthStore: ObservableObject {
    static let shared = MenstrualHealthStore()

    @Published private(set) var settings: MenstrualTrackingSettings
    @Published private(set) var logs: [CycleDayLog]
    @Published private(set) var snapshot: MenstrualCycleSnapshot

    /// Partner (e.g. girlfriend/wife) cycle logged by the user for relationship coaching.
    @Published private(set) var partnerSettings: PartnerCycleSettings
    @Published private(set) var partnerLogs: [CycleDayLog]
    @Published private(set) var partnerSnapshot: MenstrualCycleSnapshot
    @Published private(set) var partnerSupportBrief: PartnerSupportBrief?

    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var isSyncing = false
    @Published private(set) var accuracyReport: CycleAccuracyReport = .empty
    @Published private(set) var predictionFeedback: [CyclePredictionFeedback] = []
    /// Frozen forecasts scored on actual starts (honest MAE).
    @Published private(set) var forecastArchive: [CycleForecastRecord] = []
    @Published private(set) var lastEvaluation: CycleDataEvaluation = .empty
    @Published private(set) var lastAriaBrief: CycleAriaAnalyst.Brief?
    @Published private(set) var lastTeachingMessage: String?
    /// Last live next-period median we advertised (cache; archive is source of truth).
    @Published private(set) var lastAdvertisedNextPeriodMedian: String?
    /// Short toast after model auto-corrects (cleared by UI).
    @Published var lastModelUpdateMessage: String?

    private let defaults = UserDefaults.standard
    private let settingsKey = "forge.menstrual.settings.v1"
    private let logsKey = "forge.menstrual.logs.v1"
    private let partnerSettingsKey = "forge.menstrual.partner.settings.v1"
    private let partnerLogsKey = "forge.menstrual.partner.logs.v1"
    private let feedbackKey = "forge.menstrual.prediction.feedback.v1"
    private let forecastKey = "forge.menstrual.forecast.archive.v1"
    private let advertisedKey = "forge.menstrual.advertised.next.v1"
    private let quietSyncKey = "forge.menstrual.quiet.sync.at"

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
        if let data = defaults.data(forKey: partnerSettingsKey),
           let s = try? JSONDecoder().decode(PartnerCycleSettings.self, from: data) {
            partnerSettings = s
        } else {
            partnerSettings = .default
        }
        if let data = defaults.data(forKey: partnerLogsKey),
           let l = try? JSONDecoder().decode([CycleDayLog].self, from: data) {
            partnerLogs = l
        } else {
            partnerLogs = []
        }
        if let data = defaults.data(forKey: feedbackKey),
           let f = try? JSONDecoder().decode([CyclePredictionFeedback].self, from: data) {
            predictionFeedback = f
        }
        if let data = defaults.data(forKey: forecastKey),
           let f = try? JSONDecoder().decode([CycleForecastRecord].self, from: data) {
            forecastArchive = f
        }
        lastAdvertisedNextPeriodMedian = defaults.string(forKey: advertisedKey)
        snapshot = .empty
        partnerSnapshot = .empty
        partnerSupportBrief = nil
        recompute()
        recomputePartner()
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

    func updatePartnerSettings(_ mutate: (inout PartnerCycleSettings) -> Void) {
        var s = partnerSettings
        mutate(&s)
        partnerSettings = s
        persistPartnerSettings()
        recomputePartner()
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

    /// Surface partner tracking for users who may support a female partner (any gender).
    func enablePartnerTrackingIfAppropriate(gender: Gender) {
        // Soft suggest only — do not auto-enable without consent flag.
        _ = gender
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
        // Capture feedback vs advertised prediction before logs change the engine state.
        recordPredictionFeedbackIfNeeded(actualStartDayKey: dayKey)
        upsertLog(CycleDayLog(dayKey: dayKey, flow: flow, source: "manual"))
    }

    /// Delete a single day log (day edit wipe).
    func deleteLog(dayKey: String) {
        logs.removeAll { $0.dayKey == dayKey }
        persistLogs()
        recompute()
        pushAriaTags()
    }

    /// Wipe self cycle logs (and optionally settings). Keeps partner logs by design.
    func wipeSelfCycleData(includingSettings: Bool = false) {
        logs = []
        predictionFeedback = []
        lastAdvertisedNextPeriodMedian = nil
        defaults.removeObject(forKey: feedbackKey)
        defaults.removeObject(forKey: advertisedKey)
        persistLogs()
        if includingSettings {
            settings = .default
            persistSettings()
        }
        recompute()
        pushAriaTags()
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

    // MARK: Partner logging (never HealthKit — partner is not the device owner)

    func upsertPartnerLog(_ log: CycleDayLog) {
        var entry = log
        entry.source = entry.source == "healthkit" ? "manual" : entry.source
        if let idx = partnerLogs.firstIndex(where: { $0.dayKey == entry.dayKey }) {
            var merged = partnerLogs[idx]
            merged.flow = entry.flow
            merged.symptoms = entry.symptoms
            if let n = entry.notes { merged.notes = n }
            merged.source = "manual"
            merged.updatedAt = Date()
            partnerLogs[idx] = merged
        } else {
            partnerLogs.append(entry)
        }
        partnerLogs.sort { $0.dayKey < $1.dayKey }
        if partnerLogs.count > 800 {
            partnerLogs = Array(partnerLogs.suffix(800))
        }
        persistPartnerLogs()
        recomputePartner()
        pushAriaTags()
    }

    func logPartnerPeriodStart(on dayKey: String = CycleDayKey.key(), flow: MenstrualFlowLevel = .medium) {
        // Partner predictions retained; score against last partner forecast when available.
        if let predicted = partnerSnapshot.nextPeriod?.medianDayKey,
           let err = CycleDayKey.daysBetween(predicted, dayKey),
           abs(err) <= 21 {
            lastModelUpdateMessage = "Support model updated · error \(err >= 0 ? "+" : "")\(err) days"
        }
        upsertPartnerLog(CycleDayLog(dayKey: dayKey, flow: flow, source: "manual"))
    }

    /// User says period started today (feedback + log).
    @discardableResult
    func confirmPeriodStartedToday(flow: MenstrualFlowLevel = .medium) -> String {
        let key = CycleDayKey.key()
        logPeriodStart(on: key, flow: flow)
        updateSettings { $0.overdueWidenDays = 0 }
        let msg = lastModelUpdateMessage ?? "Period logged · model refreshed"
        return msg
    }

    /// Manual early/late correction: period came `days` before (negative) or after (positive) prediction.
    @discardableResult
    func confirmPeriodOffsetFromPrediction(daysFromPredicted: Int, flow: MenstrualFlowLevel = .medium) -> String {
        guard let predicted = lastAdvertisedNextPeriodMedian ?? snapshot.nextPeriod?.medianDayKey,
              let actual = CycleDayKey.addDays(predicted, daysFromPredicted) else {
            let key = CycleDayKey.key()
            logPeriodStart(on: key, flow: flow)
            return lastModelUpdateMessage ?? "Period logged"
        }
        logPeriodStart(on: actual, flow: flow)
        updateSettings { $0.overdueWidenDays = 0 }
        return lastModelUpdateMessage ?? "Model updated · error \(daysFromPredicted >= 0 ? "+" : "")\(daysFromPredicted) days"
    }

    /// Still no period past window — widen forecast, lower certainty, keep history.
    @discardableResult
    func reportStillNoPeriod() -> String {
        updateSettings {
            $0.overdueWidenDays = min(10, $0.overdueWidenDays + 2)
        }
        recompute()
        let msg = "Window widened · still waiting (confidence tempered)"
        lastModelUpdateMessage = msg
        return msg
    }

    func logPartnerToday(flow: MenstrualFlowLevel? = nil, symptoms: [CycleSymptom]? = nil, notes: String? = nil) {
        let key = CycleDayKey.key()
        var existing = partnerLogs.first(where: { $0.dayKey == key }) ?? CycleDayLog(dayKey: key)
        if let flow { existing.flow = flow }
        if let symptoms { existing.symptoms = symptoms }
        if let notes { existing.notes = notes }
        existing.source = "manual"
        existing.updatedAt = Date()
        upsertPartnerLog(existing)
    }

    // MARK: Engine

    func recompute(readinessHRV: Int? = nil, baselineHRV: Int? = nil, restingHR: Int? = nil) {
        var snap = MenstrualCycleEngine.evaluate(
            logs: logs,
            settings: settings,
            recentHRV: readinessHRV,
            baselineHRV: baselineHRV,
            restingHR: restingHR
        )
        accuracyReport = CycleAccuracyReport.compute(
            from: predictionFeedback,
            calibrationOffset: settings.calibrationOffsetDays
        )
        snap.accuracyMAE = accuracyReport.maeDays
        snap.accuracySampleCount = accuracyReport.sampleCount
        snap.accuracyGrade = accuracyReport.gradeLabel
        snap.calibrationOffsetDays = settings.calibrationOffsetDays
        if accuracyReport.sampleCount > 0, let mae = accuracyReport.maeDays {
            snap.insights.insert(
                "Personal timing MAE: \(String(format: "%.1f", mae)) days over \(accuracyReport.sampleCount) confirms (\(accuracyReport.gradeLabel.replacingOccurrences(of: "_", with: " "))).",
                at: 0
            )
        }
        snapshot = snap
        archiveOpenForecastIfNeeded(from: snap)
        lastEvaluation = CycleDataEvaluator.evaluate(
            snapshot: snap,
            settings: settings,
            logs: logs,
            feedback: predictionFeedback
        )
        lastAriaBrief = CycleAriaAnalyst.localBrief(
            evaluation: lastEvaluation,
            snapshot: snap
        )
    }

    /// Freeze one open forecast per anchor period start (honest MAE source).
    private func archiveOpenForecastIfNeeded(from snap: MenstrualCycleSnapshot) {
        guard let next = snap.nextPeriod,
              let anchor = snap.lastPeriodStartDayKey else { return }
        // Update cache
        lastAdvertisedNextPeriodMedian = next.medianDayKey
        defaults.set(next.medianDayKey, forKey: advertisedKey)

        if let idx = forecastArchive.firstIndex(where: { $0.anchorPeriodStartDayKey == anchor && $0.isOpen }) {
            // Refresh open forecast with latest engine view (same cycle)
            var rec = forecastArchive[idx]
            rec.predictedMedianDayKey = next.medianDayKey
            rec.earliestDayKey = next.earliestDayKey
            rec.latestDayKey = next.latestDayKey
            rec.cycleLengthUsed = snap.cycleLengthMedian
            rec.calibrationOffsetUsed = settings.calibrationOffsetDays
            rec.confidence = snap.periodTimingConfidence
            rec.methodSummary = snap.predictionMethodSummary
            rec.asOfDayKey = snap.asOfDayKey
            forecastArchive[idx] = rec
        } else if !forecastArchive.contains(where: { $0.anchorPeriodStartDayKey == anchor }) {
            let rec = CycleForecastRecord(
                id: UUID().uuidString,
                asOfDayKey: snap.asOfDayKey,
                anchorPeriodStartDayKey: anchor,
                predictedMedianDayKey: next.medianDayKey,
                earliestDayKey: next.earliestDayKey,
                latestDayKey: next.latestDayKey,
                cycleLengthUsed: snap.cycleLengthMedian,
                calibrationOffsetUsed: settings.calibrationOffsetDays,
                confidence: snap.periodTimingConfidence,
                methodSummary: snap.predictionMethodSummary,
                createdAt: Date()
            )
            forecastArchive.append(rec)
        }
        if forecastArchive.count > 36 {
            forecastArchive = Array(forecastArchive.suffix(36))
        }
        persistForecasts()
    }

    /// Score actual start against the correct archived forecast; adaptive calibration.
    func recordPredictionFeedbackIfNeeded(actualStartDayKey: String) {
        if predictionFeedback.contains(where: { $0.actualStartDayKey == actualStartDayKey }) {
            return
        }

        // Prefer open forecast whose window is nearest to this actual start.
        let open = forecastArchive.filter(\.isOpen)
        let predicted: String
        var forecastId: String?
        if let best = open.min(by: { a, b in
            abs((CycleDayKey.daysBetween(a.predictedMedianDayKey, actualStartDayKey) ?? 99))
                < abs((CycleDayKey.daysBetween(b.predictedMedianDayKey, actualStartDayKey) ?? 99))
        }), let err0 = CycleDayKey.daysBetween(best.predictedMedianDayKey, actualStartDayKey), abs(err0) <= 21 {
            predicted = best.predictedMedianDayKey
            forecastId = best.id
        } else if let fallback = lastAdvertisedNextPeriodMedian ?? snapshot.nextPeriod?.medianDayKey {
            predicted = fallback
        } else {
            return
        }

        guard let err = CycleDayKey.daysBetween(predicted, actualStartDayKey), abs(err) <= 21 else { return }

        let entry = CyclePredictionFeedback(
            predictedMedianDayKey: predicted,
            actualStartDayKey: actualStartDayKey,
            errorDays: err,
            recordedAt: Date()
        )
        predictionFeedback.append(entry)
        if predictionFeedback.count > 24 {
            predictionFeedback = Array(predictionFeedback.suffix(24))
        }
        persistFeedback()

        if let fid = forecastId, let idx = forecastArchive.firstIndex(where: { $0.id == fid }) {
            forecastArchive[idx].scoredActualStartDayKey = actualStartDayKey
            forecastArchive[idx].scoredErrorDays = err
            persistForecasts()
        }

        // Adaptive EMA: stronger alpha when last 3 errors share a sign.
        let recent = predictionFeedback.suffix(3).map(\.errorDays)
        let sameSign = recent.count >= 3
            && (recent.allSatisfy { $0 > 0 } || recent.allSatisfy { $0 < 0 })
        let alpha = sameSign ? 0.5 : 0.35
        let newOffset = settings.calibrationOffsetDays * (1 - alpha) + Double(err) * alpha

        // Learn luteal when prior cycle had high-signal ovulation
        maybeLearnLuteal(actualStartDayKey: actualStartDayKey)

        // Direct settings mutate without nested recompute storm
        var s = settings
        s.calibrationOffsetDays = max(-5, min(5, newOffset))
        s.overdueWidenDays = 0
        settings = s
        persistSettings()

        lastModelUpdateMessage = "Model updated · last error \(err >= 0 ? "+" : "")\(err) days"
        let eval = CycleDataEvaluator.evaluate(
            snapshot: snapshot,
            settings: settings,
            logs: logs,
            feedback: predictionFeedback,
            lastAction: "period_start_confirmed"
        )
        lastEvaluation = eval
        lastTeachingMessage = CycleAriaAnalyst.teachingAfterFeedback(
            errorDays: err,
            evaluation: eval,
            snapshot: snapshot
        )
        lastAriaBrief = CycleAriaAnalyst.localBrief(
            evaluation: eval,
            snapshot: snapshot,
            lastAction: "period_start_confirmed"
        )
    }

    /// Update learned luteal from LH/BBT-tagged prior ovulation when next start arrives.
    private func maybeLearnLuteal(actualStartDayKey: String) {
        guard let method = snapshot.ovulationMethod,
              method == "lh_surge" || method == "bbt_shift",
              let ovuDay = snapshot.ovulationDayInCycle,
              let lastStart = snapshot.lastPeriodStartDayKey,
              let ovuKey = CycleDayKey.addDays(lastStart, ovuDay - 1),
              let luteal = CycleDayKey.daysBetween(ovuKey, actualStartDayKey),
              luteal >= 10, luteal <= 16
        else { return }

        let prior = settings.learnedLutealDays ?? Double(settings.typicalLutealDays)
        let blended = prior * 0.6 + Double(luteal) * 0.4
        settings.learnedLutealDays = blended
        persistSettings()
    }

    func recomputePartner() {
        let engineSettings = MenstrualTrackingSettings(
            enabled: partnerSettings.enabled && partnerSettings.consentAcknowledged,
            shareWithAria: partnerSettings.shareWithAria,
            averageCycleOverride: partnerSettings.averageCycleOverride,
            averagePeriodOverride: partnerSettings.averagePeriodOverride,
            typicalLutealDays: partnerSettings.typicalLutealDays,
            usesHormonalContraception: partnerSettings.usesHormonalContraception,
            notes: partnerSettings.notes
        )
        partnerSnapshot = MenstrualCycleEngine.evaluate(
            logs: partnerLogs,
            settings: engineSettings
        )
        if partnerSettings.enabled, partnerSettings.consentAcknowledged {
            partnerSupportBrief = PartnerSupportCoach.brief(
                snapshot: partnerSnapshot,
                settings: partnerSettings
            )
        } else {
            partnerSupportBrief = nil
        }
    }

    func refresh(from store: AppStore) {
        recompute(
            readinessHRV: store.dailyMetrics.hrv,
            baselineHRV: max(store.dailyMetrics.hrv, 40),
            restingHR: store.dailyMetrics.restingHR
        )
        recomputePartner()
        pushAriaTags()
    }

    // MARK: HealthKit

    func syncFromHealthKit(days: Int = 400) async {
        guard settings.enabled else { return }
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
        if settings.enabled, settings.shareWithAria {
            AriaContextStore.shared.applyCycleSnapshot(snapshot)
        } else {
            AriaContextStore.shared.clearCycleTags()
        }
        if partnerSettings.enabled,
           partnerSettings.consentAcknowledged,
           partnerSettings.shareWithAria {
            AriaContextStore.shared.applyPartnerCycleSnapshot(
                partnerSnapshot,
                partnerName: partnerSettings.displayName,
                relationshipLabel: partnerSettings.relationshipLabel,
                role: partnerSettings.resolvedRole
            )
        } else {
            AriaContextStore.shared.clearPartnerCycleTags()
        }
    }

    func ariaContextLines() -> [String] {
        var lines: [String] = []
        if settings.enabled, settings.shareWithAria {
            lines.append("Self cycle phase: \(snapshot.phase.label)")
            if let d = snapshot.dayInCycle {
                lines.append("Self day in cycle: \(d)")
            }
            lines.append(snapshot.trainingNote)
        }
        if partnerSettings.enabled, partnerSettings.consentAcknowledged, partnerSettings.shareWithAria {
            lines.append("Partner (\(partnerSettings.displayName)) phase: \(partnerSnapshot.phase.label)")
            if let d = partnerSnapshot.dayInCycle {
                lines.append("Partner day in cycle: \(d)")
            }
            if let brief = partnerSupportBrief {
                lines.append(brief.headline)
                lines.append(brief.communicationTip)
            }
            lines.append(PartnerSupportBrief.disclaimer)
        }
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

    private func persistPartnerSettings() {
        if let data = try? JSONEncoder().encode(partnerSettings) {
            defaults.set(data, forKey: partnerSettingsKey)
        }
    }

    private func persistPartnerLogs() {
        if let data = try? JSONEncoder().encode(partnerLogs) {
            defaults.set(data, forKey: partnerLogsKey)
        }
    }

    private func persistFeedback() {
        if let data = try? JSONEncoder().encode(predictionFeedback) {
            defaults.set(data, forKey: feedbackKey)
        }
    }

    private func persistForecasts() {
        if let data = try? JSONEncoder().encode(forecastArchive) {
            defaults.set(data, forKey: forecastKey)
        }
    }

    /// Refresh evaluation + local ARIA brief after a user action label.
    func refreshAnalyst(lastAction: String? = nil, isPartner: Bool = false) {
        let snap = isPartner ? partnerSnapshot : snapshot
        let set = isPartner
            ? MenstrualTrackingSettings(
                enabled: partnerSettings.enabled,
                shareWithAria: partnerSettings.shareWithAria,
                averageCycleOverride: partnerSettings.averageCycleOverride,
                averagePeriodOverride: partnerSettings.averagePeriodOverride,
                typicalLutealDays: partnerSettings.typicalLutealDays,
                usesHormonalContraception: partnerSettings.usesHormonalContraception,
                notes: partnerSettings.notes,
                highAccuracyMode: settings.highAccuracyMode
            )
            : settings
        let logSet = isPartner ? partnerLogs : logs
        let eval = CycleDataEvaluator.evaluate(
            snapshot: snap,
            settings: set,
            logs: logSet,
            feedback: isPartner ? [] : predictionFeedback,
            lastAction: lastAction,
            isPartner: isPartner
        )
        lastEvaluation = eval
        lastAriaBrief = CycleAriaAnalyst.localBrief(
            evaluation: eval,
            snapshot: snap,
            lastAction: lastAction,
            isPartner: isPartner
        )
    }

    func ariaChatPromptForCycle(isPartner: Bool = false) -> String? {
        let share = isPartner ? partnerSettings.shareWithAria : settings.shareWithAria
        guard share else { return nil }
        let ctx = CycleAriaAnalyst.makeContext(
            snapshot: isPartner ? partnerSnapshot : snapshot,
            evaluation: lastEvaluation,
            settings: settings,
            lastAction: lastTeachingMessage,
            isPartner: isPartner
        )
        return CycleAriaAnalyst.chatPrompt(context: ctx, evaluation: lastEvaluation)
    }
}

// MARK: - HealthKit DTO

struct MenstrualHealthKitBundle {
    var flowSamples: [(date: Date, flow: MenstrualFlowLevel)]
    var bbtSamples: [(date: Date, celsius: Double)]
    var ovulationTests: [(date: Date, result: OvulationTestResult)]
    var mucusSamples: [(date: Date, quality: CervicalMucusQuality)]
}
