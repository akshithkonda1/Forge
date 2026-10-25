import Foundation
import ForgeCore

/// On-device HealthKit ingest. Used to POST ~11 daily metrics plus a deep
/// backfill to `/ai/observe`. That path is gone.
///
/// Flow: HealthKit batch → dedup → Health Scout (gaps + re-gather) →
/// clean canonical batch → on-device BodyModel / daily story → ARIA.
/// Nothing here talks to a server.
@MainActor
final class BiometricsObserveService {
    static let shared = BiometricsObserveService()

    private let contextStore = AriaContextStore.shared
    private static let backfillCompletedKey = "forge.biometrics.initialBackfillCompleted.v1"

    private init() {}

    /// Seeds local BodyModel / learner history from the on-device HealthKit
    /// window. Never uploads. The onboarding "Pulling Apple Health" copy is
    /// this work becoming real.
    @discardableResult
    func runInitialBackfillIfNeeded(store: AppStore, days: Int = 90) async -> Bool {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.backfillCompletedKey) else { return false }

        let trends = await HealthKitManager.shared.fetchHistoricalTrends(days: days)
        guard !trends.isEmpty else { return false }

        var incoming: [HealthIngestSample] = []
        for day in trends {
            if day.avgHRV > 0 {
                incoming.append(HealthIngestSample(
                    metric: .hrv, value: day.avgHRV, unit: "ms",
                    start: day.date, source: "apple-health"
                ))
                BodyModelHRVBaselineStore.ingest(HRVObservation(
                    statistic: .sdnn,
                    milliseconds: day.avgHRV,
                    timestamp: day.date,
                    source: "apple-health"
                ))
            }
            if day.steps > 0 {
                incoming.append(HealthIngestSample(
                    metric: .steps, value: Double(day.steps), unit: "count",
                    start: day.date, source: "apple-health"
                ))
            }
            if day.sleepHours > 0 {
                incoming.append(HealthIngestSample(
                    metric: .sleep, value: day.sleepHours * 60, unit: "min",
                    start: day.date, source: "apple-health"
                ))
            }
        }
        _ = ingestLocally(store: store, incoming: incoming)
        defaults.set(true, forKey: Self.backfillCompletedKey)
        return true
    }

    @discardableResult
    func observe(
        store: AppStore,
        samples: [HealthSamplePayload] = [],
        message: String? = nil
    ) async -> ObserveResponsePayload? {
        _ = message
        _ = ForgeDeviceViabilityCheck.evaluateCurrent(
            healthKitAvailable: HealthKitManager.shared.isHealthDataAvailable(),
            healthKitAuthorized: HealthKitManager.shared.isAuthorized
        )
        let incoming = samples.isEmpty
            ? await localIngestSamples(from: store)
            : samples.compactMap(Self.ingestSample(from:))
        let batch = ingestLocally(store: store, incoming: incoming)
        applyProjection(store: store, batch: batch)
        return ObserveResponsePayload(
            ariaContext: contextStore.lastObservedContext,
            restrictedDomains: DataPermissionsStore.shared.restrictedDomains.isEmpty
                ? nil
                : DataPermissionsStore.shared.restrictedDomains,
            missingFields: batch.scout.openGaps.map(\.field),
            dailyStory: contextStore.lastDailyStory
        )
    }

    /// Dated HealthKit samples already on this iPhone, shaped for local ingest.
    func samplesFromStore(_ store: AppStore) async -> [HealthSamplePayload] {
        let incoming = await localIngestSamples(from: store)
        return incoming.map { sample in
            HealthSamplePayload(
                metric: sample.metric.rawValue,
                value: sample.value,
                unit: sample.unit,
                timestamp: ISO8601DateFormatter().string(from: sample.start),
                source: sample.source
            )
        }
    }

    // MARK: - Local pipeline

    @discardableResult
    func ingestLocally(store: AppStore, incoming: [HealthIngestSample]) -> HealthCanonicalBatch {
        let connected = store.metricSources + ["apple-health"]
        var learner = HealthIngestLearner.load()
        let expected = HealthScout.expectedMetrics(
            connectedSources: connected,
            samples: incoming
        ).union([.sleep, .hrv, .restingHR, .steps])
        let (batch, next) = HealthIngestLayer.process(
            incoming: incoming,
            connectedSources: connected,
            expected: expected,
            day: Date(),
            learner: learner,
            reGather: { gap in Self.fillFromOnDeviceHealthKit(gap, store: store) }
        )
        learner = next
        HealthIngestLearner.save(learner)
        contextStore.applyHealthScout(batch.scout)
        contextStore.persistContinuity(learner: learner, scout: batch.scout)
        return batch
    }

    private func applyProjection(store: AppStore, batch: HealthCanonicalBatch) {
        let hrv = batch.samples.filter { $0.metric == .hrv }.map(\.value)
        let sleep = batch.samples.filter { $0.metric == .sleep }.map(\.value)
        let steps = batch.samples.filter { $0.metric == .steps }.map(\.value)
        let projection = OnDeviceBodyModel.project(
            dailyHRV: hrv,
            dailySleepMinutes: sleep,
            dailySteps: steps
        )
        var context = contextStore.buildARIAContext(from: store)
        context.readiness.hrv7DayTrend = projection.hrv7DayTrend
        context.readiness.hrv30DayBaseline = projection.hrv30DayBaseline
        context.readiness.hrvDaysAvailable = projection.hrvDaysAvailable
        contextStore.applyObservedContext(context)

        if let story = OnDeviceDailyStory.build(
            hrvTrend: projection.hrv7DayTrend,
            sleepMinutes: sleep.last,
            sleepBaselineMinutes: projection.sleepBaselineMinutes,
            steps3Day: steps.suffix(3).isEmpty ? nil : steps.suffix(3).reduce(0, +) / Double(steps.suffix(3).count),
            stepsBaseline: projection.stepsBaseline
        ) {
            contextStore.applyDailyStory(DailyStoryPayload(
                generatedAt: story.generatedAt,
                narrative: story.narrative,
                insights: story.insights.map { DailyStoryInsight(text: $0.text, domain: $0.domain, evidence: $0.evidence) },
                sources: story.sources
            ))
        }
    }

    private func localIngestSamples(from store: AppStore) async -> [HealthIngestSample] {
        var incoming: [HealthIngestSample] = []
        for day in HealthKitManager.shared.weeklyTrends {
            if day.avgHRV > 0 {
                incoming.append(HealthIngestSample(metric: .hrv, value: day.avgHRV, unit: "ms", start: day.date, source: "apple-health"))
            }
            if day.steps > 0 {
                incoming.append(HealthIngestSample(metric: .steps, value: Double(day.steps), unit: "count", start: day.date, source: "apple-health"))
            }
            if day.activeCalories > 0 {
                incoming.append(HealthIngestSample(metric: .activeCalories, value: Double(day.activeCalories), unit: "kcal", start: day.date, source: "apple-health"))
            }
            if day.sleepHours > 0 {
                incoming.append(HealthIngestSample(metric: .sleep, value: day.sleepHours * 60, unit: "min", start: day.date, source: "apple-health"))
            }
        }
        for night in store.sleepData where night.totalHours > 0 {
            let start = ISO8601DateFormatter().date(from: night.date) ?? Date()
            incoming.append(HealthIngestSample(
                metric: .sleep, value: night.totalHours * 60, unit: "min",
                start: start, source: "apple-health"
            ))
        }
        if HealthKitManager.shared.weeklyTrends.isEmpty {
            let now = Date()
            if store.dailyMetrics.hrv > 0 {
                incoming.append(HealthIngestSample(metric: .hrv, value: Double(store.dailyMetrics.hrv), unit: "ms", start: now, source: "apple-health"))
            }
            if store.dailyMetrics.steps > 0 {
                incoming.append(HealthIngestSample(metric: .steps, value: Double(store.dailyMetrics.steps), unit: "count", start: now, source: "apple-health"))
            }
        }
        if store.dailyMetrics.restingHR > 0 {
            incoming.append(HealthIngestSample(
                metric: .restingHR, value: Double(store.dailyMetrics.restingHR),
                unit: "bpm", start: Date(), source: "apple-health"
            ))
        }
        if let rmssd = BodyModelHRVBaselineStore.load().rmssd.last, rmssd > 0 {
            incoming.append(HealthIngestSample(metric: .hrv, value: rmssd, unit: "ms", start: Date(), source: "apple-health"))
        }
        for workout in store.workoutHistory.prefix(7) {
            if let start = WorkoutHistoryWindow.parseDate(workout.date) {
                incoming.append(HealthIngestSample(
                    metric: .workout,
                    value: Double(workout.duration),
                    unit: "min",
                    start: start,
                    end: start.addingTimeInterval(TimeInterval(workout.duration * 60)),
                    source: "apple-health",
                    workoutType: workout.type.rawValue
                ))
            }
        }
        return incoming
    }

    /// HealthKit already sitting on this phone. Never a URL. Empty when the
    /// field is not here — Scout then marks an explicit gap.
    static func fillFromOnDeviceHealthKit(_ gap: HealthScoutGap, store: AppStore) -> [HealthIngestSample] {
        let hk = HealthKitManager.shared
        switch gap.field {
        case "hrv":
            if let day = hk.weeklyTrends.first(where: { $0.avgHRV > 0 }) {
                return [HealthIngestSample(metric: .hrv, value: day.avgHRV, unit: "ms", start: day.date, source: "apple-health")]
            }
            if store.dailyMetrics.hrv > 0 {
                return [HealthIngestSample(metric: .hrv, value: Double(store.dailyMetrics.hrv), unit: "ms", start: Date(), source: "apple-health")]
            }
        case "sleep":
            if let night = store.sleepData.first(where: { $0.totalHours > 0 }) {
                let start = ISO8601DateFormatter().date(from: night.date) ?? Date()
                return [HealthIngestSample(metric: .sleep, value: night.totalHours * 60, unit: "min", start: start, source: "apple-health")]
            }
            if let day = hk.weeklyTrends.first(where: { $0.sleepHours > 0 }) {
                return [HealthIngestSample(metric: .sleep, value: day.sleepHours * 60, unit: "min", start: day.date, source: "apple-health")]
            }
        case "restingHR":
            if store.dailyMetrics.restingHR > 0 {
                return [HealthIngestSample(metric: .restingHR, value: Double(store.dailyMetrics.restingHR), unit: "bpm", start: Date(), source: "apple-health")]
            }
        case "steps":
            if let day = hk.weeklyTrends.first(where: { $0.steps > 0 }) {
                return [HealthIngestSample(metric: .steps, value: Double(day.steps), unit: "count", start: day.date, source: "apple-health")]
            }
        case "workout":
            if let workout = store.workoutHistory.first,
               let start = WorkoutHistoryWindow.parseDate(workout.date) {
                return [HealthIngestSample(
                    metric: .workout,
                    value: Double(workout.duration),
                    unit: "min",
                    start: start,
                    end: start.addingTimeInterval(TimeInterval(workout.duration * 60)),
                    source: "apple-health",
                    workoutType: workout.type.rawValue
                )]
            }
        case "workoutHR":
            // Workout history has duration, not HR. Only return a value
            // already sitting in HealthKit — never invent one.
            break
        default:
            break
        }
        return []
    }

    private static func ingestSample(from payload: HealthSamplePayload) -> HealthIngestSample? {
        let name = (payload.metric ?? "").lowercased().replacingOccurrences(of: "-", with: "_")
        let metric: HealthIngestMetric?
        switch name {
        case "hrv", "hrv_sdnn", "hrv_rmssd": metric = .hrv
        case "sleep", "sleep_duration": metric = .sleep
        case "steps": metric = .steps
        case "resting_hr", "resting_heart_rate": metric = .restingHR
        case "active_calories", "active-calories": metric = .activeCalories
        case "workout": metric = .workout
        case "workout_hr", "heart_rate": metric = .workoutHR
        default: metric = nil
        }
        guard let metric, payload.value > 0 else { return nil }
        let start = payload.timestamp.flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
        return HealthIngestSample(
            metric: metric,
            value: payload.value,
            unit: payload.unit ?? "",
            start: start,
            source: payload.source ?? "apple-health"
        )
    }
}
