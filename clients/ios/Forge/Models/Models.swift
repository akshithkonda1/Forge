import Foundation

// MARK: - Date Helpers

func isoDateString(daysAgo: Int) -> String {
    let date = Date().addingTimeInterval(-86400 * Double(daysAgo))
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate]
    return String(formatter.string(from: date).prefix(10))
}

// MARK: - Enums

enum CoachingStyle: String, CaseIterable, Codable {
    case pushHard = "push-hard"
    case balanced
    case patient
    case dataDriven = "data-driven"
    case ultraElite = "athletic"

    var label: String {
        switch self {
        case .pushHard: return "Push Me Hard"
        case .balanced: return "Keep It Balanced"
        case .patient: return "Be Patient With Me"
        case .dataDriven: return "Data-Driven & Precise"
        case .ultraElite: return "Ultra Elite"
        }
    }

    var description: String {
        switch self {
        case .pushHard: return "No excuses. Maximum intensity. I want to be challenged every session."
        case .balanced: return "Push when I can, back off when I need to. Smart training."
        case .patient: return "I'm building habits. Encouraging and supportive."
        case .dataDriven: return "Numbers don't lie. Optimize everything based on my metrics."
        case .ultraElite: return "Designed for athletes — numbers and personal data guide every step."
        }
    }

    var iconName: String {
        switch self {
        case .pushHard: return "flame.fill"
        case .balanced: return "scale.3d"
        case .patient: return "heart.fill"
        case .dataDriven: return "chart.bar.fill"
        case .ultraElite: return "star.fill"
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

enum Chronotype: String, CaseIterable, Codable, Identifiable {
    case lion, bear, wolf, dolphin

    var id: String { rawValue }

    var displayName: String { rawValue.capitalized }

    var targetSleepHours: Double {
        switch self {
        case .lion: return 7.5
        case .bear: return 8.0
        case .wolf: return 8.5
        case .dolphin: return 7.0
        }
    }

    var deepSleepGoalMinutes: Int {
        switch self {
        case .lion: return 75
        case .bear: return 90
        case .wolf: return 85
        case .dolphin: return 60
        }
    }

    var remSleepGoalMinutes: Int {
        switch self {
        case .lion: return 80
        case .bear: return 90
        case .wolf: return 95
        case .dolphin: return 85
        }
    }

    var baseSunriseDuration: Int {
        switch self {
        case .lion: return 15
        case .bear: return 20
        case .wolf: return 25
        case .dolphin: return 30
        }
    }

    var baseSunriseColorTemp: Double {
        switch self {
        case .lion: return 0.65
        case .bear: return 0.5
        case .wolf: return 0.35
        case .dolphin: return 0.25
        }
    }

    var baseSunriseIntensity: Double {
        switch self {
        case .lion: return 0.8
        case .bear: return 0.7
        case .wolf: return 0.6
        case .dolphin: return 0.45
        }
    }
}

// MARK: - Data Structures

struct UserProfile: Codable {
    var name: String
    var fitnessGoals: [FitnessGoal]
    var experienceLevel: ExperienceLevel
    var preferredWorkouts: [WorkoutType]
    var coachingStyle: CoachingStyle
    var connectedDevices: [String]
    var weeklySchedule: [Int]
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
    var deepSleep: Int
    var totalSleep: Int
}

struct Exercise: Identifiable {
    let id: String
    var name: String
    var sets: Int
    var reps: String
    var weight: Int?
    var restSeconds: Int
    var notes: String?
    var videoURL: URL?
    var has3DModel: Bool = false
}

struct WorkoutPlan: Identifiable {
    let id: String
    var name: String
    var type: WorkoutType
    var duration: Int
    var intensity: Intensity
    var exercises: [Exercise]
    var estimatedCalories: Int { duration * 8 }
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

typealias RichCardData = RichCard

struct WorkoutCardData {
    var name: String
    var duration: Int
    var exercises: [(name: String, sets: Int, reps: String)]
}

struct ChartCardData {
    var title: String
    var values: [Double]
    var insight: String
    var color: String
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

struct UserSleepProfile: Codable, Equatable {
    var chronotype: Chronotype = .bear
    var personality: String = ""
    var notes: String = ""
    var bedtimeGoalHour: Double?
    var wakeGoalHour: Double?
}

struct AdaptiveSunriseConfig: Equatable {
    var durationMinutes: Int
    var colorTemp: Double
    var intensity: Double
    var rationale: String
}

struct AdaptiveSleepGoal: Identifiable, Equatable {
    var id: String
    var title: String
    var current: Double
    var target: Double
    var unit: String
    var icon: String
}

struct SleepAchievementState: Identifiable, Equatable {
    var id: String
    var title: String
    var description: String
    var unlocked: Bool
    var progress: Double
    var colorName: String
}

struct SleepRecommendation: Identifiable, Equatable {
    var id: String
    var icon: String
    var title: String
    var description: String
    var priority: String
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

// MARK: - Defaults & Mock Data

let emptyProfile = UserProfile(
    name: "",
    fitnessGoals: [],
    experienceLevel: .beginner,
    preferredWorkouts: [],
    coachingStyle: .balanced,
    connectedDevices: [],
    weeklySchedule: []
)

let mockReadiness = ReadinessData(
    overall: 82, sleepQuality: 88, recoveryScore: 79,
    stressLevel: 24, energyBank: 76
)

let mockMetrics = DailyMetrics(
    steps: 3241, activeCalories: 186, hrv: 52,
    restingHR: 58, deepSleep: 102, totalSleep: 432
)

let mockWorkout = WorkoutPlan(
    id: "w1", name: "Upper Body Power", type: .strength,
    duration: 55, intensity: .high,
    exercises: [
        Exercise(id: "e1", name: "Barbell Bench Press", sets: 4, reps: "6-8", weight: 185, restSeconds: 120, notes: "Focus on controlled eccentric"),
        Exercise(id: "e2", name: "Weighted Pull-Ups", sets: 4, reps: "6-8", weight: 25, restSeconds: 120),
        Exercise(id: "e3", name: "Overhead Press", sets: 3, reps: "8-10", weight: 115, restSeconds: 90),
        Exercise(id: "e4", name: "Barbell Rows", sets: 3, reps: "8-10", weight: 155, restSeconds: 90),
        Exercise(id: "e5", name: "Incline Dumbbell Press", sets: 3, reps: "10-12", weight: 65, restSeconds: 60),
        Exercise(id: "e6", name: "Face Pulls", sets: 3, reps: "15-20", weight: 30, restSeconds: 60),
    ]
)

let mockChatMessages: [ChatMessage] = [
    ChatMessage(id: "m1", role: .trainer,
                content: "Hey Akshith, welcome to Forge. I'm your AI training partner.",
                timestamp: Date().addingTimeInterval(-172800)),
    ChatMessage(id: "m12", role: .trainer,
                content: "Morning Akshith! Your deep sleep was solid last night. HRV is up 12%. Ready to hit upper body?",
                timestamp: Date().addingTimeInterval(-3600)),
    ChatMessage(id: "m13", role: .user,
                content: "Yeah I'm feeling good today. What's the plan?",
                timestamp: Date().addingTimeInterval(-3500)),
    ChatMessage(id: "m14", role: .trainer,
                content: "Upper Body Power — bench, pull-ups, OHP, rows. About 55 minutes.",
                timestamp: Date().addingTimeInterval(-3400),
                richCard: RichCard(type: .workoutPlan, workoutData: WorkoutCardData(
                    name: "Upper Body Power", duration: 55,
                    exercises: [
                        ("Barbell Bench Press", 4, "6-8"),
                        ("Weighted Pull-Ups", 4, "6-8"),
                        ("Overhead Press", 3, "8-10"),
                        ("Barbell Rows", 3, "8-10"),
                    ]
                ))),
]

let mockSleepData: [SleepData] = [
    SleepData(date: isoDateString(daysAgo: 0), totalHours: 7.2, deepMinutes: 102, remMinutes: 95, lightMinutes: 215, awakeMinutes: 20, score: 88),
    SleepData(date: isoDateString(daysAgo: 1), totalHours: 6.8, deepMinutes: 78, remMinutes: 88, lightMinutes: 225, awakeMinutes: 17, score: 74),
    SleepData(date: isoDateString(daysAgo: 2), totalHours: 7.5, deepMinutes: 110, remMinutes: 100, lightMinutes: 220, awakeMinutes: 20, score: 91),
    SleepData(date: isoDateString(daysAgo: 3), totalHours: 6.2, deepMinutes: 65, remMinutes: 72, lightMinutes: 210, awakeMinutes: 25, score: 62),
    SleepData(date: isoDateString(daysAgo: 4), totalHours: 7.8, deepMinutes: 115, remMinutes: 105, lightMinutes: 228, awakeMinutes: 20, score: 93),
    SleepData(date: isoDateString(daysAgo: 5), totalHours: 7.0, deepMinutes: 88, remMinutes: 92, lightMinutes: 218, awakeMinutes: 22, score: 80),
    SleepData(date: isoDateString(daysAgo: 6), totalHours: 6.5, deepMinutes: 72, remMinutes: 80, lightMinutes: 208, awakeMinutes: 30, score: 68),
    SleepData(date: isoDateString(daysAgo: 7), totalHours: 7.4, deepMinutes: 98, remMinutes: 96, lightMinutes: 222, awakeMinutes: 18, score: 85),
    SleepData(date: isoDateString(daysAgo: 8), totalHours: 6.9, deepMinutes: 82, remMinutes: 84, lightMinutes: 216, awakeMinutes: 32, score: 70),
    SleepData(date: isoDateString(daysAgo: 9), totalHours: 7.6, deepMinutes: 108, remMinutes: 102, lightMinutes: 224, awakeMinutes: 22, score: 90),
    SleepData(date: isoDateString(daysAgo: 10), totalHours: 5.8, deepMinutes: 55, remMinutes: 65, lightMinutes: 195, awakeMinutes: 33, score: 55),
    SleepData(date: isoDateString(daysAgo: 11), totalHours: 7.1, deepMinutes: 95, remMinutes: 90, lightMinutes: 218, awakeMinutes: 23, score: 82),
    SleepData(date: isoDateString(daysAgo: 12), totalHours: 7.3, deepMinutes: 100, remMinutes: 94, lightMinutes: 220, awakeMinutes: 24, score: 84),
    SleepData(date: isoDateString(daysAgo: 13), totalHours: 6.6, deepMinutes: 70, remMinutes: 78, lightMinutes: 212, awakeMinutes: 36, score: 65),
]

let mockWorkoutHistory: [WorkoutHistory] = [
    WorkoutHistory(id: "h1", date: isoDateString(daysAgo: 0), name: "Lower Body Strength", type: .strength, duration: 62, volume: 18500, intensity: "high"),
    WorkoutHistory(id: "h2", date: isoDateString(daysAgo: 2), name: "HIIT Conditioning", type: .hiit, duration: 30, volume: 0, intensity: "max"),
    WorkoutHistory(id: "h3", date: isoDateString(daysAgo: 3), name: "Upper Body Hypertrophy", type: .strength, duration: 58, volume: 22400, intensity: "moderate"),
    WorkoutHistory(id: "h4", date: isoDateString(daysAgo: 5), name: "Full Body Power", type: .strength, duration: 65, volume: 24000, intensity: "high"),
    WorkoutHistory(id: "h5", date: isoDateString(daysAgo: 7), name: "Cardio + Core", type: .cardio, duration: 45, volume: 0, intensity: "moderate"),
    WorkoutHistory(id: "h6", date: isoDateString(daysAgo: 9), name: "Push Day", type: .strength, duration: 52, volume: 19800, intensity: "high"),
    WorkoutHistory(id: "h7", date: isoDateString(daysAgo: 10), name: "Pull Day", type: .strength, duration: 55, volume: 21000, intensity: "high"),
    WorkoutHistory(id: "h8", date: isoDateString(daysAgo: 12), name: "Leg Day", type: .strength, duration: 60, volume: 26500, intensity: "high"),
]

let mockPersonalRecords: [PersonalRecord] = [
    PersonalRecord(exercise: "Bench Press", value: 225, unit: "lbs", date: isoDateString(daysAgo: 13)),
    PersonalRecord(exercise: "Squat", value: 315, unit: "lbs", date: isoDateString(daysAgo: 9)),
    PersonalRecord(exercise: "Deadlift", value: 365, unit: "lbs", date: isoDateString(daysAgo: 30)),
    PersonalRecord(exercise: "Mile Run", value: 6.45, unit: "min", date: isoDateString(daysAgo: 5)),
    PersonalRecord(exercise: "Pull-Ups", value: 18, unit: "reps", date: isoDateString(daysAgo: 2)),
]

let mockProgressSummary = ProgressSummary(
    workoutsCompleted: 18,
    newPRCount: 3,
    recoveryDelta: 0.22,
    summary: "Strong month — consistency on Mon/Wed/Fri and 3 new PRs."
)

let mockTrainingInsight = TrainingInsight(
    title: "Recovery Trending Up",
    body: "Your sleep quality improved 22% this month. Keep protecting your deep-sleep window."
)