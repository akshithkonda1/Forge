import Foundation

// MARK: - Sleep morning summary, need parts, published score, debt meter
//
// Pure arithmetic so Day / Tonight / web / tests share one copy bar.
// Does not touch readiness scoring (PR #449). HRV, resting HR, and training
// stay out of the published sleep score. Copy bar lives in SleepCoachCopy.

public enum SleepCalibrationState: Equatable, Sendable {
    public static let readyNights = 7
    public static let debtReadyNights = 5

    case learning(nights: Int, need: Int)
    case ready
    case notScorable

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    public var caption: String {
        switch self {
        case .learning(let nights, let need):
            return "Learning \(min(nights, need))/\(need)"
        case .ready:
            return "Ready"
        case .notScorable:
            return "No Watch night on file"
        }
    }

    public static func from(scoredNights: Int, watchWorn: Bool = true) -> SleepCalibrationState {
        if !watchWorn && scoredNights == 0 { return .notScorable }
        if scoredNights < readyNights {
            return .learning(nights: scoredNights, need: readyNights)
        }
        return .ready
    }
}

/// WHOOP-style terms, Garmin 7–9 h clamp, Rise editable baseline.
public struct SleepNeedParts: Equatable, Sendable {
    public static let clampMin: Double = 7.0
    public static let clampMax: Double = 9.0
    public static let defaultBaseline: Double = 8.0

    public var baselineHours: Double
    public var loadAdjHours: Double
    public var debtAdjHours: Double
    public var napCreditHours: Double
    public var userOverride: Bool

    public var totalHours: Double {
        let raw = baselineHours + loadAdjHours + debtAdjHours - napCreditHours
        return min(Self.clampMax, max(Self.clampMin, raw))
    }

    public var whyLines: [String] {
        var lines = [
            String(format: "Baseline %.1fh", baselineHours),
        ]
        if loadAdjHours > 0.05 {
            lines.append(String(format: "Load +%.0f min", loadAdjHours * 60))
        }
        if debtAdjHours > 0.05 {
            lines.append(String(format: "Short stretch +%.0f min", debtAdjHours * 60))
        }
        if napCreditHours > 0.05 {
            lines.append(String(format: "Naps −%.0f min", napCreditHours * 60))
        }
        if userOverride {
            lines.append("You set the baseline")
        }
        lines.append(String(format: "Tonight's need %.1fh (kept between %.0f–%.0f)", totalHours, Self.clampMin, Self.clampMax))
        return lines
    }

    public static func make(
        estimatedBaseline: Double,
        overrideBaseline: Double? = nil,
        loadHours: Double = 0,
        debtHours: Double = 0,
        napHours: Double = 0
    ) -> SleepNeedParts {
        let userOverride = overrideBaseline != nil
        let baseline = overrideBaseline ?? estimatedBaseline
        let clampedBaseline = min(clampMax, max(clampMin, baseline))
        let loadAdj = min(0.75, max(0, loadHours) * 0.05)
        let debtAdj = min(0.75, max(0, debtHours) * 0.08)
        let napCredit = min(1.0, max(0, napHours))
        return SleepNeedParts(
            baselineHours: clampedBaseline,
            loadAdjHours: loadAdj,
            debtAdjHours: debtAdj,
            napCreditHours: napCredit,
            userOverride: userOverride
        )
    }
}

public enum SleepNeedBaselineStore: Sendable {
    public static let defaultsKey = "forge.sleep.needBaselineHours"

    public static func load(defaults: UserDefaults = .standard) -> Double? {
        guard defaults.object(forKey: defaultsKey) != nil else { return nil }
        let value = defaults.double(forKey: defaultsKey)
        guard value >= SleepNeedParts.clampMin - 0.05, value <= SleepNeedParts.clampMax + 0.05 else {
            return nil
        }
        return value
    }

    public static func save(_ hours: Double?, defaults: UserDefaults = .standard) {
        if let hours {
            let clamped = min(SleepNeedParts.clampMax, max(SleepNeedParts.clampMin, hours))
            defaults.set(clamped, forKey: defaultsKey)
        } else {
            defaults.removeObject(forKey: defaultsKey)
        }
    }
}

/// Apple-style published weights: duration 50, consistency 30, interruptions 20.
/// HRV / resting HR / training stay in ARIA's narrative, not here.
public enum SleepPublishedScore: Sendable {
    public static let durationWeight = 0.50
    public static let consistencyWeight = 0.30
    public static let interruptionWeight = 0.20

    public struct Breakdown: Equatable, Sendable {
        public var duration: Int
        public var consistency: Int
        public var interruptions: Int
        public var total: Int

        public var parts: [(name: String, weight: String, value: Int)] {
            [
                ("Time asleep vs your need", "50", duration),
                ("Bedtime consistency", "30", consistency),
                ("Interruptions", "20", interruptions),
            ]
        }
    }

    public static func breakdown(
        asleepHours: Double,
        needHours: Double,
        consistency: Double,
        awakeMinutes: Double
    ) -> Breakdown {
        let duration = Int(min(100, max(0, (asleepHours / max(0.1, needHours)) * 100)).rounded())
        let consist = Int(min(100, max(0, consistency)).rounded())
        let awakePenalty = min(100, (awakeMinutes / 90) * 100)
        let interruptions = Int(min(100, max(0, 100 - awakePenalty)).rounded())
        let total = Int((
            Double(duration) * durationWeight
            + Double(consist) * consistencyWeight
            + Double(interruptions) * interruptionWeight
        ).rounded())
        return Breakdown(
            duration: duration,
            consistency: consist,
            interruptions: interruptions,
            total: min(100, max(0, total))
        )
    }

    public static func visibleScore(calibration: SleepCalibrationState, breakdown: Breakdown) -> Int? {
        calibration.isReady ? breakdown.total : nil
    }
}

public struct SleepDebtDay: Equatable, Sendable, Identifiable {
    public var id: String { dateKey }
    public var dateKey: String
    public var weekday: String
    public var hours: Double?
    public var missed: Bool
    public var fill: Double
}

public enum SleepDebtMeter: Sendable {
    public static let displayNights = 7
    public static let windowNights = 14
    public static let lastNightWeight = 0.15
    public static let paybackCapMinutes = 25.0
    public static let hitSlackHours = 0.4

    public struct Result: Equatable, Sendable {
        public var days: [SleepDebtDay]
        public var stretchHours: Double
        public var isLearning: Bool
        public var paybackMinutes: Int
        public var paybackNights: Int
        public var headline: String
        public var detail: String
    }

    public static func hoursLabel(_ hours: Double) -> String {
        let minutes = Int((hours * 60).rounded())
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    /// Rise-style 14-night stretch: last night 15%, earlier nights share 85%.
    public static func stretchHours(asleepHoursOldestFirst: [Double], needHours: Double) -> Double {
        let window = Array(asleepHoursOldestFirst.suffix(windowNights))
        guard !window.isEmpty else { return 0 }
        if window.count == 1 {
            return max(0, needHours - window[0])
        }
        let last = window[window.count - 1]
        let earlier = window.dropLast()
        let lastShort = max(0, needHours - last) * lastNightWeight
        let earlierWeight = (1 - lastNightWeight) / Double(earlier.count)
        let earlierShort = earlier.reduce(0.0) { $0 + max(0, needHours - $1) * earlierWeight }
        return lastShort + earlierShort
    }

    public static func payback(stretchHours: Double) -> (minutes: Int, nights: Int) {
        guard stretchHours > 0.15 else { return (0, 0) }
        let totalMinutes = stretchHours * 60
        var nights = max(1, Int((totalMinutes / paybackCapMinutes).rounded(.up)))
        nights = min(14, nights)
        let perNight = min(paybackCapMinutes, totalMinutes / Double(nights))
        return (Int(perNight.rounded()), nights)
    }

    public static func make(
        nightsByDate: [String: Double],
        needHours: Double,
        asleepHoursOldestFirst: [Double],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Result {
        let stretch = stretchHours(asleepHoursOldestFirst: asleepHoursOldestFirst, needHours: needHours)
        let learning = asleepHoursOldestFirst.count < SleepCalibrationState.debtReadyNights
        let pay = payback(stretchHours: learning ? 0 : stretch)

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale
        formatter.setLocalizedDateFormatFromTemplate("EEEEE")
        let iso = DateFormatter()
        iso.calendar = calendar
        iso.locale = Locale(identifier: "en_US_POSIX")
        iso.timeZone = calendar.timeZone
        iso.dateFormat = "yyyy-MM-dd"

        let today = calendar.startOfDay(for: now)
        var days: [SleepDebtDay] = []
        for offset in (0..<displayNights).reversed() {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let key = iso.string(from: day)
            let hours = nightsByDate[key]
            let missed = hours == nil || (hours ?? 0) < needHours - hitSlackHours
            let fill = min(1, (hours ?? 0) / max(needHours, 0.1))
            days.append(SleepDebtDay(
                dateKey: key,
                weekday: formatter.string(from: day),
                hours: hours,
                missed: missed,
                fill: fill
            ))
        }

        let headline: String
        let detail: String
        if learning {
            headline = SleepCalibrationState.from(scoredNights: asleepHoursOldestFirst.count).caption
            detail = "These bars are nights on file. The stretch isn't a call until about \(SleepCalibrationState.debtReadyNights) nights land."
        } else if stretch < 0.2 {
            headline = "Square on sleep"
            detail = String(format: "Against a %.1fh need over the last fortnight. Nothing extra to add tonight.", needHours)
        } else {
            headline = String(format: "%.1fh short stretch", stretch)
            detail = "About \(pay.minutes) extra minutes for \(pay.nights) night\(pay.nights == 1 ? "" : "s") — a short stretch."
        }

        return Result(
            days: days,
            stretchHours: learning ? 0 : stretch,
            isLearning: learning,
            paybackMinutes: pay.minutes,
            paybackNights: pay.nights,
            headline: headline,
            detail: detail
        )
    }
}

public enum SleepFeeling: String, CaseIterable, Codable, Sendable {
    case rested, ok, groggy

    public var label: String {
        switch self {
        case .rested: return "Rested"
        case .ok: return "Okay"
        case .groggy: return "Groggy"
        }
    }
}

public enum SleepFeelingStore: Sendable {
    public static let defaultsKey = "forge.sleep.feelingByDate"

    public static func load(defaults: UserDefaults = .standard) -> [String: String] {
        defaults.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
    }

    public static func feeling(on dateKey: String, defaults: UserDefaults = .standard) -> SleepFeeling? {
        guard let raw = load(defaults: defaults)[dateKey] else { return nil }
        return SleepFeeling(rawValue: raw)
    }

    public static func save(_ feeling: SleepFeeling, on dateKey: String, defaults: UserDefaults = .standard) {
        var map = load(defaults: defaults)
        map[dateKey] = feeling.rawValue
        defaults.set(map, forKey: defaultsKey)
    }
}

public struct SleepMorningSummary: Equatable, Sendable {
    public var hoursLabel: String
    public var visibleScore: Int?
    public var calibration: SleepCalibrationState
    public var contextLine: String
    public var nextStep: String
    public var bedtimeLabel: String?
    public var need: SleepNeedParts
    public var published: SleepPublishedScore.Breakdown?

    public static func make(
        lastNightHours: Double?,
        lastNightAwakeMinutes: Double = 0,
        lastNightConsistency: Double = 80,
        scoredNightCount: Int,
        bedtimeLabel: String?,
        need: SleepNeedParts,
        watchWorn: Bool = true,
        calendar: Calendar = .current
    ) -> SleepMorningSummary {
        let calibration = SleepCalibrationState.from(
            scoredNights: scoredNightCount,
            watchWorn: watchWorn
        )
        let hoursLabel: String
        if let lastNightHours, lastNightHours > 0 {
            hoursLabel = SleepDebtMeter.hoursLabel(lastNightHours)
        } else {
            hoursLabel = "—"
        }

        var published: SleepPublishedScore.Breakdown?
        var visibleScore: Int?
        if let lastNightHours, lastNightHours > 0 {
            let breakdown = SleepPublishedScore.breakdown(
                asleepHours: lastNightHours,
                needHours: need.totalHours,
                consistency: lastNightConsistency,
                awakeMinutes: lastNightAwakeMinutes
            )
            published = breakdown
            visibleScore = SleepPublishedScore.visibleScore(calibration: calibration, breakdown: breakdown)
        }

        let contextLine: String
        let nextStep: String
        if lastNightHours == nil || lastNightHours == 0 {
            contextLine = calibration == .notScorable
                ? "No Watch night on file yet. Log in-bed on Tonight so last night can land."
                : SleepCoachCopy.stillLearning
            nextStep = "Tonight, log in-bed so the bedtime target can land."
        } else if !calibration.isReady {
            contextLine = "Last night is on file. ARIA is still learning your rhythm — no score until \(SleepCalibrationState.readyNights) nights."
            if let bedtimeLabel {
                nextStep = "Tonight, lights out at \(bedtimeLabel)."
            } else {
                nextStep = "Tonight, start winding down when the room feels dim."
            }
        } else if let lastNightHours, lastNightHours + 0.4 < need.totalHours {
            contextLine = "Short night. Keep today easy and get to bed a bit earlier."
            if let bedtimeLabel {
                nextStep = "Tonight, lights out at \(bedtimeLabel)."
            } else {
                nextStep = "Tonight, get to bed a bit earlier."
            }
        } else {
            contextLine = "You covered last night. Keep the same lights-out tonight."
            if let bedtimeLabel {
                nextStep = "Tonight, lights out at \(bedtimeLabel)."
            } else {
                nextStep = "Tonight, keep the same window."
            }
        }

        return SleepMorningSummary(
            hoursLabel: hoursLabel,
            visibleScore: visibleScore,
            calibration: calibration,
            contextLine: contextLine,
            nextStep: nextStep,
            bedtimeLabel: bedtimeLabel,
            need: need,
            published: published
        )
    }
}
