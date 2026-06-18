import Foundation

/// Full v1.1 ARIA context — mirrors `shared/api-contracts.ts` / `aria_engine.py`.
struct ARIAContextPayload: Codable, Equatable {
    var timestamp: String
    var sleep: SleepDomain
    var readiness: ReadinessDomain
    var training: TrainingDomain
    var activity: ActivityDomain
    var chronotype: ChronotypeDomain
    var body: BodyDomain
    var nutrition: NutritionDomain
    var profile: ProfileDomain
    var progress: ProgressDomain
    var lifestyle: LifestyleDomain

    struct SleepDomain: Codable, Equatable {
        var durationMinutes: Double?
        var efficiency: Double?
        var remMinutes: Double?
        var deepMinutes: Double?
        var hrv: Double?
        var restingHR: Double?
        var nightsAvailable: Int?
    }

    struct ReadinessDomain: Codable, Equatable {
        var hrv7DayTrend: Double?
        var hrv30DayBaseline: Double?
        var recoveryScore: Double?
        var hrvDaysAvailable: Int?
    }

    struct TrainingDomain: Codable, Equatable {
        var lastWorkoutType: String?
        var lastWorkoutDurationMinutes: Double?
        var hoursSinceLastWorkout: Double?
        var weeklyLoadScore: Double?
    }

    struct ActivityDomain: Codable, Equatable {
        var steps3DayAvg: Double?
        var activeCalories3DayAvg: Double?
    }

    struct ChronotypeDomain: Codable, Equatable {
        var typicalSleepOnset: String?
        var typicalWakeTime: String?
        var consistencyScore: Double?
    }

    struct BodyDomain: Codable, Equatable {
        var weightKg: Double?
        var weightTrendKg: Double?
        var bodyFatPct: Double?
        var vo2Max: Double?
    }

    struct NutritionDomain: Codable, Equatable {
        var caloriesIn3DayAvg: Double?
        var proteinG3DayAvg: Double?
        var hydrationMl3DayAvg: Double?
        var calorieTarget: Double?
    }

    struct ProfileDomain: Codable, Equatable {
        var primaryGoal: String?
        var experienceLevel: String?
        var coachingStyle: String?
        var constraints: [String]
    }

    struct ProgressDomain: Codable, Equatable {
        var workoutsCompleted30d: Int?
        var newPersonalRecords: Int?
        var trainingLoadTrend: String?
        var recoveryConsistencyDelta: Double?
    }

    struct LifestyleDomain: Codable, Equatable {
        var tags: [String]
        var recentPatterns: [String]
        var goals: [String]
    }
}

/// Health sample for POST /ai/observe.
struct HealthSamplePayload: Codable, Equatable {
    var metric: String?
    var value: Double
    var unit: String?
    var timestamp: String?
    var source: String?
}

struct ObserveRequestPayload: Codable {
    let userId: String
    var samples: [HealthSamplePayload]?
    var includeStored: Bool?
    var ageYears: Int?
    var permissions: [String: Bool]?
    var message: String?
    var voiceMode: Bool?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case samples
        case includeStored = "include_stored"
        case ageYears = "age_years"
        case permissions
        case message
        case voiceMode = "voice_mode"
    }
}

struct ObserveResponsePayload: Codable, Equatable {
    var ariaContext: ARIAContextPayload?
    var restrictedDomains: [String]?
    var missingFields: [String]?

    enum CodingKeys: String, CodingKey {
        case ariaContext = "aria_context"
        case restrictedDomains = "restricted_domains"
        case missingFields = "missing_fields"
    }
}