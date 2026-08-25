import SwiftUI
#if canImport(HealthKit)
import HealthKit
#endif

// MARK: - Workout models (shared iOS + watchOS)
//
// `ForgeWorkoutType` mirrors the iOS `WorkoutType` enum (Models.swift) so
// plans and history read the same on both platforms. Structured plans are
// a deliberately lightweight Codable subset of the iOS WorkoutPlan/
// Exercise models — enough for wrist navigation, sync-friendly.

public enum ForgeWorkoutType: String, Codable, CaseIterable, Identifiable, Sendable {
    case strength
    case cardio
    case hiit
    case yoga
    case mobility

    public var id: String { rawValue }

    public var displayName: String {
        rawValue == "hiit" ? "HIIT" : rawValue.capitalized
    }

    public var symbolName: String {
        switch self {
        case .strength: return "dumbbell.fill"
        case .cardio:   return "figure.run"
        case .hiit:     return "bolt.fill"
        case .yoga:     return "figure.yoga"
        case .mobility: return "figure.flexibility"
        }
    }

    /// Mirrors iOS WorkoutType colors (ember/steel/danger/success/violet).
    public var accentColor: Color {
        switch self {
        case .strength: return ForgePalette.ember
        case .cardio:   return ForgePalette.steel
        case .hiit:     return ForgePalette.danger
        case .yoga:     return ForgePalette.success
        case .mobility: return ForgePalette.violet
        }
    }

    /// The zone the session is "at home" in — coaching cues anchor to it.
    public var targetZone: Int {
        switch self {
        case .mobility, .yoga: return 1
        case .cardio:          return 2
        case .strength:        return 3
        case .hiit:            return 4
        }
    }

    #if canImport(HealthKit)
    public var hkActivityType: HKWorkoutActivityType {
        switch self {
        case .strength: return .traditionalStrengthTraining
        case .cardio:   return .running
        case .hiit:     return .highIntensityIntervalTraining
        case .yoga:     return .yoga
        case .mobility: return .flexibility
        }
    }

    /// The Forge type behind a HealthKit configuration.
    ///
    /// Recovering a session the app did not start this launch gives back an
    /// `HKWorkoutConfiguration` and nothing else, so the mapping has to run
    /// backwards. Recovery only ever returns this app's own sessions, so the
    /// fallback is unreachable in practice — it exists so the API is total.
    public init(hkActivityType: HKWorkoutActivityType) {
        self = ForgeWorkoutType.allCases.first { $0.hkActivityType == hkActivityType } ?? .cardio
    }
    #endif
}

// MARK: - Structured plans

public struct WorkoutSet: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var reps: Int
    public var weightKg: Double?

    public init(id: UUID = UUID(), reps: Int, weightKg: Double? = nil) {
        self.id = id
        self.reps = reps
        self.weightKg = weightKg
    }
}

public struct WorkoutExercise: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var sets: [WorkoutSet]
    public var restSeconds: Int

    public init(id: UUID = UUID(), name: String, sets: [WorkoutSet], restSeconds: Int = 90) {
        self.id = id
        self.name = name
        self.sets = sets
        self.restSeconds = restSeconds
    }
}

public struct StructuredWorkout: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var type: ForgeWorkoutType
    public var exercises: [WorkoutExercise]

    public init(id: UUID = UUID(), name: String, type: ForgeWorkoutType, exercises: [WorkoutExercise]) {
        self.id = id
        self.name = name
        self.type = type
        self.exercises = exercises
    }

    public var totalSets: Int {
        exercises.reduce(0) { $0 + $1.sets.count }
    }

    /// The plan offered on the wrist before a personalised one has synced.
    ///
    /// Named for what it is. It was `demoStrength`, described as a "v1 demo
    /// plan", while being the only guided session the watch actually offers —
    /// and the watch offers it to real users. Nothing about it is fabricated:
    /// four compound movements needing no equipment beyond a single weight,
    /// which is a defensible starting point for someone Forge knows nothing
    /// about yet. A synced plan should replace it; until one does, this is a
    /// real answer rather than a placeholder pretending to be one.
    public static var starterStrength: StructuredWorkout {
        StructuredWorkout(
            name: "Full-Body Strength",
            type: .strength,
            exercises: [
                WorkoutExercise(name: "Goblet Squat", sets: [WorkoutSet(reps: 10), WorkoutSet(reps: 10), WorkoutSet(reps: 8)], restSeconds: 90),
                WorkoutExercise(name: "Push-Up", sets: [WorkoutSet(reps: 12), WorkoutSet(reps: 12), WorkoutSet(reps: 10)], restSeconds: 75),
                WorkoutExercise(name: "One-Arm Row", sets: [WorkoutSet(reps: 10), WorkoutSet(reps: 10), WorkoutSet(reps: 10)], restSeconds: 90),
                WorkoutExercise(name: "Plank", sets: [WorkoutSet(reps: 45), WorkoutSet(reps: 45)], restSeconds: 60),
            ]
        )
    }
}
