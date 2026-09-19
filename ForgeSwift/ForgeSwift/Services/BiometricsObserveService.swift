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

    private init() {}

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
                return response
            }
        }
        return ObserveResponsePayload(
            ariaContext: contextStore.lastObservedContext,
            restrictedDomains: DataPermissionsStore.shared.restrictedDomains.isEmpty
                ? nil
                : DataPermissionsStore.shared.restrictedDomains,
            missingFields: nil
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
        return samples
    }
}
