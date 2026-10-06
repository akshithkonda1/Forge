import Foundation

// ============================================================
// MARK: - Readiness Forecast
// ============================================================

/// Predicts *tomorrow morning's* readiness, tonight.
///
/// Oura, Whoop, and Apple Health all report today's state. Nobody in the
/// consumer space forecasts tomorrow — yet tomorrow is the decision that
/// matters ("should I move my intervals to Thursday?"). This engine is the
/// forecasting half of that answer; `TrainingLoadModel` is the load half.
///
/// The model is deliberately transparent: every point of movement is
/// attributed to a named driver the UI can show. A black-box score cannot
/// coach; an explained forecast can.
public enum ReadinessForecastEngine {

    // MARK: - Input

    /// Everything the forecast needs. Missing baselines degrade confidence,
    /// never correctness — the engine says what it doesn't know.
    public struct Input: Sendable {
        /// Today's readiness, 0–100.
        public var currentReadiness: Int
        /// Last night's sleep, minutes.
        public var sleepMinutes: Int
        /// Personal sleep need, minutes. Defaults to 8h when unknown.
        public var sleepNeedMinutes: Int
        /// Today's HRV (ms, SDNN-shaped).
        public var hrvMs: Int
        /// Personal HRV baseline (ms). Nil when not yet established.
        public var hrvBaselineMs: Int?
        /// Today's resting HR (bpm).
        public var restingHR: Int
        /// Personal resting-HR baseline (bpm). Nil when unknown.
        public var restingHRBaseline: Int?
        /// Today's training strain, 0–21 (Whoop-scale equivalent).
        public var todayStrain: Double
        /// Planned strain for the rest of today (this evening's session), 0–21.
        public var plannedStrain: Double
        /// Acute:chronic workload ratio from `TrainingLoadModel`, 7d:28d.
        /// Nil when history is too short.
        public var acwr: Double?
        /// Self-reported stress, 0–100.
        public var stressLevel: Int
        /// Whether the person is in luteal phase (recovery is slower).
        /// Nil when cycle tracking is off.
        public var isLutealPhase: Bool?

        public init(
            currentReadiness: Int,
            sleepMinutes: Int,
            sleepNeedMinutes: Int = 480,
            hrvMs: Int,
            hrvBaselineMs: Int? = nil,
            restingHR: Int,
            restingHRBaseline: Int? = nil,
            todayStrain: Double,
            plannedStrain: Double = 0,
            acwr: Double? = nil,
            stressLevel: Int,
            isLutealPhase: Bool? = nil
        ) {
            self.currentReadiness = currentReadiness
            self.sleepMinutes = sleepMinutes
            self.sleepNeedMinutes = sleepNeedMinutes
            self.hrvMs = hrvMs
            self.hrvBaselineMs = hrvBaselineMs
            self.restingHR = restingHR
            self.restingHRBaseline = restingHRBaseline
            self.todayStrain = todayStrain
            self.plannedStrain = plannedStrain
            self.acwr = acwr
            self.stressLevel = stressLevel
            self.isLutealPhase = isLutealPhase
        }
    }

    // MARK: - Output

    public enum Confidence: String, Sendable {
        case low, medium, high
    }

    /// Which way ARIA should lean tomorrow morning.
    public enum Posture: String, Sendable {
        /// Green light — the body can absorb load.
        case push
        /// Normal training day.
        case steady
        /// Cap intensity; favor technique and aerobic work.
        case protect
        /// Take the rest day. The forecast is confident it pays off.
        case rest

        public var glanceTitle: String {
            switch self {
            case .push: return "Green light"
            case .steady: return "Steady"
            case .protect: return "Protect"
            case .rest: return "Rest"
            }
        }

        public var keepLight: Bool {
            self == .protect || self == .rest
        }
    }

    public struct Driver: Sendable, Identifiable {
        public var id: String { title }
        public var title: String
        public var detail: String
        /// Points added to (or removed from) the forecast.
        public var impact: Int
        /// SF Symbol name.
        public var icon: String

        public init(title: String, detail: String, impact: Int, icon: String) {
            self.title = title
            self.detail = detail
            self.impact = impact
            self.icon = icon
        }
    }

    public struct Forecast: Sendable {
        /// Predicted readiness tomorrow morning, 0–100.
        public var predictedScore: Int
        public var confidence: Confidence
        public var drivers: [Driver]
        public var recommendation: String
        public var posture: Posture

        /// Tags ARIA already reads on `lifestyle.recentPatterns`.
        public var ariaTags: [String] {
            [
                "forecast:tomorrow:\(predictedScore):\(posture.rawValue)",
                "forecast:confidence:\(confidence.rawValue)",
            ]
        }

        /// The prompt Home, Watch, and tests all send when someone asks ARIA
        /// about tomorrow. One function — the button is not a tab switch.
        public var chatPrompt: String {
            "Tomorrow's readiness looks like \(predictedScore) with a \(posture.rawValue) day. \(recommendation) How should I train around that?"
        }

        /// One line ARIA can lead with. Lifestyle coach, not a diagnosis.
        public var steeringLine: String {
            switch posture {
            case .push:
                return "Tomorrow looks available — keep the hard session if they want it."
            case .steady:
                return "Tomorrow looks like a normal training day — keep the plan."
            case .protect:
                return "Tomorrow looks like a cap-intensity day — protect the session, don't add load."
            case .rest:
                return "Tomorrow looks like a rest day — showing up easy beats pushing through."
            }
        }

        public var glanceTitle: String { posture.glanceTitle }

        public var glanceLine: String {
            "Tomorrow \(predictedScore) · \(glanceTitle)"
        }
    }

    public static func parseTag(_ token: String) -> (Int, Posture)? {
        let parts = token.split(separator: ":").map(String.init)
        guard parts.count >= 4, parts[0] == "forecast", parts[1] == "tomorrow",
              let score = Int(parts[2]),
              let posture = Posture(rawValue: parts[3]) else { return nil }
        return (score, posture)
    }

    // MARK: - Model

    public static func forecast(_ input: Input) -> Forecast {
        var score = Double(input.currentReadiness)
        var drivers: [Driver] = []
        var knownSignals = 0
        var totalSignals = 0

        // --- Sleep debt ---
        // Each hour under need costs ~8 points; each hour over repays ~4
        // (oversleep repays less than the debt cost — sleep isn't a bank).
        totalSignals += 1
        let sleepDebtHours = Double(input.sleepNeedMinutes - input.sleepMinutes) / 60.0
        if sleepDebtHours > 0.25 {
            let impact = -Int(min(20, sleepDebtHours * 8))
            score += Double(impact)
            drivers.append(Driver(
                title: "Sleep debt",
                detail: String(format: "%.1fh under your need tonight", sleepDebtHours),
                impact: impact,
                icon: "moon.zzz.fill"
            ))
            knownSignals += 1
        } else if sleepDebtHours < -0.5 {
            let impact = min(6, Int(-sleepDebtHours * 4))
            score += Double(impact)
            drivers.append(Driver(
                title: "Sleep surplus",
                detail: "Extra sleep banked tonight",
                impact: impact,
                icon: "moon.stars.fill"
            ))
            knownSignals += 1
        } else {
            knownSignals += 1
        }

        // --- HRV vs baseline ---
        totalSignals += 1
        if let baseline = input.hrvBaselineMs, baseline > 0, input.hrvMs > 0 {
            let deviation = Double(input.hrvMs - baseline) / Double(baseline)
            // ±30% deviation maps to ±15 points against the forecast, capped.
            // Below baseline drags the score down; above lifts it.
            let impact = Int(max(-15, min(12, deviation * 50)))
            if abs(impact) >= 2 {
                score += Double(impact)
                drivers.append(Driver(
                    title: impact < 0 ? "HRV suppressed" : "HRV elevated",
                    detail: String(format: "%d%% vs your baseline", Int(deviation * 100)),
                    impact: impact,
                    icon: "waveform.path.ecg"
                ))
            }
            knownSignals += 1
        }

        // --- Resting HR vs baseline ---
        totalSignals += 1
        if let baseline = input.restingHRBaseline, baseline > 0, input.restingHR > 0 {
            let delta = input.restingHR - baseline
            if delta >= 4 {
                let impact = -min(10, (delta - 3) * 2)
                score += Double(impact)
                drivers.append(Driver(
                    title: "Resting HR elevated",
                    detail: "+\(delta) bpm vs baseline — recovery incomplete",
                    impact: impact,
                    icon: "heart.fill"
                ))
                knownSignals += 1
            } else {
                knownSignals += 1
            }
        }

        // --- Today's + planned strain ---
        totalSignals += 1
        let combinedStrain = input.todayStrain + input.plannedStrain
        if combinedStrain >= 16 {
            let impact = -12
            score += Double(impact)
            drivers.append(Driver(
                title: "Heavy load today",
                detail: String(format: "Strain %.1f — expect residual fatigue", combinedStrain),
                impact: impact,
                icon: "flame.fill"
            ))
        } else if combinedStrain >= 10 {
            let impact = -6
            score += Double(impact)
            drivers.append(Driver(
                title: "Moderate load today",
                detail: String(format: "Strain %.1f — mild fatigue carryover", combinedStrain),
                impact: impact,
                icon: "flame"
            ))
        } else if combinedStrain < 4 {
            let impact = 5
            score += Double(impact)
            drivers.append(Driver(
                title: "Recovery day",
                detail: "Low strain lets adaptation catch up",
                impact: impact,
                icon: "leaf.fill"
            ))
        }
        knownSignals += 1

        // --- Acute:chronic workload ratio ---
        totalSignals += 1
        if let acwr = input.acwr {
            if acwr > 1.5 {
                let impact = -10
                score += Double(impact)
                drivers.append(Driver(
                    title: "Load spiking",
                    detail: String(format: "This week is %.1fx your 4-week average — overreaching risk", acwr),
                    impact: impact,
                    icon: "exclamationmark.triangle.fill"
                ))
            } else if acwr < 0.8 {
                let impact = 4
                score += Double(impact)
                drivers.append(Driver(
                    title: "Load dip",
                    detail: String(format: "This week is %.1fx your average — freshness building", acwr),
                    impact: impact,
                    icon: "arrow.down.circle.fill"
                ))
            }
            knownSignals += 1
        }

        // --- Stress ---
        totalSignals += 1
        if input.stressLevel >= 70 {
            let impact = -6
            score += Double(impact)
            drivers.append(Driver(
                title: "High stress",
                detail: "Mental load taxes recovery too",
                impact: impact,
                icon: "brain.head.profile"
            ))
        } else if input.stressLevel <= 25 {
            let impact = 3
            score += Double(impact)
            drivers.append(Driver(
                title: "Low stress",
                detail: "Recovery environment is clean",
                impact: impact,
                icon: "checkmark.circle.fill"
            ))
        }
        knownSignals += 1

        // --- Luteal phase (recovery is measurably slower) ---
        if input.isLutealPhase == true {
            let impact = -4
            score += Double(impact)
            drivers.append(Driver(
                title: "Luteal phase",
                detail: "Recovery runs ~5% slower — plan lighter",
                impact: impact,
                icon: "circle.dotted"
            ))
        }

        // --- Clamp and posture ---
        let predicted = Int(max(5, min(98, score.rounded())))
        let posture: Posture
        switch predicted {
        case 80...: posture = .push
        case 65..<80: posture = .steady
        case 50..<65: posture = .protect
        default: posture = .rest
        }

        let coverage = Double(knownSignals) / Double(max(1, totalSignals))
        let confidence: Confidence
        switch coverage {
        case 0.85...: confidence = .high
        case 0.6..<0.85: confidence = .medium
        default: confidence = .low
        }

        let recommendation = makeRecommendation(
            posture: posture,
            drivers: drivers,
            predicted: predicted,
            current: input.currentReadiness
        )

        // Strongest movers first — the UI shows the top 3.
        let sorted = drivers.sorted { abs($0.impact) > abs($1.impact) }

        return Forecast(
            predictedScore: predicted,
            confidence: confidence,
            drivers: sorted,
            recommendation: recommendation,
            posture: posture
        )
    }

    private static func makeRecommendation(
        posture: Posture,
        drivers: [Driver],
        predicted: Int,
        current: Int
    ) -> String {
        let delta = predicted - current
        let trend = delta >= 5 ? "trending up" : (delta <= -5 ? "dipping" : "holding steady")
        let leadDriver = drivers.first.map { " — \($0.title.lowercased()) is the biggest factor" } ?? ""
        switch posture {
        case .push:
            return "Green light for tomorrow (\(trend)\(leadDriver)). Good day for the hard session you've been holding."
        case .steady:
            return "Normal training day tomorrow (\(trend)\(leadDriver)). Keep the plan as written."
        case .protect:
            return "Cap intensity tomorrow (\(trend)\(leadDriver)). Swap intervals for aerobic base or technique work."
        case .rest:
            return "Take the rest day tomorrow (\(trend)\(leadDriver)). It pays back more than pushing through."
        }
    }
}
