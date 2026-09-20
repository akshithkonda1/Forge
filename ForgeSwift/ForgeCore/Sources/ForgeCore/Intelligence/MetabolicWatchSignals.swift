import Foundation

/// Inputs for the Apple Watch-derived metabolic estimate.
///
/// Every value is an already-available HealthKit rollup (DailyHealthStats +
/// weekly trends) — no new HealthKit queries were added for this. A value of 0
/// (or negative) means "no data": HealthKit leaves missing fields at 0, and the
/// estimator treats them as absent rather than inventing a reading.
public struct MetabolicWatchInputs: Sendable, Equatable {
    public var restingHRBpm: Double
    public var hrvMs: Double
    public var hrvBaselineMs: Double
    public var vo2Max: Double
    public var activeCalories: Double
    public var exerciseMinutes: Double
    public var sleepHours: Double
    public var sleepBaselineHours: Double

    public init(
        restingHRBpm: Double = 0,
        hrvMs: Double = 0,
        hrvBaselineMs: Double = 0,
        vo2Max: Double = 0,
        activeCalories: Double = 0,
        exerciseMinutes: Double = 0,
        sleepHours: Double = 0,
        sleepBaselineHours: Double = 0
    ) {
        self.restingHRBpm = restingHRBpm
        self.hrvMs = hrvMs
        self.hrvBaselineMs = hrvBaselineMs
        self.vo2Max = vo2Max
        self.activeCalories = activeCalories
        self.exerciseMinutes = exerciseMinutes
        self.sleepHours = sleepHours
        self.sleepBaselineHours = sleepBaselineHours
    }
}

/// One Apple Watch-derived hint shown in the Metabolic section.
///
/// Honesty contract: `line` always names its source ("Apple Watch"), and any
/// line that interprets data (vs. merely reporting it) says "estimate". These
/// are lifestyle hints — never measurements of metabolic state, never medical
/// advice, never a diagnosis.
public struct MetabolicWatchSignal: Sendable, Equatable {
    public var id: String
    public var title: String
    public var line: String

    public init(id: String, title: String, line: String) {
        self.id = id
        self.title = title
        self.line = line
    }
}

/// The Apple Watch-derived metabolic estimate.
///
/// This exists so Metabolic Health is useful with no CGM. It is deliberately
/// NOT a score: a list of labeled, source-traceable hints plus one summary
/// line. CGM glucose remains the source of truth — `MetabolicHealthSnapshot`
/// only attaches this when there is no glucose data.
public struct MetabolicWatchEstimate: Sendable, Equatable {
    public var signals: [MetabolicWatchSignal]
    public var summaryLine: String

    public var hasSignals: Bool { !signals.isEmpty }
    public var displayLines: [String] { signals.map(\.line) }

    public static let empty = MetabolicWatchEstimate(signals: [], summaryLine: "")

    public init(signals: [MetabolicWatchSignal], summaryLine: String) {
        self.signals = signals
        self.summaryLine = summaryLine
    }

    /// Builds the estimate from watch rollups.
    ///
    /// Returns `.empty` unless at least two independent signals are present:
    /// a single data point is not a metabolic picture, and surfacing one
    /// invites over-interpretation. Zero/negative/implausible values are
    /// treated as missing, never as real readings.
    public static func evaluate(_ inputs: MetabolicWatchInputs) -> MetabolicWatchEstimate {
        var signals: [MetabolicWatchSignal] = []

        if let vo2 = plausible(inputs.vo2Max, range: 15...80) {
            signals.append(MetabolicWatchSignal(
                id: "cardio-fitness",
                title: "Cardio fitness",
                line: "≈ \(Int(vo2.rounded())) — estimated by Apple Watch"
            ))
        }

        if let rhr = plausible(inputs.restingHRBpm, range: 25...120) {
            signals.append(MetabolicWatchSignal(
                id: "resting-hr",
                title: "Resting heart rate",
                line: "\(Int(rhr.rounded())) bpm today — Apple Watch"
            ))
        }

        if let hrv = plausible(inputs.hrvMs, range: 5...300) {
            let line: String
            if let base = plausible(inputs.hrvBaselineMs, range: 5...300) {
                line = "\(Int(hrv.rounded())) ms vs your recent \(Int(base.rounded())) ms — Apple Watch estimate"
            } else {
                line = "\(Int(hrv.rounded())) ms today — Apple Watch"
            }
            signals.append(MetabolicWatchSignal(id: "hrv", title: "Heart rate variability", line: line))
        }

        let calories = inputs.activeCalories > 0 ? Int(inputs.activeCalories.rounded()) : nil
        let minutes = inputs.exerciseMinutes > 0 ? Int(inputs.exerciseMinutes.rounded()) : nil
        if calories != nil || minutes != nil {
            let bits = [
                calories.map { "\($0) active calories" },
                minutes.map { "\($0) exercise minutes" },
            ].compactMap { $0 }
            signals.append(MetabolicWatchSignal(
                id: "movement",
                title: "Movement",
                line: "\(bits.joined(separator: " · ")) today — Apple Watch"
            ))
        }

        if let sleep = plausible(inputs.sleepHours, range: 0.5...16) {
            let line: String
            if let usual = plausible(inputs.sleepBaselineHours, range: 0.5...16) {
                line = String(format: "%.1f h vs your usual %.1f h — Apple Watch estimate", sleep, usual)
            } else {
                line = String(format: "%.1f h last night — Apple Watch", sleep)
            }
            signals.append(MetabolicWatchSignal(id: "sleep", title: "Sleep", line: line))
        }

        guard signals.count >= 2 else { return .empty }

        return MetabolicWatchEstimate(
            signals: signals,
            summaryLine: "No glucose sensor connected. These are estimates from Apple Watch trends — not measurements, and not medical advice."
        )
    }
}

/// Zero/negative means "no data"; outside the range means a corrupt sample.
/// Either way the value is dropped, never presented as a reading.
private func plausible(_ value: Double, range: ClosedRange<Double>) -> Double? {
    guard value > 0, range.contains(value) else { return nil }
    return value
}
