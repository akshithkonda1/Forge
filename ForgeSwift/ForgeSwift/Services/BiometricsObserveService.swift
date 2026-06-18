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

        guard let url = URL(string: "ai/observe", relativeTo: AriaService.shared.baseURL) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(payload)

        guard let (data, response) = try? await URLSession.shared.data(for: request),
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
    func samplesFromStore(_ store: AppStore) -> [HealthSamplePayload] {
        let iso = ISO8601DateFormatter().string(from: Date())
        var samples: [HealthSamplePayload] = []
        if store.dailyMetrics.hrv > 0 {
            samples.append(.init(metric: "hrv", value: Double(store.dailyMetrics.hrv), unit: "ms", timestamp: iso, source: "apple-health"))
        }
        if store.dailyMetrics.restingHR > 0 {
            samples.append(.init(metric: "resting_hr", value: Double(store.dailyMetrics.restingHR), unit: "bpm", timestamp: iso, source: "apple-health"))
        }
        if store.dailyMetrics.steps > 0 {
            samples.append(.init(metric: "steps", value: Double(store.dailyMetrics.steps), unit: "count", timestamp: iso, source: "apple-health"))
        }
        if store.dailyMetrics.activeCalories > 0 {
            samples.append(.init(metric: "active_calories", value: Double(store.dailyMetrics.activeCalories), unit: "kcal", timestamp: iso, source: "apple-health"))
        }
        if let weight = store.userProfile.weight {
            samples.append(.init(metric: "weight", value: weight, unit: "kg", timestamp: iso, source: "apple-health"))
        }
        return samples
    }
}