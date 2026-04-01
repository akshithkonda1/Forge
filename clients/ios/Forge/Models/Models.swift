import Foundation

// MARK: - Enums

enum CoachingStyle: String, CaseIterable, Codable {
    case pushHard = "push-hard"
    case balanced
    case patient
    case dataDriven = "data-driven"

    var label: String {
        switch self {
        case .pushHard: return "Push Me Hard"
        case .balanced: return "Keep It Balanced"
        case .patient: return "Be Patient With Me"
        case .dataDriven: return "Data-Driven & Precise"
        }
    }

    var description: String {
        switch self {
        case .pushHard: return "No excuses. Maximum intensity. I want to be challenged every session."
        case .balanced: return "Push when I can, back off when I need to. Smart training."
        case .patient: return "I'm building habits. Encouraging and supportive."
        case .dataDriven: return "Numbers don't lie. Optimize everything based on my metrics."
        }
    }

    var iconName: String {
        switch self {
        case .pushHard: return "flame.fill"
        case .balanced: return "scale.3d"
        case .patient: return "heart.fill"
        case .dataDriven: return "chart.bar.fill"
        }
    }
}

enum FitnessGoal: String, CaseIterable, Codable, Identifiable {
    case buildMuscle = "build-muscle"
    case loseFat = "lose-fat"
    case improveEndurance = "improve-endurance"
    case generalFitness = "general-fitness"
    case athleticPerformance = "athletic-performance"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .buildMuscle: return "Build Muscle"
        case .loseFat: return "Lose Fat"
        case .improveEndurance: return "Improve Endurance"
        case .generalFitness: return "General Fitness"
        case .athleticPerformance: return "Athletic Performance"
        }
    }
}

enum ExperienceLevel: String, CaseIterable, Codable {
    case beginner, intermediate, advanced, elite

    var label: String { rawValue.capitalized }

    var description: String {
        switch self {
        case .beginner: return "New to structured training. Learning the fundamentals."
        case .intermediate: return "Consistent training for 1-3 years. Solid foundation."
        case .advanced: return "3+ years of dedicated training. Refined technique."
        case .elite: return "Competitive athlete or 5+ years of advanced training."
        }
    }
}

enum WorkoutType: String, CaseIterable, Codable, Identifiable {
    case strength, cardio, hiit, yoga, mobility
    case sportSpecific = "sport-specific"

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum Intensity: String, Codable {
    case low, moderate, high, max
}

// MARK: - Data Structures

struct UserProfile: Codable {
    var name: String
    var fitnessGoals: [FitnessGoal]
    var experienceLevel: ExperienceLevel
    var preferredWorkouts: [WorkoutType]
    var coachingStyle: CoachingStyle
    var connectedDevices: [String]
    var weeklySchedule: [Int] // 0=Sun, 1=Mon...
}

struct ReadinessData {
    var overall: Int
    var sleepQuality: Int
    var recoveryScore: Int
    var stressLevel: Int
    var energyBank: Int
}

struct DailyMetrics {
    var steps: Int
    var activeCalories: Int
    var hrv: Int
    var restingHR: Int
    var deepSleep: Int   // minutes
    var totalSleep: Int  // minutes
}

struct Exercise: Identifiable {
    let id: String
    var name: String
    var sets: Int
    var reps: String
    var weight: Int?
    var restSeconds: Int
    var notes: String?
}

struct WorkoutPlan: Identifiable {
    let id: String
    var name: String
    var type: WorkoutType
    var duration: Int
    var intensity: Intensity
    var exercises: [Exercise]
}

struct ChatMessage: Identifiable {
    let id: String
    var role: MessageRole
    var content: String
    var timestamp: Date
    var richCard: RichCard?
}

enum MessageRole {
    case trainer, user
}

enum RichCardType {
    case workoutPlan, dataChart
}

struct RichCard {
    var type: RichCardType
    var workoutData: WorkoutCardData?
    var chartData: ChartCardData?
}

struct WorkoutCardData {
    var name: String
    var duration: Int
    var exercises: [(name: String, sets: Int, reps: String)]
}

struct ChartCardData {
    var title: String
    var values: [Double]
    var insight: String
    var color: String // hex
}

struct SleepData: Identifiable {
    var id: String { date }
    var date: String
    var totalHours: Double
    var deepMinutes: Int
    var remMinutes: Int
    var lightMinutes: Int
    var awakeMinutes: Int
    var score: Int
}

struct WorkoutHistory: Identifiable {
    let id: String
    var date: String
    var name: String
    var type: WorkoutType
    var duration: Int
    var volume: Int
    var intensity: String
}

struct PersonalRecord: Identifiable {
    var id: String { exercise }
    var exercise: String
    var value: Double
    var unit: String
    var date: String
}

struct DeviceOption: Identifiable {
    let id: String
    let name: String
    let iconName: String
}
