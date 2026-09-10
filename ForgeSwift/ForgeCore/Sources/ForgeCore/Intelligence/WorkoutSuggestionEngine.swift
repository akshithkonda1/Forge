import Foundation

// MARK: - WorkoutSuggestionEngine
//
// The workout sibling of MindfulnessSuggestionEngine: pure, deterministic,
// on-device. Readiness decides the *shape* of the day's training; the user
// always decides whether to follow it. Same voice rules: supportive,
// <= 2 sentences, hedged when confidence is low, zero guilt.

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
            // Not enough signal to prescribe intensity, so offer the safe
            // middle and say why instead of faking certainty.
            return WorkoutSuggestion(
                type: .cardio,
                targetZone: 2,
                reason: "I don't have enough data yet to read your recovery, so easy Zone 2 is the honest call. Move how you feel - we'll calibrate as I learn you.",
                trigger: "low-confidence-default"
            )
        }

        switch ReadinessBand(score: readiness) {
        case .recovery:
            return WorkoutSuggestion(
                type: .mobility,
                targetZone: 1,
                reason: "Recovery-day readiness - gentle mobility keeps you moving while your body finishes rebuilding. Easy today is what makes hard possible later this week.",
                trigger: "recovery-band"
            )
        case .moderate:
            return WorkoutSuggestion(
                type: .cardio,
                targetZone: 2,
                reason: "Readiness is middling, so Zone 2 pays the most today - real fitness, low recovery cost. Save the intensity for a greener day.",
                trigger: "moderate-band"
            )
        case .ready:
            return WorkoutSuggestion(
                type: .strength,
                targetZone: 3,
                reason: "Solid recovery - a proper strength session will land well today. Steady effort, quality reps.",
                trigger: "ready-band"
            )
        case .primed:
            return WorkoutSuggestion(
                type: .hiit,
                targetZone: 4,
                reason: "You're primed - today can absorb real intensity if you want it. Reach for it, or bank the readiness; both are winning.",
                trigger: "primed-band"
            )
        }
    }
}

/// Upcoming classified events (kinds + days-until) reshape training.
/// A wedding in two weeks is lighter, more progressive, less volume, with
/// chest / arms / abs emphasis so a suit still fits. Wedding day stays protect.
public struct EventTrainingPlan: Sendable, Equatable {
    public var kind: String
    public var daysUntil: Int
    public var emphasis: [String]
    public var progressive: Bool
    public var reduceVolume: Bool
    public var keepLight: Bool
    public var reason: String

    public init(
        kind: String,
        daysUntil: Int,
        emphasis: [String],
        progressive: Bool,
        reduceVolume: Bool,
        keepLight: Bool,
        reason: String
    ) {
        self.kind = kind
        self.daysUntil = daysUntil
        self.emphasis = emphasis
        self.progressive = progressive
        self.reduceVolume = reduceVolume
        self.keepLight = keepLight
        self.reason = reason
    }
}

public enum EventTrainingPolicy: Sendable {
    public static func plan(fromTags tags: [String]) -> EventTrainingPlan? {
        let horizon = parseHorizon(tags)
        if let wedding = horizon.first(where: { $0.kind == "wedding" }) {
            return weddingPlan(daysUntil: wedding.days)
        }
        return nil
    }

    public static func weddingPlan(daysUntil: Int) -> EventTrainingPlan {
        if daysUntil <= 0 {
            return EventTrainingPlan(
                kind: "wedding",
                daysUntil: daysUntil,
                emphasis: [],
                progressive: false,
                reduceVolume: true,
                keepLight: true,
                reason: "Wedding day — protect the event, skip the hero session."
            )
        }
        return EventTrainingPlan(
            kind: "wedding",
            daysUntil: daysUntil,
            emphasis: ["chest", "arms", "abs"],
            progressive: true,
            reduceVolume: true,
            keepLight: daysUntil <= 7,
            reason: "Wedding in \(daysUntil) day\(daysUntil == 1 ? "" : "s") — progressive lighter loads, less volume, more recovery, chest/arms/abs so the suit sits right."
        )
    }

    public static func parseHorizon(_ tags: [String]) -> [(kind: String, days: Int)] {
        var out: [(kind: String, days: Int)] = []
        for tag in tags {
            guard tag.hasPrefix("calendar:horizon:") else { continue }
            let rest = String(tag.dropFirst("calendar:horizon:".count))
            let parts = rest.split(separator: ":")
            guard parts.count == 2, let days = Int(parts[1]) else { continue }
            out.append((kind: String(parts[0]), days: days))
        }
        return out.sorted { $0.days < $1.days }
    }
}
