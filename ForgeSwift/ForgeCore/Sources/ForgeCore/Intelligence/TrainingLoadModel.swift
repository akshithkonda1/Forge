import Foundation

// ============================================================
// MARK: - Training Load Model
// ============================================================

/// Quantifies training load the way elite sport does, then explains it
/// the way a consumer app should.
///
/// Two concepts, both missing from Oura / Whoop / Apple Health:
///
/// 1. **Strain (0–21)** — a session's cardiovascular + muscular cost, from
///    duration × intensity. Comparable across days, sports, and people
///    because it's anchored to *your* history, not a population table.
///
/// 2. **Acute:chronic workload ratio (ACWR)** — recent load against what
///    you are used to (the "sweet spot" is 0.8–1.3; above 1.5 is the danger
///    zone). Computed with exponentially weighted moving averages (7-day
///    acute, 28-day chronic; Williams et al. 2017), not rolling sums: a
///    rolling average weights a session from 27 days ago the same as
///    yesterday's and then drops it abruptly when it leaves the window, and
///    the coupled 7:28 ratio puts this week inside its own denominator.
///    EWMA lets each session's effect fade, which is how fatigue behaves.
///
/// Pure value types, no I/O — the app maps its `WorkoutHistory` into
/// `Session` and reads back `LoadPicture`.
public enum TrainingLoadModel {

    // MARK: - Input

    /// One training session's load.
    public struct Session: Sendable {
        /// Calendar day of the session.
        public var date: Date
        /// Minutes of active work.
        public var durationMinutes: Int
        /// 1 = easy … 4 = all-out.
        public var intensityLevel: Int

        public init(date: Date, durationMinutes: Int, intensityLevel: Int) {
            self.date = date
            self.durationMinutes = durationMinutes
            self.intensityLevel = max(1, min(4, intensityLevel))
        }

        /// Session-RPE style strain: duration × intensity, scaled to 0–21.
        /// A 60-min hard session ≈ 14; an all-out 90-min session ≈ 21.
        public var strain: Double {
            let raw = Double(durationMinutes) * Double(intensityLevel) / 17.0
            return max(0, min(21, raw))
        }
    }

    // MARK: - Output

    /// Load zone for a single day or week.
    public enum Zone: String, Sendable {
        case rest      // < 4 strain
        case light     // 4–9
        case moderate  // 10–15
        case heavy     // 16–21

        public static func zone(for strain: Double) -> Zone {
            switch strain {
            case ..<4: return .rest
            case ..<10: return .light
            case ..<16: return .moderate
            default: return .heavy
            }
        }
    }

    public struct DayLoad: Sendable, Identifiable {
        public var id: String { dayKey }
        public var dayKey: String      // yyyy-MM-dd
        public var date: Date
        public var strain: Double
        public var zone: Zone
        public var sessionCount: Int
    }

    public struct LoadPicture: Sendable {
        /// Last 14 days, oldest → newest.
        public var days: [DayLoad]
        /// Mean daily strain over the last 7 days.
        public var acuteLoad: Double
        /// Mean daily strain over the last 28 days (0 when there is no
        /// history in that window).
        public var chronicLoad: Double
        /// EWMA acute ÷ EWMA chronic. Nil when history is too short.
        public var acwr: Double?
        /// Plain-language read on the ratio.
        public var acwrVerdict: String?
        /// Consecutive heavy days (strain ≥ 16) ending today.
        public var heavyStreak: Int
    }

    // MARK: - Model

    /// Builds the 14-day picture ending today (or `referenceDate`).
    public static func picture(
        sessions: [Session],
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> LoadPicture {
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = calendar
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"

        // Bucket sessions by day.
        var strainByDay: [String: Double] = [:]
        var countByDay: [String: Int] = [:]
        for s in sessions {
            let key = dayFormatter.string(from: s.date)
            strainByDay[key, default: 0] += s.strain
            countByDay[key, default: 0] += 1
        }

        // Last 14 days, oldest → newest.
        var days: [DayLoad] = []
        for offset in (0..<14).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: referenceDate) else { continue }
            let key = dayFormatter.string(from: date)
            let strain = strainByDay[key] ?? 0
            days.append(DayLoad(
                dayKey: key,
                date: calendar.startOfDay(for: date),
                strain: strain,
                zone: Zone.zone(for: strain),
                sessionCount: countByDay[key] ?? 0
            ))
        }

        let last7 = days.suffix(7)
        let acute = last7.reduce(0) { $0 + $1.strain } / 7.0

        // Daily strain for the last 56 days (two chronic windows), so the
        // 28-day EWMA has history to settle on. Days before the first logged
        // session are not "rest" — they are before the person started
        // logging — so the series starts at the first session.
        let today = calendar.startOfDay(for: referenceDate)
        var dailyStrain: [Double] = []
        var started = false
        var sessionsLast28 = 0
        var chronicSum = 0.0
        for offset in (0..<56).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let strain = strainByDay[dayFormatter.string(from: date)] ?? 0
            if offset < 28 {
                chronicSum += strain
                sessionsLast28 += countByDay[dayFormatter.string(from: date)] ?? 0
            }
            if strain > 0 { started = true }
            if started { dailyStrain.append(strain) }
        }
        let chronic = sessionsLast28 > 0 ? chronicSum / 28.0 : 0

        var acwr: Double?
        var verdict: String?
        // Same evidence bar as before: at least 8 sessions in 28 days and a
        // chronic base that is more than noise.
        if sessionsLast28 >= 8, let ratio = ewmaACWR(dailyStrain) {
            acwr = ratio
            verdict = verdictForACWR(ratio)
        }

        // Heavy streak ending today.
        var streak = 0
        for day in days.reversed() {
            if day.strain >= 16 { streak += 1 } else { break }
        }

        return LoadPicture(
            days: days,
            acuteLoad: acute,
            chronicLoad: chronic,
            acwr: acwr,
            acwrVerdict: verdict,
            heavyStreak: streak
        )
    }

    /// EWMA smoothing for a window of N days: λ = 2 / (N + 1).
    public static let acuteLambda = 2.0 / (7.0 + 1.0)
    public static let chronicLambda = 2.0 / (28.0 + 1.0)

    /// Acute ÷ chronic exponentially weighted load over a daily series
    /// (oldest → newest). Both averages start at the first day's value.
    /// Nil when the chronic average is too small to divide by (≤ 0.5).
    public static func ewmaACWR(_ dailyStrain: [Double]) -> Double? {
        guard let first = dailyStrain.first else { return nil }
        var acute = first
        var chronic = first
        for value in dailyStrain.dropFirst() {
            acute = acuteLambda * value + (1 - acuteLambda) * acute
            chronic = chronicLambda * value + (1 - chronicLambda) * chronic
        }
        guard chronic > 0.5 else { return nil }
        return acute / chronic
    }

    private static func verdictForACWR(_ ratio: Double) -> String {
        switch ratio {
        case ..<0.8:
            return "Detraining zone — fitness is leaking. Good time to build."
        case 0.8..<1.3:
            return "Sweet spot — loading optimally for your history."
        case 1.3...1.5:
            return "Loading aggressively — watch recovery signals closely."
        default:
            return "Danger zone — injury risk climbs steeply here. Back off."
        }
    }
}
