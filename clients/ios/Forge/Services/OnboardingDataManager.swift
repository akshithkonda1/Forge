import Foundation
import Combine

struct HealthDataSnapshot {
    var restingHeartRate: Int?
    var steps: Int?
    var activeCalories: Int?
    var sleepHours: Double?
}

struct WorkoutTimeSlot: Identifiable {
    var id: String { time }
    var time: String
    var day: String
    var confidence: Double
}

final class OnboardingDataManager: ObservableObject {
    static let shared = OnboardingDataManager()

    @Published var healthKitAuthorized: Bool = false
    @Published var calendarAuthorized: Bool = false
    @Published var notificationsAuthorized: Bool = false
    @Published var contactsAuthorized: Bool = false
    @Published var healthSnapshot: HealthDataSnapshot? = nil
    @Published var suggestedWorkoutTimes: [WorkoutTimeSlot] = []

    private init() {}

    func requestAllPermissions() async {
        _ = await requestHealthKitPermission()
        _ = await requestCalendarPermission()
        _ = await requestNotificationPermission()
        _ = await requestContactsPermission()
        await fetchHealthData()
        await analyzeCalendarForWorkoutSlots()
    }

    func requestHealthKitPermission() async -> Bool {
        try? await Task.sleep(nanoseconds: 800_000_000)
        await MainActor.run { healthKitAuthorized = true }
        return true
    }

    func requestCalendarPermission() async -> Bool {
        try? await Task.sleep(nanoseconds: 800_000_000)
        await MainActor.run { calendarAuthorized = true }
        return true
    }

    func requestNotificationPermission() async -> Bool {
        try? await Task.sleep(nanoseconds: 800_000_000)
        await MainActor.run { notificationsAuthorized = true }
        return true
    }

    func requestContactsPermission() async -> Bool {
        try? await Task.sleep(nanoseconds: 800_000_000)
        await MainActor.run { contactsAuthorized = true }
        return true
    }

    func fetchHealthData() async {
        try? await Task.sleep(nanoseconds: 500_000_000)
        await MainActor.run {
            healthSnapshot = HealthDataSnapshot(
                restingHeartRate: 58,
                steps: 3241,
                activeCalories: 186,
                sleepHours: 7.2
            )
        }
    }

    func analyzeCalendarForWorkoutSlots() async {
        try? await Task.sleep(nanoseconds: 500_000_000)
        await MainActor.run {
            suggestedWorkoutTimes = [
                WorkoutTimeSlot(time: "7:00 AM", day: "Monday", confidence: 0.92),
                WorkoutTimeSlot(time: "6:30 PM", day: "Wednesday", confidence: 0.85),
                WorkoutTimeSlot(time: "8:00 AM", day: "Friday", confidence: 0.78),
            ]
        }
    }

    func generatePersonalizedRecommendations() -> [String] {
        [
            "Your HRV suggests morning strength sessions on Mon/Wed.",
            "Protect a 45-minute wind-down — your deep sleep responds well.",
            "Friday is your highest-risk skip day; schedule a lighter fallback session.",
        ]
    }
}