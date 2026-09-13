import Foundation

/// One night's numbers, stripped of HealthKit types so scoring is testable.
public struct SleepNightMetrics: Equatable, Sendable {
    public var totalHours: Double
    public var deepMinutes: Double
    public var remMinutes: Double
    public var efficiencyPercent: Double
    public var wakeConsistency: Double

    public init(
        totalHours: Double,
        deepMinutes: Double,
        remMinutes: Double,
        efficiencyPercent: Double,
        wakeConsistency: Double
    ) {
        self.totalHours = totalHours
        self.deepMinutes = deepMinutes
        self.remMinutes = remMinutes
        self.efficiencyPercent = efficiencyPercent
        self.wakeConsistency = wakeConsistency
    }

    /// Asleep / (asleep + awake). `totalHours` is asleep time.
    public static func efficiencyPercent(asleepHours: Double, awakeMinutes: Double) -> Double {
        let asleep = max(0, asleepHours * 60)
        let bed = asleep + max(0, awakeMinutes)
        guard bed > 0 else { return 0 }
        return min(100, max(0, (asleep / bed) * 100))
    }
}

public struct SleepChronotypeTargets: Equatable, Sendable {
    public var targetHours: Double
    public var deepGoalMinutes: Double
    public var remGoalMinutes: Double

    public init(targetHours: Double, deepGoalMinutes: Double, remGoalMinutes: Double) {
        self.targetHours = targetHours
        self.deepGoalMinutes = deepGoalMinutes
        self.remGoalMinutes = remGoalMinutes
    }
}

/// Per-person running baselines. Cold start is empty; `observe` fills them.
public struct SleepDepthBaselines: Codable, Equatable, Sendable {
    public var duration: OnlineStat
    public var deep: OnlineStat
    public var rem: OnlineStat
    public var efficiency: OnlineStat
    public var observedNightKeys: [String]

    public init(
        duration: OnlineStat = OnlineStat(),
        deep: OnlineStat = OnlineStat(),
        rem: OnlineStat = OnlineStat(),
        efficiency: OnlineStat = OnlineStat(),
        observedNightKeys: [String] = []
    ) {
        self.duration = duration
        self.deep = deep
        self.rem = rem
        self.efficiency = efficiency
        self.observedNightKeys = observedNightKeys
    }

    public var sampleCount: Int { duration.n }
}

public struct SleepDepthResult: Equatable, Sendable {
    public var score: Int
    /// 0 = chronotype formula only, 1 = fully personal.
    public var personalBlend: Double
    public var unusualFlags: [String]
    public var source: String

    public init(score: Int, personalBlend: Double, unusualFlags: [String], source: String) {
        self.score = score
        self.personalBlend = personalBlend
        self.unusualFlags = unusualFlags
        self.source = source
    }

    public var headline: String? { unusualFlags.first }
}

/// Sleep score versus *this person's* nights, blended with chronotype targets
/// until the baseline is thick enough to trust.
public enum SleepDepthScorer: Sendable {
    public static let coldStartNights = 5
    public static let fullPersonalNights = 14
    public static let unusualZ = 1.5
    public static let observedKeyCap = 60

    public static func chronotypeScore(
        metrics: SleepNightMetrics,
        targets: SleepChronotypeTargets
    ) -> Int {
        let duration = min(100, (metrics.totalHours / max(0.1, targets.targetHours)) * 100)
        let deep = min(100, (metrics.deepMinutes / max(1, targets.deepGoalMinutes)) * 100)
        let rem = min(100, (metrics.remMinutes / max(1, targets.remGoalMinutes)) * 100)
        let weighted = duration * 0.35
            + deep * 0.25
            + rem * 0.20
            + min(100, max(0, metrics.efficiencyPercent)) * 0.15
            + min(100, max(0, metrics.wakeConsistency)) * 0.05
        return min(100, max(0, Int(weighted.rounded())))
    }

    public static func score(
        metrics: SleepNightMetrics,
        targets: SleepChronotypeTargets,
        baselines: SleepDepthBaselines
    ) -> SleepDepthResult {
        let chrono = Double(chronotypeScore(metrics: metrics, targets: targets))
        let n = baselines.sampleCount
        let blend: Double
        if n < coldStartNights {
            blend = 0
        } else {
            blend = min(1, Double(n - (coldStartNights - 1)) / Double(fullPersonalNights - (coldStartNights - 1)))
        }
        let personal = personalScore(metrics: metrics, baselines: baselines)
        let mixed = chrono * (1 - blend) + personal * blend
        let flags = unusualFlags(metrics: metrics, baselines: baselines)
        let source: String
        if blend <= 0 {
            source = "chronotype"
        } else if blend >= 1 {
            source = "personal"
        } else {
            source = "blended"
        }
        return SleepDepthResult(
            score: min(100, max(0, Int(mixed.rounded()))),
            personalBlend: blend,
            unusualFlags: flags,
            source: source
        )
    }

    /// Fold a finished night into the baseline. Same `nightKey` is a no-op so
    /// HealthKit refreshes do not double-count.
    public static func observe(
        _ baselines: inout SleepDepthBaselines,
        metrics: SleepNightMetrics,
        nightKey: String
    ) {
        let key = nightKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        if baselines.observedNightKeys.contains(key) { return }
        baselines.duration.update(metrics.totalHours)
        baselines.deep.update(metrics.deepMinutes)
        baselines.rem.update(metrics.remMinutes)
        baselines.efficiency.update(metrics.efficiencyPercent)
        baselines.observedNightKeys.append(key)
        if baselines.observedNightKeys.count > observedKeyCap {
            let extra = baselines.observedNightKeys.count - observedKeyCap
            baselines.observedNightKeys.removeFirst(extra)
        }
    }

    private static func personalScore(
        metrics: SleepNightMetrics,
        baselines: SleepDepthBaselines
    ) -> Double {
        let duration = component(metrics.totalHours, baselines.duration, higherIsBetter: true)
        let deep = component(metrics.deepMinutes, baselines.deep, higherIsBetter: true)
        let rem = component(metrics.remMinutes, baselines.rem, higherIsBetter: true)
        let efficiency = component(metrics.efficiencyPercent, baselines.efficiency, higherIsBetter: true)
        return duration * 0.35
            + deep * 0.25
            + rem * 0.20
            + efficiency * 0.15
            + min(100, max(0, metrics.wakeConsistency)) * 0.05
    }

    /// Mean maps to 80, +1 SD to 95, −1 SD to 65.
    private static func component(_ value: Double, _ stat: OnlineStat, higherIsBetter: Bool) -> Double {
        guard stat.n >= 2 else { return 80 }
        let z = stat.zscore(value)
        let signed = higherIsBetter ? z : -z
        return min(100, max(0, 80 + signed * 15))
    }

    private static func unusualFlags(
        metrics: SleepNightMetrics,
        baselines: SleepDepthBaselines
    ) -> [String] {
        guard baselines.sampleCount >= coldStartNights else { return [] }
        var flags: [String] = []
        func note(_ stat: OnlineStat, _ value: Double, low: String, high: String) {
            let z = stat.zscore(value)
            if z <= -unusualZ { flags.append(low) }
            else if z >= unusualZ { flags.append(high) }
        }
        note(
            baselines.duration, metrics.totalHours,
            low: "Shorter than your usual night",
            high: "Longer than your usual night"
        )
        note(
            baselines.deep, metrics.deepMinutes,
            low: "Less deep sleep than you usually get",
            high: "More deep sleep than is usual for you"
        )
        note(
            baselines.rem, metrics.remMinutes,
            low: "Less REM than you usually get",
            high: "More REM than is usual for you"
        )
        note(
            baselines.efficiency, metrics.efficiencyPercent,
            low: "More time awake than is usual for you",
            high: "You stayed asleep more steadily than usual"
        )
        return flags
    }
}

public enum SleepDepthBaselineStore: Sendable {
    public static let defaultsKey = "forge.sleep.depthBaselines.v1"

    public static func load(defaults: UserDefaults = .standard) -> SleepDepthBaselines {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(SleepDepthBaselines.self, from: data) else {
            return SleepDepthBaselines()
        }
        return decoded
    }

    public static func save(_ baselines: SleepDepthBaselines, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(baselines) {
            defaults.set(data, forKey: defaultsKey)
        }
    }

    public static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }
}
