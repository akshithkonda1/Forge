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
    /// Personal HRV center, ms (geometric mean when it comes from
    /// `PersonalBaseline`).
    public var hrvBaselineMs: Double?
    /// SD of ln(HRV) across days. Nil → `ReadinessCalculator.defaultHRVSdLn`.
    public var hrvBaselineSdLn: Double?
    public var restingHR: Double?
    public var restingHRBaseline: Double?
    /// SD of resting HR across days, bpm. Nil → `defaultRestingHRSd`.
    public var restingHRBaselineSd: Double?
    public var sleepMinutes: Double?
    public var sleepNeedMinutes: Double
    public var deepSleepMinutes: Double?
    public var remSleepMinutes: Double?
    /// 0...1 rough strain of the previous day (nil = unknown).
    public var yesterdayStrain: Double?

    public init(
        hrvMs: Double? = nil,
        hrvBaselineMs: Double? = nil,
        hrvBaselineSdLn: Double? = nil,
        restingHR: Double? = nil,
        restingHRBaseline: Double? = nil,
        restingHRBaselineSd: Double? = nil,
        sleepMinutes: Double? = nil,
        sleepNeedMinutes: Double = 8 * 60,
        deepSleepMinutes: Double? = nil,
        remSleepMinutes: Double? = nil,
        yesterdayStrain: Double? = nil
    ) {
        self.hrvMs = hrvMs
        self.hrvBaselineMs = hrvBaselineMs
        self.hrvBaselineSdLn = hrvBaselineSdLn
        self.restingHR = restingHR
        self.restingHRBaseline = restingHRBaseline
        self.restingHRBaselineSd = restingHRBaselineSd
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

/// Readiness inputs as read from Health on this device. The one place the
/// iPhone and the Watch turn raw samples into `ReadinessInputs`, so the two
/// cannot show different numbers for the same morning.
public struct ReadinessHealthContext: Sendable, Equatable {
    /// Last night's staged sleep.
    public var night: SleepNight?
    /// HRV (SDNN, ms) across last night's sleep window — the stable overnight
    /// reading — or the latest reading when the night has none.
    public var hrvMs: Double?
    /// Personal HRV normal (ln space), today left out.
    public var hrvBaseline: PersonalBaseline?
    public var restingHR: Double?
    /// Personal resting-HR normal (bpm), today left out.
    public var restingHRBaseline: PersonalBaseline?
    /// When Health was read. A context from before today describes a night
    /// that is already over.
    public var readAt: Date?

    public init(
        night: SleepNight? = nil,
        hrvMs: Double? = nil,
        hrvBaseline: PersonalBaseline? = nil,
        restingHR: Double? = nil,
        restingHRBaseline: PersonalBaseline? = nil,
        readAt: Date? = nil
    ) {
        self.night = night
        self.hrvMs = hrvMs
        self.hrvBaseline = hrvBaseline
        self.restingHR = restingHR
        self.restingHRBaseline = restingHRBaseline
        self.readAt = readAt
    }

    public var hasAnySignal: Bool {
        (night?.totalMinutes ?? 0) > 0 || (hrvMs ?? 0) > 0 || (restingHR ?? 0) > 0
    }

    public func inputs(
        yesterdayStrain: Double? = nil,
        sleepNeedMinutes: Double = 8 * 60
    ) -> ReadinessInputs {
        let asleep = (night?.totalMinutes ?? 0) > 0 ? night?.totalMinutes : nil
        // Unstaged sleep (older watches, phone-only, third-party apps) arrives
        // as zero deep and zero REM. That is "stages unknown", not "no deep
        // sleep" — scoring it as zero would dock every such night.
        let staged = (night?.deepMinutes ?? 0) > 0 || (night?.remMinutes ?? 0) > 0
        return ReadinessInputs(
            hrvMs: (hrvMs ?? 0) > 0 ? hrvMs : nil,
            hrvBaselineMs: hrvBaseline?.mean,
            hrvBaselineSdLn: hrvBaseline?.spread,
            restingHR: (restingHR ?? 0) > 0 ? restingHR : nil,
            restingHRBaseline: restingHRBaseline?.mean,
            restingHRBaselineSd: restingHRBaseline?.spread,
            sleepMinutes: asleep,
            sleepNeedMinutes: sleepNeedMinutes,
            deepSleepMinutes: staged ? night?.deepMinutes : nil,
            remSleepMinutes: staged ? night?.remMinutes : nil,
            yesterdayStrain: yesterdayStrain
        )
    }
}

public enum ReadinessCalculator {

    // Typical day-to-day spread used until a personal one is known. ln(HRV)
    // between-day SD on wrist SDNN/RMSSD sits around 0.2-0.3; resting HR
    // around 2-4 bpm. Floors stop a suspiciously tight history from turning a
    // 1 ms wobble into a five-sigma event; ceilings stop a noisy one from
    // flattening every day. Same constants as readiness_calculator.py.
    public static let defaultHRVSdLn = 0.25
    public static let hrvSdLnFloor = 0.08
    public static let hrvSdLnCeiling = 0.6
    public static let defaultRestingHRSd = 3.0
    public static let restingHRSdFloor = 1.5
    public static let restingHRSdCeiling = 8.0

    /// At your own normal (z = 0) HRV scores 75 and resting HR 80; each SD of
    /// HRV moves 20 points, each SD of resting HR 12.
    public static let hrvCenter = 75.0
    public static let hrvPointsPerSd = 20.0
    public static let restingHRCenter = 80.0
    public static let restingHRPointsPerSd = 12.0

    /// Weighted blend: sleep 45%, HRV-vs-your-normal 30%, resting-HR-vs-your-
    /// normal 15%, prior-day strain 10%. Missing components redistribute their
    /// weight and lower confidence instead of dragging the score down —
    /// absence of data is not evidence of poor recovery.
    public static func score(from inputs: ReadinessInputs) -> ReadinessScore {
        var weighted: [(value: Double, weight: Double)] = []

        let sleepComponent = sleepScore(inputs)
        if let sleep = sleepComponent { weighted.append((sleep, 0.45)) }

        if let hrv = hrvComponent(
            hrvMs: inputs.hrvMs,
            baselineMs: inputs.hrvBaselineMs,
            baselineSdLn: inputs.hrvBaselineSdLn
        ) {
            weighted.append((hrv, 0.30))
        }

        if let rhr = restingHRComponent(
            restingHR: inputs.restingHR,
            baseline: inputs.restingHRBaseline,
            baselineSd: inputs.restingHRBaselineSd
        ) {
            weighted.append((rhr, 0.15))
        }

        if let strain = inputs.yesterdayStrain {
            let value = clamp(90 - clamp(strain, 0, 1) * 45, 0, 100)
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

    /// HRV vs your own normal: 75 at baseline, ±20 per SD of ln(HRV). HRV is
    /// log-normal, so half and double your normal are equally unusual.
    public static func hrvComponent(hrvMs: Double?, baselineMs: Double?, baselineSdLn: Double? = nil) -> Double? {
        guard let hrv = hrvMs, let base = baselineMs, hrv > 0, base > 0 else { return nil }
        let sd = baselineSdLn.flatMap { $0 > 0 ? $0 : nil } ?? defaultHRVSdLn
        let baseline = PersonalBaseline(mean: base, spread: sd, days: 0, logScaled: true)
        guard let z = baseline.zScore(hrv, floor: hrvSdLnFloor, ceiling: hrvSdLnCeiling) else { return nil }
        return clamp(hrvCenter + hrvPointsPerSd * z, 0, 100)
    }

    /// Resting HR vs your own normal: 80 at baseline, ∓12 per SD (bpm).
    public static func restingHRComponent(restingHR: Double?, baseline: Double?, baselineSd: Double? = nil) -> Double? {
        guard let rhr = restingHR, let base = baseline, rhr > 0, base > 0 else { return nil }
        let sd = baselineSd.flatMap { $0 > 0 ? $0 : nil } ?? defaultRestingHRSd
        let personal = PersonalBaseline(mean: base, spread: sd, days: 0, logScaled: false)
        guard let z = personal.zScore(rhr, floor: restingHRSdFloor, ceiling: restingHRSdCeiling) else { return nil }
        return clamp(restingHRCenter - restingHRPointsPerSd * z, 0, 100)
    }

    private static func sleepScore(_ inputs: ReadinessInputs) -> Double? {
        guard let sleep = inputs.sleepMinutes, sleep > 0 else { return nil }
        let need = inputs.sleepNeedMinutes > 0 ? inputs.sleepNeedMinutes : 8 * 60
        // Sleeping past your need earns no extra credit — long sleep is at
        // best neutral, and a sudden 10-hour night is as often illness as
        // recovery.
        let durationScore = clamp(sleep / need, 0, 1.0) * 80
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
