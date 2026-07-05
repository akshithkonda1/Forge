import Foundation

// MARK: - WorkoutSuggestionEngine
//
// The workout sibling of MindfulnessSuggestionEngine: pure, deterministic,
// on-device. Readiness decides the *shape* of the day's training; the user
// always decides whether to follow it. Same voice rules: supportive,
// ≤ 2 sentences, hedged when confidence is low, zero guilt.

public struct WorkoutSuggestion: Codable, Sendable, Equatable {
    public var type: ForgeWorkoutType
    public var targetZone: Int
    public var reason: String
    public var trigger: String

    public init(type: ForgeWorkoutType, targetZone: Int, reason: String, trigger: String) {
        self.type = type
        self.targetZone = targetZone
        self.reason = reason
        self.trigger = trigger
    }
}

public enum WorkoutSuggestionEngine {

    public static func suggest(for context: WatchARIAContext) -> WorkoutSuggestion {
        let confidence = context.readinessConfidence ?? 0

        guard let readiness = context.readinessOverall, confidence >= 0.4 else {
            // Not enough signal to prescribe intensity — offer the safe
            // middle and say why, instead of faking certainty.
            return WorkoutSuggestion(
                type: .cardio,
                targetZone: 2,
                reason: "I don't have enough data yet to read your recovery, so easy Zone 2 is the honest call. Move how you feel — we'll calibrate as I learn you.",
                trigger: "low-confidence-default"
            )
        }

        switch ReadinessBand(score: readiness) {
        case .recovery:
            return WorkoutSuggestion(
                type: .mobility,
                targetZone: 1,
                reason: "Recovery-day readiness — gentle mobility keeps you moving while your body finishes rebuilding. Easy today is what makes hard possible later this week.",
                trigger: "recovery-band"
            )
        case .moderate:
            return WorkoutSuggestion(
                type: .cardio,
                targetZone: 2,
                reason: "Readiness is middling, so Zone 2 pays the most today — real fitness, low recovery cost. Save the intensity for a greener day.",
                trigger: "moderate-band"
            )
        case .ready:
            return WorkoutSuggestion(
                type: .strength,
                targetZone: 3,
                reason: "Solid recovery — a proper strength session will land well today. Steady effort, quality reps.",
                trigger: "ready-band"
            )
        case .primed:
            return WorkoutSuggestion(
                type: .hiit,
                targetZone: 4,
                reason: "You're primed — today can absorb real intensity if you want it. Reach for it, or bank the readiness; both are winning.",
                trigger: "primed-band"
            )
        }
    }
}
