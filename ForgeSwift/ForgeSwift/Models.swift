import Foundation
import SwiftUI

// MARK: - Enums (mirrors /src/types/index.ts)

enum CoachingStyle: String, Codable, CaseIterable, Identifiable {
    case pushHard    = "push-hard"
    case balanced    = "balanced"
    case patient     = "patient"
    case dataDriven  = "data-driven"
    case ultraElite  = "athletic"
    var id: String { rawValue }

    var label: String {
        switch self {
        case .pushHard:   return "Push Me Hard"
        case .balanced:   return "Keep It Balanced"
        case .patient:    return "Be Patient With Me"
        case .dataDriven: return "Data-Driven & Precise"
        case .ultraElite: return "Data-Driven & Precise but on a higher level. "
        }
    }
    var description: String {
        switch self {
        case .pushHard:   return "Maximum intensity every session. No excuses."
        case .balanced:   return "Smart training — push when ready, recover when needed."
        case .patient:    return "Encouraging, supportive, and habit-focused."
        case .dataDriven: return "Optimized by metrics. Numbers guide everything."
        case .ultraElite: return "Designed for athletes of all levels and types, numbers and personal data guide every step."
        }
    }
    
    var icon: String {
        switch self {
        case .pushHard:   return "flame.fill"
        case .balanced:   return "chart.xyaxis.line"
        case .patient:    return "heart.fill"
        case .dataDriven: return "brain.head.profile"
        case .ultraElite: return "star.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .pushHard:   return .ember
        case .balanced:   return .cyan
        case .patient:    return .green
        case .dataDriven: return .purple
        case .ultraElite: return .orange
        }
    }
}

enum UserFitnessGoal: String, Codable, CaseIterable, Identifiable {
    case buildMuscle         = "build-muscle"
    case loseFat             = "lose-fat"
    case improveEndurance    = "improve-endurance"
    case generalFitness      = "general-fitness"
    case athleticPerformance = "athletic-performance"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .buildMuscle:         return "Build Muscle"
        case .loseFat:             return "Lose Fat"
        case .improveEndurance:    return "Improve Endurance"
        case .generalFitness:      return "General Fitness"
        case .athleticPerformance: return "Athletic Performance"
        }
    }
}

enum ExperienceLevel: String, Codable, CaseIterable, Identifiable {
    case beginner, intermediate, advanced, elite
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var description: String {
        switch self {
        case .beginner:     return "Just getting started"
        case .intermediate: return "1–3 years of consistent training"
        case .advanced:     return "3+ years, structured programming"
        case .elite:        return "Competitive / high-performance athlete"
        }
    }
}

enum Gender: String, Codable, CaseIterable, Identifiable {
    case male = "Male"
    case female = "Female"
    case nonBinary = "Non-binary"
    case preferNotToSay = "Prefer not to say"
    case other = "Other"
    
    var id: String { rawValue }
    var label: String { rawValue }
    var icon: String {
        switch self {
        case .male: return "person.fill"
        case .female: return "person.fill"
        case .nonBinary: return "person.fill"
        case .preferNotToSay: return "person.fill.questionmark"
        case .other: return "person.fill"
        }
    }
}

enum WorkoutType: String, Codable, CaseIterable, Identifiable {
    case strength, cardio, hiit, yoga, mobility
    case sportSpecific = "sport-specific"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .sportSpecific: return "Sport-Specific"
        default: return rawValue.capitalized
        }
    }
    var color: Color {
        switch self {
        case .strength:     return .ember
        case .hiit:         return .danger
        case .cardio:       return .steel
        case .yoga:         return .success
        case .mobility:     return Color(hex: "A855F7")
        case .sportSpecific: return .textSecondary
        }
    }
}

enum WorkoutIntensity: String, Codable {
    case low, moderate, high, max
    var label: String { rawValue.capitalized }
    var color: Color {
        switch self {
        case .max:      return .danger
        case .high:     return .ember
        case .moderate: return .warning
        case .low:      return .success
        }
    }
}

enum MessageRole: String { case trainer, user }

// MARK: - Data Models

struct UserProfile: Codable {
    var name: String
    var gender: Gender
    var fitnessGoals: [UserFitnessGoal]
    var experienceLevel: ExperienceLevel
    var preferredWorkouts: [WorkoutType]
    var coachingStyle: CoachingStyle
    var connectedDevices: [String]
    var weeklySchedule: [Int]
    
    // HealthKit-derived health metrics
    var age: Int?
    var weight: Double?  // in kg
    var height: Double?  // in cm

    var initials: String {
        name.split(separator: " ").compactMap { $0.first.map { String($0).uppercased() } }.joined().prefix(2).description
    }
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

// Add video/3D model support to exercises
struct Exercise: Identifiable {
    var id: String
    var name: String
    var sets: Int
    var reps: String
    var weight: Int?
    var restSeconds: Int
    var notes: String?
    var videoURL: URL?
    var has3DModel: Bool
    
    // For AR/3D visualization
    var modelName: String? {
        has3DModel ? name.replacingOccurrences(of: " ", with: "_").lowercased() : nil
    }
}

struct WorkoutPlan: Identifiable {
    var id: String
    var name: String
    var type: WorkoutType
    var duration: Int
    var intensity: WorkoutIntensity
    var exercises: [Exercise]
    var estimatedCalories: Int {
        // Estimate based on duration and intensity
        let baseCalories = duration * 5 // ~5 cal per minute base
        let multiplier: Double = switch intensity {
        case .low: 0.7
        case .moderate: 1.0
        case .high: 1.3
        case .max: 1.5
        }
        return Int(Double(baseCalories) * multiplier)
    }
}

// Rich card attached to a chat message
struct RichCardData {
    enum CardType { case workoutPlan, dataChart }
    var type: CardType
    // workout-plan fields
    var workoutName: String?
    var workoutDuration: Int?
    var workoutExercises: [(name: String, sets: Int, reps: String)]?
    // data-chart fields
    var chartTitle: String?
    var chartValues: [Double]?
    var chartInsight: String?
    var chartColor: Color?
}

struct ChatMessage: Identifiable {
    var id: String
    var role: MessageRole
    var content: String
    var timestamp: Date
    var richCard: RichCardData?
    var toolCallsMade: [String]?
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

// MARK: - Sleep Intelligence

enum Chronotype: String, CaseIterable, Codable, Identifiable {
    case lion, bear, wolf, dolphin

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lion: return "Lion"
        case .bear: return "Bear"
        case .wolf: return "Wolf"
        case .dolphin: return "Dolphin"
        }
    }

    var icon: String {
        switch self {
        case .lion: return "sunrise.fill"
        case .bear: return "moon.zzz.fill"
        case .wolf: return "moon.stars.fill"
        case .dolphin: return "waveform.path.ecg"
        }
    }

    var tagline: String {
        switch self {
        case .lion: return "Early riser — peak energy before noon"
        case .bear: return "Solar-aligned — steady 8-hour rhythm"
        case .wolf: return "Night owl — creative after dark"
        case .dolphin: return "Light sleeper — needs gentle recovery"
        }
    }

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

    var idealWakeHour: Double {
        switch self {
        case .lion: return 6.0
        case .bear: return 7.0
        case .wolf: return 8.5
        case .dolphin: return 7.5
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
    var id: String
    var date: String
    var name: String
    var type: WorkoutType
    var duration: Int
    var volume: Int
    var intensity: WorkoutIntensity
}

struct PersonalRecord: Identifiable {
    var id: String { exercise }
    var exercise: String
    var value: Double
    var unit: String
    var date: String

    var formattedValue: String {
        if unit == "min" {
            let minutes = Int(value)
            let seconds = Int((value - Double(minutes)) * 100)
            return String(format: "%d:%02d", minutes, seconds)
        }
        if value == value.rounded() { return String(Int(value)) }
        return String(format: "%.2f", value)
    }
}

// MARK: - Empty defaults (production / pre-load state)

let emptyProfile = UserProfile(
    name: "",
    gender: .preferNotToSay,
    fitnessGoals: [],
    experienceLevel: .beginner,
    preferredWorkouts: [],
    coachingStyle: .balanced,
    connectedDevices: [],
    weeklySchedule: []
)

let emptyReadiness = ReadinessData(
    overall: 0,
    sleepQuality: 0,
    recoveryScore: 0,
    stressLevel: 0,
    energyBank: 0
)

let emptyMetrics = DailyMetrics(
    steps: 0,
    activeCalories: 0,
    hrv: 0,
    restingHR: 0,
    deepSleep: 0,
    totalSleep: 0
)

// MARK: - Mock Data (DEBUG fallback only — mirrors useAppStore.ts)

let mockProfile = UserProfile(
    name: "Akshith",
    gender: Gender.male,
    fitnessGoals: [UserFitnessGoal.buildMuscle],
    experienceLevel: ExperienceLevel.intermediate,
    preferredWorkouts: [WorkoutType.strength, WorkoutType.hiit],
    coachingStyle: CoachingStyle.pushHard,
    connectedDevices: ["Apple Watch", "Oura Ring"],
    weeklySchedule: [1, 3, 5]
)

let mockReadiness = ReadinessData(
    overall: 82,
    sleepQuality: 88,
    recoveryScore: 79,
    stressLevel: 24,
    energyBank: 76
)

let mockMetrics = DailyMetrics(
    steps: 3241,
    activeCalories: 186,
    hrv: 52,
    restingHR: 58,
    deepSleep: 102,
    totalSleep: 432
)

let mockWorkout = WorkoutPlan(
    id: "w1",
    name: "Upper Body Power",
    type: WorkoutType.strength,
    duration: 55,
    intensity: WorkoutIntensity.high,
    exercises: [
        Exercise(id:"e1", name:"Barbell Bench Press",    sets:4, reps:"6-8",   weight:185, restSeconds:120, notes:"Focus on controlled eccentric", videoURL: URL(string: "https://example.com/bench-press.mp4"), has3DModel: true),
        Exercise(id:"e2", name:"Weighted Pull-Ups",       sets:4, reps:"6-8",   weight:25,  restSeconds:120, videoURL: URL(string: "https://example.com/pullups.mp4"), has3DModel: true),
        Exercise(id:"e3", name:"Overhead Press",          sets:3, reps:"8-10",  weight:115, restSeconds:90, videoURL: URL(string: "https://example.com/ohp.mp4"), has3DModel: true),
        Exercise(id:"e4", name:"Barbell Rows",            sets:3, reps:"8-10",  weight:155, restSeconds:90, videoURL: URL(string: "https://example.com/rows.mp4"), has3DModel: true),
        Exercise(id:"e5", name:"Incline Dumbbell Press",  sets:3, reps:"10-12", weight:65,  restSeconds:60, videoURL: URL(string: "https://example.com/incline.mp4"), has3DModel: true),
        Exercise(id:"e6", name:"Face Pulls",              sets:3, reps:"15-20", weight:30,  restSeconds:60, videoURL: URL(string: "https://example.com/facepulls.mp4"), has3DModel: true),
    ]
)

// Lazy loading for expensive mock data
let mockChatMessages: [ChatMessage] = {
    let now = Date()
    let d2 = now.addingTimeInterval(-86400 * 2)
    let d1 = now.addingTimeInterval(-86400)
    let h1 = now.addingTimeInterval(-3600)
    return [
        ChatMessage(id:"m1",  role: MessageRole.trainer, content:"Hey Akshith, welcome to Forge. I'm your AI training partner. I've synced up with your Apple Watch and Oura Ring — already pulling in your biometrics. Let's build something serious together.", timestamp: d2),
        ChatMessage(id:"m2",  role: MessageRole.user,    content:"Excited to get started. I've been training for about 2 years but feel like I've plateaued.", timestamp: d2.addingTimeInterval(60)),
        ChatMessage(id:"m3",  role: MessageRole.trainer, content:"Plateaus are normal — and breakable. Your training history shows solid consistency but your programming might need periodization. I'll structure progressive overload cycles and track your recovery so we push at the right times. First things first: let's establish your baseline this week.", timestamp: d2.addingTimeInterval(120)),
        ChatMessage(id:"m4",  role: MessageRole.user,    content:"Sounds good. What should I focus on today?", timestamp: d1.addingTimeInterval(30)),
        ChatMessage(id:"m5",  role: MessageRole.trainer, content:"Yesterday was a rest day and your HRV bounced back nicely — 48ms up to 52ms. Deep sleep hit 1hr 42min which is solid for recovery. I'd say you're primed for a strength session. How about lower body? Your squat has been progressing well.", timestamp: d1.addingTimeInterval(90)),
        ChatMessage(id:"m6",  role: MessageRole.user,    content:"Actually I'm a bit sore from the hike over the weekend. Can we do upper body instead?", timestamp: d1.addingTimeInterval(150)),
        ChatMessage(id:"m7",  role: MessageRole.trainer, content:"Smart call — listening to your body is part of the game. I'll slot in Upper Body Power today and shift legs to Wednesday when you'll be fully recovered. Your bench has been stuck at 225 — today we're going to attack that with heavy triples and back-off sets.", timestamp: d1.addingTimeInterval(210)),
        ChatMessage(id:"m8",  role: MessageRole.user,    content:"Let's do it. Also, I've been waking up at like 3am lately. Any idea why?", timestamp: d1.addingTimeInterval(270)),
        ChatMessage(id:"m9",  role: MessageRole.trainer, content:"I noticed that in your Oura data — you've had 3 wake-ups between 2–4am this week. A few things could cause this: cortisol spikes from late training, screen time before bed, or caffeine after 2pm. Your deep sleep is still decent but your awake time has crept up 40% this week. Try cutting screens 45 min before bed and see if it helps. I'll track the trend.", timestamp: d1.addingTimeInterval(330)),
        ChatMessage(id:"m10", role: MessageRole.user,    content:"Good catch. I have been scrolling before bed more lately.", timestamp: d1.addingTimeInterval(390)),
        ChatMessage(id:"m11", role: MessageRole.trainer, content:"There it is. Small habit, big impact on recovery. Your muscles literally rebuild during deep sleep — protecting that window is as important as the workout itself. I'll check in on this next week to see if the numbers improve.", timestamp: d1.addingTimeInterval(450)),
        ChatMessage(id:"m12", role: MessageRole.trainer, content:"Morning Akshith! Your deep sleep was solid last night — 1hr 42min. HRV is up 12% from yesterday. You're primed for a heavy session today. Ready to hit upper body?", timestamp: h1),
        ChatMessage(id:"m13", role: MessageRole.user,    content:"Yeah I'm feeling good today. What's the plan?", timestamp: h1.addingTimeInterval(100)),
        ChatMessage(
            id:"m14", role: MessageRole.trainer,
            content:"Love the energy. I've got an Upper Body Power session lined up — bench press, weighted pull-ups, OHP, rows. About 55 minutes, high intensity. Your recovery metrics say you can handle it. Want me to break down the full workout?",
            timestamp: h1.addingTimeInterval(200),
            richCard: RichCardData(
                type: .workoutPlan,
                workoutName: "Upper Body Power",
                workoutDuration: 55,
                workoutExercises: [
                    ("Barbell Bench Press", 4, "6-8"),
                    ("Weighted Pull-Ups", 4, "6-8"),
                    ("Overhead Press", 3, "8-10"),
                    ("Barbell Rows", 3, "8-10"),
                    ("Incline DB Press", 3, "10-12"),
                    ("Face Pulls", 3, "15-20"),
                ]
            )
        ),
        ChatMessage(id:"m15", role: MessageRole.user, content:"Looks perfect. Let's go!", timestamp: h1.addingTimeInterval(300)),
    ]
}()

let mockSleepData: [SleepData] = [
    SleepData(date:"2026-02-10", totalHours:7.2, deepMinutes:102, remMinutes:95,  lightMinutes:215, awakeMinutes:20, score:88),
    SleepData(date:"2026-02-09", totalHours:6.8, deepMinutes:78,  remMinutes:88,  lightMinutes:225, awakeMinutes:17, score:74),
    SleepData(date:"2026-02-08", totalHours:7.5, deepMinutes:110, remMinutes:100, lightMinutes:220, awakeMinutes:20, score:91),
    SleepData(date:"2026-02-07", totalHours:6.2, deepMinutes:65,  remMinutes:72,  lightMinutes:210, awakeMinutes:25, score:62),
    SleepData(date:"2026-02-06", totalHours:7.8, deepMinutes:115, remMinutes:105, lightMinutes:228, awakeMinutes:20, score:93),
    SleepData(date:"2026-02-05", totalHours:7.0, deepMinutes:88,  remMinutes:92,  lightMinutes:218, awakeMinutes:22, score:80),
    SleepData(date:"2026-02-04", totalHours:6.5, deepMinutes:72,  remMinutes:80,  lightMinutes:208, awakeMinutes:30, score:68),
    SleepData(date:"2026-02-03", totalHours:7.4, deepMinutes:98,  remMinutes:96,  lightMinutes:222, awakeMinutes:18, score:85),
    SleepData(date:"2026-02-02", totalHours:6.9, deepMinutes:82,  remMinutes:84,  lightMinutes:216, awakeMinutes:32, score:70),
    SleepData(date:"2026-02-01", totalHours:7.6, deepMinutes:108, remMinutes:102, lightMinutes:224, awakeMinutes:22, score:90),
    SleepData(date:"2026-01-31", totalHours:5.8, deepMinutes:55,  remMinutes:65,  lightMinutes:195, awakeMinutes:33, score:55),
    SleepData(date:"2026-01-30", totalHours:7.1, deepMinutes:95,  remMinutes:90,  lightMinutes:218, awakeMinutes:23, score:82),
    SleepData(date:"2026-01-29", totalHours:7.3, deepMinutes:100, remMinutes:94,  lightMinutes:220, awakeMinutes:24, score:84),
    SleepData(date:"2026-01-28", totalHours:6.6, deepMinutes:70,  remMinutes:78,  lightMinutes:212, awakeMinutes:36, score:65),
]

let mockWorkoutHistory: [WorkoutHistory] = [
    WorkoutHistory(id:"h1",  date:"2026-02-10", name:"Lower Body Strength",    type: WorkoutType.strength, duration:62, volume:18500, intensity: WorkoutIntensity.high),
    WorkoutHistory(id:"h2",  date:"2026-02-08", name:"HIIT Conditioning",       type: WorkoutType.hiit,     duration:30, volume:0,     intensity: WorkoutIntensity.max),
    WorkoutHistory(id:"h3",  date:"2026-02-07", name:"Upper Body Hypertrophy",  type: WorkoutType.strength, duration:58, volume:22400, intensity: WorkoutIntensity.moderate),
    WorkoutHistory(id:"h4",  date:"2026-02-05", name:"Full Body Power",          type: WorkoutType.strength, duration:65, volume:24000, intensity: WorkoutIntensity.high),
    WorkoutHistory(id:"h5",  date:"2026-02-03", name:"Cardio + Core",            type: WorkoutType.cardio,   duration:45, volume:0,     intensity: WorkoutIntensity.moderate),
    WorkoutHistory(id:"h6",  date:"2026-02-01", name:"Push Day",                 type: WorkoutType.strength, duration:52, volume:19800, intensity: WorkoutIntensity.high),
    WorkoutHistory(id:"h7",  date:"2026-01-31", name:"Pull Day",                 type: WorkoutType.strength, duration:55, volume:21000, intensity: WorkoutIntensity.high),
    WorkoutHistory(id:"h8",  date:"2026-01-29", name:"Leg Day",                  type: WorkoutType.strength, duration:60, volume:26500, intensity: WorkoutIntensity.high),
    WorkoutHistory(id:"h9",  date:"2026-01-28", name:"HIIT Sprint Intervals",    type: WorkoutType.hiit,     duration:25, volume:0,     intensity: WorkoutIntensity.max),
    WorkoutHistory(id:"h10", date:"2026-01-27", name:"Mobility & Recovery",      type: WorkoutType.mobility, duration:35, volume:0,     intensity: WorkoutIntensity.low),
]

let mockPersonalRecords: [PersonalRecord] = [
    PersonalRecord(exercise:"Bench Press", value:225,  unit:"lbs",  date:"2026-01-28"),
    PersonalRecord(exercise:"Squat",       value:315,  unit:"lbs",  date:"2026-02-01"),
    PersonalRecord(exercise:"Deadlift",    value:365,  unit:"lbs",  date:"2026-01-15"),
    PersonalRecord(exercise:"Mile Run",    value:6.45, unit:"min",  date:"2026-02-05"),
    PersonalRecord(exercise:"Pull-Ups",    value:18,   unit:"reps", date:"2026-02-08"),
]
