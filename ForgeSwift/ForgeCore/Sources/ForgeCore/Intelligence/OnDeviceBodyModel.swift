import Foundation

/// Local stand-in for the BodyModel projection `/ai/observe` used to compute
/// on the server. HRV trend, personal baselines, and the daily story stay
/// on this device. Never talks to the network.
public struct OnDeviceBodyProjection: Equatable, Sendable {
    public var hrv7DayTrend: Double?
    public var hrv30DayBaseline: Double?
    public var hrvDaysAvailable: Int
    public var sleepBaselineMinutes: Double?
    public var stepsBaseline: Double?
    public var sleepDebt7dHours: Double?

    public init(
        hrv7DayTrend: Double? = nil,
        hrv30DayBaseline: Double? = nil,
        hrvDaysAvailable: Int = 0,
        sleepBaselineMinutes: Double? = nil,
        stepsBaseline: Double? = nil,
        sleepDebt7dHours: Double? = nil
    ) {
        self.hrv7DayTrend = hrv7DayTrend
        self.hrv30DayBaseline = hrv30DayBaseline
        self.hrvDaysAvailable = hrvDaysAvailable
        self.sleepBaselineMinutes = sleepBaselineMinutes
        self.stepsBaseline = stepsBaseline
        self.sleepDebt7dHours = sleepDebt7dHours
    }
}

public enum OnDeviceBodyModel: Sendable {
    public static let sleepTargetHours = 8.0

    /// `dailyHRV` / `dailySleepMinutes` / `dailySteps` are oldest-first,
    /// one value per day. Zeros are missing days, not readings.
    public static func project(
        dailyHRV: [Double],
        dailySleepMinutes: [Double],
        dailySteps: [Double]
    ) -> OnDeviceBodyProjection {
        let hrv = dailyHRV.filter { $0 > 0 && $0.isFinite }
        let sleep = dailySleepMinutes.filter { $0 > 0 && $0.isFinite }
        let steps = dailySteps.filter { $0 > 0 && $0.isFinite }

        var online = OnlineStat()
        for value in hrv { online.update(value) }

        let hrvMedian = median(hrv)
        let trend: Double?
        if let base = hrvMedian, base > 0, online.n > 0 {
            trend = ((online.ewma - base) / base * 100.0 * 10).rounded() / 10
        } else {
            trend = nil
        }

        let debt: Double?
        if sleep.isEmpty {
            debt = nil
        } else {
            let recent = sleep.suffix(7)
            debt = (recent.reduce(0.0) { $0 + max(0, sleepTargetHours - $1 / 60.0) } * 100).rounded() / 100
        }

        return OnDeviceBodyProjection(
            hrv7DayTrend: trend,
            hrv30DayBaseline: hrvMedian,
            hrvDaysAvailable: hrv.count,
            sleepBaselineMinutes: median(sleep),
            stepsBaseline: median(steps),
            sleepDebt7dHours: debt
        )
    }

    public static func median(_ values: [Double]) -> Double? {
        let sorted = values.filter { $0 > 0 && $0.isFinite }.sorted()
        guard !sorted.isEmpty else { return nil }
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }
}

/// Local daily story. Same thresholds as `services/daily_story.py`, run here
/// so Home still has a card after `/ai/observe` stopped ingesting health.
public struct OnDeviceDailyStory: Equatable, Sendable {
    public struct Insight: Equatable, Sendable {
        public var text: String
        public var domain: String
        public var evidence: String

        public init(text: String, domain: String, evidence: String) {
            self.text = text
            self.domain = domain
            self.evidence = evidence
        }
    }

    public var generatedAt: String
    public var narrative: String
    public var insights: [Insight]
    public var sources: [String]

    public init(generatedAt: String, narrative: String, insights: [Insight], sources: [String]) {
        self.generatedAt = generatedAt
        self.narrative = narrative
        self.insights = insights
        self.sources = sources
    }

    public static let hrvTrendNotable = 8.0

    public static func build(
        hrvTrend: Double?,
        sleepMinutes: Double?,
        sleepBaselineMinutes: Double?,
        steps3Day: Double?,
        stepsBaseline: Double?,
        now: Date = Date()
    ) -> OnDeviceDailyStory? {
        var insights: [Insight] = []
        var sources: Set<String> = []

        if let trend = hrvTrend, abs(trend) >= hrvTrendNotable {
            if trend <= -hrvTrendNotable {
                insights.append(Insight(
                    text: "Your HRV has been trending down this week — recovery is asking for easier days, not harder ones.",
                    domain: "readiness",
                    evidence: String(format: "HRV 7-day trend %+.1f", trend)
                ))
            } else {
                insights.append(Insight(
                    text: "Your HRV has been trending up this week — recovery has room for you to push if you want it.",
                    domain: "readiness",
                    evidence: String(format: "HRV 7-day trend %+.1f", trend)
                ))
            }
            sources.insert("apple-health")
        }

        if let steps = steps3Day, let base = stepsBaseline, base > 0 {
            let ratio = steps / base
            if ratio >= 1.25 {
                insights.append(Insight(
                    text: "You've been moving more than usual the last few days — that activity is showing up in the numbers above.",
                    domain: "activity",
                    evidence: "3-day steps vs personal baseline"
                ))
                sources.insert("apple-health")
            } else if ratio <= 0.6 {
                insights.append(Insight(
                    text: "Activity has been quieter than your usual the last few days.",
                    domain: "activity",
                    evidence: "3-day steps vs personal baseline"
                ))
                sources.insert("apple-health")
            }
        }

        if let sleep = sleepMinutes, let base = sleepBaselineMinutes, base > 0, sleep < 0.85 * base {
            insights.append(Insight(
                text: "Last night ran short of what you usually get — worth protecting tonight.",
                domain: "sleep",
                evidence: "last night vs personal baseline"
            ))
            sources.insert("apple-health")
        }

        guard !insights.isEmpty else { return nil }
        let narrative: String
        if insights.count == 1 {
            narrative = insights[0].text
        } else {
            narrative = insights.map(\.text).joined(separator: " ")
        }
        let stamp = ISO8601DateFormatter().string(from: now)
        return OnDeviceDailyStory(
            generatedAt: stamp,
            narrative: narrative,
            insights: insights,
            sources: sources.sorted()
        )
    }
}
