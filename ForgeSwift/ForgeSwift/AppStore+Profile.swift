import SwiftUI
import ForgeCore

extension AppStore {
    var lifestyleTargets: LifestyleTargets {
        LifestyleTargets.resolve(profile: userProfile, overrides: nutritionPreferences)
    }

    var dataLoadState: DataLoadState {
        .loaded
    }

    var progressSummary: ProgressSummary? {
        guard !workoutHistory.isEmpty || !personalRecords.isEmpty else { return nil }

        let calendar = Calendar.current
        let now = Date()
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? now
        let monthlyWorkouts = workoutHistory.filter { workout in
            guard let date = ForgeDates.parse(workout.date) else { return false }
            return date >= monthStart && date <= now
        }
        let monthlyRecords = personalRecords.filter { record in
            guard let date = ForgeDates.parse(record.date) else { return false }
            return date >= monthStart && date <= now
        }
        let recoveryDelta = Double(readiness.recoveryScore - readiness.sleepQuality)
        let summary = "You completed \(monthlyWorkouts.count) workouts this month with \(monthlyRecords.count) new PRs. Recovery is \(readiness.recoveryScore >= readiness.sleepQuality ? "trending up" : "asking for more attention")."

        return ProgressSummary(
            workoutsCompleted: monthlyWorkouts.count,
            newPRCount: monthlyRecords.count,
            recoveryDelta: recoveryDelta,
            summary: summary
        )
    }

    var primaryTrainingInsight: TrainingInsight? {
        guard !workoutHistory.isEmpty else { return nil }

        switch readinessTrend {
        case .improving:
            return TrainingInsight(
                title: "Recovery Trend Improving",
                observation: "Your readiness is running above your recent sleep-score baseline.",
                recommendation: "This is a good window for progressive overload if soreness is manageable."
            )
        case .declining:
            return TrainingInsight(
                title: "Recovery Needs Attention",
                observation: "Your readiness is trailing your recent sleep-score baseline.",
                recommendation: "Keep intensity controlled and prioritize sleep before the next hard session."
            )
        case .stable:
            return TrainingInsight(
                title: "Consistency Pattern",
                observation: "Your training and recovery signals are holding steady.",
                recommendation: "Maintain the current rhythm and look for small weekly volume increases."
            )
        }
    }

    /// Pushes the same training-pattern read `BehavioralInsightView` already
    /// shows on the Progress tab into ARIA's shared context, so the main chat
    /// can reference it instead of reasoning about the identical numbers from
    /// scratch. Guards against re-pushing the same read every time the tab is
    /// revisited — only a genuinely new insight (trend changed, more history)
    /// is worth another line in `lastInsights`.
    @MainActor
    func shareProgressInsightIfNeeded() {
        guard let insight = primaryTrainingInsight else { return }
        let text = "Progress: \(insight.title) — \(insight.observation) \(insight.recommendation)"
        guard AriaContextStore.shared.context.lastInsights.first != text else { return }
        AriaContextStore.shared.addInsight(text)
    }

    func updateNotificationSettings(_ settings: AppNotificationSettings) {
        notificationSettings = settings   // didSet persists + reschedules
    }

    func setBriefNotificationsEnabled(_ isEnabled: Bool) {
        briefNotificationsEnabled = isEnabled   // didSet persists + reschedules
    }

    func updateBriefNotificationSchedule(
        morningHour: Int,
        morningMinute: Int,
        eveningHour: Int,
        eveningMinute: Int
    ) {
        let settings = BriefNotificationSettings(
            morningHour: morningHour,
            morningMinute: morningMinute,
            eveningHour: eveningHour,
            eveningMinute: eveningMinute
        )
        ForgePersistence.saveBriefNotificationSettings(settings)
        objectWillChange.send()
        Task { await resyncNotifications() }
    }

    func updateNutritionPreferences(_ preferences: NutritionPreferences) {
        nutritionPreferences = preferences   // didSet persists
        publishHomeWidgets()
    }

    func resyncNotifications() async {
        await ForgeNotificationScheduler.sync(
            settings: notificationSettings,
            briefEnabled: briefNotificationsEnabled,
            brief: ForgePersistence.loadBriefNotificationSettings()
        )
    }

    func loadDashboardFromAPI() async {
        await Task.yield()
        objectWillChange.send()
    }

    func signOut() {
        ForgeAuthClient.shared.signOut()
        isAuthenticated = false
        isOnboarded = false
        authProvider = ""
        authEmail = ""
        UserDefaults.standard.set(false, forKey: "forge.auth.session.v1")
        UserDefaults.standard.removeObject(forKey: "forge.auth.provider.v1")
        UserDefaults.standard.removeObject(forKey: "forge.auth.email.v1")
        activeTab = .home
        onboardingStep = 0
    }

    /// Force HealthKit reconnect from Settings / Home offline pill.
    func reconnectHealthKit() async {
        do {
            try await HealthKitManager.shared.requestAuthorization()
            healthKitLive = await HealthKitManager.shared.checkAuthorizationStatus()
            if healthKitLive {
                await refreshDailyData()
            }
        } catch {
            healthKitLive = false
        }
        objectWillChange.send()
    }
}
