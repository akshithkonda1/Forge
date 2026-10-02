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
/// 2. **Acute:chronic workload ratio (ACWR)** — this week's load divided by
///    the 4-week average. Sports science's best-validated injury-risk
///    signal (the "sweet spot" is 0.8–1.3; above 1.5 is the danger zone).
///    Pro teams live by it. No consumer app shows it.
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
        /// Mean daily strain over the last 28 days.
        public var chronicLoad: Double
        /// Acute ÷ chronic. Nil when 28-day history is too short.
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

        // Chronic needs 28 days of sessions; we only chart 14, so compute
        // the 28-day mean directly from the session list.
        let cutoff28 = calendar.date(byAdding: .day, value: -28, to: referenceDate) ?? referenceDate
        let recent28 = sessions.filter { $0.date >= cutoff28 }
        var acwr: Double?
        var verdict: String?
        if recent28.count >= 8 {
            var daily28: [String: Double] = [:]
            for s in recent28 {
                daily28[dayFormatter.string(from: s.date), default: 0] += s.strain
            }
            let chronic = daily28.values.reduce(0, +) / 28.0
            if chronic > 0.5 {
                let ratio = acute / chronic
                acwr = ratio
                verdict = verdictForACWR(ratio)
            }
        }

        // Heavy streak ending today.
        var streak = 0
        for day in days.reversed() {
            if day.strain >= 16 { streak += 1 } else { break }
        }

        return LoadPicture(
            days: days,
            acuteLoad: acute,
            chronicLoad: recent28.isEmpty ? 0 : (acwr.map { acute / $0 } ?? 0),
            acwr: acwr,
            acwrVerdict: verdict,
            heavyStreak: streak
        )
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
