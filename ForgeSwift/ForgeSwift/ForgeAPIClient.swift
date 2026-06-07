import Foundation

enum ForgeAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case server(Int, String)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid API URL"
        case .invalidResponse: return "Invalid server response"
        case .unauthorized: return "Session expired. Sign in again."
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

struct MeResponse: Decodable {
    let profile: APIUserProfile
    let connections: [APIIntegrationConnection]
}

struct DashboardTodayResponse: Decodable {
    let profile: APIUserProfile
    let readiness: APIReadinessData
    let dailyMetrics: APIDailyMetrics
    let todayWorkout: APIWorkoutPlan?
    let recentSleep: [APISleepData]
    let recentWorkouts: [APIWorkoutHistory]
    let personalRecords: [APIPersonalRecord]
    let connections: [APIIntegrationConnection]?
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
    let richCard: APIRichCardPayload?
}

struct ARIAConversationResponse: Decodable {
    let threadId: String
    let messages: [ARIAConversationMessage]
    let messageCount: Int
}

struct ARIAChatResponse: Decodable {
    let threadId: String
    let message: APIChatMessage
    let toolCallsMade: [String]?
}

struct ARIAPlanResponse: Decodable {
    let focus: String
    let plan: String
    let generatedAt: String
}

struct ARIALifestyleResponse: Decodable {
    let focus: String
    let coaching: String
    let generatedAt: String?
}

struct CoachWorkoutPlanResponse: Decodable {
    let todayPlan: APIWorkoutPlan?
    let explanation: String
}

struct ARIAVoiceResponse: Decodable {
    let answer: String
    let processedTranscript: String
    let suitableForTTS: Bool?

    var transcript: String { processedTranscript }
    var response: String { answer }
}

struct APILifestyleMetrics: Decodable {
    let sleepAverage: Double
    let sleepTarget: Double
    let nutritionQuality: Double
    let dailySteps: Int
    let stressLevel: String
    let qualityOfLifeScore: Int
    let physicalHealth: Int
    let mentalWellbeing: Int
    let energyLevels: Int
    let sleepQuality: Int
    let nutritionScore: Int
}

struct APILifestyleRecommendation: Decodable {
    let id: String
    let title: String
    let description: String
    let impact: String
    let category: String
}

struct APINutritionMeal: Codable {
    let id: String
    let date: String
    let name: String
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let loggedAt: String?
}

struct APINutritionTargets: Decodable {
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let waterMl: Double
}

struct APINutritionDaily: Decodable {
    let date: String?
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let waterMl: Double
    let targets: APINutritionTargets
    let meals: [APINutritionMeal]
}

struct APIWellbeingHabit: Decodable {
    let id: String
    let name: String
    let completed: Bool
}

struct APILifestyleDashboardResponse: Decodable {
    let date: String
    let metrics: APILifestyleMetrics
    let recommendations: [APILifestyleRecommendation]
    let nutrition: APINutritionDaily
    let habits: [APIWellbeingHabit]
    let habitStreak: Int
}

struct APIRestaurantMenuItem: Decodable {
    let id: String
    let name: String
    let calories: Int
    let protein: Int
    let carbs: Int
    let fat: Int
    let serving: String
    let isHealthy: Bool
}

struct APIRestaurant: Decodable {
    let id: String
    let name: String
    let logo: String
    let category: String
    let items: [APIRestaurantMenuItem]
}

struct APIRestaurantsResponse: Decodable {
    let restaurants: [APIRestaurant]
    let count: Int
}

struct APIRichCardPayload: Decodable {
    let type: String
    let data: APIRichCardData?
}

struct APIRichCardData: Decodable {
    let name: String?
    let duration: Int?
    let exercises: [APIRichCardExercise]?
    let title: String?
    let values: [Double]?
    let insight: String?
    let color: String?
    let current: Double?
    let previous: Double?
    let unit: String?
}

struct APIRichCardExercise: Decodable {
    let name: String
    let sets: Int?
    let reps: StringOrNumber?
}

struct APIChatMessage: Decodable {
    let id: String
    let role: String
    let content: String
    let timestamp: String
    let richCard: APIRichCardPayload?
    let toolCallsMade: [String]?
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

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 15
            config.timeoutIntervalForResource = 30
            self.session = URLSession(configuration: config)
        }
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

    func getARIAInsights(days: Int = 7) async throws -> ARIAInsightsResponse {
        try await request(path: "/aria/insights", query: ["days": String(days)])
    }

    func getMe() async throws -> MeResponse {
        try await request(path: "/me")
    }

    func getDeviceConnectionStatus() async throws -> DeviceServiceStatus {
        try await request(path: "/integrations/terra/status")
    }

    func createWearableWidgetSession(
        successRedirectUrl: String,
        failureRedirectUrl: String,
        language: String = "en"
    ) async throws -> WidgetSessionResponse {
        struct Body: Encodable {
            let successRedirectUrl: String
            let failureRedirectUrl: String
            let language: String
        }
        return try await request(
            path: "/integrations/terra/widget",
            method: "POST",
            body: Body(
                successRedirectUrl: successRedirectUrl,
                failureRedirectUrl: failureRedirectUrl,
                language: language
            )
        )
    }

    func syncIntegration(provider: String) async throws -> IntegrationSyncResponse {
        struct EmptyBody: Encodable {}
        return try await request(
            path: "/integrations/\(provider)/sync",
            method: "POST",
            body: EmptyBody()
        )
    }

    func sendARIAChat(content: String) async throws -> ARIAChatResponse {
        try await request(path: "/aria/chat", method: "POST", body: ["content": content])
    }

    func generateARIAPlan(focus: String = "auto") async throws -> ARIAPlanResponse {
        try await request(path: "/aria/plan", method: "POST", body: ["focus": focus])
    }

    func generateARIALifestyle(focus: String = "holistic") async throws -> ARIALifestyleResponse {
        try await request(path: "/aria/lifestyle", method: "POST", body: ["focus": focus])
    }

    func fetchCoachWorkoutPlan() async throws -> CoachWorkoutPlanResponse {
        struct EmptyBody: Encodable {}
        return try await request(path: "/coach/workout-plan", method: "POST", body: EmptyBody())
    }

    func sendARIAVoice(transcript: String) async throws -> ARIAVoiceResponse {
        try await request(path: "/aria/voice", method: "POST", body: ["transcript": transcript])
    }

    func generateARIAInsights() async throws {
        struct EmptyBody: Encodable {}
        struct InsightsGenerateResponse: Decodable { let status: String? }
        let _: InsightsGenerateResponse = try await request(
            path: "/aria/insights/generate",
            method: "POST",
            body: EmptyBody()
        )
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
        intensity: String,
        avgHeartRate: Int? = nil,
        peakHeartRate: Int? = nil
    ) async throws {
        struct WorkoutLog: Encodable {
            let name: String
            let type: String
            let duration: Int
            let volume: Int
            let intensity: String
            let source: String
            let startedAt: String
            let avgHeartRate: Int?
            let peakHeartRate: Int?
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
                startedAt: ISO8601DateFormatter().string(from: Date()),
                avgHeartRate: avgHeartRate,
                peakHeartRate: peakHeartRate
            )
        )
        struct WorkoutLogResponse: Decodable {
            let workout: [String: String]
        }
        let _: WorkoutLogResponse = try await request(path: "/workouts/logs", method: "POST", body: body)
    }

    func getLifestyleDashboard(date: String? = nil) async throws -> APILifestyleDashboardResponse {
        var query: [String: String] = [:]
        if let date { query["date"] = date }
        return try await request(path: "/lifestyle/dashboard", query: query)
    }

    func postNutritionMeal(
        name: String,
        calories: Double,
        protein: Double,
        carbs: Double,
        fat: Double,
        date: String? = nil
    ) async throws -> APINutritionMeal {
        struct MealBody: Encodable {
            let name: String
            let calories: Double
            let protein: Double
            let carbs: Double
            let fat: Double
            let date: String?
        }
        struct Body: Encodable { let meal: MealBody }
        struct Response: Decodable { let meal: APINutritionMeal }
        let response: Response = try await request(
            path: "/nutrition/meals",
            method: "POST",
            body: Body(
                meal: MealBody(
                    name: name,
                    calories: calories,
                    protein: protein,
                    carbs: carbs,
                    fat: fat,
                    date: date
                )
            )
        )
        return response.meal
    }

    func postNutritionWater(waterMl: Double, date: String? = nil) async throws {
        struct WaterBody: Encodable {
            let waterMl: Double
            let date: String?
        }
        struct Body: Encodable { let water: WaterBody }
        struct Response: Decodable { let waterMl: Double }
        let _: Response = try await request(
            path: "/nutrition/water",
            method: "POST",
            body: Body(water: WaterBody(waterMl: waterMl, date: date))
        )
    }

    func getRestaurants(category: String? = nil, search: String? = nil) async throws -> APIRestaurantsResponse {
        var query: [String: String] = [:]
        if let category, !category.isEmpty, category != "All" { query["category"] = category }
        if let search, !search.isEmpty { query["search"] = search }
        return try await request(path: "/restaurants", query: query)
    }

    func completeWellbeingHabit(habitId: String, completed: Bool = true, date: String? = nil) async throws -> [APIWellbeingHabit] {
        struct Body: Encodable {
            let completed: Bool
            let date: String?
        }
        struct Response: Decodable {
            let habits: [APIWellbeingHabit]
        }
        let response: Response = try await request(
            path: "/wellbeing/habits/\(habitId)/complete",
            method: "POST",
            body: Body(completed: completed, date: date)
        )
        return response.habits
    }

    private func request<T: Decodable>(
        path: String,
        method: String = "GET",
        query: [String: String] = [:],
        body: (any Encodable)? = nil,
        retriedAfterUnauthorized: Bool = false
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

        if http.statusCode == 401, APIConfig.usesAuth, !retriedAfterUnauthorized {
            let refreshed = await CognitoAuthManager.shared.refreshSessionIfNeeded(force: true)
            if refreshed {
                return try await self.request(
                    path: path,
                    method: method,
                    query: query,
                    body: body,
                    retriedAfterUnauthorized: true
                )
            }
            await CognitoAuthManager.shared.signOut()
            throw ForgeAPIError.unauthorized
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
