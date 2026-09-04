import SwiftUI

enum AutoRegAction: Equatable {
    case increaseLoad(Int)      // +lbs next set
    case decreaseLoad(Int)      // −lbs next set
    case hold
    case extendRest(Int)        // +seconds
    case reduceReps(Int)
    case addReps(Int)
    case substitute(reason: String)
    case deload                 // global volume cut
    case stopExercise(reason: String)

    var tone: Color {
        switch self {
        case .increaseLoad, .addReps: return .success
        case .hold: return .steel
        case .decreaseLoad, .reduceReps, .extendRest, .deload: return .warning
        case .substitute, .stopExercise: return .danger
        }
    }
    var icon: String {
        switch self {
        case .increaseLoad: return "arrow.up.circle.fill"
        case .decreaseLoad, .reduceReps: return "arrow.down.circle.fill"
        case .hold: return "equal.circle.fill"
        case .addReps: return "plus.circle.fill"
        case .extendRest: return "clock.badge.fill"
        case .substitute: return "arrow.triangle.swap"
        case .deload: return "tortoise.fill"
        case .stopExercise: return "hand.raised.fill"
        }
    }
}

struct SetRecommendation {
    var weightDelta: Int
    var repTarget: Int
    var restSeconds: Int
    var rpeTarget: Int
    var primaryAction: AutoRegAction
    var rationale: String
}

/// What the plan should look like given today's recovery state.
struct PlanScaling {
    var volumeMultiplier: Double   // applied to sets
    var intensityMultiplier: Double // applied to load
    var headline: String
    var detail: String
    var tone: Color
    var isModified: Bool { abs(volumeMultiplier - 1) > 0.01 || abs(intensityMultiplier - 1) > 0.01 }
}

enum AdaptiveEngine {

    // ── Pre-workout: scale the whole session to recovery ──────────────────────
    static func scaling(readiness: ReadinessData, experience: ExperienceLevel) -> PlanScaling {
        let r = readiness.overall
        switch r {
        case 85...:
            return PlanScaling(volumeMultiplier: 1.10, intensityMultiplier: 1.03,
                               headline: "Primed — green light",
                               detail: "Recovery is excellent. ARIA added a top-set and nudged loads up ~3%. Chase a rep PR on your first compound.",
                               tone: .success)
        case 70..<85:
            return PlanScaling(volumeMultiplier: 1.0, intensityMultiplier: 1.0,
                               headline: "On plan",
                               detail: "Readiness is solid. Run the session as written and let RPE guide your top sets.",
                               tone: .steel)
        case 55..<70:
            return PlanScaling(volumeMultiplier: 0.85, intensityMultiplier: 0.93,
                               headline: "Trim the volume",
                               detail: "Recovery is moderate. ARIA cut ~15% of volume and held loads ~7% lighter to protect tomorrow.",
                               tone: .warning)
        default:
            return PlanScaling(volumeMultiplier: 0.65, intensityMultiplier: 0.85,
                               headline: "Recovery day protocol",
                               detail: "Readiness is low. ARIA pulled volume and intensity back hard — move well, leave 3+ reps in reserve, prioritize sleep.",
                               tone: .danger)
        }
    }

    /// Applies scaling to a single plan row (non-destructive — returns a new Exercise).
    static func scaled(_ exercise: Exercise, by scaling: PlanScaling) -> Exercise {
        guard scaling.isModified else { return exercise }
        var ex = exercise
        ex.sets = max(1, Int((Double(exercise.sets) * scaling.volumeMultiplier).rounded()))
        if let w = exercise.weight, w > 0 {
            ex.weight = max(5, Int(((Double(w) * scaling.intensityMultiplier) / 5).rounded()) * 5)
        }
        return ex
    }

    // ── Intra-set: recommend the next set from live data ──────────────────────
    static func recommend(
        definition: ExerciseDefinition?,
        targetReps: Int, targetRPE: Int, baseRest: Int, currentWeight: Int,
        lastRPE: Int?, lastReps: Int?,
        readiness: ReadinessData, experience: ExperienceLevel,
        currentHR: Int, hrZone: Int, spO2: Int,
        painSeverity: Int?, painLocation: String?
    ) -> SetRecommendation {
        var rec = SetRecommendation(weightDelta: 0, repTarget: targetReps, restSeconds: baseRest,
                                    rpeTarget: targetRPE, primaryAction: .hold,
                                    rationale: "Match last set and own every rep.")

        // 1) Pain trumps everything (sports-medicine first principle).
        if let sev = painSeverity, sev >= 7 {
            rec.primaryAction = .stopExercise(reason: painLocation ?? "pain")
            rec.rationale = "Sharp \(painLocation?.lowercased() ?? "joint") pain at \(sev)/10 — stop this movement. ARIA will swap to a joint-friendly option."
            return rec
        }
        if let sev = painSeverity, sev >= 5, let loc = painLocation,
           (definition?.painContraindications.contains(loc) ?? false) {
            rec.primaryAction = .substitute(reason: loc)
            rec.rationale = "\(loc) discomfort on a movement that loads it — ARIA is lining up a substitution."
            return rec
        }

        // 2) Cardiopulmonary guardrails — extend rest before more load.
        if spO2 < 94 {
            rec.primaryAction = .extendRest(45)
            rec.restSeconds = baseRest + 45
            rec.rationale = "O₂ dipped to \(spO2)%. Breathe it back above 95% before the next set."
            return rec
        }
        if hrZone >= 5 {
            rec.primaryAction = .extendRest(30)
            rec.restSeconds = baseRest + 30
            rec.rationale = "HR is in Zone 5 (\(currentHR) bpm). +30s rest so strength output stays high."
            return rec
        }

        // 3) RIR/RPE autoregulation off the last set.
        let isCompound = definition?.isCompound ?? true
        let loadStep = isCompound ? (experience == .beginner ? 5 : 10) : 5
        if let rpe = lastRPE {
            let reps = lastReps ?? targetReps
            if rpe <= targetRPE - 2 && reps >= targetReps {
                rec.weightDelta = loadStep
                rec.primaryAction = .increaseLoad(loadStep)
                rec.rationale = "Last set was RPE \(rpe) with reps in the tank — add \(loadStep) lb and keep the bar speed."
            } else if rpe >= targetRPE + 1 || reps < max(1, targetReps - 2) {
                if readiness.overall < 60 {
                    rec.weightDelta = -loadStep
                    rec.primaryAction = .decreaseLoad(loadStep)
                    rec.rationale = "RPE \(rpe) on low readiness — drop \(loadStep) lb and keep crisp reps."
                } else {
                    rec.repTarget = max(1, targetReps - 2)
                    rec.primaryAction = .reduceReps(2)
                    rec.rationale = "RPE \(rpe) is past target — hold the load, aim for \(rec.repTarget) clean reps."
                }
            } else if rpe == targetRPE - 1 {
                rec.primaryAction = .hold
                rec.rationale = "Dialed in at RPE \(rpe). Repeat the load and chase one more rep if it moves well."
            }
        } else {
            // First working set — anchor to readiness.
            if readiness.overall >= 85 {
                rec.rationale = "Recovery is high — treat the first set as a primer, then push the top set."
            } else if readiness.overall < 60 {
                rec.rpeTarget = max(6, targetRPE - 1)
                rec.rationale = "Cap effort near RPE \(rec.rpeTarget) today and leave reps in reserve."
            }
        }

        // 4) Rest length: heavier compounds + higher effort → longer.
        if rec.restSeconds == baseRest {
            if isCompound && rec.rpeTarget >= 8 { rec.restSeconds = max(baseRest, 120) }
            else if !isCompound { rec.restSeconds = min(baseRest, 75) }
        }
        return rec
    }

    /// Finds a joint-friendly replacement for a flagged movement.
    static func substitution(for exercise: Exercise, painLocation: String) -> ExerciseDefinition? {
        let current = ExerciseLibrary.definition(for: exercise)
        // Prefer the movement's own listed substitutes that don't load the painful joint.
        if let subs = current?.substitutes {
            for name in subs {
                if let def = ExerciseLibrary.match(name), !def.painContraindications.contains(painLocation) {
                    return def
                }
            }
        }
        // Otherwise: same pattern/region, equipment-light, no contraindication.
        guard let current else { return nil }
        return ExerciseLibrary.all.first { def in
            def.id != current.id
            && def.region == current.region
            && !def.painContraindications.contains(painLocation)
            && def.mechanic == current.mechanic
        }
    }
}
