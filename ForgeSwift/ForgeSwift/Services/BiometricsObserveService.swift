import Foundation

/// Client for POST /ai/observe — fuses HealthKit samples with stored metrics.
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
        let payload = ObserveRequestPayload(
            userId: contextStore.context.userId,
            samples: samples.isEmpty ? nil : samples,
            includeStored: true,
            ageYears: store.userProfile.age,
            permissions: contextStore.permissions.payload,
            message: message,
            voiceMode: store.ariaVoiceMode
        )

        if AriaService.shouldUseTestReadyDummy {
            return ObserveResponsePayload(
                ariaContext: contextStore.lastObservedContext,
                restrictedDomains: nil,
                missingFields: nil
            )
        }

        guard let url = URL(string: "ai/observe", relativeTo: AriaService.shared.baseURL) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(payload)

        guard let (data, response) = try? await ForgeAPI.send(request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(ObserveResponsePayload.self, from: data) else {
            return nil
        }

        if let ctx = decoded.ariaContext {
            contextStore.applyObservedContext(ctx)
        }
        return decoded
    }

    /// Build HealthKit samples from current daily metrics for observe sync.
    /// Real dated history, not one snapshot stamped "now".
    ///
    /// This used to emit a single sample per metric, all timestamped `Date()`,
    /// so `BodyModel` accumulated at most one point per refresh and could never
    /// establish a personal baseline — which is why `hrv_7day_trend` came back
    /// empty and the client felt obliged to invent one.
    ///
    /// `HealthKitManager.weeklyTrends` already holds seven days of per-day HRV
    /// and step counts, correctly dated, fetched on the same refresh. Sending it
    /// is what lets the server's median-based baseline mean anything.
    func samplesFromStore(_ store: AppStore) -> [HealthSamplePayload] {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let now = iso.string(from: Date())
        var samples: [HealthSamplePayload] = []

        for day in HealthKitManager.shared.weeklyTrends {
            let stamp = iso.string(from: day.date)
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
