import Foundation
import ForgeCore

/// Talks to the Forge HTTP API for dashboard, HealthKit ingest, chat history,
/// and coach routes. Chat generation still goes through `AriaService` / `/ai/chat`.
@MainActor
final class ForgeCloudSync {
    static let shared = ForgeCloudSync()

    private init() {}

    var isRemoteEligible: Bool {
        if AriaService.shouldUseTestReadyDummy { return false }
        if AriaOperatingMode.current.isLocalTesting { return false }
        return true
    }

    func fetchDashboard() async throws -> CloudDashboardToday {
        try await get("dashboard/today")
    }

    func postHealthBatch(_ metrics: [CloudHealthMetric]) async throws -> CloudHealthBatchResult {
        guard !metrics.isEmpty else {
            return CloudHealthBatchResult(accepted: 0, rejected: 0)
        }
        return try await post("health/batch", body: ["metrics": metrics])
    }

    func fetchChatThread() async throws -> CloudChatThread {
        try await get("chat/threads/current")
    }

    func generateWorkoutPlan() async throws -> CloudCoachWorkoutPlan {
        try await post("coach/workout-plan", body: [String: String]())
    }

    func fetchSleepInsight() async throws -> CloudCoachSleepInsight {
        try await post("coach/sleep-insight", body: [String: String]())
    }

    func fetchProgressReview() async throws -> CloudCoachProgressReview {
        try await post("coach/progress-review", body: [String: String]())
    }

    static func healthMetrics(from store: AppStore) -> [CloudHealthMetric] {
        var samples: [(type: String, value: Double, unit: String?, timestamp: String?, source: String?)] = []
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        for day in HealthKitManager.shared.weeklyTrends {
            let stamp = iso.string(from: day.date)
            if day.avgHRV > 0 {
                samples.append((type: "hrv", value: day.avgHRV, unit: "ms", timestamp: stamp, source: "apple-health"))
            }
            if day.steps > 0 {
                samples.append((type: "steps", value: Double(day.steps), unit: "count", timestamp: stamp, source: "apple-health"))
            }
            if day.activeCalories > 0 {
                samples.append((type: "active-calories", value: Double(day.activeCalories), unit: "kcal", timestamp: stamp, source: "apple-health"))
            }
        }

        let now = iso.string(from: Date())
        let metrics = store.dailyMetrics
        if HealthKitManager.shared.weeklyTrends.isEmpty {
            if metrics.hrv > 0 {
                samples.append((type: "hrv", value: Double(metrics.hrv), unit: "ms", timestamp: now, source: "apple-health"))
            }
            if metrics.steps > 0 {
                samples.append((type: "steps", value: Double(metrics.steps), unit: "count", timestamp: now, source: "apple-health"))
            }
            if metrics.activeCalories > 0 {
                samples.append((type: "active-calories", value: Double(metrics.activeCalories), unit: "kcal", timestamp: now, source: "apple-health"))
            }
        }
        if metrics.restingHR > 0 {
            samples.append((type: "resting-heart-rate", value: Double(metrics.restingHR), unit: "bpm", timestamp: now, source: "apple-health"))
        }
        if let weight = store.userProfile.weight, weight > 0 {
            samples.append((type: "body-weight", value: weight, unit: "kg", timestamp: now, source: "apple-health"))
        }
        if let sleep = store.sleepData.first, sleep.deepMinutes > 0 {
            let stamp = sleep.date.isEmpty ? now : sleep.date
            samples.append((type: "sleep-stage", value: Double(sleep.deepMinutes), unit: "min", timestamp: stamp, source: "apple-health"))
        }
        return CloudHealthMetricType.metrics(from: samples)
    }

    // MARK: - Transport

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let request = try makeRequest(path: path, method: "GET", body: Optional<Data>.none)
        let (data, _) = try await ForgeAPI.send(request)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func post<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        let encoded = try JSONEncoder().encode(body)
        let request = try makeRequest(path: path, method: "POST", body: encoded)
        let (data, _) = try await ForgeAPI.send(request)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func makeRequest(path: String, method: String, body: Data?) throws -> URLRequest {
        let url = AriaService.shared.baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        return request
    }
}
