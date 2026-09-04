import SwiftUI
import Combine
import ForgeCore

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

struct SmartReminder: Identifiable {
    let id: String
    let type: ReminderType
    let time: DateComponents
    let enabled: Bool
}

enum ReminderType {
    case hydration, meal, sleep, workout, supplement
}

/// Snapshot the Lifestyle Home Screen widget reads from the shared App Group.
/// Lives in the app target (so it compiles in CI); the widget extension — added
/// separately in Xcode — decodes the same struct from the same suite + key.
struct LifestyleWidgetSnapshot: Codable {
    var qol: Int
    var topTitle: String?
    var topCategory: String?
    var updatedAt: Date
}

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

struct DailyHabit: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var done: Bool
}

struct QOLDay: Identifiable, Codable {
    var id = UUID()
    let date: Date
    let score: Int
}

enum LifestyleSegment: Int, CaseIterable {
    case aiOptimization, homeCooking, restaurants, nutrition, wellbeing
    var title: String {
        switch self {
        case .aiOptimization: return "Optimize"
        case .homeCooking:    return "Cook"
        case .restaurants:    return "Places"
        case .nutrition:      return "Nutrition"
        case .wellbeing:      return "Wellbeing"
        }
    }
    var icon: String {
        switch self {
        case .aiOptimization: return "sparkles"
        case .homeCooking:    return "frying.pan.fill"
        case .restaurants:    return "map.fill"
        case .nutrition:      return "chart.pie.fill"
        case .wellbeing:      return "heart.fill"
        }
    }
}

enum InsightStatus {
    case excellent, good, warning, poor
    var color: Color {
        switch self { case .excellent: return .success; case .good: return .steel; case .warning: return .warning; case .poor: return .danger }
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

// Scoring a menu item is model logic, not view logic, so this rides with the
// enum rather than staying file-private next to the card that happens to call it.
extension NutritionRating {
    init(proteinEfficiency: Int) {
        switch proteinEfficiency {
        case 100...: self = .excellent
        case 60..<100: self = .good
        case 30..<60: self = .fair
        default: self = .poor
        }
    }
}

struct AIRestaurantPick: Identifiable {
    let id = UUID()
    let restaurant: String; let emoji: String; let item: String
    let cal: Int; let protein: Int; let reason: String
}

struct LifestyleInsight: Identifiable {
    let id = UUID()
    let title: String; let insight: String; let action: String; let color: Color
}
