import SwiftUI
import Combine
import ForgeCore

@MainActor
final class LifestyleViewModel: ObservableObject {
    @Published private(set) var metrics: LifestyleMetrics = .default
    @Published private(set) var recommendations: [AIRecommendation] = []
    @Published private(set) var isLoading = false
    @Published var error: LifestyleError?
    
    // Real-time health data
    @Published var healthStats: DailyHealthStats?
    @Published var weeklyTrends: [WeeklyHealthTrend] = []
    @Published var mindfulTrend: [MindfulDay] = []
    @Published var qolHistory: [QOLDay] = []
    /// 0...1 — share of life's pillars that had data behind the latest QoL score.
    /// The UI presents the number as an estimate when this is low.
    @Published private(set) var qolConfidence: Double = 0
    @Published var aiWorkouts: [AIWorkoutSuggestion] = []
    @Published var loggedMeals: [MealLog] = []
    @Published var mindfulMinutesToday: Int = 0
    @Published var mindfulMinutesWeek: Int = 0
    @Published var deepHabits: [DeepHabit] = []

    // Live ARIA insights — overlay real Claude/Bedrock reasoning onto the cards.
    // When nil, the cards render their existing local heuristic content (fallback).
    @Published var aiLifeAnalysis: String?
    @Published var aiNutritionInsight: String?
    @Published var aiBestPicksNote: String?
    @Published var aiMealNote: String?
    @Published var aiInsightsLive = false      // true when the last refresh came from the remote engine
    @Published var aiInsightsLoading = false

    private let healthManager = HealthKitManager.shared
    private let workoutManager = WorkoutPlanManager()
    private let notificationManager = SmartNotificationManager.shared
    static let shared = LifestyleViewModel()

    private var lastLoadAt: Date?
    private var remindersArmed = false
    private var lastInsightAt: Date?
    private var lastInsightKey: String?
    private static let loadTTL: TimeInterval = 90
    private static let insightTTL: TimeInterval = 15 * 60

    init() {}

    // Personalization for QoL targets (protein/calorie/hydration/sleep-need).
    // Optional: population defaults are used when the profile has not set them.
    private var personalWeightKg: Double?
    private var personalAge: Int?
    private var personalSexFemale: Bool?

    /// Feed the signed-in profile so QoL targets are personal, not one-size-fits-all.
    /// Safe to call repeatedly; it only copies the fields QoL uses.
    func applyPersonalization(_ profile: UserProfile?) {
        personalWeightKg = profile?.weight
        personalAge = profile?.age
        if let sex = profile?.biologicalSex {
            personalSexFemale = (sex == .female)
        }
    }

    func load(force: Bool = false) async {
        guard !isLoading else { return }
        if !force,
           let last = lastLoadAt,
           Date().timeIntervalSince(last) < Self.loadTTL,
           healthStats != nil {
            applyCachedHealth()
            return
        }
        isLoading = true
        defer { isLoading = false }
        error = nil

        // Apple Health and notifications are optional. A denied prompt must not
        // blank the whole Lifestyle tab — that was the "unusable" bug.
        // Don't re-prompt on every tab tap.
        if !healthManager.isAuthorized {
            _ = try? await healthManager.requestAuthorization()
        }

        await healthManager.fetchTodayStats(force: force)
        healthStats = healthManager.todayStats
        loggedMeals = healthManager.loggedMeals

        metrics = (try? await fetchMetrics()) ?? .default
        recommendations = (try? await fetchRecommendations()) ?? []
        qolHistory = LifestyleWellbeingStore.recordQOL(metrics.qualityOfLifeScore)
        lastLoadAt = Date()

        if !remindersArmed {
            remindersArmed = true
            await scheduleSmartReminders()
        }
        syncAriaContext()
    }

    func refresh() async { await load(force: true) }

    /// Trends and mindful minutes — only when Wellbeing is on screen.
    func loadWellbeingExtrasIfNeeded() async {
        if weeklyTrends.isEmpty {
            await healthManager.fetchWeeklyTrends()
            weeklyTrends = healthManager.weeklyTrends
        }
        if mindfulTrend.isEmpty {
            await healthManager.fetchMindfulTrend()
            mindfulTrend = healthManager.mindfulTrend
        }
        if mindfulMinutesToday == 0 && mindfulMinutesWeek == 0 {
            let now = Date()
            let startOfDay = Calendar.current.startOfDay(for: now)
            let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? startOfDay
            async let today = healthManager.fetchMindfulMinutes(from: startOfDay, to: now)
            async let week = healthManager.fetchMindfulMinutes(from: weekAgo, to: now)
            mindfulMinutesToday = Int(await today)
            mindfulMinutesWeek = Int(await week)
        }
    }

    /// Workout cards — only when AI Optimize is on screen.
    func loadWorkoutsIfNeeded() async {
        guard aiWorkouts.isEmpty else { return }
        aiWorkouts = await generateAIWorkouts(from: healthStats)
    }

    private func applyCachedHealth() {
        if healthStats == nil { healthStats = healthManager.todayStats }
        if loggedMeals.isEmpty { loggedMeals = healthManager.loggedMeals }
        if weeklyTrends.isEmpty { weeklyTrends = healthManager.weeklyTrends }
        if mindfulTrend.isEmpty { mindfulTrend = healthManager.mindfulTrend }
    }

    func syncAriaContext() {
        // Deep habit companion: markers/social are carried via FakeHealthPack when HealthKit is seeded;
        // until HealthKitManager exposes them, HabitEngine works from sleep variance + steps + macros.
        AriaContextStore.shared.syncLifestyleSignals(
            metrics: metrics,
            stats: healthStats,
            recommendations: recommendations,
            loggedMeals: loggedMeals
        )
        deepHabits = AriaContextStore.shared.context.deepHabits
        LifestyleWidgetBridge.update(metrics: metrics, recommendations: recommendations)
    }

    /// Overlay ARIA onto the cards. Default is local + cache. Network is
    /// opt-in (insights sheet or pull-to-refresh) so opening Lifestyle
    /// does not fire two Bedrock rounds.
    func refreshAIInsights(store: AppStore, allowNetwork: Bool = false) async {
        guard !aiInsightsLoading else { return }
        if aiLifeAnalysis == nil {
            aiLifeAnalysis = localLifestyleSummary()
        }
        guard allowNetwork else { return }

        let key = insightCacheKey
        if let lastInsightAt,
           lastInsightKey == key,
           Date().timeIntervalSince(lastInsightAt) < Self.insightTTL {
            return
        }

        aiInsightsLoading = true
        defer { aiInsightsLoading = false }

        syncAriaContext()
        // One short insight, not two sequential chat rounds.
        let analysisResp = await store.ariaInsight(prompt: lifestyleAnalysisPrompt())
        if let prose = analysisResp.map({ $0.proseSummary ?? $0.message }) {
            aiLifeAnalysis = prose
        }
        aiInsightsLive = !AriaService.shared.isLocalFallback && analysisResp != nil
        lastInsightAt = Date()
        lastInsightKey = key
    }

    private var insightCacheKey: String {
        "\(metrics.qualityOfLifeScore)|\(metrics.dailySteps)|\(Int(healthStats?.protein ?? 0))|\(metrics.stressLevel.rawValue)"
    }

    private func localLifestyleSummary() -> String {
        let qol = metrics.qualityOfLifeScore
        if qol >= 80 {
            return "Today looks solid — keep the same small habits. Sleep, water, and a walk will compound."
        }
        if metrics.stressLevel == .high || (healthStats?.hrv ?? 100) < 40 {
            return "Recovery is asking for less today. One easy win: water, a short walk, or an earlier night."
        }
        if metrics.sleepAverage < 7 {
            return "Sleep is the highest-leverage change right now. Protect bedtime — everything else gets easier."
        }
        return "One small change today beats a perfect plan. Pick water, a walk, or protein at the next meal."
    }

    private func lifestyleAnalysisPrompt() -> String {
        let s = healthStats
        return """
        Analyze my lifestyle today in 2-3 sentences. QOL \(metrics.qualityOfLifeScore)/100, \
        sleep \(String(format: "%.1f", metrics.sleepAverage))h, \(metrics.dailySteps) steps, \
        stress \(metrics.stressLevel.rawValue), protein \(Int(s?.protein ?? 0))g, HRV \(Int(s?.hrv ?? 0))ms. \
        What is the single highest-impact change I should make right now?
        """
    }

    private func nutritionCoachPrompt() -> String {
        let s = healthStats
        return """
        Coach my nutrition in 2-3 sentences. Today: \(Int(s?.protein ?? 0))g protein (target 180), \
        \(s?.totalCalories ?? 0) kcal (target 2600), \(Int(s?.water ?? 0)) glasses water today. \
        Give one specific, actionable tip for my next meal.
        """
    }

    /// Lazy ARIA coaching note for the restaurant "Best Picks" — fired only when the
    /// Restaurants tab appears. Leaves the note nil (heuristic-only) on failure.
    func refreshBestPicksNote(store: AppStore) async {
        guard aiBestPicksNote == nil else { return }
        let gap = max(0, Int(180 - (healthStats?.protein ?? 0)))
        let kcalLeft = max(0, 2600 - (healthStats?.totalCalories ?? 0))
        let prompt = """
        I'm picking a restaurant meal. I have about \(gap)g protein and \(kcalLeft) kcal left today. \
        In 1-2 sentences, what should I prioritize ordering to close my protein gap without \
        overshooting calories?
        """
        let resp = await store.ariaInsight(prompt: prompt)
        aiBestPicksNote = resp.map { $0.proseSummary ?? $0.message }
    }

    /// Lazy ARIA dish suggestion for the Nutrition tab's meal-suggestions card.
    /// Distinct from the macro coach tip; nil → heuristic rows only.
    func refreshMealNote(store: AppStore) async {
        guard aiMealNote == nil else { return }
        let gap = max(0, Int(180 - (healthStats?.protein ?? 0)))
        let kcalLeft = max(0, 2600 - (healthStats?.totalCalories ?? 0))
        let prompt = """
        Suggest one specific dish or meal to eat next, in a single sentence, to help me close \
        a \(gap)g protein gap within \(kcalLeft) kcal remaining today.
        """
        let resp = await store.ariaInsight(prompt: prompt)
        aiMealNote = resp.map { $0.proseSummary ?? $0.message }
    }

    /// Lazy ARIA macro coaching tip for `AINutritionCoachCard` — fired only when
    /// that card appears. Distinct from the meal-suggestion and best-picks notes
    /// above; nil → the card's local heuristic tips render instead (never fake
    /// "LIVE" badge, since the card only shows that badge once this is set).
    func refreshNutritionCoachNote(store: AppStore) async {
        guard aiNutritionInsight == nil else { return }
        let resp = await store.ariaInsight(prompt: nutritionCoachPrompt())
        aiNutritionInsight = resp.map { $0.proseSummary ?? $0.message }
    }

    func logMeal(name: String, calories: Double, protein: Double, carbs: Double, fat: Double) async {
        let meal = MealLog(name: name, calories: calories, protein: protein, carbs: carbs, fat: fat)
        try? await healthManager.logMeal(meal)
        await refresh()
    }
    
    func logWater(glasses: Int) async {
        try? await healthManager.logWater(
            milliliters: HydrationEngine.milliliters(fromGlasses: Double(glasses))
        )
        await refresh()
    }
    
    func logMindfulSession(minutes: Int) async {
        try? await healthManager.logMindfulSession(minutes: Double(minutes))
        await refresh()
    }

    private func generateAIWorkouts(from stats: DailyHealthStats?) async -> [AIWorkoutSuggestion] {
        var suggestions: [AIWorkoutSuggestion] = []
        
        if let hrv = stats?.hrv, hrv < 30 {
            let recoveryWorkout = await workoutManager.generateAIWorkout(
                goals: [.mobility],
                equipment: [.bodyweight, .bands],
                duration: 30
            )
            suggestions.append(AIWorkoutSuggestion(
                title: "Active Recovery",
                reason: "HRV is low (\(Int(hrv))ms) — prioritize mobility and light movement",
                workout: recoveryWorkout
            ))
        } else {
            let strengthWorkout = await workoutManager.generateAIWorkout(
                goals: [.strength, .hypertrophy],
                equipment: [.barbell, .dumbbells],
                duration: 60
            )
            suggestions.append(AIWorkoutSuggestion(
                title: "Strength Focus",
                reason: "Recovery metrics are solid — time to push hard",
                workout: strengthWorkout
            ))
        }
        
        if let stats, stats.steps < 6000 {
            let cardioWorkout = await workoutManager.generateAIWorkout(
                goals: [.endurance],
                equipment: [.bodyweight],
                duration: 30
            )
            suggestions.append(AIWorkoutSuggestion(
                title: "HIIT Cardio",
                reason: "Only \(stats.steps) steps today — let's boost activity",
                workout: cardioWorkout
            ))
        }
        
        return suggestions
    }
    
    private func scheduleSmartReminders() async {
        // Hydration reminder every 2 hours
        await notificationManager.scheduleHydrationReminder(every: 2)
        
        // Meal reminders
        var lunch = DateComponents()
        lunch.hour = 12
        lunch.minute = 0
        await notificationManager.scheduleMealReminder(time: lunch, mealType: "Lunch")
        
        var dinner = DateComponents()
        dinner.hour = 18
        dinner.minute = 30
        await notificationManager.scheduleMealReminder(time: dinner, mealType: "Dinner")
        
        // Sleep reminder
        var bedtime = DateComponents()
        bedtime.hour = 22
        bedtime.minute = 0
        await notificationManager.scheduleSleepReminder(bedtime: bedtime)
    }

    private func fetchMetrics() async throws -> LifestyleMetrics {
        // Grade every aspect of life we actually have data for, personalized to
        // the profile. No fabricated "82" when data is thin and no "insufficient
        // data" refusal — the calculator scores whatever is present and reports
        // how much of life that covered via `confidence`.
        let stats = healthStats
        let inputs = qualityOfLifeInputs(from: stats)
        // Smooth against yesterday so one noisy night doesn't swing a measure
        // that is meant to be stable; scaled by today's confidence internally.
        let previousOverall = LifestyleWellbeingStore.loadQOLHistory()
            .last { !Calendar.current.isDateInToday($0.date) }?.score
        let qol = QualityOfLifeCalculator.score(from: inputs).smoothed(previousOverall: previousOverall)
        qolConfidence = qol.confidence

        let sleepQuality = qol.score(for: .sleep) ?? 0
        let nutritionScore = qol.score(for: .nutrition) ?? 0

        // Legacy display fields are projections of the independent pillars so the
        // existing cards keep rendering; `qualityOfLifeScore` is the authority.
        let physicalHealth = average(of: [qol.score(for: .activity),
                                          qol.score(for: .vitals),
                                          qol.score(for: .hydration)])
        let mentalWellbeing = qol.score(for: .mind) ?? qol.score(for: .vitals) ?? 0
        let energyLevels = average(of: [qol.score(for: .sleep),
                                        qol.score(for: .activity),
                                        qol.score(for: .vitals)])

        let sleepNeed = personalAge.map { $0 < 18 ? 9.0 : ($0 >= 65 ? 7.5 : 8.0) } ?? 8.0
        let stress: StressLevel = {
            guard let hrv = stats?.hrv, hrv > 0 else { return .medium }
            return hrv < 30 ? .high : hrv < 50 ? .medium : .low
        }()

        return LifestyleMetrics(
            sleepAverage: stats?.sleepHours ?? 0,
            sleepTarget: sleepNeed,
            nutritionQuality: Double(nutritionScore) / 100.0,
            dailySteps: stats?.steps ?? 0,
            stressLevel: stress,
            qualityOfLifeScore: qol.overall,
            physicalHealth: physicalHealth,
            mentalWellbeing: mentalWellbeing,
            energyLevels: energyLevels,
            sleepQuality: sleepQuality,
            nutritionScore: nutritionScore
        )
    }

    /// Map today's HealthKit stats + profile + mindful minutes into the holistic
    /// QoL inputs. Zeros are treated as "not measured" so an absent signal lowers
    /// confidence rather than dragging a pillar to zero.
    private func qualityOfLifeInputs(from stats: DailyHealthStats?) -> QualityOfLifeInputs {
        var inputs = QualityOfLifeInputs()
        inputs.bodyMassKg = personalWeightKg
        inputs.age = personalAge
        inputs.biologicalSexFemale = personalSexFemale
        inputs.mindfulMinutes = mindfulMinutesToday > 0 ? Double(mindfulMinutesToday) : nil

        // Personal HRV baseline from the trailing week, so recovery is scored
        // against the individual's own norm rather than a population constant.
        let recentHRV = weeklyTrends.map(\.avgHRV).filter { $0 > 0 }
        if !recentHRV.isEmpty {
            inputs.hrvBaselineMs = recentHRV.reduce(0, +) / Double(recentHRV.count)
        }

        guard let stats else { return inputs }
        inputs.sleepHours = stats.sleepHours > 0 ? stats.sleepHours : nil
        inputs.steps = stats.steps > 0 ? stats.steps : nil
        inputs.activeCalories = stats.activeCalories > 0 ? stats.activeCalories : nil
        inputs.exerciseMinutes = stats.exerciseMinutes > 0 ? stats.exerciseMinutes : nil
        inputs.proteinGrams = stats.protein > 0 ? stats.protein : nil
        inputs.totalCalories = stats.totalCalories > 0 ? stats.totalCalories : nil
        inputs.fiberGrams = stats.fiber > 0 ? stats.fiber : nil
        inputs.addedSugarGrams = stats.sugar > 0 ? stats.sugar : nil
        inputs.waterGlasses = stats.water > 0 ? stats.water : nil
        inputs.hrvMs = stats.hrv > 0 ? stats.hrv : nil
        inputs.restingHR = stats.restingHeartRate > 0 ? stats.restingHeartRate : nil
        inputs.vo2Max = stats.vo2Max > 0 ? stats.vo2Max : nil
        if stats.oxygenSaturation > 0 {
            // HealthKit reports SpO2 as a 0...1 fraction; the scorer wants percent.
            inputs.oxygenSaturationPercent = stats.oxygenSaturation <= 1
                ? stats.oxygenSaturation * 100
                : stats.oxygenSaturation
        }
        inputs.respiratoryRate = stats.respiratoryRate > 0 ? stats.respiratoryRate : nil
        return inputs
    }

    private func average(of values: [Int?]) -> Int {
        let present = values.compactMap { $0 }
        guard !present.isEmpty else { return 0 }
        return present.reduce(0, +) / present.count
    }

    private func fetchRecommendations() async throws -> [AIRecommendation] {
        var recommendations: [AIRecommendation] = []
        
        // Generate personalized recommendations based on real data
        if let stats = healthStats {
            // Protein recommendation
            if stats.protein < 150 {
                let deficit = Int(180 - stats.protein)
                recommendations.append(AIRecommendation(
                    title: "Increase protein by \(deficit)g",
                    description: "You've consumed \(Int(stats.protein))g today. Add \(deficit)g to hit your 180g target — try Greek yogurt or chicken.",
                    impact: .high,
                    category: .nutrition
                ))
            }
            
            // Sleep recommendation
            if stats.sleepHours < 7.5 {
                let deficit = 8.0 - stats.sleepHours
                recommendations.append(AIRecommendation(
                    title: "Add \(String(format: "%.1f", deficit)) hours of sleep",
                    description: "Last night: \(String(format: "%.1f", stats.sleepHours))h. Deep sleep improves by 18% when you hit 8 hours.",
                    impact: .high,
                    category: .sleep
                ))
            }
            
            // HRV/Recovery recommendation
            if stats.hrv < 40 {
                recommendations.append(AIRecommendation(
                    title: "Priority: Recovery",
                    description: "HRV is \(Int(stats.hrv))ms (low). Consider mobility work, meditation, or a rest day.",
                    impact: .high,
                    category: .wellbeing
                ))
            }
            
            // Steps recommendation
            if stats.steps < 8000 {
                let deficit = 10000 - stats.steps
                recommendations.append(AIRecommendation(
                    title: "Boost movement by \(deficit.formatted()) steps",
                    description: "Currently at \(stats.steps.formatted()) steps. A 15-min walk adds ~2,000 steps.",
                    impact: .medium,
                    category: .fitness
                ))
            }
        }
        
        // Add baseline recommendations if none generated
        if recommendations.isEmpty {
            return AIRecommendation.sampleRecommendations
        }
        
        return recommendations
    }
}
