import Foundation
import Combine

// MARK: - Tab Enum

enum AppTab { case home, chat, workout, sleep, profile }

// MARK: - Supporting Types

struct NotificationSettings {
    var workoutReminders: Bool = true
    var sleepReminders: Bool = true
    var lifestyleReminders: Bool = true
    var briefReminders: Bool = true
}

enum DataLoadState { case loading, loaded, error }

struct ProgressSummary {
    var workoutsCompleted: Int
    var newPRCount: Int
    var recoveryDelta: Double?
    var summary: String
}

struct TrainingInsight {
    var title: String
    var body: String
}

// MARK: - App Store

final class AppStore: ObservableObject {
    @Published var userProfile: UserProfile = emptyProfile
    @Published var readiness: ReadinessData = mockReadiness
    @Published var dailyMetrics: DailyMetrics = mockMetrics
    @Published var todayWorkout: WorkoutPlan? = mockWorkout
    @Published var chatMessages: [ChatMessage] = mockChatMessages
    @Published var sleepData: [SleepData] = mockSleepData
    @Published var workoutHistory: [WorkoutHistory] = mockWorkoutHistory
    @Published var personalRecords: [PersonalRecord] = mockPersonalRecords
    @Published var isWorkoutActive: Bool = false
    @Published var currentExerciseIndex: Int = 0
    @Published var currentSet: Int = 1
    @Published var activeTab: AppTab = .home
    @Published var currentStreak: Int = 7
    @Published var readinessTrend: [Int] = [72, 75, 68, 80, 82, 79, 82]
    @Published var briefNotificationsEnabled: Bool = true
    @Published var notificationSettings: NotificationSettings = .init()
    @Published var pendingProfileSubTab: String? = nil
    @Published var dataLoadState: DataLoadState = .loaded
    @Published var progressSummary: ProgressSummary? = mockProgressSummary
    @Published var primaryTrainingInsight: TrainingInsight? = mockTrainingInsight

    // Onboarding (required by existing views)
    @Published var isOnboarded: Bool = true
    @Published var onboardingStep: Int = 0

    func addMessage(_ message: ChatMessage) {
        chatMessages.append(message)
    }

    func trainerResponse(for text: String) -> (String, RichCardData?) {
        let lower = text.lowercased()
        if lower.contains("workout") || lower.contains("train") {
            return ("Your readiness is at \(readiness.overall)%. " +
                    (readiness.overall >= 75 ? "You're primed — let's hit it hard today."
                                             : "Slightly fatigued. I'll scale volume down 15%."), nil)
        }
        if lower.contains("sleep") {
            let hours = dailyMetrics.totalSleep / 60
            let mins = dailyMetrics.totalSleep % 60
            return ("Last night: \(hours)h \(mins)m. Sleep quality at \(readiness.sleepQuality)%. " +
                    (readiness.sleepQuality >= 80 ? "Solid recovery." : "Could be better — cut screens 45min before bed."), nil)
        }
        if lower.contains("progress") || lower.contains("improve") {
            return ("You've logged \(workoutHistory.count) sessions this month. " +
                    "Your bench is trending up. Keep the consistency.", nil)
        }
        return ("I'm tracking everything. Your next move: \(todayWorkout?.name ?? "rest and recover"). " +
                "Readiness \(readiness.overall)%. Let's be intentional today.", nil)
    }

    func startWorkout() {
        isWorkoutActive = true
        currentExerciseIndex = 0
        currentSet = 1
    }

    func endWorkout() {
        isWorkoutActive = false
    }

    func nextSet() {
        currentSet += 1
    }

    func nextExercise() {
        currentExerciseIndex += 1
        currentSet = 1
    }

    func updateProfile(_ profile: UserProfile) {
        userProfile = profile
    }

    func setBriefNotificationsEnabled(_ enabled: Bool) {
        briefNotificationsEnabled = enabled
    }

    func updateNotificationSettings(_ settings: NotificationSettings) {
        notificationSettings = settings
    }

    func updateBriefNotificationSchedule() {}

    func signOut() {
        userProfile = emptyProfile
        readiness = mockReadiness
        dailyMetrics = mockMetrics
        todayWorkout = mockWorkout
        chatMessages = mockChatMessages
        sleepData = mockSleepData
        workoutHistory = mockWorkoutHistory
        personalRecords = mockPersonalRecords
        isWorkoutActive = false
        currentExerciseIndex = 0
        currentSet = 1
        activeTab = .home
        currentStreak = 7
        readinessTrend = [72, 75, 68, 80, 82, 79, 82]
        briefNotificationsEnabled = true
        notificationSettings = .init()
        pendingProfileSubTab = nil
        dataLoadState = .loaded
        progressSummary = mockProgressSummary
        primaryTrainingInsight = mockTrainingInsight
        isOnboarded = false
        onboardingStep = 0
    }

    func mergeSleepDataLocally(_ data: [SleepData]) {
        sleepData = data
    }

    func refreshDailyData() async {
        dataLoadState = .loading
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        dataLoadState = .loaded
    }

    func loadDashboardFromAPI() async {
        dataLoadState = .loading
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        dataLoadState = .loaded
    }

    func sendUserMessage(_ text: String) {
        let userMsg = ChatMessage(
            id: "user-\(Date().timeIntervalSince1970)",
            role: .user, content: text, timestamp: Date()
        )
        addMessage(userMsg)

        let (reply, card) = trainerResponse(for: text)
        let trainerMsg = ChatMessage(
            id: "trainer-\(Date().timeIntervalSince1970)",
            role: .trainer, content: reply, timestamp: Date(), richCard: card
        )
        addMessage(trainerMsg)
    }
}