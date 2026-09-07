import Foundation

/// Client for on-device observation. Wearable samples stay in Apple Health;
/// ARIA reads them on this iPhone. Forge `/ai/observe` is not a warehouse.
@MainActor
final class BiometricsObserveService {
    static let shared = BiometricsObserveService()

    private let contextStore = AriaContextStore.shared

    private init() {}

    func observe(
        store: AppStore,
        samples: [HealthSamplePayload] = [],
        message: String? = nil
    ) async -> ObserveResponsePayload? {
        _ = samples
        _ = message
        _ = store
        return ObserveResponsePayload(
            ariaContext: contextStore.lastObservedContext,
            restrictedDomains: DataPermissionsStore.shared.restrictedDomains.isEmpty
                ? nil
                : DataPermissionsStore.shared.restrictedDomains,
            missingFields: nil
        )
    }

    /// Dated HealthKit samples ARIA already has on this iPhone.
    /// Used for on-device opinions — not uploaded to Forge.
    func samplesFromStore(_ store: AppStore) -> [HealthSamplePayload] {
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
        if let weight = store.userProfile.weight {
            samples.append(.init(metric: "weight", value: weight, unit: "kg",
                                 timestamp: now, source: "apple-health"))
        }
        return samples
    }
}
