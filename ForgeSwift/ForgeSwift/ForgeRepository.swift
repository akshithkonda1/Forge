import Foundation

enum DataLoadState: Equatable {
    case idle
    case loading
    case loaded
    case error(String)
    case offlineFallback
}

@MainActor
final class ForgeRepository: ObservableObject {
    static let shared = ForgeRepository()

    private let api = ForgeAPIClient.shared
    @Published private(set) var loadState: DataLoadState = .idle

    private init() {}

    func fetchDashboard() async throws -> DashboardSnapshot {
        loadState = .loading
        do {
            let response = try await api.getDashboardToday()
            loadState = .loaded
            return mapDashboard(response)
        } catch {
            loadState = .offlineFallback
            throw error
        }
    }

    func fetchSleep(days: Int = 14) async throws -> [SleepData] {
        let response = try await api.getSleep(days: days)
        return response.sleep.map(mapSleep)
    }

    func fetchWorkoutHistory(days: Int = 30) async throws -> (history: [WorkoutHistory], records: [PersonalRecord]) {
        let response = try await api.getWorkoutHistory(days: days)
        return (response.workouts.map(mapWorkoutHistory), response.personalRecords.map(mapPersonalRecord))
    }

    func sendChatMessage(_ content: String) async throws -> ChatMessage {
        let response = try await api.sendARIAChat(content: content)
        return mapChatMessage(response.message)
    }

    func fetchConversation() async throws -> [ChatMessage] {
        let response = try await api.getARIAConversation()
        let formatter = ISO8601DateFormatter()
        return response.messages.compactMap { message in
            let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if trimmed.hasPrefix("[ARIA CONVERSATION SUMMARY") { return nil }

            let role: MessageRole = message.role == "user" ? .user : .trainer
            let timestamp = message.timestamp.flatMap { formatter.date(from: $0) } ?? Date()
            return ChatMessage(
                id: message.id ?? UUID().uuidString,
                role: role,
                content: trimmed,
                timestamp: timestamp,
                richCard: nil
            )
        }
    }

    func fetchProgressSummary(days: Int = 30) async throws -> ProgressSummarySnapshot {
        let response = try await api.getProgressSummary(days: days)
        return ProgressSummarySnapshot(
            periodDays: response.periodDays,
            workoutsCompleted: response.workoutsCompleted,
            newPRCount: response.newPersonalRecords.count,
            recoveryDelta: response.recoveryConsistencyDelta,
            summary: response.summary
        )
    }

    func saveProfile(_ profile: UserProfile) async throws {
        let payload: [String: AnyEncodable] = [
            "name": AnyEncodable(profile.name),
            "fitnessGoals": AnyEncodable(profile.fitnessGoals.map(\.rawValue)),
            "experienceLevel": AnyEncodable(profile.experienceLevel.rawValue),
            "preferredWorkouts": AnyEncodable(profile.preferredWorkouts.map(\.rawValue)),
            "coachingStyle": AnyEncodable(profile.coachingStyle.rawValue),
            "connectedDevices": AnyEncodable(profile.connectedDevices),
            "weeklySchedule": AnyEncodable(profile.weeklySchedule),
        ]
        _ = try await api.updateProfile(payload)
    }

    func logWorkout(_ workout: WorkoutPlan, volume: Int) async throws {
        try await api.postWorkoutLog(
            name: workout.name,
            type: workout.type.rawValue,
            duration: workout.duration,
            volume: volume,
            intensity: workout.intensity.rawValue
        )
    }

    func syncHealthMetrics(
        steps: Int?,
        activeCalories: Int?,
        hrv: Int?,
        restingHR: Int?
    ) async throws {
        var metrics: [HealthMetricInput] = []
        let now = ISO8601DateFormatter().string(from: Date())

        if let steps {
            metrics.append(.init(source: "apple-health", metricType: "steps", startedAt: now, endedAt: nil, value: Double(steps), unit: "count"))
        }
        if let activeCalories {
            metrics.append(.init(source: "apple-health", metricType: "active-calories", startedAt: now, endedAt: nil, value: Double(activeCalories), unit: "kcal"))
        }
        if let hrv {
            metrics.append(.init(source: "apple-health", metricType: "hrv", startedAt: now, endedAt: nil, value: Double(hrv), unit: "ms"))
        }
        if let restingHR {
            metrics.append(.init(source: "apple-health", metricType: "resting-heart-rate", startedAt: now, endedAt: nil, value: Double(restingHR), unit: "bpm"))
        }

        guard !metrics.isEmpty else { return }
        try await api.syncHealthBatch(metrics)
    }
}

struct DashboardSnapshot {
    var profile: UserProfile
    var readiness: ReadinessData
    var dailyMetrics: DailyMetrics
    var todayWorkout: WorkoutPlan?
    var sleepData: [SleepData]
    var workoutHistory: [WorkoutHistory]
    var personalRecords: [PersonalRecord]
}

struct ProgressSummarySnapshot {
    let periodDays: Int
    let workoutsCompleted: Int
    let newPRCount: Int
    let recoveryDelta: Double
    let summary: String
}

// MARK: - Mapping

private func mapDashboard(_ response: DashboardTodayResponse) -> DashboardSnapshot {
    DashboardSnapshot(
        profile: mapProfile(response.profile),
        readiness: ReadinessData(
            overall: response.readiness.overall,
            sleepQuality: response.readiness.sleepQuality,
            recoveryScore: response.readiness.recoveryScore,
            stressLevel: response.readiness.stressLevel,
            energyBank: response.readiness.energyBank
        ),
        dailyMetrics: DailyMetrics(
            steps: response.dailyMetrics.steps,
            activeCalories: response.dailyMetrics.activeCalories,
            hrv: response.dailyMetrics.hrv,
            restingHR: response.dailyMetrics.restingHR,
            deepSleep: response.dailyMetrics.deepSleep,
            totalSleep: response.dailyMetrics.totalSleep
        ),
        todayWorkout: response.todayWorkout.map(mapWorkoutPlan),
        sleepData: response.recentSleep.map(mapSleep),
        workoutHistory: response.recentWorkouts.map(mapWorkoutHistory),
        personalRecords: response.personalRecords.map(mapPersonalRecord)
    )
}

private func mapProfile(_ profile: APIUserProfile) -> UserProfile {
    UserProfile(
        name: profile.name,
        gender: .preferNotToSay,
        fitnessGoals: profile.fitnessGoals.compactMap { UserFitnessGoal(rawValue: $0) },
        experienceLevel: ExperienceLevel(rawValue: profile.experienceLevel) ?? .intermediate,
        preferredWorkouts: profile.preferredWorkouts.compactMap { WorkoutType(rawValue: $0) },
        coachingStyle: CoachingStyle(rawValue: profile.coachingStyle) ?? .balanced,
        connectedDevices: profile.connectedDevices,
        weeklySchedule: profile.weeklySchedule
    )
}

private func mapWorkoutPlan(_ plan: APIWorkoutPlan) -> WorkoutPlan {
    WorkoutPlan(
        id: plan.id,
        name: plan.name,
        type: WorkoutType(rawValue: plan.type) ?? .strength,
        duration: plan.duration,
        intensity: WorkoutIntensity(rawValue: plan.intensity) ?? .moderate,
        exercises: plan.exercises.map {
            Exercise(
                id: $0.id,
                name: $0.name,
                sets: $0.sets,
                reps: $0.reps.display,
                weight: $0.weight,
                restSeconds: $0.restSeconds,
                notes: $0.notes,
                videoURL: nil,
                has3DModel: false
            )
        }
    )
}

private func mapSleep(_ sleep: APISleepData) -> SleepData {
    SleepData(
        date: sleep.date,
        totalHours: sleep.totalHours,
        deepMinutes: sleep.deepMinutes,
        remMinutes: sleep.remMinutes,
        lightMinutes: sleep.lightMinutes,
        awakeMinutes: sleep.awakeMinutes,
        score: sleep.score
    )
}

private func mapWorkoutHistory(_ workout: APIWorkoutHistory) -> WorkoutHistory {
    WorkoutHistory(
        id: workout.id,
        date: workout.date,
        name: workout.name,
        type: WorkoutType(rawValue: workout.type) ?? .strength,
        duration: workout.duration,
        volume: workout.volume,
        intensity: WorkoutIntensity(rawValue: workout.intensity) ?? .moderate
    )
}

private func mapPersonalRecord(_ record: APIPersonalRecord) -> PersonalRecord {
    PersonalRecord(exercise: record.exercise, value: record.value, unit: record.unit, date: record.date)
}

private func mapChatMessage(_ message: APIChatMessage) -> ChatMessage {
    let formatter = ISO8601DateFormatter()
    return ChatMessage(
        id: message.id,
        role: message.role == "user" ? .user : .trainer,
        content: message.content,
        timestamp: formatter.date(from: message.timestamp) ?? Date(),
        richCard: nil
    )
}
