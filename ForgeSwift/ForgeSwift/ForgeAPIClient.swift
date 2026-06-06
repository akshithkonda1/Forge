import Foundation

enum ForgeAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case server(Int, String)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid API URL"
        case .invalidResponse: return "Invalid server response"
        case .server(let code, let message): return "Server error (\(code)): \(message)"
        case .decoding(let error): return "Failed to decode response: \(error.localizedDescription)"
        }
    }
}

struct APIErrorBody: Decodable {
    let message: String
    let code: String?
}

// MARK: - API DTOs

struct APIReadinessData: Decodable {
    let overall: Int
    let sleepQuality: Int
    let recoveryScore: Int
    let stressLevel: Int
    let energyBank: Int
}

struct APIDailyMetrics: Decodable {
    let steps: Int
    let activeCalories: Int
    let hrv: Int
    let restingHR: Int
    let deepSleep: Int
    let totalSleep: Int
}

struct APIExercise: Decodable {
    let id: String
    let name: String
    let sets: Int
    let reps: StringOrNumber
    let weight: Int?
    let restSeconds: Int
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id, name, sets, reps, weight, restSeconds, notes
    }
}

enum StringOrNumber: Decodable {
    case string(String)
    case number(Int)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Int.self) {
            self = .number(value)
        } else {
            self = .string("")
        }
    }

    var display: String {
        switch self {
        case .string(let value): return value
        case .number(let value): return String(value)
        }
    }
}

struct APIWorkoutPlan: Decodable {
    let id: String
    let name: String
    let type: String
    let duration: Int
    let intensity: String
    let exercises: [APIExercise]
}

struct APISleepData: Decodable {
    let date: String
    let totalHours: Double
    let deepMinutes: Int
    let remMinutes: Int
    let lightMinutes: Int
    let awakeMinutes: Int
    let score: Int
}

struct APIWorkoutHistory: Decodable {
    let id: String
    let date: String
    let name: String
    let type: String
    let duration: Int
    let volume: Int
    let intensity: String
}

struct APIPersonalRecord: Decodable {
    let exercise: String
    let value: Double
    let unit: String
    let date: String
}

struct APIUserProfile: Decodable {
    let name: String
    let fitnessGoals: [String]
    let experienceLevel: String
    let preferredWorkouts: [String]
    let coachingStyle: String
    let connectedDevices: [String]
    let weeklySchedule: [Int]
}

struct DashboardTodayResponse: Decodable {
    let profile: APIUserProfile
    let readiness: APIReadinessData
    let dailyMetrics: APIDailyMetrics
    let todayWorkout: APIWorkoutPlan?
    let recentSleep: [APISleepData]
    let recentWorkouts: [APIWorkoutHistory]
    let personalRecords: [APIPersonalRecord]
}

struct SleepListResponse: Decodable {
    let sleep: [APISleepData]
}

struct WorkoutHistoryResponse: Decodable {
    let workouts: [APIWorkoutHistory]
    let personalRecords: [APIPersonalRecord]
}

struct ProgressSummaryResponse: Decodable {
    let periodDays: Int
    let workoutsCompleted: Int
    let newPersonalRecords: [APIPersonalRecord]
    let recoveryConsistencyDelta: Double
    let summary: String
}

struct ARIAConversationMessage: Decodable {
    let role: String
    let content: String
    let id: String?
    let timestamp: String?
}

struct ARIAConversationResponse: Decodable {
    let threadId: String
    let messages: [ARIAConversationMessage]
    let messageCount: Int
}

struct ARIAChatResponse: Decodable {
    let threadId: String
    let message: APIChatMessage
}

struct APIChatMessage: Decodable {
    let id: String
    let role: String
    let content: String
    let timestamp: String
}

struct HealthMetricInput: Encodable {
    let source: String
    let metricType: String
    let startedAt: String
    let endedAt: String?
    let value: Double
    let unit: String
}

struct HealthBatchRequest: Encodable {
    let metrics: [HealthMetricInput]
}

struct UpdateProfileRequest: Encodable {
    let profile: [String: AnyEncodable]
}

struct AnyEncodable: Encodable {
    private let encodeFunc: (Encoder) throws -> Void

    init<T: Encodable>(_ value: T) {
        encodeFunc = { encoder in try value.encode(to: encoder) }
    }

    func encode(to encoder: Encoder) throws {
        try encodeFunc(encoder)
    }
}

// MARK: - Client

final class ForgeAPIClient {
    static let shared = ForgeAPIClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    func getDashboardToday() async throws -> DashboardTodayResponse {
        try await request(path: "/dashboard/today")
    }

    func getSleep(days: Int = 14) async throws -> SleepListResponse {
        try await request(path: "/sleep", query: ["days": String(days)])
    }

    func getWorkoutHistory(days: Int = 30) async throws -> WorkoutHistoryResponse {
        try await request(path: "/workouts/history", query: ["days": String(days)])
    }

    func getProgressSummary(days: Int = 30) async throws -> ProgressSummaryResponse {
        try await request(path: "/progress/summary", query: ["days": String(days)])
    }

    func getARIAConversation(threadId: String = "current") async throws -> ARIAConversationResponse {
        try await request(path: "/aria/conversation", query: ["threadId": threadId])
    }

    func sendARIAChat(content: String) async throws -> ARIAChatResponse {
        try await request(path: "/aria/chat", method: "POST", body: ["content": content])
    }

    func updateProfile(_ profile: [String: AnyEncodable]) async throws -> APIUserProfile {
        struct ProfileResponse: Decodable { let profile: APIUserProfile }
        let response: ProfileResponse = try await request(
            path: "/me/profile",
            method: "PUT",
            body: UpdateProfileRequest(profile: profile)
        )
        return response.profile
    }

    func syncHealthBatch(_ metrics: [HealthMetricInput]) async throws {
        struct HealthBatchResponse: Decodable {
            let accepted: Int
            let rejected: Int
        }
        let _: HealthBatchResponse = try await request(
            path: "/health/batch",
            method: "POST",
            body: HealthBatchRequest(metrics: metrics)
        )
    }

    func postWorkoutLog(
        name: String,
        type: String,
        duration: Int,
        volume: Int,
        intensity: String
    ) async throws {
        struct WorkoutLog: Encodable {
            let name: String
            let type: String
            let duration: Int
            let volume: Int
            let intensity: String
            let source: String
            let startedAt: String
        }
        struct Body: Encodable {
            let workout: WorkoutLog
        }
        let body = Body(
            workout: WorkoutLog(
                name: name,
                type: type,
                duration: duration,
                volume: volume,
                intensity: intensity,
                source: "apple-health",
                startedAt: ISO8601DateFormatter().string(from: Date())
            )
        )
        struct WorkoutLogResponse: Decodable {
            let workout: [String: String]
        }
        let _: WorkoutLogResponse = try await request(path: "/workouts/logs", method: "POST", body: body)
    }

    private func request<T: Decodable>(
        path: String,
        method: String = "GET",
        query: [String: String] = [:],
        body: (any Encodable)? = nil
    ) async throws -> T {
        var components = URLComponents(url: APIConfig.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components?.url else { throw ForgeAPIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let header = await CognitoAuthManager.shared.authorizationHeader {
            request.setValue(header, forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.httpBody = try encoder.encode(body)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ForgeAPIError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            let message = (try? decoder.decode(APIErrorBody.self, from: data))?.message
                ?? String(data: data, encoding: .utf8)
                ?? "Unknown error"
            throw ForgeAPIError.server(http.statusCode, message)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw ForgeAPIError.decoding(error)
        }
    }
}
