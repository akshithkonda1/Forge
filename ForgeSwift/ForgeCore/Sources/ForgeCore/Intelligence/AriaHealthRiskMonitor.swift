import Foundation

/// On-device literacy for Watch / HealthKit vitals — not a diagnosis.
///
/// Apple Watch wrist temperature is typically an overnight deviation from
/// the wearer's baseline (`appleSleepingWristTemperature`), not a clinical
/// thermometer. Body temperature in HealthKit is whatever the user or
/// another app logged. ARIA may notice "this looks high versus typical"
/// and suggest a clinician; it must not name a disease.
public enum AriaHealthRiskKind: String, Sendable, Codable, Equatable {
    case elevatedTemperature
    case wristTemperatureRise
    case restingHeartRateSpike
    case hrvDrop
}

public enum AriaHealthRiskSeverity: String, Sendable, Codable, Equatable {
    /// A bit high versus typical. Worth noticing; not an emergency line.
    case watch
    /// More clearly elevated. Still not a diagnosis — point at a clinician.
    case concern
}

public struct AriaVitalReading: Sendable, Equatable {
    public var sampledAt: Date
    public var bodyTemperatureF: Double?
    public var wristTemperatureDeviationC: Double?
    public var restingHeartRate: Double?
    public var restingHeartRateBaseline: Double?
    public var hrvMs: Double?
    public var hrvBaselineMs: Double?
    public var hoursSinceLastWorkout: Double?

    public init(
        sampledAt: Date = Date(),
        bodyTemperatureF: Double? = nil,
        wristTemperatureDeviationC: Double? = nil,
        restingHeartRate: Double? = nil,
        restingHeartRateBaseline: Double? = nil,
        hrvMs: Double? = nil,
        hrvBaselineMs: Double? = nil,
        hoursSinceLastWorkout: Double? = nil
    ) {
        self.sampledAt = sampledAt
        self.bodyTemperatureF = bodyTemperatureF
        self.wristTemperatureDeviationC = wristTemperatureDeviationC
        self.restingHeartRate = restingHeartRate
        self.restingHeartRateBaseline = restingHeartRateBaseline
        self.hrvMs = hrvMs
        self.hrvBaselineMs = hrvBaselineMs
        self.hoursSinceLastWorkout = hoursSinceLastWorkout
    }
}

public struct AriaHealthRiskFinding: Sendable, Equatable {
    public var kind: AriaHealthRiskKind
    public var severity: AriaHealthRiskSeverity
    public var title: String
    /// Lock-screen safe. Never a diagnosis, never a cycle phase.
    public var body: String
    /// Prefills ARIA chat when the human taps the notification.
    public var chatOpener: String
    /// On-device coaching line when they are already talking to ARIA.
    public var coachLine: String

    public init(
        kind: AriaHealthRiskKind,
        severity: AriaHealthRiskSeverity,
        title: String,
        body: String,
        chatOpener: String,
        coachLine: String
    ) {
        self.kind = kind
        self.severity = severity
        self.title = title
        self.body = body
        self.chatOpener = chatOpener
        self.coachLine = coachLine
    }

    var rank: Int {
        switch (severity, kind) {
        case (.concern, .elevatedTemperature): return 40
        case (.concern, .wristTemperatureRise): return 36
        case (.concern, .restingHeartRateSpike): return 32
        case (.concern, .hrvDrop): return 28
        case (.watch, .elevatedTemperature): return 24
        case (.watch, .wristTemperatureRise): return 20
        case (.watch, .restingHeartRateSpike): return 16
        case (.watch, .hrvDrop): return 12
        }
    }
}

public enum AriaHealthRiskMonitor {

    public static let slightlyHighBodyTempF = 99.5
    public static let feverRangeBodyTempF = 100.4
    public static let wristRiseWatchC = 0.5
    public static let wristRiseConcernC = 0.8
    public static let rhrDeltaWatch = 8.0
    public static let rhrDeltaConcern = 12.0
    public static let hrvDropFraction = 0.25
    public static let hrvDropAbsolute = 15.0
    /// Ignore stale samples so a last-week reading cannot fire tonight.
    public static let sampleMaxAge: TimeInterval = 16 * 3600
    /// Gym sessions raise skin temp; do not treat that as a health check.
    public static let workoutIgnoreHours = 1.5

    public static func evaluate(_ reading: AriaVitalReading, now: Date = Date()) -> [AriaHealthRiskFinding] {
        guard now.timeIntervalSince(reading.sampledAt) <= sampleMaxAge else { return [] }
        var findings: [AriaHealthRiskFinding] = []

        let recentlyWorkedOut = (reading.hoursSinceLastWorkout ?? .greatestFiniteMagnitude) < workoutIgnoreHours

        if let temp = reading.bodyTemperatureF, temp >= slightlyHighBodyTempF, !recentlyWorkedOut {
            let concern = temp >= feverRangeBodyTempF
            let rounded = String(format: "%.1f", temp)
            findings.append(
                AriaHealthRiskFinding(
                    kind: .elevatedTemperature,
                    severity: concern ? .concern : .watch,
                    title: concern ? "Temperature looks high" : "Temperature a bit high",
                    body: concern
                        ? "A recent reading is \(rounded)°F — higher than typical. I'm not diagnosing. If you feel unwell, a clinician is the right call."
                        : "A recent reading is \(rounded)°F, a little above typical. Worth noticing and taking it easy — a clinician can tell you more.",
                    chatOpener: "My temperature is reading \(rounded)°F. What should I actually do with that?",
                    coachLine: concern
                        ? "Your latest temperature is \(rounded)°F, which is in the range people often call a fever. I can't diagnose. Ease off training, hydrate, and talk to a clinician if it holds or you feel worse."
                        : "Your latest temperature is \(rounded)°F — a bit high versus typical. Not a diagnosis. I'd keep today easy and watch how you feel."
                )
            )
        }

        if let delta = reading.wristTemperatureDeviationC, delta >= wristRiseWatchC {
            let concern = delta >= wristRiseConcernC
            let rounded = String(format: "%.2f", delta)
            findings.append(
                AriaHealthRiskFinding(
                    kind: .wristTemperatureRise,
                    severity: concern ? .concern : .watch,
                    title: "Wrist temperature is up",
                    body: concern
                        ? "Overnight wrist temperature is about \(rounded)°C above your baseline. That's a Watch sleeping reading, not a medical thermometer — still worth a clinician if you feel off."
                        : "Overnight wrist temperature is about \(rounded)°C above your baseline. A small rise happens; if you feel unwell, treat a clinician as the source of truth.",
                    chatOpener: "My Apple Watch wrist temperature is \(rounded)°C above baseline. What does that mean for today?",
                    coachLine: concern
                        ? "Your Watch sleeping wrist temperature is \(rounded)°C above your usual overnight baseline. That's a sensor hint, not a diagnosis. I'd make today recovery-shaped and check in with a clinician if you feel sick."
                        : "Watch says overnight wrist temperature is \(rounded)°C above your baseline. Small drifts happen. If you feel fine, note it; if you don't, a clinician beats my guess."
                )
            )
        }

        if let rhr = reading.restingHeartRate, let base = reading.restingHeartRateBaseline, base > 0 {
            let delta = rhr - base
            if delta >= rhrDeltaWatch {
                let concern = delta >= rhrDeltaConcern
                findings.append(
                    AriaHealthRiskFinding(
                        kind: .restingHeartRateSpike,
                        severity: concern ? .concern : .watch,
                        title: concern ? "Resting heart rate is up" : "Resting heart rate a bit high",
                        body: "Resting heart rate is \(Int(rhr.rounded())) vs a usual \(Int(base.rounded())). Load, heat, or being run-down can do that — I can't name which.",
                        chatOpener: "My resting heart rate is \(Int(rhr.rounded())) versus a usual \(Int(base.rounded())). How should I train?",
                        coachLine: concern
                            ? "Resting HR is \(Int(rhr.rounded())) against a baseline near \(Int(base.rounded())). That's a real gap. I'd skip intensity and see how sleep and how you feel look tonight."
                            : "Resting HR is a bit high versus your usual. Easy movement is fine; I'd keep the hard work for a better signal."
                    )
                )
            }
        }

        if let hrv = reading.hrvMs, let base = reading.hrvBaselineMs, base > 0 {
            let drop = base - hrv
            if drop >= hrvDropAbsolute || hrv <= base * (1 - hrvDropFraction) {
                let concern = drop >= hrvDropAbsolute * 1.4 || hrv <= base * 0.65
                findings.append(
                    AriaHealthRiskFinding(
                        kind: .hrvDrop,
                        severity: concern ? .concern : .watch,
                        title: "HRV looks low",
                        body: "HRV is \(Int(hrv.rounded())) ms versus a usual \(Int(base.rounded())) ms. That's a recovery hint, not a diagnosis.",
                        chatOpener: "My HRV dropped to \(Int(hrv.rounded())) ms from about \(Int(base.rounded())) ms. What should today look like?",
                        coachLine: concern
                            ? "HRV is well below your baseline (\(Int(hrv.rounded())) vs \(Int(base.rounded())) ms). I'd treat today as restore: walk, food, earlier night — not a PR."
                            : "HRV is softer than your usual. A lighter day protects tomorrow better than pushing through."
                    )
                )
            }
        }

        return findings.sorted { $0.rank > $1.rank }
    }

    public static func primary(_ findings: [AriaHealthRiskFinding]) -> AriaHealthRiskFinding? {
        findings.first
    }

    /// Surface a finding in chat when the human is asking about how they feel,
    /// temperature, or recovery — not on "what's for dinner".
    public static func shouldSurfaceInChat(text: String) -> Bool {
        let lower = text.lowercased()
        let needles = [
            "temp", "fever", "hot", "chills", "sick", "unwell", "ill",
            "hrv", "resting heart", "heart rate", "recovery", "readiness",
            "why am i tired", "feel off", "feel awful", "don't feel", "dont feel",
            "wrist", "watch say", "apple watch",
        ]
        return needles.contains { lower.contains($0) }
    }
}

public enum AriaHealthRiskCooldown {
    public static let interval: TimeInterval = 8 * 3600

    public static func shouldNotify(lastNotified: Date?, now: Date = Date()) -> Bool {
        guard let lastNotified else { return true }
        return now.timeIntervalSince(lastNotified) >= interval
    }

    public static func storageKey(for kind: AriaHealthRiskKind) -> String {
        "forge.aria.risk.lastNotified.\(kind.rawValue)"
    }
}
