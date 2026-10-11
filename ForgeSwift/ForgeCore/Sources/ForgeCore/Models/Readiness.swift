import SwiftUI

// MARK: - Readiness (shared model + calculator)
//
// Mirrors the iOS `ReadinessData` semantics (overall / sleepQuality /
// recoveryScore bands) while adding two things the watch needs:
//
// 1. A pure, testable calculator that turns raw HealthKit-derived inputs
//    into a score on-device (no network required for a glanceable wrist
//    number).
// 2. An explicit `confidence` value. SimRunner's epistemic-honesty rule
//    applies on the wrist too: when we only have partial data we say so
//    instead of pretending precision.

public enum ReadinessBand: String, Codable, CaseIterable, Sendable {
    case peak
    case good
    case fair
    case low

    public init(score: Int) {
        switch HomeReadinessTokens.band(for: score) {
        case .peak: self = .peak
        case .good: self = .good
        case .fair: self = .fair
        case .low: self = .low
        }
    }

    /// Accepts Home ids and the retired Primed / Ready / Moderate / Recovery
    /// raw values so persisted watch snapshots keep decoding.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "peak", "primed": self = .peak
        case "good", "ready": self = .good
        case "fair", "moderate": self = .fair
        case "low", "recovery": self = .low
        default:
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Unknown readiness band \(raw)")
            )
        }
    }

    public var label: String {
        switch self {
        case .peak: return HomeReadinessTokens.Band.peak.label
        case .good: return HomeReadinessTokens.Band.good.label
        case .fair: return HomeReadinessTokens.Band.fair.label
        case .low: return HomeReadinessTokens.Band.low.label
        }
    }

    /// Home band hex. Low is the alert color on the ring; miss / rest
    /// chrome still uses steel (`HomeReadinessTokens.missHex`).
    public var color: Color {
        Color(forgeHex: HomeReadinessTokens.hex(for: minScore))
    }

    public var hex: String {
        HomeReadinessTokens.hex(for: minScore)
    }

    public var minScore: Int {
        switch self {
        case .peak: return HomeReadinessTokens.Band.peak.minScore
        case .good: return HomeReadinessTokens.Band.good.minScore
        case .fair: return HomeReadinessTokens.Band.fair.minScore
        case .low: return HomeReadinessTokens.Band.low.minScore
        }
    }

    /// Identity-first, forward-looking. Never clinical, never guilt.
    public var supportiveDescriptor: String {
        switch self {
        case .peak: return "You're at Peak. A full session fits if you want it."
        case .good: return "You're at Good. A solid session still makes you someone who trains."
        case .fair: return "You're at Fair. Train smart — a lighter win still counts."
        case .low: return "You're at Low. A lighter win still makes today count."
        }
    }
}

/// Raw inputs the watch can gather locally. Everything is optional:
/// the calculator degrades gracefully and reports its confidence.
public struct ReadinessInputs: Sendable, Equatable {
    public var hrvMs: Double?
    public var hrvBaselineMs: Double?
    public var restingHR: Double?
    public var restingHRBaseline: Double?
    public var sleepMinutes: Double?
    public var sleepNeedMinutes: Double
    public var deepSleepMinutes: Double?
    public var remSleepMinutes: Double?
    /// 0...1 rough strain of the previous day (nil = unknown).
    public var yesterdayStrain: Double?

    public init(
        hrvMs: Double? = nil,
        hrvBaselineMs: Double? = nil,
        restingHR: Double? = nil,
        restingHRBaseline: Double? = nil,
        sleepMinutes: Double? = nil,
        sleepNeedMinutes: Double = 8 * 60,
        deepSleepMinutes: Double? = nil,
        remSleepMinutes: Double? = nil,
        yesterdayStrain: Double? = nil
    ) {
        self.hrvMs = hrvMs
        self.hrvBaselineMs = hrvBaselineMs
        self.restingHR = restingHR
        self.restingHRBaseline = restingHRBaseline
        self.sleepMinutes = sleepMinutes
        self.sleepNeedMinutes = sleepNeedMinutes
        self.deepSleepMinutes = deepSleepMinutes
        self.remSleepMinutes = remSleepMinutes
        self.yesterdayStrain = yesterdayStrain
    }
}

public struct ReadinessScore: Codable, Sendable, Equatable {
    public var overall: Int
    public var sleepQuality: Int
    public var recovery: Int
    /// 0...1 — how much signal backed this score. Below ~0.4 the UI should
    /// present the number as an estimate ("about", "roughly"), never as fact.
    public var confidence: Double
    public var band: ReadinessBand { ReadinessBand(score: overall) }

    public init(overall: Int, sleepQuality: Int, recovery: Int, confidence: Double) {
        self.overall = overall
        self.sleepQuality = sleepQuality
        self.recovery = recovery
        self.confidence = confidence
    }
}

public enum ReadinessCalculator {

    /// Weighted blend: sleep 45%, HRV-vs-baseline 30%, resting-HR-vs-baseline
    /// 15%, prior-day strain 10%. Missing components redistribute their
    /// weight and lower confidence instead of dragging the score down —
    /// absence of data is not evidence of poor recovery.
    public static func score(from inputs: ReadinessInputs) -> ReadinessScore {
        var weighted: [(value: Double, weight: Double)] = []

        let sleepComponent = sleepScore(inputs)
        if let sleep = sleepComponent { weighted.append((sleep, 0.45)) }

        if let hrv = inputs.hrvMs, let base = inputs.hrvBaselineMs, base > 0 {
            // ±30% around baseline maps to 0...100, centered at 75.
            let ratio = hrv / base
            let value = clamp(75 + (ratio - 1.0) / 0.30 * 25, 0, 100)
            weighted.append((value, 0.30))
        }

        if let rhr = inputs.restingHR, let base = inputs.restingHRBaseline, base > 0 {
            // Elevated resting HR vs baseline is a recovery cost signal.
            let delta = (rhr - base) / base
            let value = clamp(80 - delta / 0.15 * 30, 0, 100)
            weighted.append((value, 0.15))
        }

        if let strain = inputs.yesterdayStrain {
            let value = clamp(90 - strain * 45, 0, 100)
            weighted.append((value, 0.10))
        }

        let totalWeight = weighted.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else {
            return ReadinessScore(overall: 0, sleepQuality: 0, recovery: 0, confidence: 0)
        }

        let overall = weighted.reduce(0) { $0 + $1.value * $1.weight } / totalWeight
        let recoveryPairs = weighted.dropFirst(sleepComponent == nil ? 0 : 1)
        let recoveryWeight = recoveryPairs.reduce(0) { $0 + $1.weight }
        let recovery = recoveryWeight > 0
            ? recoveryPairs.reduce(0) { $0 + $1.value * $1.weight } / recoveryWeight
            : overall

        return ReadinessScore(
            overall: Int(overall.rounded()),
            sleepQuality: Int((sleepComponent ?? overall).rounded()),
            recovery: Int(recovery.rounded()),
            confidence: clamp(totalWeight, 0, 1)
        )
    }

    private static func sleepScore(_ inputs: ReadinessInputs) -> Double? {
        guard let sleep = inputs.sleepMinutes, sleep > 0 else { return nil }
        let durationScore = clamp(sleep / inputs.sleepNeedMinutes, 0, 1.1) * 80
        var architectureBonus = 10.0 // neutral midpoint when stages are unknown
        if let deep = inputs.deepSleepMinutes {
            // ~13-23% deep is typical; 60+ min earns the full bonus.
            architectureBonus = clamp(deep / 60.0, 0, 1) * 12
        }
        if let rem = inputs.remSleepMinutes {
            architectureBonus += clamp(rem / 90.0, 0, 1) * 8
        } else {
            architectureBonus += 4
        }
        return clamp(durationScore + architectureBonus, 0, 100)
    }

    private static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}
