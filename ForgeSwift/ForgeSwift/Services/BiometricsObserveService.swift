import Foundation
import ForgeCore

/// Client for `/ai/observe` — the fusion endpoint that turns raw HealthKit
/// samples into derived signals (HRV trend/baseline, chronotype) only the
/// server can compute from history. Only calls out when
/// `ForgeCloudSync.isRemoteEligible` (never in Dummy/local-testing, matching
/// every other backend call); otherwise falls back to whatever was last
/// observed, same as before this endpoint was wired up.
@MainActor
final class BiometricsObserveService {
    static let shared = BiometricsObserveService()

    private let contextStore = AriaContextStore.shared
    private static let backfillCompletedKey = "forge.biometrics.initialBackfillCompleted.v1"
    private static let backfillBatchSize = 400

    private init() {}

    /// One-time deep historical backfill so personal baselines (and the
    /// daily story) don't need a week of live usage to have anything to say —
    /// runs from the onboarding boot sequence (`AriaForgePrep.loadUserData`),
    /// which already holds the UI open behind "Pulling Apple Health" while
    /// real work happens; this is the work becoming real, not just the copy.
    /// Chunked to `backfillBatchSize` to stay under the server's 500-samples-
    /// per-call cap regardless of how many metrics/days this later grows to.
    @discardableResult
    func runInitialBackfillIfNeeded(store: AppStore, days: Int = 90) async -> Bool {
        let defaults = UserDefaults.standard
        guard ForgeCloudSync.shared.isRemoteEligible,
              !defaults.bool(forKey: Self.backfillCompletedKey) else {
            return false
        }

        let trends = await HealthKitManager.shared.fetchHistoricalTrends(days: days)
        guard !trends.isEmpty else { return false }

        var samples: [HealthSamplePayload] = []
        for day in trends {
            let stamp = day.date.ISO8601Format()
            if day.avgHRV > 0 {
                samples.append(.init(metric: "hrv", value: day.avgHRV, unit: "ms",
                                     timestamp: stamp, source: "apple-health"))
            }
            if day.steps > 0 {
                samples.append(.init(metric: "steps", value: Double(day.steps), unit: "count",
                                     timestamp: stamp, source: "apple-health"))
            }
            if day.activeCalories > 0 {
                samples.append(.init(metric: "active_calories", value: Double(day.activeCalories),
                                     unit: "kcal", timestamp: stamp, source: "apple-health"))
            }
            if day.sleepHours > 0 {
                samples.append(.init(metric: "sleep_duration", value: day.sleepHours * 60, unit: "min",
                                     timestamp: stamp, source: "apple-health"))
            }
        }
        guard !samples.isEmpty else { return false }

        for chunk in samples.forgeChunked(into: Self.backfillBatchSize) {
            _ = await observe(store: store, samples: chunk)
        }
        defaults.set(true, forKey: Self.backfillCompletedKey)
        return true
    }

    @discardableResult
    func observe(
        store: AppStore,
        samples: [HealthSamplePayload] = [],
        message: String? = nil
    ) async -> ObserveResponsePayload? {
        if ForgeCloudSync.shared.isRemoteEligible {
            let request = ObserveRequestPayload(
                userId: contextStore.context.userId,
                samples: samples,
                includeStored: true,
                ageYears: store.userProfile.age,
                permissions: DataPermissionsStore.shared.payloadIfRestricted(),
                message: message,
                voiceMode: nil
            )
            if let response = try? await postObserve(request) {
                if let ariaContext = response.ariaContext {
                    contextStore.applyObservedContext(ariaContext)
                }
                if let dailyStory = response.dailyStory {
                    contextStore.applyDailyStory(dailyStory)
                }
                return response
            }
        }
        return ObserveResponsePayload(
            ariaContext: contextStore.lastObservedContext,
            restrictedDomains: DataPermissionsStore.shared.restrictedDomains.isEmpty
                ? nil
                : DataPermissionsStore.shared.restrictedDomains,
            missingFields: nil,
            dailyStory: contextStore.lastDailyStory
        )
    }

    private func postObserve(_ payload: ObserveRequestPayload) async throws -> ObserveResponsePayload {
        let url = AriaService.shared.baseURL.appendingPathComponent("ai/observe")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        let (data, _) = try await ForgeAPI.send(request)
        return try JSONDecoder().decode(ObserveResponsePayload.self, from: data)
    }

    /// Dated HealthKit samples ARIA already has on this iPhone, shaped for
    /// `observe(store:samples:)` — the values, not raw Health records.
    func samplesFromStore(_ store: AppStore) async -> [HealthSamplePayload] {
        let now = Date.now.ISO8601Format()
        var samples: [HealthSamplePayload] = []

        for day in HealthKitManager.shared.weeklyTrends {
            let stamp = day.date.ISO8601Format()
            if day.avgHRV > 0 {
                samples.append(.init(metric: "hrv", value: day.avgHRV, unit: "ms",
                                     timestamp: stamp, source: "apple-health"))
            }
            if day.steps > 0 {
                samples.append(.init(metric: "steps", value: Double(day.steps), unit: "count",
                                     timestamp: stamp, source: "apple-health"))
            }
            if day.activeCalories > 0 {
                samples.append(.init(metric: "active_calories", value: Double(day.activeCalories),
                                     unit: "kcal", timestamp: stamp, source: "apple-health"))
            }
        }

        // Nightly sleep duration. `sleep_duration` is the one server-side sleep
        // metric that needs no extra shape beyond metric/value/unit — stage
        // minutes (deep/rem/light/awake) need a per-sample stage tag this
        // payload does not carry yet, so they stay client-only for now.
        for night in store.sleepData where night.totalHours > 0 {
            samples.append(.init(metric: "sleep_duration", value: night.totalHours * 60, unit: "min",
                                 timestamp: night.date, source: "apple-health"))
        }

        // Today's readings, for whatever the weekly series does not carry. HRV,
        // steps and calories are only added here when the series is empty —
        // otherwise today is already in it and would be double-counted, which
        // would drag the median toward a single day.
        let haveSeries = !HealthKitManager.shared.weeklyTrends.isEmpty
        if !haveSeries, store.dailyMetrics.hrv > 0 {
            samples.append(.init(metric: "hrv", value: Double(store.dailyMetrics.hrv), unit: "ms",
                                 timestamp: now, source: "apple-health"))
        }
        if !haveSeries, store.dailyMetrics.steps > 0 {
            samples.append(.init(metric: "steps", value: Double(store.dailyMetrics.steps),
                                 unit: "count", timestamp: now, source: "apple-health"))
        }
        if !haveSeries, store.dailyMetrics.activeCalories > 0 {
            samples.append(.init(metric: "active_calories", value: Double(store.dailyMetrics.activeCalories),
                                 unit: "kcal", timestamp: now, source: "apple-health"))
        }
        // Resting heart rate has no per-day series on the client yet — the weekly
        // trend does not carry it — so today's value is all there is to send.
        if store.dailyMetrics.restingHR > 0 {
            samples.append(.init(metric: "resting_hr", value: Double(store.dailyMetrics.restingHR),
                                 unit: "bpm", timestamp: now, source: "apple-health"))
        }
        // RMSSD is its own metric. Weekly `hrv` above is SDNN-shaped HealthKit
        // history — never retagged as rmssd. Emit RMSSD only when BodyModel
        // actually ingested a sample.
        if let rmssd = BodyModelHRVBaselineStore.load().rmssd.last, rmssd > 0 {
            samples.append(.init(metric: "hrv_rmssd", value: rmssd, unit: "ms",
                                 timestamp: now, source: "apple-health"))
        }
        if let weight = store.userProfile.weight {
            samples.append(.init(metric: "weight", value: weight, unit: "kg",
                                 timestamp: now, source: "apple-health"))
        }
        // Respiratory/metabolic/BP vitals — fetched daily into `todayStats`
        // already (used on-device for the QoL score and risk monitor) but
        // never previously sent to /ai/observe, so ARIA's server-side
        // classification/interpretation of them went unused. `oxygenSaturation`
        // is HealthKit's native 0-1 fraction (`.percent()` is a fraction unit,
        // not 0-100) — sent as "fraction" so classify.py's unit check doesn't
        // divide it by 100 a second time. `bodyTemperature` is fetched in
        // Fahrenheit (`.degreeFahrenheit()`); the server converts to Celsius
        // from the declared unit, not by guessing from magnitude.
        if let today = HealthKitManager.shared.todayStats {
            if today.respiratoryRate > 0 {
                samples.append(.init(metric: "respiratory_rate", value: today.respiratoryRate,
                                     unit: "breaths/min", timestamp: now, source: "apple-health"))
            }
            if today.oxygenSaturation > 0 {
                samples.append(.init(metric: "oxygen_saturation", value: today.oxygenSaturation,
                                     unit: "fraction", timestamp: now, source: "apple-health"))
            }
            if today.bloodPressureSystolic > 0 {
                samples.append(.init(metric: "blood_pressure_systolic", value: today.bloodPressureSystolic,
                                     unit: "mmHg", timestamp: now, source: "apple-health"))
            }
            if today.bloodPressureDiastolic > 0 {
                samples.append(.init(metric: "blood_pressure_diastolic", value: today.bloodPressureDiastolic,
                                     unit: "mmHg", timestamp: now, source: "apple-health"))
            }
            if today.bodyTemperature > 0 {
                samples.append(.init(metric: "body_temperature", value: today.bodyTemperature,
                                     unit: "fahrenheit", timestamp: now, source: "apple-health"))
            }
        }
        if let glucose = await HealthKitManager.shared.fetchLatestBloodGlucoseMgDl(), glucose > 0 {
            samples.append(.init(metric: "blood_glucose", value: glucose, unit: "mg/dL",
                                 timestamp: now, source: "apple-health"))
        }
        return samples
    }
}

private extension Array {
    /// Splits into `size`-element (or smaller final) slices, oldest-first —
    /// used to keep a backfill POST under the server's per-call sample cap.
    func forgeChunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
