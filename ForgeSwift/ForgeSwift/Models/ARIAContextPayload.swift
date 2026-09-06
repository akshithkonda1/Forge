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
    /// Structured Health records (Non PHI). Names only. Notes never included.
    var clinicalData: ClinicalDataDomain? = nil
    /// Federal pharmacy context: Health/saved meds plus names mentioned this
    /// turn, each resolved to brand, generic, archetype, and disease.
    var medicationLayer: MedicationContextLayer? = nil
    /// Token-efficient conversational memory: a handful of verbatim recent
    /// turns plus compressed anchors for everything older. Optional so older
    /// backends that don't know the field simply ignore it.
    var conversation: ConversationDomain? = nil

    struct SleepDomain: Codable, Equatable {
        var durationMinutes: Double? = nil
        var efficiency: Double? = nil
        var remMinutes: Double? = nil
        var deepMinutes: Double? = nil
        var hrv: Double? = nil
        var restingHR: Double? = nil
        var nightsAvailable: Int? = nil
    }

    struct ReadinessDomain: Codable, Equatable {
        var hrv7DayTrend: Double? = nil
        var hrv30DayBaseline: Double? = nil
        var recoveryScore: Double? = nil
        var hrvDaysAvailable: Int? = nil
    }

    struct TrainingDomain: Codable, Equatable {
        var lastWorkoutType: String? = nil
        var lastWorkoutDurationMinutes: Double? = nil
        var hoursSinceLastWorkout: Double? = nil
        var weeklyLoadScore: Double? = nil
    }

    struct ActivityDomain: Codable, Equatable {
        var steps3DayAvg: Double? = nil
        var activeCalories3DayAvg: Double? = nil
    }

    struct ChronotypeDomain: Codable, Equatable {
        var typicalSleepOnset: String? = nil
        var typicalWakeTime: String? = nil
        var consistencyScore: Double? = nil
    }

    struct BodyDomain: Codable, Equatable {
        var weightKg: Double? = nil
        var weightTrendKg: Double? = nil
        var bodyFatPct: Double? = nil
        var vo2Max: Double? = nil
    }

    struct NutritionDomain: Codable, Equatable {
        var caloriesIn3DayAvg: Double? = nil
        var proteinG3DayAvg: Double? = nil
        var hydrationMl3DayAvg: Double? = nil
        var calorieTarget: Double? = nil
    }

    struct ProfileDomain: Codable, Equatable {
        var primaryGoal: String? = nil
        var experienceLevel: String? = nil
        var coachingStyle: String? = nil
        var constraints: [String] = []
    }

    struct ProgressDomain: Codable, Equatable {
        var workoutsCompleted30d: Int? = nil
        var newPersonalRecords: Int? = nil
        var trainingLoadTrend: String? = nil
        var recoveryConsistencyDelta: Double? = nil
    }

    struct LifestyleDomain: Codable, Equatable {
        var tags: [String] = []
        var recentPatterns: [String] = []
        var goals: [String] = []
        /// Biology-grounded coaching text for the user's current cycle phase.
        /// Local ARIA may read this. Remote Claude/Grok must not — stripped
        /// by `AriaOnDeviceHealthPolicy` before `/ai/chat`.
        var cyclePhaseDirective: String? = nil
    }

    /// Allergies, meds, conditions, immunizations, labs, procedures.
    /// Display names only — never notes, coverage, or FHIR.
    struct ClinicalDataDomain: Codable, Equatable {
        var allergies: [String]
        var medications: [String]
        var conditions: [String]
        var immunizations: [String]
        var labResults: [String]
        var procedures: [String]

        var isEmpty: Bool {
            allergies.isEmpty && medications.isEmpty && conditions.isEmpty
                && immunizations.isEmpty && labResults.isEmpty && procedures.isEmpty
        }
    }

    struct ConversationDomain: Codable, Equatable {
        /// Verbatim recent turns, oldest first.
        var recentTurns: [Turn]
        /// Compressed anchors for turns older than the recent window.
        var summary: String?
        /// Turns exchanged in total, including the compressed ones.
        var totalTurns: Int

        struct Turn: Codable, Equatable {
            var role: String
            var content: String
        }
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