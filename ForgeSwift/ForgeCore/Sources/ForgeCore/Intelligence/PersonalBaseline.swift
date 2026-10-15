import Foundation

/// A person's own center and day-to-day spread for one signal.
///
/// Readiness reads HRV and resting HR against *your* normal range, not a
/// population table: a z-score says how unusual today is for this person.
/// HRV is log-normal, so its baseline is kept in ln space — `mean` is the
/// geometric mean (ms) and `spread` is the SD of ln(HRV). Resting HR is
/// linear — both are in bpm.
///
/// Mirrors `personal_baseline` / `PersonalBaseline` in
/// `backend/infra/lambda/aria_core/readiness_calculator.py`.
public struct PersonalBaseline: Codable, Equatable, Sendable {
    public var mean: Double
    public var spread: Double
    public var days: Int
    public var logScaled: Bool

    public init(mean: Double, spread: Double, days: Int, logScaled: Bool) {
        self.mean = mean
        self.spread = spread
        self.days = days
        self.logScaled = logScaled
    }

    /// One timestamped reading.
    public struct Sample: Equatable, Sendable {
        public var date: Date
        public var value: Double

        public init(date: Date, value: Double) {
            self.date = date
            self.value = value
        }
    }

    /// Today's distance from this baseline in SDs. `spread` is clamped to
    /// `floor...ceiling` so a suspiciously tight history cannot turn a 1 ms
    /// wobble into a five-sigma event. Nil for non-positive values.
    public func zScore(_ value: Double, floor: Double, ceiling: Double) -> Double? {
        guard value > 0, mean > 0 else { return nil }
        let sd = min(max(spread, floor), ceiling)
        if logScaled {
            return (log(value) - log(mean)) / sd
        }
        return (value - mean) / sd
    }

    /// Baseline from one value per day. Non-positive values are missing
    /// readings, not data. Nil until `minimumDays` real days exist.
    public static func fromDailyValues(
        _ values: [Double],
        logScaled: Bool,
        minimumDays: Int = 5
    ) -> PersonalBaseline? {
        let real = values.filter { $0 > 0 && $0.isFinite }
        guard real.count >= max(2, minimumDays) else { return nil }
        let series = logScaled ? real.map { log($0) } : real
        let mu = series.reduce(0, +) / Double(series.count)
        let variance = series.reduce(0) { $0 + ($1 - mu) * ($1 - mu) } / Double(series.count - 1)
        return PersonalBaseline(
            mean: logScaled ? exp(mu) : mu,
            spread: variance.squareRoot(),
            days: real.count,
            logScaled: logScaled
        )
    }

    /// Baseline from raw samples: each calendar day collapses to one value
    /// (mean, in ln space when `logScaled`) so a day with twelve watch
    /// readings does not outvote a day with two, and the day containing
    /// `excluding` is left out so today is never compared against itself.
    ///
    /// When `preferNight` is set and at least `minimumDays` days have
    /// readings between 22:00 and 08:00, only those readings are used —
    /// overnight HRV is the stable one; daytime readings swing with posture,
    /// caffeine, and the last flight of stairs. The night of 23:30 belongs
    /// to the next morning's day.
    public static func daily(
        samples: [Sample],
        logScaled: Bool,
        excluding: Date? = nil,
        preferNight: Bool = false,
        minimumDays: Int = 5,
        calendar: Calendar = .current
    ) -> PersonalBaseline? {
        let excludedDay = excluding.map { calendar.startOfDay(for: $0) }

        func dayKey(_ date: Date) -> Date {
            let hour = calendar.component(.hour, from: date)
            let shifted = hour >= 22 ? (calendar.date(byAdding: .day, value: 1, to: date) ?? date) : date
            return calendar.startOfDay(for: shifted)
        }

        func isNight(_ date: Date) -> Bool {
            let hour = calendar.component(.hour, from: date)
            return hour >= 22 || hour < 8
        }

        func collapse(_ pool: [Sample]) -> [Double] {
            var byDay: [Date: [Double]] = [:]
            for sample in pool where sample.value > 0 && sample.value.isFinite {
                let key = dayKey(sample.date)
                if let excludedDay, key == excludedDay { continue }
                byDay[key, default: []].append(logScaled ? log(sample.value) : sample.value)
            }
            return byDay.values.map { values in
                let m = values.reduce(0, +) / Double(values.count)
                return logScaled ? exp(m) : m
            }
        }

        if preferNight {
            let nightly = collapse(samples.filter { isNight($0.date) })
            if nightly.count >= minimumDays {
                return fromDailyValues(nightly, logScaled: logScaled, minimumDays: minimumDays)
            }
        }
        return fromDailyValues(collapse(samples), logScaled: logScaled, minimumDays: minimumDays)
    }

    /// Mean of readings inside `window` (geometric when `logScaled`). Nil
    /// when the window holds none — the caller falls back, never invents.
    public static func windowMean(
        samples: [Sample],
        in window: DateInterval,
        logScaled: Bool
    ) -> Double? {
        let values = samples
            .filter { window.contains($0.date) && $0.value > 0 && $0.value.isFinite }
            .map { logScaled ? log($0.value) : $0.value }
        guard !values.isEmpty else { return nil }
        let m = values.reduce(0, +) / Double(values.count)
        return logScaled ? exp(m) : m
    }
}
