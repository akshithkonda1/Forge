import Foundation
import Combine

final class HealthKitSleepService: ObservableObject {
    @Published var userProfile: UserSleepProfile = UserSleepProfile()
    @Published var currentSunriseConfig: AdaptiveSunriseConfig = .init(
        durationMinutes: 20,
        colorTemp: 0.5,
        intensity: 0.7,
        rationale: "Balanced wake for Bear chronotype"
    )
    @Published var isAuthorized: Bool = false

    func requestAuthorization() async -> Bool {
        try? await Task.sleep(nanoseconds: 800_000_000)
        await MainActor.run { isAuthorized = true }
        return true
    }

    func fetchRecentSleepData(days: Int) async -> [SleepData] {
        try? await Task.sleep(nanoseconds: 400_000_000)
        return Array(mockSleepData.prefix(days))
    }

    func computeSleepDebt(from data: [SleepData]) -> Double {
        let target = userProfile.chronotype.targetSleepHours
        return data.prefix(7).reduce(0.0) { acc, night in
            acc + max(0, target - night.totalHours)
        }
    }

    func computeAdaptiveSunrise(debt: Double, metrics: DailyMetrics, profile: UserSleepProfile) -> AdaptiveSunriseConfig {
        var duration = profile.chronotype.baseSunriseDuration
        var intensity = profile.chronotype.baseSunriseIntensity
        var rationale = "Balanced wake for \(profile.chronotype.displayName) chronotype"
        if debt > 3 {
            duration += 8
            intensity = max(0.35, intensity - 0.15)
            rationale = "Gentler ramp — sleep debt detected"
        }
        if metrics.hrv < 45 {
            duration += 5
            rationale = "Extra-soft sunrise for low HRV recovery"
        }
        return AdaptiveSunriseConfig(
            durationMinutes: duration,
            colorTemp: profile.chronotype.baseSunriseColorTemp,
            intensity: intensity,
            rationale: rationale
        )
    }

    func computeSmartAlarmWindow(targetWake: Date, chronotype: Chronotype) -> (Date, Date) {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .minute, value: -30, to: targetWake) ?? targetWake
        let end = calendar.date(byAdding: .minute, value: 15, to: targetWake) ?? targetWake
        _ = chronotype
        return (start, end)
    }

    func computeAdaptiveGoals(from data: [SleepData]) -> [AdaptiveSleepGoal] {
        let avgHours = data.prefix(7).map(\.totalHours).reduce(0, +) / Double(max(1, min(7, data.count)))
        return [
            AdaptiveSleepGoal(id: "duration", title: "Sleep Duration", current: avgHours, target: userProfile.chronotype.targetSleepHours, unit: "hrs", icon: "moon.fill"),
            AdaptiveSleepGoal(id: "deep", title: "Deep Sleep", current: Double(data.first?.deepMinutes ?? 0), target: Double(userProfile.chronotype.deepSleepGoalMinutes), unit: "min", icon: "bed.double.fill"),
        ]
    }

    func chronotypeRecommendations(debt: Double) -> [SleepRecommendation] {
        var items: [SleepRecommendation] = [
            SleepRecommendation(id: "wind-down", icon: "iphone.slash", title: "Screen curfew", description: "Cut screens 45 minutes before bed.", priority: "high")
        ]
        if debt > 2 {
            items.append(SleepRecommendation(id: "catch-up", icon: "clock.badge.checkmark", title: "Catch-up window", description: "Aim for an earlier bedtime tonight.", priority: "medium"))
        }
        return items
    }

    func computeAchievements(from data: [SleepData]) -> [SleepAchievementState] {
        let streak = data.prefix(7).filter { $0.score >= 80 }.count
        return [
            SleepAchievementState(id: "streak", title: "Recovery Streak", description: "7 nights above 80 sleep score", unlocked: streak >= 5, progress: Double(streak) / 7.0, colorName: "steel"),
            SleepAchievementState(id: "deep", title: "Deep Sleep Pro", description: "90+ min deep sleep", unlocked: (data.first?.deepMinutes ?? 0) >= 90, progress: min(1, Double(data.first?.deepMinutes ?? 0) / 90.0), colorName: "ember"),
        ]
    }

    func buildARIAContext(sleepData: [SleepData], store: AppStore) -> String {
        let latest = sleepData.first
        return "Sleep score \(latest?.score ?? 0), readiness \(store.readiness.overall), HRV \(store.dailyMetrics.hrv)ms."
    }

    func chronotypeInsightPrefix() -> String {
        "As a \(userProfile.chronotype.displayName), "
    }

    func updateProfile(_ profile: UserSleepProfile) {
        userProfile = profile
        currentSunriseConfig = computeAdaptiveSunrise(
            debt: computeSleepDebt(from: mockSleepData),
            metrics: mockMetrics,
            profile: profile
        )
    }
}