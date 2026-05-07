import SwiftUI
import Combine
import HealthKit
import WorkoutKit
import CoreLocation
import UserNotifications
import UIKit

// MARK: - Supporting Data Models (HealthKit types defined in HealthKitManager.swift)

// MARK: - WorkoutKit Manager

@MainActor
final class WorkoutPlanManager: ObservableObject {
    @Published var customWorkouts: [CustomWorkoutPlan] = []
    @Published var aiGeneratedWorkouts: [AIWorkoutSuggestion] = []
    @Published var aiGeneratedWorkoutsSuggested: [AIWorkoutSuggestion] = []
    @Published var isLoading: Bool = false
    @Published var isLoadingSuggested: Bool = false

    func generateAIWorkout(goals: [FitnessGoal], equipment: [Equipment], duration: Int) async -> CustomWorkoutPlan {
        // Simulate AI generation with workout patterns
        let exercises = selectExercises(for: goals, with: equipment)
        
        return CustomWorkoutPlan(
            id: UUID(),
            name: "\(goals.first?.rawValue ?? "Custom") Workout",
            duration: duration,
            exercises: exercises,
            targetMuscles: goals.compactMap { $0.primaryMuscles }.flatMap { $0 },
            difficulty: .intermediate,
            caloriesBurn: duration * 8
        )
    }
    
    private func selectExercises(for goals: [FitnessGoal], with equipment: [Equipment]) -> [WorkoutExercise] {
        var exercises: [WorkoutExercise] = []
        
        for goal in goals {
            switch goal {
            case .strength:
                exercises.append(contentsOf: [
                    WorkoutExercise(name: "Bench Press", sets: 4, reps: 8, restSeconds: 90, muscleGroup: .chest),
                    WorkoutExercise(name: "Squats", sets: 4, reps: 10, restSeconds: 120, muscleGroup: .legs),
                    WorkoutExercise(name: "Deadlifts", sets: 3, reps: 6, restSeconds: 180, muscleGroup: .back)
                ])
            case .hypertrophy:
                exercises.append(contentsOf: [
                    WorkoutExercise(name: "Incline DB Press", sets: 4, reps: 12, restSeconds: 60, muscleGroup: .chest),
                    WorkoutExercise(name: "Leg Press", sets: 4, reps: 15, restSeconds: 90, muscleGroup: .legs),
                    WorkoutExercise(name: "Pull-ups", sets: 3, reps: 10, restSeconds: 60, muscleGroup: .back)
                ])
            case .endurance:
                exercises.append(contentsOf: [
                    WorkoutExercise(name: "Burpees", sets: 3, reps: 20, restSeconds: 45, muscleGroup: .fullBody),
                    WorkoutExercise(name: "Jump Rope", sets: 4, reps: 100, restSeconds: 30, muscleGroup: .cardio),
                    WorkoutExercise(name: "Mountain Climbers", sets: 3, reps: 30, restSeconds: 30, muscleGroup: .core)
                ])
            case .mobility:
                exercises.append(contentsOf: [
                    WorkoutExercise(name: "Hip Flexor Stretch", sets: 3, reps: 10, restSeconds: 30, muscleGroup: .legs),
                    WorkoutExercise(name: "Shoulder Dislocations", sets: 3, reps: 15, restSeconds: 20, muscleGroup: .shoulders),
                    WorkoutExercise(name: "Cat-Cow Stretch", sets: 3, reps: 12, restSeconds: 20, muscleGroup: .back)
                ])
            }
        }
        
        return exercises
    }
}

struct CustomWorkoutPlan: Identifiable, Codable {
    let id: UUID
    let name: String
    let duration: Int
    let exercises: [WorkoutExercise]
    let targetMuscles: [MuscleGroup]
    let difficulty: WorkoutDifficulty
    let caloriesBurn: Int
}

struct WorkoutExercise: Identifiable, Codable {
    var id = UUID()
    let name: String
    let sets: Int
    let reps: Int
    let restSeconds: Int
    let muscleGroup: MuscleGroup
}

enum FitnessGoal: String, CaseIterable {
    case strength = "Strength"
    case hypertrophy = "Hypertrophy"
    case endurance = "Endurance"
    case mobility = "Mobility"
    
    var primaryMuscles: [MuscleGroup] {
        switch self {
        case .strength: return [.chest, .back, .legs]
        case .hypertrophy: return [.chest, .back, .legs, .arms, .shoulders]
        case .endurance: return [.cardio, .fullBody]
        case .mobility: return [.fullBody]
        }
    }
}

enum Equipment: String, CaseIterable {
    case barbell = "Barbell"
    case dumbbells = "Dumbbells"
    case cables = "Cables"
    case machines = "Machines"
    case bodyweight = "Bodyweight"
    case bands = "Resistance Bands"
}

enum MuscleGroup: String, Codable {
    case chest, back, legs, arms, shoulders, core, cardio, fullBody
}

enum WorkoutDifficulty: String, Codable {
    case beginner, intermediate, advanced
}

struct AIWorkoutSuggestion: Identifiable {
    let id = UUID()
    let title: String
    let reason: String
    let workout: CustomWorkoutPlan
}

// MARK: - Notification Manager

@MainActor
final class SmartNotificationManager: ObservableObject {
    static let shared = SmartNotificationManager()
    
    @Published var scheduledReminders: [SmartReminder] = []
    
    private init() {}
    
    func requestAuthorization() async throws {
        let center = UNUserNotificationCenter.current()
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }
    
    func scheduleHydrationReminder(every hours: Int) async {
        let content = UNMutableNotificationContent()
        content.title = "💧 Hydration Check"
        content.body = "Time to drink some water! You're doing great staying hydrated."
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(hours * 3600), repeats: true)
        let request = UNNotificationRequest(identifier: "hydration-\(UUID())", content: content, trigger: trigger)
        
        try? await UNUserNotificationCenter.current().add(request)
    }
    
    func scheduleMealReminder(time: DateComponents, mealType: String) async {
        let content = UNMutableNotificationContent()
        content.title = "🍽️ \(mealType) Time"
        content.body = "Don't forget your \(mealType.lowercased())! Hit your protein goals today."
        content.sound = .default
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: time, repeats: true)
        let request = UNNotificationRequest(identifier: "meal-\(mealType)-\(UUID())", content: content, trigger: trigger)
        
        try? await UNUserNotificationCenter.current().add(request)
    }
    
    func scheduleSleepReminder(bedtime: DateComponents) async {
        let content = UNMutableNotificationContent()
        content.title = "🌙 Wind Down Time"
        content.body = "Start your bedtime routine. Quality sleep = better gains!"
        content.sound = .default
        
        var earlyTime = bedtime
        earlyTime.hour = (earlyTime.hour ?? 22) - 1
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: earlyTime, repeats: true)
        let request = UNNotificationRequest(identifier: "sleep-\(UUID())", content: content, trigger: trigger)
        
        try? await UNUserNotificationCenter.current().add(request)
    }
}

struct SmartReminder: Identifiable {
    let id: String
    let type: ReminderType
    let time: DateComponents
    let enabled: Bool
}

enum ReminderType {
    case hydration, meal, sleep, workout, supplement
}

// MARK: - Domain Models

struct Restaurant: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let logo: String
    let items: [MenuItem]
    let category: RestaurantCategory

    init(id: UUID = UUID(), name: String, logo: String, items: [MenuItem], category: RestaurantCategory) {
        self.id = id; self.name = name; self.logo = logo; self.items = items; self.category = category
    }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Restaurant, rhs: Restaurant) -> Bool { lhs.id == rhs.id }
}

struct MenuItem: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let calories: Int
    let protein: Int
    let carbs: Int
    let fat: Int
    let serving: String
    let isHealthy: Bool

    init(id: UUID = UUID(), name: String, calories: Int, protein: Int, carbs: Int, fat: Int, serving: String, isHealthy: Bool) {
        self.id = id; self.name = name; self.calories = calories; self.protein = protein
        self.carbs = carbs; self.fat = fat; self.serving = serving; self.isHealthy = isHealthy
    }

    /// Protein per 100 kcal — higher = better ratio
    var proteinEfficiency: Int {
        guard calories > 0 else { return 0 }
        return Int(Double(protein) / Double(calories) * 1000)
    }

    var nutritionalRating: NutritionRating {
        switch proteinEfficiency {
        case 150...: return .excellent
        case 100..<150: return .good
        case 50..<100: return .fair
        default: return .poor
        }
    }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: MenuItem, rhs: MenuItem) -> Bool { lhs.id == rhs.id }
}

enum NutritionRating {
    case excellent, good, fair, poor
    var color: Color {
        switch self {
        case .excellent: return .success
        case .good: return .steel
        case .fair: return .warning
        case .poor: return .danger
        }
    }
    var label: String {
        switch self {
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .fair: return "Fair"
        case .poor: return "Poor"
        }
    }
}

enum RestaurantCategory: String, CaseIterable, Codable {
    case all = "All"
    case fastFood = "Fast Food"
    case chicken = "Chicken"
    case mexican = "Mexican"
    case burgers = "Burgers"
    case pizza = "Pizza"
    case healthy = "Healthy"
}

// MARK: - Lifestyle Domain Models

struct LifestyleMetrics: Codable {
    let sleepAverage: Double
    let sleepTarget: Double
    let nutritionQuality: Double
    let dailySteps: Int
    let stressLevel: StressLevel
    let qualityOfLifeScore: Int
    let physicalHealth: Int
    let mentalWellbeing: Int
    let energyLevels: Int
    let sleepQuality: Int
    let nutritionScore: Int

    static var `default`: LifestyleMetrics {
        LifestyleMetrics(
            sleepAverage: 7.2, sleepTarget: 8.0, nutritionQuality: 0.78,
            dailySteps: 8400, stressLevel: .medium, qualityOfLifeScore: 82,
            physicalHealth: 88, mentalWellbeing: 75, energyLevels: 82,
            sleepQuality: 79, nutritionScore: 85
        )
    }
}

enum StressLevel: String, Codable {
    case low = "Low", medium = "Medium", high = "High"
    var color: Color {
        switch self { case .low: return .success; case .medium: return .warning; case .high: return .danger }
    }
}

struct AIRecommendation: Identifiable, Codable {
    let id: UUID
    let title: String
    let description: String
    let impact: ImpactLevel
    let category: RecommendationCategory

    init(id: UUID = UUID(), title: String, description: String, impact: ImpactLevel, category: RecommendationCategory) {
        self.id = id; self.title = title; self.description = description
        self.impact = impact; self.category = category
    }

    static var sampleRecommendations: [AIRecommendation] {[
        AIRecommendation(title: "Increase protein by 30g", description: "Muscle recovery improves with 180g daily. You're averaging 150g — add a serving of Greek yogurt or chicken after training.", impact: .high, category: .nutrition),
        AIRecommendation(title: "Earlier bedtime (9:30 PM)", description: "Your deep sleep increases by 18% when asleep before 10 PM. Oura data across 47 nights confirms this pattern.", impact: .high, category: .sleep),
        AIRecommendation(title: "10 min morning sunlight", description: "Cortisol regulation and circadian rhythm improve with early light. Best before 9 AM.", impact: .medium, category: .wellbeing),
        AIRecommendation(title: "No caffeine after 2 PM", description: "Late caffeine correlates with 40 fewer minutes of deep sleep in your personal data.", impact: .medium, category: .sleep),
    ]}
}

enum ImpactLevel: String, Codable {
    case high = "High", medium = "Medium", low = "Low"
    var color: Color {
        switch self { case .high: return .ember; case .medium: return .warning; case .low: return .steel }
    }
}

enum RecommendationCategory: String, Codable {
    case nutrition = "Nutrition", sleep = "Sleep", wellbeing = "Wellbeing", fitness = "Fitness"
    var icon: String {
        switch self {
        case .nutrition: return "fork.knife"
        case .sleep:     return "moon.stars.fill"
        case .wellbeing: return "heart.fill"
        case .fitness:   return "dumbbell.fill"
        }
    }
}

enum LifestyleError: Error, LocalizedError {
    case networkError, dataParsingError, unauthorizedAccess, unknownError
    var errorDescription: String? {
        switch self {
        case .networkError:      return "Unable to connect. Check your internet connection."
        case .dataParsingError:  return "Unable to process data. Please try again."
        case .unauthorizedAccess: return "You don't have access to this data."
        case .unknownError:      return "An unexpected error occurred."
        }
    }
}

// MARK: - ViewModel (integrated with HealthKit + AI)

@MainActor
final class LifestyleViewModel: ObservableObject {
    @Published private(set) var metrics: LifestyleMetrics = .default
    @Published private(set) var recommendations: [AIRecommendation] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: LifestyleError?
    
    // Real-time health data
    @Published var healthStats: DailyHealthStats?
    @Published var weeklyTrends: [WeeklyHealthTrend] = []
    @Published var aiWorkouts: [AIWorkoutSuggestion] = []
    
    private let healthManager = HealthKitManager.shared
    private let workoutManager = WorkoutPlanManager()
    private let notificationManager = SmartNotificationManager.shared
    
    init() {}

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Request HealthKit authorization
            try await healthManager.requestAuthorization()
            
            // Request notification authorization
            try await notificationManager.requestAuthorization()
            
            // Fetch real data
            async let m = fetchMetrics()
            async let r = fetchRecommendations()
            async let h = healthManager.fetchTodayStats()
            async let w = healthManager.fetchWeeklyTrends()
            async let ai = generateAIWorkouts()
            
            metrics = try await m
            recommendations = try await r
            await h
            healthStats = healthManager.todayStats
            await w
            weeklyTrends = healthManager.weeklyTrends
            aiWorkouts = await ai
            
            // Schedule smart notifications
            await scheduleSmartReminders()
            
            error = nil
        } catch {
            self.error = error as? LifestyleError ?? .unknownError
        }
    }

    func refresh() async { 
        await healthManager.fetchTodayStats()
        await healthManager.fetchWeeklyTrends()
        healthStats = healthManager.todayStats
        weeklyTrends = healthManager.weeklyTrends
        await load() 
    }
    
    func logMeal(name: String, calories: Double, protein: Double, carbs: Double, fat: Double) async {
        let meal = MealLog(name: name, calories: calories, protein: protein, carbs: carbs, fat: fat)
        try? await healthManager.logMeal(meal)
        await refresh()
    }
    
    func logWater(glasses: Int) async {
        try? await healthManager.logWater(ounces: Double(glasses * 8))
        await refresh()
    }
    
    private func generateAIWorkouts() async -> [AIWorkoutSuggestion] {
        // AI-powered workout generation based on user data
        var suggestions: [AIWorkoutSuggestion] = []
        
        // Analyze recovery state
        if let hrv = healthStats?.hrv, hrv < 30 {
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
        
        // Add endurance if steps are low
        if let stats = healthStats, stats.steps < 6000 {
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
        try await Task.sleep(nanoseconds: 400_000_000)
        
        // Generate metrics from real health data
        guard let stats = healthStats else {
            return .default
        }
        
        let sleepQuality = Int((stats.sleepHours / 8.0) * 100)
        let nutritionScore = calculateNutritionScore(stats: stats)
        let physicalHealth = calculatePhysicalHealth(stats: stats)
        let mentalWellbeing = calculateMentalWellbeing(stats: stats)
        let energyLevels = calculateEnergyLevels(stats: stats)
        
        let qol = (sleepQuality + nutritionScore + physicalHealth + mentalWellbeing + energyLevels) / 5
        
        return LifestyleMetrics(
            sleepAverage: stats.sleepHours,
            sleepTarget: 8.0,
            nutritionQuality: Double(nutritionScore) / 100.0,
            dailySteps: stats.steps,
            stressLevel: stats.hrv < 30 ? .high : stats.hrv < 50 ? .medium : .low,
            qualityOfLifeScore: qol,
            physicalHealth: physicalHealth,
            mentalWellbeing: mentalWellbeing,
            energyLevels: energyLevels,
            sleepQuality: sleepQuality,
            nutritionScore: nutritionScore
        )
    }
    
    private func calculateNutritionScore(stats: DailyHealthStats) -> Int {
        var score = 0
        
        // Protein (target 180g)
        let proteinScore = min(Int((stats.protein / 180.0) * 100), 100)
        score += proteinScore
        
        // Calorie balance (target 2600)
        let calorieScore = stats.totalCalories > 0 ? min(Int((Double(stats.totalCalories) / 2600.0) * 100), 100) : 50
        score += calorieScore
        
        // Hydration (target 8 glasses)
        let hydrationScore = min(Int((stats.water / 8.0) * 100), 100)
        score += hydrationScore
        
        return score / 3
    }
    
    private func calculatePhysicalHealth(stats: DailyHealthStats) -> Int {
        var score = 0
        
        // Steps (target 10000)
        let stepScore = min(Int((Double(stats.steps) / 10000.0) * 100), 100)
        score += stepScore
        
        // Active calories (target 600)
        let calorieScore = min(Int((Double(stats.activeCalories) / 600.0) * 100), 100)
        score += calorieScore
        
        // Resting HR (lower is better, 60 is optimal)
        let hrScore = stats.restingHeartRate > 0 ? max(100 - Int((stats.restingHeartRate - 60) * 2), 0) : 70
        score += hrScore
        
        return score / 3
    }
    
    private func calculateMentalWellbeing(stats: DailyHealthStats) -> Int {
        var score = 70 // Base score
        
        // HRV (higher is better, 50+ is good)
        if stats.hrv > 0 {
            score = min(Int(stats.hrv * 1.5), 100)
        }
        
        // Sleep quality bonus
        if stats.sleepHours >= 7.5 {
            score = min(score + 10, 100)
        }
        
        return score
    }
    
    private func calculateEnergyLevels(stats: DailyHealthStats) -> Int {
        var score = 0
        
        // Sleep impact (40% weight)
        let sleepScore = Int((stats.sleepHours / 8.0) * 100)
        score += Int(Double(sleepScore) * 0.4)
        
        // Nutrition impact (30% weight)
        let nutritionScore = calculateNutritionScore(stats: stats)
        score += Int(Double(nutritionScore) * 0.3)
        
        // Activity impact (30% weight)
        let activityScore = min(Int((Double(stats.steps) / 10000.0) * 100), 100)
        score += Int(Double(activityScore) * 0.3)
        
        return min(score, 100)
    }

    private func fetchRecommendations() async throws -> [AIRecommendation] {
        try await Task.sleep(nanoseconds: 250_000_000)
        
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

// MARK: - Lifestyle Segments

enum LifestyleSegment: Int, CaseIterable {
    case aiOptimization, restaurants, nutrition, wellbeing
    var title: String {
        switch self {
        case .aiOptimization: return "AI Optimize"
        case .restaurants:    return "Restaurants"
        case .nutrition:      return "Nutrition"
        case .wellbeing:      return "Wellbeing"
        }
    }
    var icon: String {
        switch self {
        case .aiOptimization: return "sparkles"
        case .restaurants:    return "fork.knife"
        case .nutrition:      return "chart.pie.fill"
        case .wellbeing:      return "heart.fill"
        }
    }
}

// MARK: - Root View

struct LifestyleView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var vm = LifestyleViewModel()
    @State private var selectedSegment: LifestyleSegment = .aiOptimization
    @State private var showInsights = false
    @Namespace private var segmentNS

    var body: some View {
        ZStack {
            // Background — subtle radial haze tuned to selected segment
            LifestyleBackground(segment: selectedSegment)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                LifestyleHeaderView(showInsights: $showInsights, metrics: vm.metrics)
                    .padding(.horizontal, 20)
                    .padding(.top, 60)
                    .padding(.bottom, 16)

                SegmentedPillControl(selected: $selectedSegment, namespace: segmentNS)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        segmentContent
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 110)
                }
                .refreshable { await vm.refresh() }
            }

            if showInsights {
                AIInsightsModal(isPresented: $showInsights, recommendations: vm.recommendations)
                    .zIndex(10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showInsights)
        // Single load point — fixes double-call bug
        .task { await vm.load() }
        .alert("Error", isPresented: .constant(vm.error != nil), presenting: vm.error) { _ in
            Button("OK") {}
        } message: { err in Text(err.localizedDescription) }
    }

    @ViewBuilder
    private var segmentContent: some View {
        switch selectedSegment {
        case .aiOptimization: AIOptimizationContent(vm: vm)
        case .restaurants:    NutritionDatabaseView()
        case .nutrition:      DailyNutritionView()
        case .wellbeing:      WellbeingView()
        }
    }
}

// MARK: - Dynamic Background

struct LifestyleBackground: View {
    let segment: LifestyleSegment
    @State private var phase = false

    private var accentColor: Color {
        switch segment {
        case .aiOptimization: return .ember
        case .restaurants:    return .steel
        case .nutrition:      return Color(hex: "FFB84D")
        case .wellbeing:      return .success
        }
    }

    var body: some View {
        ZStack {
            Color.background
            LinearGradient(
                colors: [accentColor.opacity(phase ? 0.06 : 0.03), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) { phase = true }
        }
        .animation(.easeInOut(duration: 0.8), value: segment)
    }
}

// MARK: - Header

struct LifestyleHeaderView: View {
    @Binding var showInsights: Bool
    let metrics: LifestyleMetrics
    @State private var appeared = false

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text("LIFESTYLE")
                    .font(.system(size: 11, weight: .black))
                    .foregroundColor(.textTertiary)
                    .tracking(3)
                Text("Optimization")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(.textPrimary)
            }

            Spacer()

            // QOL score chip + AI button
            HStack(spacing: 12) {
                VStack(spacing: 2) {
                    Text("\(metrics.qualityOfLifeScore)")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(.textPrimary)
                    Text("QOL")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.textTertiary)
                        .tracking(1.5)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.surface)
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.ember.opacity(0.3), lineWidth: 1))
                .shadow(color: .black.opacity(0.05), radius: 6, y: 3)

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) { showInsights = true }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    ZStack {
                        Circle().fill(Color.ember.opacity(0.15)).frame(width: 46, height: 46)
                        Image(systemName: "sparkles")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.ember)
                    }
                }
                .shadow(color: Color.ember.opacity(0.2), radius: 8, y: 4)
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -12)
        .onAppear { withAnimation(.spring(response: 0.55, dampingFraction: 0.78).delay(0.05)) { appeared = true } }
    }
}

// MARK: - Segmented Control with matchedGeometryEffect

struct SegmentedPillControl: View {
    @Binding var selected: LifestyleSegment
    let namespace: Namespace.ID

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(LifestyleSegment.allCases, id: \.self) { seg in
                    Button {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.75)) { selected = seg }
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: seg.icon)
                                .font(.system(size: 12, weight: .semibold))
                            Text(seg.title)
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(selected == seg ? .white : .textTertiary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background {
                            if selected == seg {
                                Capsule()
                                    .fill(Color.ember)
                                    .matchedGeometryEffect(id: "pill", in: namespace)
                                    .shadow(color: Color.ember.opacity(0.45), radius: 10, y: 4)
                            } else {
                                Capsule().fill(Color.surface.opacity(0.6))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

// MARK: - AI Optimization Content

struct AIOptimizationContent: View {
    @ObservedObject var vm: LifestyleViewModel

    var body: some View {
        LazyVStack(spacing: 20) {
            // NEW: AI-powered daily focus card
            TodaysFocusCard(vm: vm)
            
            // NEW: Real-time HealthKit Dashboard
            if let stats = vm.healthStats {
                LiveHealthDashboard(stats: stats, trends: vm.weeklyTrends)
            }
            
            // NEW: AI Workout Suggestions
            if !vm.aiWorkouts.isEmpty {
                AIWorkoutSuggestionsCard(workouts: vm.aiWorkouts)
            }
            
            MultiArcQOLCard(metrics: vm.metrics)
            AILifeAnalysisCard(metrics: vm.metrics)
            AIRecommendationsCard(recommendations: vm.recommendations)
            OptimizationGoalsCard()
            
            // NEW: Recovery & Performance
            if let stats = vm.healthStats {
                RecoveryMetricsCard(stats: stats)
            }
        }
    }
}

// MARK: - Today's Focus Card (Award-Winning Feature)

struct TodaysFocusCard: View {
    @ObservedObject var vm: LifestyleViewModel
    @State private var appeared = false
    
    private var focusArea: (title: String, icon: String, priority: String, action: String, color: Color, gradient: [Color]) {
        guard let stats = vm.healthStats else {
            return ("Start Your Day", "sun.max.fill", "Morning Routine", "Log your first meal", .ember, [.ember, .ember.opacity(0.7)])
        }
        
        // AI decision tree for daily focus
        if stats.hrv < 30 {
            return ("Recovery Focus", "heart.circle.fill", "Critical", "Take an active recovery day", .danger, [.danger, Color(hex: "FF6B6B")])
        }
        
        if stats.sleepHours < 6.5 {
            return ("Sleep Priority", "moon.zzz.fill", "High", "Aim for 8+ hours tonight", Color(hex: "A855F7"), [Color(hex: "A855F7"), Color(hex: "C77DFF")])
        }
        
        if stats.protein < 120 {
            let remaining = Int(180 - stats.protein)
            return ("Protein Deficit", "fork.knife.circle.fill", "High", "Add \(remaining)g protein today", .ember, [.ember, Color(hex: "FFB84D")])
        }
        
        if stats.steps < 5000 {
            return ("Movement Goal", "figure.walk.circle.fill", "Medium", "Hit 10K steps today", .steel, [.steel, .success])
        }
        
        if stats.water < 6 {
            return ("Hydration Check", "drop.circle.fill", "Medium", "Drink more water", Color(hex: "4A9EFF"), [Color(hex: "4A9EFF"), Color(hex: "00D4FF")])
        }
        
        return ("Peak Performance", "bolt.circle.fill", "Ready", "Crush your workout", .success, [.success, Color(hex: "00FF88")])
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Animated gradient header
            ZStack(alignment: .topLeading) {
                // Background gradient
                LinearGradient(
                    colors: focusArea.gradient + [focusArea.gradient.first!.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(
                    LinearGradient(
                        colors: [.white.opacity(0.15), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                
                // Animated particles
                TimelineView(.animation(minimumInterval: 2)) { timeline in
                    Canvas { context, size in
                        let now = timeline.date.timeIntervalSinceReferenceDate
                        for i in 0..<8 {
                            let x = (CGFloat(i) / 8.0) * size.width + CGFloat(sin(now * 0.5 + Double(i))) * 30
                            let y = (CGFloat(i % 3) / 3.0) * size.height + CGFloat(cos(now * 0.3 + Double(i))) * 20
                            let opacity = 0.1 + abs(sin(now + Double(i))) * 0.2
                            
                            context.opacity = opacity
                            context.fill(
                                Circle().path(in: CGRect(x: x, y: y, width: 4, height: 4)),
                                with: .color(.white)
                            )
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 16) {
                    // Priority badge
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.white.opacity(0.9))
                            .frame(width: 6, height: 6)
                            .shadow(color: .white.opacity(0.6), radius: 4)
                        Text(focusArea.priority.uppercased())
                            .font(.system(size: 10, weight: .black))
                            .foregroundColor(.white)
                            .tracking(1.5)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.2))
                    .cornerRadius(20)
                    .overlay(
                        Capsule()
                            .stroke(.white.opacity(0.3), lineWidth: 1)
                    )
                    
                    // Main content
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(.white.opacity(0.2))
                                .frame(width: 70, height: 70)
                            Circle()
                                .fill(.white.opacity(0.1))
                                .frame(width: 70, height: 70)
                                .blur(radius: 8)
                            
                            Image(systemName: focusArea.icon)
                                .font(.system(size: 32, weight: .semibold))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.2), radius: 4)
                        }
                        .scaleEffect(appeared ? 1 : 0.7)
                        .animation(.spring(response: 0.6, dampingFraction: 0.65).delay(0.1), value: appeared)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("TODAY'S FOCUS")
                                .font(.system(size: 11, weight: .black))
                                .foregroundColor(.white.opacity(0.8))
                                .tracking(2)
                            
                            Text(focusArea.title)
                                .font(.system(size: 24, weight: .black))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.2), radius: 4)
                            
                            Text(focusArea.action)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                }
                .padding(24)
            }
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            
            // Quick action button
            Button {
                // Navigate to relevant section
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                    Text("Take Action")
                        .font(.system(size: 16, weight: .bold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(focusArea.color)
                .padding(18)
                .background(focusArea.color.opacity(0.1))
                .cornerRadius(16)
            }
            .padding(16)
            .background(Color.surface)
        }
        .background(Color.surface)
        .cornerRadius(24)
        .shadow(color: focusArea.color.opacity(0.2), radius: 20, y: 10)
        .onAppear { appeared = true }
    }
}

// MARK: - Live Health Dashboard (HealthKit Integration)

struct LiveHealthDashboard: View {
    let stats: DailyHealthStats
    let trends: [WeeklyHealthTrend]
    @State private var appeared = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header with live indicator
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.success.opacity(0.15)).frame(width: 46, height: 46)
                    Image(systemName: "heart.text.square.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(LinearGradient(colors: [.success, .ember], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("Live Health Data")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.textPrimary)
                        
                        // Pulsing live indicator
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.success)
                                .frame(width: 6, height: 6)
                                .overlay(
                                    Circle()
                                        .stroke(Color.success.opacity(0.3), lineWidth: 2)
                                        .scaleEffect(appeared ? 1.5 : 1)
                                        .opacity(appeared ? 0 : 1)
                                        .animation(.easeOut(duration: 1.2).repeatForever(autoreverses: false), value: appeared)
                                )
                            Text("LIVE")
                                .font(.system(size: 10, weight: .black))
                                .foregroundColor(.success)
                                .tracking(1)
                        }
                    }
                    Text("Powered by HealthKit")
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                }
                Spacer()
            }
            .padding(.bottom, 4)
            
            // Today's Key Metrics
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                HealthMetricTile(
                    icon: "figure.walk",
                    label: "Steps",
                    value: "\(stats.steps.formatted())",
                    target: "10,000",
                    progress: Double(stats.steps) / 10000.0,
                    color: .steel,
                    appeared: appeared
                )
                
                HealthMetricTile(
                    icon: "flame.fill",
                    label: "Active Cal",
                    value: "\(stats.activeCalories)",
                    target: "600",
                    progress: Double(stats.activeCalories) / 600.0,
                    color: .ember,
                    appeared: appeared
                )
                
                HealthMetricTile(
                    icon: "moon.zzz.fill",
                    label: "Sleep",
                    value: String(format: "%.1fh", stats.sleepHours),
                    target: "8h",
                    progress: stats.sleepHours / 8.0,
                    color: Color(hex: "A855F7"),
                    appeared: appeared
                )
                
                HealthMetricTile(
                    icon: "waveform.path.ecg",
                    label: "HRV",
                    value: "\(Int(stats.hrv))",
                    target: "50+",
                    progress: stats.hrv / 50.0,
                    color: .success,
                    appeared: appeared
                )
            }
            
            // Weekly Trend Sparkline
            if !trends.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("7-Day Trends")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    
                    HStack(spacing: 4) {
                        ForEach(Array(trends.enumerated()), id: \.offset) { i, trend in
                            let maxSteps = max(trends.map { $0.steps }.max() ?? 0, 1)
                            let height = max(CGFloat(trend.steps), 0) / CGFloat(maxSteps) * 60
                            
                            VStack(spacing: 4) {
                                Spacer()
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(LinearGradient(
                                        colors: [Color.steel, Color.steel.opacity(0.5)],
                                        startPoint: .top, endPoint: .bottom
                                    ))
                                    .frame(height: appeared ? height : 4)
                                    .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(Double(i) * 0.05), value: appeared)
                                
                                Text(trend.date, format: .dateTime.weekday(.abbreviated))
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.textTertiary)
                            }
                        }
                    }
                    .frame(height: 80)
                }
                .padding(.top, 8)
            }
        }
        .padding(22)
        .background(Color.surface)
        .cornerRadius(22)
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(LinearGradient(
                    colors: [Color.success.opacity(0.3), Color.ember.opacity(0.2)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 20, y: 8)
        .onAppear { appeared = true }
    }
}

struct HealthMetricTile: View {
    let icon: String
    let label: String
    let value: String
    let target: String
    let progress: Double
    let color: Color
    let appeared: Bool
    
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(color)
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.textSecondary)
                Spacer()
            }
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundColor(.textPrimary)
                Text("/ \(target)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textTertiary)
                Spacer()
            }
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.borderColor.opacity(0.3))
                    Capsule()
                        .fill(color)
                        .frame(width: appeared ? geo.size.width * CGFloat(min(progress, 1.0)) : 0)
                        .animation(.spring(response: 1.0, dampingFraction: 0.7).delay(0.2), value: appeared)
                }
            }
            .frame(height: 4)
        }
        .padding(14)
        .background(Color.surfaceElevated)
        .cornerRadius(14)
    }
}

// MARK: - AI Workout Suggestions Card

struct AIWorkoutSuggestionsCard: View {
    let workouts: [AIWorkoutSuggestion]
    @State private var appeared = false
    @State private var selectedWorkout: CustomWorkoutPlan?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.ember)
                Text("AI Workout Suggestions")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("\(workouts.count) ready")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.ember)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.ember.opacity(0.12))
                    .cornerRadius(8)
            }
            
            VStack(spacing: 12) {
                ForEach(Array(workouts.enumerated()), id: \.element.id) { i, suggestion in
                    AIWorkoutCard(suggestion: suggestion)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 20)
                        .animation(.spring(response: 0.5, dampingFraction: 0.76).delay(Double(i) * 0.1), value: appeared)
                        .onTapGesture {
                            selectedWorkout = suggestion.workout
                        }
                }
            }
        }
        .padding(22)
        .background(Color.surface)
        .cornerRadius(22)
        .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
        .onAppear { appeared = true }
        .sheet(item: $selectedWorkout) { workout in
            WorkoutDetailSheet(workout: workout)
        }
    }
}

struct AIWorkoutCard: View {
    let suggestion: AIWorkoutSuggestion
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.ember.opacity(0.12))
                        .frame(width: 50, height: 50)
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(LinearGradient.emberGradient)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(suggestion.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.textPrimary)
                    HStack(spacing: 8) {
                        Label("\(suggestion.workout.duration) min", systemImage: "clock.fill")
                        Label("\(suggestion.workout.exercises.count) exercises", systemImage: "list.bullet")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textSecondary)
                }
                
                Spacer()
                
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.ember)
            }
            
            Divider().background(Color.borderColor.opacity(0.4))
            
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11))
                    .foregroundColor(.ember)
                Text(suggestion.reason)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(16)
        .background(Color.surfaceElevated)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.ember.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Recovery Metrics Card

struct RecoveryMetricsCard: View {
    let stats: DailyHealthStats
    @State private var appeared = false
    
    var recoveryScore: Int {
        var score = 0
        
        // HRV component (40% weight)
        let hrvScore = min(Int(stats.hrv * 1.5), 100)
        score += Int(Double(hrvScore) * 0.4)
        
        // Resting HR component (30% weight)
        let hrScore = stats.restingHeartRate > 0 ? max(100 - Int((stats.restingHeartRate - 60) * 2), 0) : 70
        score += Int(Double(hrScore) * 0.3)
        
        // Sleep component (30% weight)
        let sleepScore = Int((stats.sleepHours / 8.0) * 100)
        score += Int(Double(sleepScore) * 0.3)
        
        return min(score, 100)
    }
    
    var recoveryStatus: (label: String, color: Color) {
        switch recoveryScore {
        case 80...: return ("Excellent", .success)
        case 60..<80: return ("Good", .steel)
        case 40..<60: return ("Moderate", .warning)
        default: return ("Low", .danger)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(recoveryStatus.color.opacity(0.15)).frame(width: 46, height: 46)
                    Image(systemName: "bolt.heart.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(recoveryStatus.color)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Recovery Status")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Text(recoveryStatus.label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(recoveryStatus.color)
                }
                Spacer()
                
                // Recovery score ring
                ZStack {
                    Circle()
                        .stroke(Color.borderColor.opacity(0.3), lineWidth: 8)
                        .frame(width: 60, height: 60)
                    
                    Circle()
                        .trim(from: 0, to: appeared ? CGFloat(recoveryScore) / 100 : 0)
                        .stroke(recoveryStatus.color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 60, height: 60)
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 1.2, dampingFraction: 0.7).delay(0.2), value: appeared)
                    
                    Text("\(recoveryScore)")
                        .font(.system(size: 20, weight: .black))
                        .foregroundColor(.textPrimary)
                }
            }
            .padding(.bottom, 20)
            
            // Recovery metrics grid
            VStack(spacing: 12) {
                RecoveryMetricRow(
                    icon: "waveform.path.ecg",
                    label: "Heart Rate Variability",
                    value: "\(Int(stats.hrv)) ms",
                    status: stats.hrv > 50 ? "Optimal" : stats.hrv > 30 ? "Good" : "Low",
                    color: stats.hrv > 50 ? .success : stats.hrv > 30 ? .warning : .danger
                )
                
                RecoveryMetricRow(
                    icon: "heart.fill",
                    label: "Resting Heart Rate",
                    value: "\(Int(stats.restingHeartRate)) bpm",
                    status: stats.restingHeartRate < 60 ? "Excellent" : stats.restingHeartRate < 70 ? "Good" : "Elevated",
                    color: stats.restingHeartRate < 60 ? .success : stats.restingHeartRate < 70 ? .steel : .warning
                )
                
                RecoveryMetricRow(
                    icon: "bed.double.fill",
                    label: "Sleep Duration",
                    value: String(format: "%.1f hours", stats.sleepHours),
                    status: stats.sleepHours >= 8 ? "Optimal" : stats.sleepHours >= 7 ? "Good" : "Low",
                    color: stats.sleepHours >= 8 ? .success : stats.sleepHours >= 7 ? .steel : .warning
                )
            }
            
            Divider().background(Color.borderColor.opacity(0.4)).padding(.vertical, 16)
            
            // Training readiness
            HStack(spacing: 12) {
                Image(systemName: recoveryScore > 70 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(recoveryScore > 70 ? .success : .warning)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(recoveryScore > 70 ? "Ready to Train" : "Consider Active Recovery")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Text(recoveryScore > 70 
                         ? "Your body is primed for a hard session"
                         : "Focus on mobility, stretching, or light cardio")
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)
                        .lineSpacing(3)
                }
            }
            .padding(14)
            .background(recoveryStatus.color.opacity(0.08))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(recoveryStatus.color.opacity(0.2), lineWidth: 1)
            )
        }
        .padding(22)
        .background(Color.surface)
        .cornerRadius(22)
        .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
        .onAppear { appeared = true }
    }
}

struct RecoveryMetricRow: View {
    let icon: String
    let label: String
    let value: String
    let status: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(color.opacity(0.12)).frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.textSecondary)
                Text(value)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.textPrimary)
            }
            
            Spacer()
            
            Text(status)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(color)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(color.opacity(0.12))
                .cornerRadius(8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.surfaceElevated)
        .cornerRadius(12)
    }
}

// MARK: - Workout Detail Sheet

struct WorkoutDetailSheet: View {
    let workout: CustomWorkoutPlan
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    // Header stats
                    VStack(alignment: .leading, spacing: 12) {
                        Text(workout.name)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.textPrimary)
                        
                        HStack(spacing: 16) {
                            StatPill(icon: "clock.fill", value: "\(workout.duration) min", color: .steel)
                            StatPill(icon: "flame.fill", value: "~\(workout.caloriesBurn) cal", color: .ember)
                            StatPill(icon: "list.bullet", value: "\(workout.exercises.count) exercises", color: .success)
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Exercise list
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Exercises")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.textPrimary)
                            .padding(.horizontal, 20)
                        
                        ForEach(Array(workout.exercises.enumerated()), id: \.element.id) { i, exercise in
                            ExerciseRow(index: i + 1, exercise: exercise)
                                .padding(.horizontal, 20)
                        }
                    }
                    
                    // Start workout button
                    Button {
                        // Integration with WorkoutKit would go here
                        dismiss()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 16, weight: .bold))
                            Text("Start Workout")
                                .font(.system(size: 17, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(LinearGradient.emberGradient)
                        .cornerRadius(16)
                        .shadow(color: Color.ember.opacity(0.4), radius: 12, y: 6)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
                .padding(.vertical, 24)
            }
            .background(Color.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.ember)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

struct StatPill: View {
    let icon: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
            Text(value)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(0.12))
        .cornerRadius(10)
    }
}

struct ExerciseRow: View {
    let index: Int
    let exercise: WorkoutExercise
    
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.ember.opacity(0.12)).frame(width: 40, height: 40)
                Text("\(index)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.ember)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.textPrimary)
                HStack(spacing: 8) {
                    Text("\(exercise.sets) sets")
                    Text("·")
                    Text("\(exercise.reps) reps")
                    Text("·")
                    Text("\(exercise.restSeconds)s rest")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.textSecondary)
            }
            
            Spacer()
            
            Text(exercise.muscleGroup.rawValue.capitalized)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.textTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.surfaceElevated)
                .cornerRadius(6)
        }
        .padding(14)
        .background(Color.surface)
        .cornerRadius(14)
    }
}

// MARK: - Multi-Arc QOL Card (flagship visual)

struct MultiArcQOLCard: View {
    let metrics: LifestyleMetrics
    @State private var appeared = false

    private let arcs: [(label: String, kp: KeyPath<LifestyleMetrics, Int>, color: Color, radius: CGFloat)] = [
        ("Physical",  \.physicalHealth,  .success,                  96),
        ("Mental",    \.mentalWellbeing, .steel,                    78),
        ("Energy",    \.energyLevels,    .ember,                    60),
        ("Sleep",     \.sleepQuality,    Color(hex: "A855F7"),      42),
        ("Nutrition", \.nutritionScore,  Color(hex: "FFB84D"),      24),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Section label
            HStack {
                Text("QUALITY OF LIFE")
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(.textTertiary)
                    .tracking(2.5)
                Spacer()
                Text("All dimensions")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textMuted)
            }
            .padding(.bottom, 28)

            // Arc visualisation
            ZStack {
                // Background arcs (tracks)
                ForEach(Array(arcs.enumerated()), id: \.offset) { i, arc in
                    Circle()
                        .stroke(Color.borderColor.opacity(0.3), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .frame(width: arc.radius * 2, height: arc.radius * 2)
                }

                // Progress arcs
                ForEach(Array(arcs.enumerated()), id: \.offset) { i, arc in
                    let value = metrics[keyPath: arc.kp]
                    let progress = appeared ? CGFloat(value) / 100 : 0

                    // Glow
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(arc.color.opacity(0.3), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .frame(width: arc.radius * 2, height: arc.radius * 2)
                        .rotationEffect(.degrees(-90))
                        .blur(radius: 6)

                    // Main arc
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(arc.color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .frame(width: arc.radius * 2, height: arc.radius * 2)
                        .rotationEffect(.degrees(-90))
                        .shadow(color: arc.color.opacity(0.4), radius: 6)
                        .animation(.spring(response: 1.4, dampingFraction: 0.68).delay(0.3 + Double(i) * 0.12), value: appeared)
                }

                // Center score
                VStack(spacing: 3) {
                    Text("\(metrics.qualityOfLifeScore)")
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .foregroundColor(.textPrimary)
                    Text("QOL Score")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.textTertiary)
                        .tracking(1)
                }
            }
            .frame(height: 220)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 28)

            // Legend grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(Array(arcs.enumerated()), id: \.offset) { _, arc in
                    let val = metrics[keyPath: arc.kp]
                    ArcLegendItem(label: arc.label, value: val, color: arc.color)
                }
            }
        }
        .padding(24)
        .background(Color.surface)
        .cornerRadius(24)
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.borderColor.opacity(0.5), lineWidth: 1))
        .shadow(color: .black.opacity(0.07), radius: 20, y: 8)
        .onAppear { appeared = true }
    }
}

struct ArcLegendItem: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.5), radius: 3)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.textSecondary)
            Spacer()
            Text("\(value)")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.surfaceElevated)
        .cornerRadius(12)
    }
}

// MARK: - AI Life Analysis Card

struct AILifeAnalysisCard: View {
    let metrics: LifestyleMetrics
    @State private var appeared = false
    @State private var expanded = false

    private var rows: [(icon: String, label: String, current: String, optimal: String, status: InsightStatus)] {[
        ("moon.zzz.fill", "Sleep", String(format: "%.1fh avg", metrics.sleepAverage), String(format: "%.0fh target", metrics.sleepTarget), metrics.sleepAverage >= metrics.sleepTarget ? .excellent : metrics.sleepAverage >= metrics.sleepTarget * 0.9 ? .good : .warning),
        ("fork.knife", "Nutrition", "\(Int(metrics.nutritionQuality * 100))% whole foods", "85%+", metrics.nutritionQuality >= 0.85 ? .excellent : metrics.nutritionQuality >= 0.75 ? .good : .warning),
        ("figure.walk", "Movement", "\(metrics.dailySteps.formatted()) steps", "10,000 steps", metrics.dailySteps >= 10000 ? .excellent : metrics.dailySteps >= 8000 ? .good : .warning),
        ("brain.fill", "Stress", metrics.stressLevel.rawValue, "Low", metrics.stressLevel == .low ? .excellent : metrics.stressLevel == .medium ? .warning : .poor),
    ]}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.ember.opacity(0.15)).frame(width: 46, height: 46)
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(LinearGradient.ember)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("AI Life Analysis")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Text("Behavioral pattern analysis")
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                }
                Spacer()
            }
            .padding(.bottom, 20)

            // Insight rows with left accent bar
            VStack(spacing: 12) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    AnalysisInsightRow(
                        icon: row.icon, label: row.label,
                        current: row.current, optimal: row.optimal, status: row.status
                    )
                    .opacity(appeared ? 1 : 0)
                    .offset(x: appeared ? 0 : -20)
                    .animation(.spring(response: 0.5, dampingFraction: 0.76).delay(0.1 + Double(i) * 0.07), value: appeared)
                }
            }
            .padding(.bottom, 20)

            // Full analysis CTA
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { expanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: "arrow.right.circle.fill").font(.system(size: 14))
                    Text("View Full Analysis").font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .foregroundColor(.ember)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(Color.ember.opacity(0.1))
                .cornerRadius(12)
            }
        }
        .padding(22)
        .background(Color.surface)
        .cornerRadius(22)
        .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
        .onAppear { appeared = true }
    }
}

enum InsightStatus {
    case excellent, good, warning, poor
    var color: Color {
        switch self { case .excellent: return .success; case .good: return .steel; case .warning: return .warning; case .poor: return .danger }
    }
}

struct AnalysisInsightRow: View {
    let icon: String
    let label: String
    let current: String
    let optimal: String
    let status: InsightStatus

    var body: some View {
        HStack(spacing: 14) {
            // Colored left accent + icon
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(status.color)
                    .frame(width: 3, height: 40)
                    .padding(.trailing, 10)

                ZStack {
                    Circle().fill(status.color.opacity(0.12)).frame(width: 38, height: 38)
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundColor(status.color)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textPrimary)
                HStack(spacing: 5) {
                    Text(current)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textSecondary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9))
                        .foregroundColor(.textMuted)
                    Text(optimal)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textTertiary)
                }
            }

            Spacer()

            // Status dot with glow
            Circle()
                .fill(status.color)
                .frame(width: 10, height: 10)
                .shadow(color: status.color.opacity(0.6), radius: 5)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.surfaceElevated)
        .cornerRadius(14)
    }
}

// MARK: - AI Recommendations Card (glowing accent borders)

struct AIRecommendationsCard: View {
    let recommendations: [AIRecommendation]
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.ember)
                Text("AI Recommendations")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("\(recommendations.count) active")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.ember)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.ember.opacity(0.12))
                    .cornerRadius(8)
            }

            if recommendations.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44)).foregroundColor(.success.opacity(0.6))
                    Text("You're doing great! No new recommendations.")
                        .font(.system(size: 14)).foregroundColor(.textSecondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 24)
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(recommendations.enumerated()), id: \.element.id) { i, rec in
                        RecommendationCard(recommendation: rec)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 16)
                            .animation(.spring(response: 0.5, dampingFraction: 0.76).delay(0.05 + Double(i) * 0.08), value: appeared)
                    }
                }
            }
        }
        .padding(22)
        .background(Color.surface)
        .cornerRadius(22)
        .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
        .onAppear { appeared = true }
    }
}

struct RecommendationCard: View {
    let recommendation: AIRecommendation
    @State private var expanded = false

    var body: some View {
        HStack(spacing: 0) {
            // Glowing left border — the signature visual
            RoundedRectangle(cornerRadius: 3)
                .fill(recommendation.impact.color)
                .frame(width: 4)
                .shadow(color: recommendation.impact.color.opacity(0.7), radius: 6)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) { expanded.toggle() }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            HStack(spacing: 6) {
                                Image(systemName: recommendation.category.icon)
                                    .font(.system(size: 11))
                                    .foregroundColor(recommendation.impact.color)
                                Text(recommendation.category.rawValue.uppercased())
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(recommendation.impact.color)
                                    .tracking(1.5)
                            }
                            Spacer()
                            HStack(spacing: 4) {
                                Text(recommendation.impact.rawValue)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(recommendation.impact.color)
                                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.textMuted)
                            }
                        }

                        Text(recommendation.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if expanded {
                            Text(recommendation.description)
                                .font(.system(size: 13))
                                .foregroundColor(.textSecondary)
                                .lineSpacing(4)
                                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                        }
                    }
                    .padding(14)
                }
                .buttonStyle(.plain)
            }
        }
        .background(recommendation.impact.color.opacity(0.05))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(recommendation.impact.color.opacity(0.18), lineWidth: 1)
        )
    }
}

// MARK: - Optimization Goals Card (fixed animate-on-appear)

struct OptimizationGoalsCard: View {
    @State private var appeared = false

    private let goals: [(title: String, progress: Double, current: String, target: String, color: Color)] = [
        ("Deep sleep → 90+ min", 0.75, "82 min avg", "90 min",   Color(hex: "A855F7")),
        ("Reduce stress markers", 0.60, "Medium",     "Low",      .warning),
        ("Daily protein 180g",    0.85, "150g avg",   "180g",     .ember),
        ("Morning routine 7/7",   0.50, "3/7 days",   "7/7 days", .steel),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Optimization Goals")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.textPrimary)

            VStack(spacing: 12) {
                ForEach(Array(goals.enumerated()), id: \.offset) { i, goal in
                    GoalProgressItem(
                        title: goal.title, progress: goal.progress,
                        current: goal.current, target: goal.target,
                        color: goal.color, appeared: appeared, index: i
                    )
                }
            }
        }
        .padding(22)
        .background(Color.surface)
        .cornerRadius(22)
        .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
        .onAppear { appeared = true }
    }
}

struct GoalProgressItem: View {
    let title: String
    let progress: Double
    let current: String
    let target: String
    let color: Color
    let appeared: Bool
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(color)
            }
            HStack(spacing: 6) {
                Text(current)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.textSecondary)
                Image(systemName: "arrow.right")
                    .font(.system(size: 10)).foregroundColor(.textMuted)
                Text(target)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(color)
            }
            // Responsive animated progress bar (fixed hardcoded-points bug)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.borderColor.opacity(0.3))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(
                            colors: [color, color.opacity(0.7)],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: appeared ? geo.size.width * CGFloat(progress) : 0)
                        .animation(.spring(response: 1.2, dampingFraction: 0.7).delay(0.4 + Double(index) * 0.1), value: appeared)
                }
            }
            .frame(height: 6)
        }
        .padding(14)
        .background(Color.surfaceElevated)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.15), lineWidth: 1))
    }
}

// MARK: - Daily Nutrition View (Macro Rings flagship)

struct DailyNutritionView: View {
    var body: some View {
        VStack(spacing: 20) {
            AINutritionCoachCard()
            MacroRingsCard()
            MealLogCard()
            AIMealSuggestionsCard()
            WaterIntakeCard()
            MicronutrientsCard()
        }
    }
}

// MARK: - Macro Rings Card (concentric donut rings)

struct MacroRingsCard: View {
    @State private var appeared = false

    private struct Macro {
        let label: String; let current: Int; let target: Int
        let color: Color; let unit: String; let radius: CGFloat
    }
    private let macros: [Macro] = [
        Macro(label: "Carbs",   current: 220, target: 280, color: .steel,              unit: "g", radius: 92),
        Macro(label: "Protein", current: 145, target: 180, color: .ember,              unit: "g", radius: 68),
        Macro(label: "Fats",    current: 58,  target: 70,  color: Color(hex: "FFB84D"), unit: "g", radius: 44),
    ]
    private let totalCal = 2140
    private let targetCal = 2600

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("TODAY'S MACROS")
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(.textTertiary)
                    .tracking(2.5)
                Spacer()
                Text("\(targetCal - totalCal) cal left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.ember)
            }
            .padding(.bottom, 28)

            // Three concentric macro rings
            ZStack {
                ForEach(Array(macros.enumerated()), id: \.offset) { i, macro in
                    let progress = appeared ? CGFloat(macro.current) / CGFloat(macro.target) : 0

                    // Track
                    Circle()
                        .stroke(Color.borderColor.opacity(0.3), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .frame(width: macro.radius * 2, height: macro.radius * 2)

                    // Glow
                    Circle()
                        .trim(from: 0, to: min(progress, 1))
                        .stroke(macro.color.opacity(0.3), style: StrokeStyle(lineWidth: 16, lineCap: .round))
                        .frame(width: macro.radius * 2, height: macro.radius * 2)
                        .rotationEffect(.degrees(-90))
                        .blur(radius: 7)

                    // Main
                    Circle()
                        .trim(from: 0, to: min(progress, 1))
                        .stroke(macro.color, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .frame(width: macro.radius * 2, height: macro.radius * 2)
                        .rotationEffect(.degrees(-90))
                        .shadow(color: macro.color.opacity(0.45), radius: 8)
                        .animation(.spring(response: 1.3, dampingFraction: 0.68).delay(0.25 + Double(i) * 0.15), value: appeared)
                }

                // Center: calorie total
                VStack(spacing: 2) {
                    Text("\(totalCal)")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundColor(.textPrimary)
                    Text("of \(targetCal) kcal")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.textTertiary)
                }
            }
            .frame(height: 210)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 28)

            // Macro legend — responsive bars using GeometryReader (fixed hardcoded bug)
            VStack(spacing: 14) {
                ForEach(Array(macros.enumerated()), id: \.offset) { _, macro in
                    HStack(spacing: 12) {
                        Circle().fill(macro.color).frame(width: 8, height: 8)
                            .shadow(color: macro.color.opacity(0.5), radius: 3)
                        Text(macro.label)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.textSecondary)
                            .frame(width: 52, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.borderColor.opacity(0.3))
                                Capsule().fill(macro.color.opacity(0.8))
                                    .frame(width: appeared ? geo.size.width * CGFloat(macro.current) / CGFloat(macro.target) : 0)
                                    .animation(.spring(response: 1.1, dampingFraction: 0.7).delay(0.5), value: appeared)
                            }
                        }
                        .frame(height: 6)
                        Text("\(macro.current)\(macro.unit)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.textPrimary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
        }
        .padding(24)
        .background(Color.surface)
        .cornerRadius(24)
        .shadow(color: .black.opacity(0.07), radius: 20, y: 8)
        .onAppear { appeared = true }
    }
}

// MARK: - AI Nutrition Coach Card (fixed sparkle animation)

struct AINutritionCoachCard: View {
    @State private var isAnalyzing = true
    @State private var tipIndex = 0
    @State private var sparkleScale: Double = 1.0

    private let tips: [(icon: String, color: Color, headline: String, body: String)] = [
        ("bolt.fill",       .ember,              "Protein gap — act before dinner",  "You're 35g short with one meal left. Add chicken or Greek yogurt to hit 180g."),
        ("drop.fill",       .steel,              "Hydration is on track",             "6 of 8 glasses today. Good hydration improves protein synthesis by ~12%."),
        ("moon.stars.fill", Color(hex: "A855F7"), "Carbs timed well",                 "Post-workout carbs were within 30 min. Glycogen replenishment is optimal."),
    ]

    var tip: (icon: String, color: Color, headline: String, body: String) { tips[tipIndex % tips.count] }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.ember.opacity(0.15)).frame(width: 40, height: 40)
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.ember)
                        // Fixed: single animation, not chained state changes
                        .scaleEffect(isAnalyzing ? sparkleScale : 1.0)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Nutrition Coach").font(.system(size: 16, weight: .bold)).foregroundColor(.textPrimary)
                    Text(isAnalyzing ? "Analyzing today's intake…" : "Insight ready")
                        .font(.system(size: 11, weight: .medium)).foregroundColor(.textTertiary)
                }
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { tipIndex += 1 }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.textTertiary)
                        .frame(width: 32, height: 32)
                        .background(Color.surfaceElevated)
                        .clipShape(Circle())
                }
            }

            if !isAnalyzing {
                Divider().background(Color.borderColor)

                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: tip.icon)
                        .font(.system(size: 22))
                        .foregroundColor(tip.color)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(tip.headline)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.textPrimary)
                        Text(tip.body)
                            .font(.system(size: 13))
                            .foregroundColor(.textSecondary)
                            .lineSpacing(4)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .id(tipIndex)

                // Macro snapshot chips
                HStack(spacing: 0) {
                    ForEach([
                        ("Protein", 145, 180, Color.ember),
                        ("Carbs",   220, 280, Color.steel),
                        ("Fats",    58,  70,  Color(hex: "FFB84D")),
                        ("Cal",    2140, 2600, Color(hex: "A855F7")),
                    ], id: \.0) { label, filled, total, color in
                        VStack(spacing: 3) {
                            Text(label)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.textTertiary)
                            Text("\(Int(Double(filled) / Double(total) * 100))%")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(color)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(color.opacity(0.08))
                        if label != "Cal" {
                            Divider().frame(height: 28).background(Color.borderColor)
                        }
                    }
                }
                .cornerRadius(12)
                .transition(.opacity)
            }
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.ember.opacity(0.2), lineWidth: 1))
        .onAppear {
            // Fixed: one clean pulsing animation, sparkleOpacity reset in same animation block
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                sparkleScale = 1.25
            }
            Task {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                withAnimation(.easeOut(duration: 0.4)) {
                    isAnalyzing = false
                    sparkleScale = 1.0
                }
            }
        }
    }
}

// MARK: - AI Meal Suggestions Card

struct AIMealSuggestionsCard: View {
    @State private var setIndex = 0

    private let sets: [[AIMealSuggestion]] = [
        [
            AIMealSuggestion(name: "Grilled Chicken + Rice",  cal: 480, protein: 42, carbs: 52, fat: 8,  reason: "Fills your 35g protein gap"),
            AIMealSuggestion(name: "Greek Yogurt Parfait",    cal: 320, protein: 28, carbs: 38, fat: 6,  reason: "Light, hits protein without blowing calories"),
            AIMealSuggestion(name: "Tuna Avocado Bowl",       cal: 410, protein: 38, carbs: 24, fat: 18, reason: "High protein + healthy fats for recovery"),
        ],
        [
            AIMealSuggestion(name: "Egg White Omelette",      cal: 290, protein: 32, carbs: 10, fat: 9,  reason: "Clean protein, minimal remaining calories"),
            AIMealSuggestion(name: "Salmon + Sweet Potato",   cal: 520, protein: 36, carbs: 48, fat: 14, reason: "Omega-3s accelerate recovery"),
            AIMealSuggestion(name: "Cottage Cheese & Fruit",  cal: 240, protein: 26, carbs: 28, fat: 4,  reason: "Casein protein — ideal before bed"),
        ],
    ]

    var suggestions: [AIMealSuggestion] { sets[setIndex % sets.count] }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "fork.knife.circle.fill").font(.system(size: 20)).foregroundColor(.steel)
                    Text("AI Meal Suggestions").font(.system(size: 18, weight: .bold)).foregroundColor(.textPrimary)
                }
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { setIndex += 1 }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles").font(.system(size: 10))
                        Text("Regenerate").font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.steel)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.steel.opacity(0.12))
                    .cornerRadius(8)
                }
            }

            Text("Based on 460 cal · 35g protein remaining")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.textTertiary)

            VStack(spacing: 10) {
                ForEach(suggestions) { suggestion in
                    AIMealRow(suggestion: suggestion)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                        .id("\(setIndex)-\(suggestion.id)")
                }
            }
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.05), radius: 14, y: 5)
    }
}

struct AIMealSuggestion: Identifiable {
    let id = UUID()
    let name: String
    let cal: Int
    let protein: Int
    let carbs: Int
    let fat: Int
    let reason: String
}

struct AIMealRow: View {
    let suggestion: AIMealSuggestion
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) { expanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(suggestion.name).font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
                        Text(suggestion.reason).font(.system(size: 11)).foregroundColor(.textTertiary).lineLimit(1)
                    }
                    Spacer()
                    Text("\(suggestion.cal) cal")
                        .font(.system(size: 13, weight: .bold)).foregroundColor(.ember)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold)).foregroundColor(.textMuted)
                }
                .padding(13)
            }
            .buttonStyle(.plain)

            if expanded {
                HStack(spacing: 0) {
                    InlineMacroChip(label: "P", value: "\(suggestion.protein)g", color: .ember)
                    InlineMacroChip(label: "C", value: "\(suggestion.carbs)g",   color: .steel)
                    InlineMacroChip(label: "F", value: "\(suggestion.fat)g",     color: Color(hex: "FFB84D"))
                }
                .padding(.horizontal, 13).padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.surfaceElevated)
        .cornerRadius(12)
    }
}

struct InlineMacroChip: View {
    let label: String; let value: String; let color: Color
    var body: some View {
        VStack(spacing: 3) {
            Text(label).font(.system(size: 10, weight: .bold)).foregroundColor(.textTertiary)
            Text(value).font(.system(size: 13, weight: .bold)).foregroundColor(color)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(color.opacity(0.09)).cornerRadius(8)
    }
}

// MARK: - Meal Log Card

struct MealLogCard: View {
    private let meals: [(name: String, time: String, cal: Int, icon: String)] = [
        ("Breakfast", "7:30 AM",  520, "sunrise.fill"),
        ("Lunch",     "12:45 PM", 680, "sun.max.fill"),
        ("Snack",     "3:15 PM",  240, "leaf.fill"),
        ("Dinner",    "6:30 PM",  700, "moon.fill"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Meal Log").font(.system(size: 18, weight: .bold)).foregroundColor(.textPrimary)
                Spacer()
                Button {
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                        Text("Add").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.ember)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.ember.opacity(0.1))
                    .cornerRadius(8)
                }
            }

            VStack(spacing: 10) {
                ForEach(meals, id: \.name) { meal in
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(Color.surface).frame(width: 38, height: 38)
                            Image(systemName: meal.icon)
                                .font(.system(size: 15)).foregroundColor(.ember)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(meal.name).font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
                            Text(meal.time).font(.system(size: 12)).foregroundColor(.textTertiary)
                        }
                        Spacer()
                        Text("\(meal.cal) cal")
                            .font(.system(size: 13, weight: .medium)).foregroundColor(.textSecondary)
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18)).foregroundColor(.success)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color.surfaceElevated).cornerRadius(12)
                }
            }
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.05), radius: 14, y: 5)
    }
}

// MARK: - Water Intake Card (HealthKit Integration)

struct WaterIntakeCard: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var vm = LifestyleViewModel()
    @State private var consumed: Int
    let target = 8
    
    init() {
        // Initialize from HealthKit data
        _consumed = State(initialValue: 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 16)).foregroundColor(Color(hex: "4A9EFF"))
                    Text("Water Intake").font(.system(size: 18, weight: .bold)).foregroundColor(.textPrimary)
                }
                Spacer()
                Text("\(consumed)/\(target)")
                    .font(.system(size: 14, weight: .bold)).foregroundColor(Color(hex: "4A9EFF"))
            }

            HStack(spacing: 8) {
                ForEach(0..<target, id: \.self) { i in
                    Image(systemName: i < consumed ? "drop.fill" : "drop")
                        .foregroundColor(i < consumed ? Color(hex: "4A9EFF") : Color.borderColor)
                        .font(.system(size: 22))
                        .scaleEffect(i < consumed ? 1 : 0.85)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6).delay(Double(i) * 0.03), value: consumed)
                }
            }

            Button {
                guard consumed < target else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { consumed += 1 }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                
                // Log to HealthKit
                Task {
                    await vm.logWater(glasses: 1)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill").font(.system(size: 15))
                    Text("Log a glass").font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text("Syncs with HealthKit")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(hex: "4A9EFF").opacity(0.7))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color(hex: "4A9EFF").opacity(0.1))
                        .cornerRadius(4)
                }
                .foregroundColor(Color(hex: "4A9EFF"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(hex: "4A9EFF").opacity(0.1))
                .cornerRadius(12)
            }
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.05), radius: 14, y: 5)
        .task {
            // Load current water intake from HealthKit
            if let stats = vm.healthStats {
                consumed = Int(stats.water)
            }
        }
    }
}

// MARK: - Micronutrients Card (fixed: now animates on appear)

struct MicronutrientsCard: View {
    @State private var appeared = false

    private let micros: [(label: String, current: Double, target: Double, unit: String, color: Color)] = [
        ("Vitamin D",  800,  1000, "IU", .warning),
        ("Omega-3",    1.2,  2.0,  "g",  .steel),
        ("Magnesium",  320,  400,  "mg", .success),
        ("Iron",       14,   18,   "mg", .ember),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Key Micronutrients")
                .font(.system(size: 18, weight: .bold)).foregroundColor(.textPrimary)

            VStack(spacing: 14) {
                ForEach(Array(micros.enumerated()), id: \.offset) { i, m in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(m.label).font(.system(size: 13, weight: .medium)).foregroundColor(.textSecondary)
                            Spacer()
                            Text(m.current < 10
                                 ? String(format: "%.1f / %.1f %@", m.current, m.target, m.unit)
                                 : "\(Int(m.current)) / \(Int(m.target)) \(m.unit)")
                                .font(.system(size: 13, weight: .semibold)).foregroundColor(.textPrimary)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.borderColor.opacity(0.3))
                                Capsule().fill(m.color)
                                    .frame(width: appeared ? geo.size.width * CGFloat(min(m.current / m.target, 1)) : 0)
                                    // Fixed: now animated
                                    .animation(.spring(response: 1.0, dampingFraction: 0.7).delay(0.3 + Double(i) * 0.1), value: appeared)
                            }
                        }
                        .frame(height: 6)
                    }
                }
            }
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.05), radius: 14, y: 5)
        .onAppear { appeared = true }
    }
}

// MARK: - Restaurant Nutrition Database

struct NutritionDatabaseView: View {
    @State private var selectedCategory: RestaurantCategory = .all
    @State private var searchText = ""
    @State private var selectedRestaurant: Restaurant?
    @State private var appeared = false

    var filtered: [Restaurant] {
        let base = selectedCategory == .all ? popularRestaurants : popularRestaurants.filter { $0.category == selectedCategory }
        if searchText.isEmpty { return base }
        return base.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.items.contains { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            // Search
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundColor(.textTertiary)
                TextField("Search restaurants or items…", text: $searchText)
                    .foregroundColor(.textPrimary)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.textMuted)
                    }
                }
            }
            .padding(13)
            .background(Color.surface)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.borderColor.opacity(0.5), lineWidth: 1))

            // Category pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(RestaurantCategory.allCases, id: \.self) { cat in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selectedCategory = cat }
                        } label: {
                            Text(cat.rawValue)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(selectedCategory == cat ? .white : .textTertiary)
                                .padding(.horizontal, 16).padding(.vertical, 9)
                                .background(
                                    selectedCategory == cat
                                        ? Color.ember : Color.surface.opacity(0.7)
                                )
                                .cornerRadius(20)
                        }
                    }
                }
            }

            AIBestPicksSection()

            // Restaurant grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                ForEach(Array(filtered.enumerated()), id: \.element.id) { i, restaurant in
                    Button { selectedRestaurant = restaurant } label: {
                        RestaurantCard(restaurant: restaurant)
                    }
                    .buttonStyle(.plain)
                    .opacity(appeared ? 1 : 0)
                    .scaleEffect(appeared ? 1 : 0.9)
                    .animation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.05 + Double(i) * 0.04), value: appeared)
                }
            }
        }
        .sheet(item: $selectedRestaurant) { r in
            RestaurantMenuSheet(restaurant: r)
        }
        .onAppear { appeared = true }
    }
}

struct RestaurantCard: View {
    let restaurant: Restaurant

    private var avgProteinEfficiency: Int {
        let scores = restaurant.items.map { $0.proteinEfficiency }
        return scores.isEmpty ? 0 : scores.reduce(0, +) / scores.count
    }

    private var efficiencyColor: Color {
        switch avgProteinEfficiency {
        case 100...: return .success
        case 60..<100: return .warning
        default: return .danger
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(restaurant.logo)
                .font(.system(size: 44))
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)

            Text(restaurant.name)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            HStack(spacing: 6) {
                Text("\(restaurant.items.count) items")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textTertiary)
                Circle().fill(Color.borderColor).frame(width: 3, height: 3)
                // Protein efficiency rating
                Text(NutritionRating(proteinEfficiency: avgProteinEfficiency).label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(efficiencyColor)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color.surface)
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.borderColor.opacity(0.4), lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }
}

private extension NutritionRating {
    init(proteinEfficiency: Int) {
        switch proteinEfficiency {
        case 100...: self = .excellent
        case 60..<100: self = .good
        case 30..<60: self = .fair
        default: self = .poor
        }
    }
}

// MARK: - Restaurant Menu Sheet (fixed: NavigationStack replacing deprecated NavigationView)

struct RestaurantMenuSheet: View {
    let restaurant: Restaurant
    @State private var sortBy: MenuSort = .calories
    @Environment(\.dismiss) private var dismiss

    enum MenuSort: String, CaseIterable {
        case calories = "Calories", protein = "Protein", name = "Name", healthy = "Healthiest"
    }

    var sorted: [MenuItem] {
        switch sortBy {
        case .calories: return restaurant.items.sorted { $0.calories < $1.calories }
        case .protein:  return restaurant.items.sorted { $0.protein > $1.protein }
        case .name:     return restaurant.items.sorted { $0.name < $1.name }
        case .healthy:  return restaurant.items.sorted { $0.proteinEfficiency > $1.proteinEfficiency }
        }
    }

    var body: some View {
        // Fixed: NavigationView → NavigationStack
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Hero header
                    HStack(spacing: 16) {
                        Text(restaurant.logo).font(.system(size: 48))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(restaurant.name)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.textPrimary)
                            Text("\(restaurant.items.count) menu items")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(20)
                    .background(Color.surface)
                    .overlay(Rectangle().fill(Color.borderColor.opacity(0.4)).frame(height: 1), alignment: .bottom)

                    Picker("Sort", selection: $sortBy) {
                        ForEach(MenuSort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20).padding(.vertical, 14)

                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 12) {
                            ForEach(sorted) { item in MenuItemCard(item: item) }
                        }
                        .padding(.horizontal, 20).padding(.bottom, 40)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.foregroundColor(.ember).fontWeight(.semibold)
                }
            }
        }
    }
}

struct MenuItemCard: View {
    let item: MenuItem
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.system(size: 15, weight: .semibold)).foregroundColor(.textPrimary)
                    Text(item.serving)
                        .font(.system(size: 11, weight: .medium)).foregroundColor(.textTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    if item.isHealthy {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 13)).foregroundColor(.success)
                    }
                    Text(item.nutritionalRating.label)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(item.nutritionalRating.color)
                }
            }

            Divider().background(Color.borderColor.opacity(0.4))

            HStack(spacing: 10) {
                MacroChip(label: "Cal",  value: "\(item.calories)",  color: .ember)
                MacroChip(label: "Prot", value: "\(item.protein)g",  color: .steel)
                MacroChip(label: "Carb", value: "\(item.carbs)g",    color: Color(hex: "FFB84D"))
                MacroChip(label: "Fat",  value: "\(item.fat)g",      color: Color(hex: "A855F7"))
            }
        }
        .padding(16)
        .background(Color.surface)
        .cornerRadius(14)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75).delay(0.05)) { appeared = true }
        }
    }
}

struct MacroChip: View {
    let label: String; let value: String; let color: Color
    var body: some View {
        VStack(spacing: 4) {
            Text(label).font(.system(size: 9, weight: .bold)).foregroundColor(.textTertiary)
            Text(value).font(.system(size: 13, weight: .bold)).foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .cornerRadius(9)
    }
}

// MARK: - AI Best Picks

struct AIBestPicksSection: View {
    private let picks: [AIRestaurantPick] = [
        AIRestaurantPick(restaurant: "Chipotle",   emoji: "🌯", item: "Chicken Bowl (no rice)", cal: 450, protein: 43, reason: "Best protein-to-calorie ratio today"),
        AIRestaurantPick(restaurant: "Chick-fil-A", emoji: "🐔", item: "Grilled Nuggets 12pc",  cal: 200, protein: 38, reason: "Leanest option, fits your 460 cal budget"),
        AIRestaurantPick(restaurant: "Subway",      emoji: "🥖", item: "Rotisserie Chicken 6\"", cal: 350, protein: 30, reason: "Hits protein gap with room for sides"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").font(.system(size: 14, weight: .semibold)).foregroundColor(.ember)
                Text("AI Best Picks for Today").font(.system(size: 15, weight: .bold)).foregroundColor(.textPrimary)
                Spacer()
                Text("35g protein left").font(.system(size: 11, weight: .medium)).foregroundColor(.textTertiary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(picks) { pick in
                        AIPickCard(pick: pick)
                    }
                }
            }
        }
        .padding(16)
        .background(LinearGradient(colors: [Color.ember.opacity(0.07), Color.surface], startPoint: .topLeading, endPoint: .bottomTrailing))
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.ember.opacity(0.18), lineWidth: 1))
    }
}

struct AIRestaurantPick: Identifiable {
    let id = UUID()
    let restaurant: String; let emoji: String; let item: String
    let cal: Int; let protein: Int; let reason: String
}

struct AIPickCard: View {
    let pick: AIRestaurantPick

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(pick.emoji).font(.system(size: 24))
                VStack(alignment: .leading, spacing: 1) {
                    Text(pick.restaurant).font(.system(size: 10, weight: .bold)).foregroundColor(.textTertiary)
                    Text(pick.item).font(.system(size: 13, weight: .semibold)).foregroundColor(.textPrimary).lineLimit(2)
                }
            }
            HStack(spacing: 8) {
                Label("\(pick.cal) cal", systemImage: "flame.fill").font(.system(size: 11, weight: .semibold)).foregroundColor(.ember)
                Label("\(pick.protein)g P", systemImage: "bolt.fill").font(.system(size: 11, weight: .semibold)).foregroundColor(.steel)
            }
            Text(pick.reason).font(.system(size: 10, weight: .medium)).foregroundColor(.textTertiary).lineLimit(2)
        }
        .frame(width: 180)
        .padding(14)
        .background(Color.surface)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.ember.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 3)
    }
}

// MARK: - Wellbeing View

struct WellbeingView: View {
    var body: some View {
        VStack(spacing: 20) {
            DailyHabitsCard()
            MindfulnessCard()
            StressManagementCard()
            SleepOptimizationCard()
        }
    }
}

struct DailyHabitsCard: View {
    @State private var habits: [(name: String, done: Bool)] = [
        ("Morning sunlight (10 min)", true),
        ("Meditation (5 min)",        true),
        ("Read (20 min)",             false),
        ("Mobility work (10 min)",    true),
        ("Cold shower",               false),
        ("Journaling",                false),
    ]

    var completed: Int { habits.filter { $0.done }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Daily Habits")
                    .font(.system(size: 18, weight: .bold)).foregroundColor(.textPrimary)
                Spacer()
                Text("\(completed)/\(habits.count)")
                    .font(.system(size: 13, weight: .bold)).foregroundColor(.ember)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.ember.opacity(0.12)).cornerRadius(8)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.borderColor.opacity(0.3))
                    Capsule().fill(LinearGradient(colors: [.ember, .ember.opacity(0.7)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(completed) / CGFloat(habits.count))
                        .animation(.spring(response: 0.6, dampingFraction: 0.72), value: completed)
                }
            }
            .frame(height: 6)
            .padding(.bottom, 4)

            VStack(spacing: 2) {
                ForEach(Array(habits.enumerated()), id: \.offset) { i, habit in
                    HabitRow(name: habit.name, isDone: habit.done) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
                            habits[i].done.toggle()
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
            }

            // Streak
            HStack(spacing: 8) {
                Image(systemName: "flame.fill").foregroundColor(.ember)
                Text("7-day streak").font(.system(size: 15, weight: .bold)).foregroundColor(.textPrimary)
                Spacer()
                Text("Keep it up 🔥").font(.system(size: 13)).foregroundColor(.textSecondary)
            }
            .padding(14)
            .background(Color.ember.opacity(0.08))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.ember.opacity(0.2), lineWidth: 1))
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
    }
}

struct HabitRow: View {
    let name: String
    let isDone: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(isDone ? Color.ember : Color.borderColor, lineWidth: 1.5)
                        .frame(width: 24, height: 24)
                    if isDone {
                        Circle().fill(Color.ember).frame(width: 24, height: 24)
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundColor(.white)
                    }
                }
                Text(name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isDone ? .textTertiary : .textPrimary)
                    .strikethrough(isDone, color: .textTertiary)
                Spacer()
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}

struct MindfulnessCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Mindfulness").font(.system(size: 18, weight: .bold)).foregroundColor(.textPrimary)

            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("5 min").font(.system(size: 26, weight: .bold)).foregroundColor(.textPrimary)
                    Text("Today").font(.system(size: 12, weight: .medium)).foregroundColor(.textSecondary)
                }
                .frame(maxWidth: .infinity)
                Divider().frame(height: 40).background(Color.borderColor)
                VStack(spacing: 4) {
                    Text("42 min").font(.system(size: 26, weight: .bold)).foregroundColor(.ember)
                    Text("This week").font(.system(size: 12, weight: .medium)).foregroundColor(.textSecondary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 8)

            Button {} label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill").font(.system(size: 14))
                    Text("Start Meditation").font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(LinearGradient.ember)
                .cornerRadius(14)
                .shadow(color: Color.ember.opacity(0.35), radius: 10, y: 4)
            }
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
    }
}

struct StressManagementCard: View {
    @State private var selectedLevel = 1  // 0=low, 1=medium, 2=high

    private let levels: [(emoji: String, label: String, color: Color)] = [
        ("😌", "Low",    .success),
        ("😐", "Medium", .warning),
        ("😰", "High",   .danger),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Stress Management").font(.system(size: 18, weight: .bold)).foregroundColor(.textPrimary)

            HStack(spacing: 12) {
                ForEach(Array(levels.enumerated()), id: \.offset) { i, level in
                    Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selectedLevel = i } } label: {
                        VStack(spacing: 8) {
                            Text(level.emoji).font(.system(size: 30))
                            Text(level.label)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(selectedLevel == i ? level.color : .textSecondary)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(selectedLevel == i ? level.color.opacity(0.12) : Color.surfaceElevated)
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(selectedLevel == i ? level.color : Color.borderColor.opacity(0.4), lineWidth: selectedLevel == i ? 1.5 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill").font(.system(size: 12)).foregroundColor(.warning)
                Text("Try: 5-minute box breathing or a short walk")
                    .font(.system(size: 13)).foregroundColor(.textSecondary).italic()
            }
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
    }
}

struct SleepOptimizationCard: View {
    private let tips: [(icon: String, tip: String, color: Color)] = [
        ("moon.fill",              "Aim for bed by 10 PM tonight",  .steel),
        ("iphone.slash",           "No screens 45 min before bed",  .warning),
        ("thermometer.medium",     "Keep room at 65–68°F",          .success),
        ("cup.and.saucer.fill",    "No caffeine after 2 PM",        .danger),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sleep Optimization").font(.system(size: 18, weight: .bold)).foregroundColor(.textPrimary)

            VStack(spacing: 10) {
                ForEach(tips, id: \.tip) { tip in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(tip.color.opacity(0.12)).frame(width: 36, height: 36)
                            Image(systemName: tip.icon).font(.system(size: 15)).foregroundColor(tip.color)
                        }
                        Text(tip.tip).font(.system(size: 13, weight: .medium)).foregroundColor(.textSecondary)
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.surfaceElevated).cornerRadius(12)
                }
            }
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
    }
}

// MARK: - AI Insights Modal (fixed: removed unused scrollOffset)

struct AIInsightsModal: View {
    @Binding var isPresented: Bool
    let recommendations: [AIRecommendation]

    private let insights: [LifestyleInsight] = [
        LifestyleInsight(title: "Your Productivity Window", insight: "You're most productive 9 AM–12 PM. Workouts scheduled here show 14% better performance vs evening sessions.", action: "Optimize schedule", color: .ember),
        LifestyleInsight(title: "Nutrition Consistency",    insight: "Protein targets hit 6/7 days. Carbs vary 180–320g daily — stabilizing at 250g improves training consistency.", action: "Adjust macros",     color: .steel),
        LifestyleInsight(title: "Sleep + Training Timing",  insight: "Training after 7 PM reduces deep sleep by 22 min on average. Morning or midday is strongly recommended.", action: "Reschedule",         color: Color(hex: "A855F7")),
        LifestyleInsight(title: "Weekly Stress Pattern",    insight: "HRV drops Monday and Thursday — correlating with work calendar density. Consider mobility work those days.", action: "Adjust weekly plan", color: .warning),
        LifestyleInsight(title: "Recovery Optimization",    insight: "Your body responds best to 48h recovery between heavy sessions. Current 72h splits may leave gains untapped.", action: "Update split",       color: .success),
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 0) {
                    // Drag handle
                    Capsule().fill(Color.textTertiary.opacity(0.5))
                        .frame(width: 36, height: 4).padding(.top, 14).padding(.bottom, 20)

                    HStack {
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles").font(.system(size: 22)).foregroundColor(.ember)
                            Text("AI Life Insights").font(.system(size: 24, weight: .bold)).foregroundColor(.textPrimary)
                        }
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 28)).foregroundColor(.textTertiary.opacity(0.7))
                        }
                    }
                    .padding(.horizontal, 20).padding(.bottom, 20)

                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 14) {
                            ForEach(insights) { insight in
                                AIInsightCard(insight: insight)
                            }
                        }
                        .padding(.horizontal, 20).padding(.bottom, 40)
                    }
                }
                .frame(maxHeight: UIScreen.main.bounds.height * 0.78)
                .background(Color.surface)
                .cornerRadius(28, corners: [.topLeft, .topRight])
            }
        }
    }

    private func dismiss() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { isPresented = false }
    }
}

struct LifestyleInsight: Identifiable {
    let id = UUID()
    let title: String; let insight: String; let action: String; let color: Color
}

struct AIInsightCard: View {
    let insight: LifestyleInsight
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle().fill(insight.color).frame(width: 8, height: 8)
                    .shadow(color: insight.color.opacity(0.6), radius: 4)
                Text(insight.title).font(.system(size: 16, weight: .bold)).foregroundColor(.textPrimary)
                Spacer()
            }
            Text(insight.insight)
                .font(.system(size: 13)).foregroundColor(.textSecondary).lineSpacing(4)
                .lineLimit(expanded ? nil : 3)
                .animation(.easeInOut(duration: 0.25), value: expanded)
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right.circle.fill").font(.system(size: 13))
                    Text(insight.action).font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(insight.color)
            }
        }
        .padding(16)
        .background(Color.surfaceElevated)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(insight.color.opacity(0.2), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) { expanded.toggle() }
        }
    }
}

// MARK: - Helpers

// Note: cornerRadius(_:corners:) extension is defined earlier in the file

// MARK: - Restaurant Data

let popularRestaurants: [Restaurant] = [
    Restaurant(name: "Raising Cane's", logo: "🍗", items: [
        MenuItem(name: "Box Combo (4 tenders)",    calories: 1220, protein: 56, carbs: 120, fat: 55, serving: "1 combo",   isHealthy: false),
        MenuItem(name: "Chicken Finger (1 piece)", calories: 130,  protein: 10, carbs: 8,   fat: 6,  serving: "1 tender",  isHealthy: true),
        MenuItem(name: "Crinkle Fries",            calories: 390,  protein: 5,  carbs: 50,  fat: 18, serving: "1 order",   isHealthy: false),
        MenuItem(name: "Coleslaw",                 calories: 170,  protein: 2,  carbs: 14,  fat: 13, serving: "1 order",   isHealthy: false),
    ], category: .chicken),

    Restaurant(name: "McDonald's", logo: "🍔", items: [
        MenuItem(name: "Egg McMuffin",             calories: 310, protein: 17, carbs: 30, fat: 13, serving: "1 sandwich", isHealthy: true),
        MenuItem(name: "Grilled Chicken Sandwich", calories: 380, protein: 37, carbs: 44, fat: 7,  serving: "1 sandwich", isHealthy: true),
        MenuItem(name: "Big Mac",                  calories: 550, protein: 25, carbs: 45, fat: 30, serving: "1 sandwich", isHealthy: false),
        MenuItem(name: "Medium Fries",             calories: 320, protein: 4,  carbs: 43, fat: 15, serving: "1 order",    isHealthy: false),
    ], category: .burgers),

    Restaurant(name: "Chick-fil-A", logo: "🐔", items: [
        MenuItem(name: "Grilled Nuggets (8-count)",    calories: 130, protein: 25, carbs: 1,  fat: 3,  serving: "8 pieces",  isHealthy: true),
        MenuItem(name: "Grilled Chicken Sandwich",     calories: 320, protein: 30, carbs: 42, fat: 6,  serving: "1 sandwich", isHealthy: true),
        MenuItem(name: "Cobb Salad (Grilled)",         calories: 390, protein: 40, carbs: 28, fat: 14, serving: "1 salad",    isHealthy: true),
        MenuItem(name: "Chicken Sandwich (fried)",     calories: 440, protein: 28, carbs: 41, fat: 19, serving: "1 sandwich", isHealthy: false),
    ], category: .chicken),

    Restaurant(name: "Chipotle", logo: "🌯", items: [
        MenuItem(name: "Chicken Bowl (no rice)",  calories: 320,  protein: 42, carbs: 21,  fat: 8,  serving: "1 bowl",    isHealthy: true),
        MenuItem(name: "Chicken Salad",           calories: 500,  protein: 44, carbs: 36,  fat: 21, serving: "1 salad",   isHealthy: true),
        MenuItem(name: "Chicken Burrito",         calories: 1025, protein: 65, carbs: 123, fat: 30, serving: "1 burrito", isHealthy: false),
        MenuItem(name: "Veggie Bowl",             calories: 430,  protein: 16, carbs: 68,  fat: 12, serving: "1 bowl",    isHealthy: true),
    ], category: .mexican),

    Restaurant(name: "Subway", logo: "🥖", items: [
        MenuItem(name: "6\" Turkey Breast",  calories: 280, protein: 18, carbs: 46, fat: 4,  serving: "6 inch", isHealthy: true),
        MenuItem(name: "Grilled Chicken Salad", calories: 130, protein: 19, carbs: 10, fat: 3, serving: "1 salad", isHealthy: true),
        MenuItem(name: "6\" Veggie Delite",  calories: 230, protein: 9,  carbs: 44, fat: 3,  serving: "6 inch", isHealthy: true),
        MenuItem(name: "6\" Spicy Italian",  calories: 480, protein: 21, carbs: 46, fat: 24, serving: "6 inch", isHealthy: false),
    ], category: .healthy),

    Restaurant(name: "Panera Bread", logo: "🥗", items: [
        MenuItem(name: "Green Goddess Cobb Salad", calories: 550, protein: 42, carbs: 23, fat: 33, serving: "1 salad", isHealthy: true),
        MenuItem(name: "Chicken Noodle Soup",      calories: 90,  protein: 7,  carbs: 10, fat: 3,  serving: "1 cup",  isHealthy: true),
        MenuItem(name: "Mediterranean Grain Bowl", calories: 430, protein: 16, carbs: 48, fat: 21, serving: "1 bowl", isHealthy: true),
        MenuItem(name: "Turkey Bravo Sandwich",    calories: 830, protein: 44, carbs: 76, fat: 37, serving: "1 item", isHealthy: false),
    ], category: .healthy),

    Restaurant(name: "Taco Bell", logo: "🌮", items: [
        MenuItem(name: "Chicken Power Bowl",  calories: 470, protein: 26, carbs: 50, fat: 19, serving: "1 bowl",  isHealthy: true),
        MenuItem(name: "Fresco Crunchy Taco", calories: 140, protein: 7,  carbs: 13, fat: 7,  serving: "1 taco",  isHealthy: true),
        MenuItem(name: "Crunchwrap Supreme",  calories: 530, protein: 16, carbs: 71, fat: 21, serving: "1 item",  isHealthy: false),
        MenuItem(name: "Black Beans",         calories: 80,  protein: 5,  carbs: 14, fat: 0,  serving: "1 side",  isHealthy: true),
    ], category: .mexican),

    Restaurant(name: "Wendy's", logo: "🍔", items: [
        MenuItem(name: "Grilled Chicken Sandwich",       calories: 350, protein: 35, carbs: 37, fat: 8,  serving: "1 sandwich", isHealthy: true),
        MenuItem(name: "Southwest Avocado Salad",        calories: 540, protein: 43, carbs: 32, fat: 27, serving: "1 salad",    isHealthy: true),
        MenuItem(name: "Dave's Single",                  calories: 590, protein: 30, carbs: 39, fat: 34, serving: "1 burger",   isHealthy: false),
        MenuItem(name: "10 Piece Chicken Nuggets",       calories: 450, protein: 23, carbs: 31, fat: 27, serving: "10 pieces",  isHealthy: false),
    ], category: .burgers),
]

// MARK: - Preview

#Preview {
    LifestyleView()
        .environmentObject(AppStore())
}
