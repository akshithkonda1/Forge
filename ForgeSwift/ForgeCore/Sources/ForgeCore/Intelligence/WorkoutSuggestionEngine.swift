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

/// Lifestyle QoL reshapes training the same way event horizons do — strained or
/// depleted life rhythm means lighter volume, never a hero session. Client is the
/// only scorer; this policy only reads `qol:` / `qol:band:` tags Life already wrote.
public struct QualityOfLifeTrainingPlan: Sendable, Equatable {
    public var overall: Int
    public var band: QualityOfLifeBand
    public var keepLight: Bool
    public var reduceVolume: Bool
    public var maxDuration: Int
    public var reason: String

    public init(
        overall: Int,
        band: QualityOfLifeBand,
        keepLight: Bool,
        reduceVolume: Bool,
        maxDuration: Int,
        reason: String
    ) {
        self.overall = overall
        self.band = band
        self.keepLight = keepLight
        self.reduceVolume = reduceVolume
        self.maxDuration = maxDuration
        self.reason = reason
    }
}

public enum QualityOfLifeTrainingPolicy: Sendable {
    public static func plan(fromTags tags: [String]) -> QualityOfLifeTrainingPlan? {
        guard let overall = parseOverall(tags) else { return nil }
        let band = parseBand(tags) ?? QualityOfLifeBand(score: overall)
        let mind = parsePillar(tags, key: "mind")
        let sleep = parsePillar(tags, key: "sleep")
        return plan(overall: overall, band: band, mindScore: mind, sleepScore: sleep)
    }

    public static func plan(
        overall: Int,
        band: QualityOfLifeBand,
        mindScore: Int? = nil,
        sleepScore: Int? = nil
    ) -> QualityOfLifeTrainingPlan? {
        let clamped = max(0, min(100, overall))
        switch band {
        case .depleted:
            return QualityOfLifeTrainingPlan(
                overall: clamped,
                band: band,
                keepLight: true,
                reduceVolume: true,
                maxDuration: 30,
                reason: "Lifestyle QoL \(clamped)/100 (depleted) — recovery-first session, keep it light."
            )
        case .strained:
            let weakMind = (mindScore ?? 100) < 55
            let weakSleep = (sleepScore ?? 100) < 55
            let keepLight = weakMind || weakSleep || clamped < 60
            return QualityOfLifeTrainingPlan(
                overall: clamped,
                band: band,
                keepLight: keepLight,
                reduceVolume: true,
                maxDuration: keepLight ? 35 : 40,
                reason: keepLight
                    ? "Lifestyle QoL \(clamped)/100 (strained) — mind/sleep asking for ease, lighter volume."
                    : "Lifestyle QoL \(clamped)/100 (strained) — trim volume, protect recovery."
            )
        case .steady, .thriving:
            return nil
        }
    }

    public static func parseOverall(_ tags: [String]) -> Int? {
        for tag in tags {
            let lower = tag.lowercased()
            guard lower.hasPrefix("qol:"), !lower.hasPrefix("qol:band:"),
                  !lower.hasPrefix("qol:driver:"), !lower.hasPrefix("qol:missing:"),
                  !lower.hasPrefix("qol:pillar:"), !lower.hasPrefix("qolconf:") else { continue }
            let rest = String(lower.dropFirst(4))
            if let value = Int(rest.split(separator: ":").first.map(String.init) ?? rest) {
                return max(0, min(100, value))
            }
        }
        return nil
    }

    public static func parseBand(_ tags: [String]) -> QualityOfLifeBand? {
        for tag in tags {
            let lower = tag.lowercased()
            guard lower.hasPrefix("qol:band:") else { continue }
            let raw = String(lower.dropFirst("qol:band:".count))
            if let band = QualityOfLifeBand(rawValue: raw) { return band }
        }
        return nil
    }

    public static func parsePillar(_ tags: [String], key: String) -> Int? {
        let prefix = "qol:pillar:\(key.lowercased()):"
        for tag in tags {
            let lower = tag.lowercased()
            guard lower.hasPrefix(prefix) else { continue }
            let rest = String(lower.dropFirst(prefix.count))
            if let value = Int(rest) { return max(0, min(100, value)) }
        }
        return nil
    }
}
