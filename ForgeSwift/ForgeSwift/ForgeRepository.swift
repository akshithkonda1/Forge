import Foundation
import SwiftUI

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

    func sendChatMessage(_ content: String) async throws -> (message: ChatMessage, toolCalls: [String]) {
        let response = try await api.sendARIAChat(content: content)
        let tools = response.toolCallsMade ?? response.message.toolCallsMade ?? []
        return (mapChatMessage(response.message), tools)
    }

    func generateDailyPlan(focus: String = "auto") async throws -> String {
        let response = try await api.generateARIAPlan(focus: focus)
        return response.plan
    }

    func fetchLifestyleCoaching(focus: String = "nutrition") async throws -> String {
        let response = try await api.generateARIALifestyle(focus: focus)
        return response.coaching
    }

    func refreshCoachWorkoutPlan() async throws -> WorkoutPlan? {
        _ = try await api.generateARIAPlan(focus: "workout")
        let dashboard = try await api.getDashboardToday()
        return dashboard.todayWorkout.map(mapWorkoutPlan)
    }

    func fetchConclusions() async throws -> DataConclusions {
        let response = try await api.getARIAConclusions()
        return DataConclusions(
            generatedAt: ISO8601DateFormatter().date(from: response.retrievedAt) ?? Date(),
            coveragePct: response.coveragePct ?? 0,
            coachingBrief: response.coachingBrief ?? "",
            compoundFlags: response.compoundFlags ?? [],
            offlineTemplates: OfflineTemplates(
                chat: response.offlineTemplates?.chat ?? response.coachingBrief ?? "",
                dashboard: response.offlineTemplates?.dashboard ?? "",
                mood: response.offlineTemplates?.mood ?? "steady",
                widget: response.offlineTemplates?.widget ?? ""
            ),
            readinessOverall: response.conclusions?.readiness?.overall ?? 0
        )
    }

    func clearARIAConversation() async throws {
        try await api.deleteARIAConversation()
    }

    func sendVoiceTranscript(_ transcript: String) async throws -> String {
        let response = try await api.sendARIAVoice(transcript: transcript)
        return response.answer
    }

    func regenerateInsights() async throws {
        try await api.generateARIAInsights()
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
                richCard: mapRichCard(message.richCard),
                toolCallsMade: nil
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

    func fetchInsights(days: Int = 7) async throws -> [CoachingInsight] {
        let response = try await api.getARIAInsights(days: days)
        return response.insights.compactMap { row in
            var dict: [String: Any] = [:]
            row.forEach { key, value in
                dict[key] = value.value
            }
            return CoachingInsight(dictionary: dict)
        }
    }

    func fetchConnections() async throws -> [IntegrationConnection] {
        let response = try await api.getMe()
        return response.connections.map(IntegrationConnection.init(apiConnection:))
    }

    func fetchDeviceServiceStatus() async throws -> DeviceServiceStatus {
        try await api.getDeviceConnectionStatus()
    }

    func fetchExtendedSleep(days: Int = 14) async throws -> [SleepData] {
        try await fetchSleep(days: days)
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

    func syncChatGamification(_ state: ChatGamificationState) async throws {
        let payload: [String: AnyEncodable] = [
            "chatGamification": AnyEncodable(state),
        ]
        _ = try await api.updateProfile(payload)
    }

    func logWorkout(
        _ workout: WorkoutPlan,
        volume: Int,
        avgHeartRate: Int? = nil,
        peakHeartRate: Int? = nil
    ) async throws {
        try await api.postWorkoutLog(
            name: workout.name,
            type: workout.type.rawValue,
            duration: workout.duration,
            volume: volume,
            intensity: workout.intensity.rawValue,
            avgHeartRate: avgHeartRate,
            peakHeartRate: peakHeartRate
        )
    }

    func syncWorkoutHeartRate(samples: [(bpm: Int, timestamp: Date)]) async throws {
        guard !samples.isEmpty else { return }
        let formatter = ISO8601DateFormatter()
        let metrics = samples.map { sample in
            HealthMetricInput(
                source: "apple-health",
                metricType: "heart-rate",
                startedAt: formatter.string(from: sample.timestamp),
                endedAt: nil,
                value: Double(sample.bpm),
                unit: "bpm"
            )
        }
        try await api.syncHealthBatch(metrics)
    }

    func fetchLifestyleDashboard() async throws -> LifestyleDashboardSnapshot {
        let response = try await api.getLifestyleDashboard()
        return mapLifestyleDashboard(response)
    }

    func fetchRestaurants(category: String? = nil, search: String? = nil) async throws -> [LifestyleRestaurant] {
        let response = try await api.getRestaurants(category: category, search: search)
        return response.restaurants.map(mapRestaurant)
    }

    func logNutritionMeal(
        name: String,
        calories: Double,
        protein: Double,
        carbs: Double,
        fat: Double
    ) async throws {
        _ = try await api.postNutritionMeal(
            name: name,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat
        )
    }

    func logNutritionWater(waterMl: Double) async throws {
        try await api.postNutritionWater(waterMl: waterMl)
    }

    func completeWellbeingHabit(id: String, completed: Bool) async throws -> [LifestyleHabit] {
        let habits = try await api.completeWellbeingHabit(habitId: id, completed: completed)
        return habits.map(mapHabit)
    }

    func syncHealthMetrics(
        steps: Int?,
        activeCalories: Int?,
        hrv: Int?,
        restingHR: Int?,
        oxygenSaturation: Int? = nil
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
        if let oxygenSaturation {
            metrics.append(.init(source: "apple-health", metricType: "oxygen-saturation", startedAt: now, endedAt: nil, value: Double(oxygenSaturation), unit: "percent"))
        }

        guard !metrics.isEmpty else { return }
        try await api.syncHealthBatch(metrics)
    }

    func syncSleepSession(_ session: SleepSessionUpload) async throws {
        try await api.postSleepSession(session)
    }

    func syncWorkoutLog(_ workout: WorkoutLogUpload) async throws {
        try await api.postWorkoutLog(workout)
    }

    func syncCycleEvents(_ events: [CycleEvent]) async throws {
        let formatter = ISO8601DateFormatter()
        let uploads = events.prefix(30).map { event in
            CycleEventUpload(
                startedAt: formatter.string(from: event.startedAt),
                flow: event.flow,
                source: "apple-health"
            )
        }
        guard !uploads.isEmpty else { return }
        try await api.postCycleEvents(uploads)
    }
}

struct LifestyleDashboardSnapshot {
    let metrics: LifestyleMetricsSnapshot
    let recommendations: [LifestyleRecommendationSnapshot]
    let nutrition: LifestyleNutritionSnapshot
    let habits: [LifestyleHabit]
    let habitStreak: Int
}

struct LifestyleMetricsSnapshot {
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

struct LifestyleRecommendationSnapshot {
    let id: String
    let title: String
    let description: String
    let impact: String
    let category: String
}

struct LifestyleNutritionSnapshot {
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let waterMl: Double
    let targets: APINutritionTargets
    let meals: [APINutritionMeal]
}

struct LifestyleHabit: Identifiable {
    let id: String
    let name: String
    var completed: Bool
}

struct LifestyleRestaurant: Identifiable {
    let id: String
    let name: String
    let logo: String
    let category: String
    let items: [LifestyleMenuItem]
}

struct LifestyleMenuItem: Identifiable {
    let id: String
    let name: String
    let calories: Int
    let protein: Int
    let carbs: Int
    let fat: Int
    let serving: String
    let isHealthy: Bool
}

struct DashboardSnapshot {
    var profile: UserProfile
    var readiness: ReadinessData
    var dailyMetrics: DailyMetrics
    var todayWorkout: WorkoutPlan?
    var sleepData: [SleepData]
    var workoutHistory: [WorkoutHistory]
    var personalRecords: [PersonalRecord]
    var dailyScores: DailyScores?
    var biologicalAge: BiologicalAge?
}

struct ProgressSummarySnapshot {
    let periodDays: Int
    let workoutsCompleted: Int
    let newPRCount: Int
    let recoveryDelta: Double
    let summary: String
}

// MARK: - Mapping

private func mapLifestyleDashboard(_ response: APILifestyleDashboardResponse) -> LifestyleDashboardSnapshot {
    LifestyleDashboardSnapshot(
        metrics: LifestyleMetricsSnapshot(
            sleepAverage: response.metrics.sleepAverage,
            sleepTarget: response.metrics.sleepTarget,
            nutritionQuality: response.metrics.nutritionQuality,
            dailySteps: response.metrics.dailySteps,
            stressLevel: response.metrics.stressLevel,
            qualityOfLifeScore: response.metrics.qualityOfLifeScore,
            physicalHealth: response.metrics.physicalHealth,
            mentalWellbeing: response.metrics.mentalWellbeing,
            energyLevels: response.metrics.energyLevels,
            sleepQuality: response.metrics.sleepQuality,
            nutritionScore: response.metrics.nutritionScore
        ),
        recommendations: response.recommendations.map {
            LifestyleRecommendationSnapshot(
                id: $0.id,
                title: $0.title,
                description: $0.description,
                impact: $0.impact,
                category: $0.category
            )
        },
        nutrition: LifestyleNutritionSnapshot(
            calories: response.nutrition.calories,
            protein: response.nutrition.protein,
            carbs: response.nutrition.carbs,
            fat: response.nutrition.fat,
            waterMl: response.nutrition.waterMl,
            targets: response.nutrition.targets,
            meals: response.nutrition.meals
        ),
        habits: response.habits.map(mapHabit),
        habitStreak: response.habitStreak
    )
}

private func mapHabit(_ habit: APIWellbeingHabit) -> LifestyleHabit {
    LifestyleHabit(id: habit.id, name: habit.name, completed: habit.completed)
}

private func mapRestaurant(_ restaurant: APIRestaurant) -> LifestyleRestaurant {
    LifestyleRestaurant(
        id: restaurant.id,
        name: restaurant.name,
        logo: restaurant.logo,
        category: restaurant.category,
        items: restaurant.items.map {
            LifestyleMenuItem(
                id: $0.id,
                name: $0.name,
                calories: $0.calories,
                protein: $0.protein,
                carbs: $0.carbs,
                fat: $0.fat,
                serving: $0.serving,
                isHealthy: $0.isHealthy
            )
        }
    )
}

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
        personalRecords: response.personalRecords.map(mapPersonalRecord),
        dailyScores: response.dailyScores.flatMap(mapDailyScores),
        biologicalAge: response.biologicalAge.flatMap(mapBiologicalAge)
    )
}

private func mapDailyScores(_ payload: APIDailyScores) -> DailyScores? {
    guard let strain = payload.strain,
          let recovery = payload.recovery,
          let sleep = payload.sleep else { return nil }

    let cycle = payload.cycleContext
    let phase = CyclePhase(rawValue: cycle?.phase ?? "unknown") ?? .unknown

    return DailyScores(
        date: payload.date ?? ForgeDates.yyyyMMdd(from: Date()),
        strain: StrainScoreBlock(
            score: strain.score,
            trend: strain.trend ?? "flat",
            baselineLoad: strain.baselineLoad ?? 0,
            todayLoad: strain.todayLoad ?? 0
        ),
        recovery: RecoveryScoreBlock(
            score: recovery.score,
            hrv: recovery.hrv,
            trend: recovery.trend ?? "unknown"
        ),
        sleep: SleepScoreBlock(
            score: sleep.score,
            sleepNeedMinutes: sleep.sleepNeedMinutes ?? 0,
            totalSleepMinutes: sleep.totalSleepMinutes ?? 0,
            deepSleepMinutes: sleep.deepSleepMinutes ?? 0
        ),
        trainingDecision: TrainingDecision(rawValue: payload.trainingDecision ?? "active_rest") ?? .activeRest,
        cycleContext: CycleContext(
            phase: phase,
            dayInCycle: cycle?.dayInCycle,
            recommendRecovery: cycle?.recommendRecovery ?? false,
            coachingNote: cycle?.coachingNote,
            hasData: cycle?.hasData ?? false,
            lastEventAt: cycle?.lastEventAt
        ),
        generatedAt: ISO8601DateFormatter().date(from: payload.generatedAt ?? "") ?? Date()
    )
}

private func mapBiologicalAge(_ payload: APIBiologicalAge) -> BiologicalAge? {
    guard let chronological = payload.chronologicalAge,
          let biological = payload.biologicalAge,
          let delta = payload.deltaYears else { return nil }
    return BiologicalAge(
        chronologicalAge: chronological,
        biologicalAge: biological,
        deltaYears: delta,
        drivers: payload.drivers ?? [],
        generatedAt: ISO8601DateFormatter().date(from: payload.generatedAt ?? "") ?? Date()
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
        richCard: mapRichCard(message.richCard),
        toolCallsMade: message.toolCallsMade
    )
}

private func mapRichCard(_ payload: APIRichCardPayload?) -> RichCardData? {
    guard let payload else { return nil }
    switch payload.type {
    case "workout-plan":
        guard let data = payload.data else { return nil }
        let exercises = (data.exercises ?? []).map { exercise in
            (
                name: exercise.name,
                sets: exercise.sets ?? 3,
                reps: exercise.reps?.display ?? "8-10"
            )
        }
        return RichCardData(
            type: .workoutPlan,
            workoutName: data.name,
            workoutDuration: data.duration,
            workoutExercises: exercises.isEmpty ? nil : exercises
        )
    case "data-chart":
        guard let data = payload.data else { return nil }
        let colorHex = data.color?.replacingOccurrences(of: "#", with: "") ?? "3B82F6"
        return RichCardData(
            type: .dataChart,
            chartTitle: data.title,
            chartValues: data.values,
            chartInsight: data.insight,
            chartColor: Color(hex: colorHex)
        )
    case "progress-comparison":
        guard let data = payload.data else { return nil }
        let values = [data.previous ?? 0, data.current ?? 0]
        return RichCardData(
            type: .dataChart,
            chartTitle: data.title ?? "Progress",
            chartValues: values,
            chartInsight: data.insight ?? "",
            chartColor: Color.ember
        )
    default:
        return nil
    }
}
