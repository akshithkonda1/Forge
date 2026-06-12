import Foundation

struct DataConclusions: Equatable {
    let generatedAt: Date
    let coveragePct: Double
    let coachingBrief: String
    let compoundFlags: [String]
    let offlineTemplates: OfflineTemplates
    let readinessOverall: Int
}

struct OfflineTemplates: Equatable {
    let chat: String
    let dashboard: String
    let mood: String
    let widget: String
}

/// Local conclusions evaluator for offline dashboard, mood, and chat templates.
enum ConclusionsEngine {
    static func evaluate(
        readiness: ReadinessData,
        dailyMetrics: DailyMetrics,
        sleepData: [SleepData],
        workoutHistory: [WorkoutHistory]
    ) -> DataConclusions {
        var signals: [String] = []
        let overall = readiness.overall

        if dailyMetrics.hrv > 0 && dailyMetrics.hrv < 35 {
            signals.append("hrv-suppressed")
        }
        if let lastSleep = sleepData.first {
            if lastSleep.score < 70 || lastSleep.deepMinutes < 60 {
                signals.append("sleep-debt")
            }
        }
        if dailyMetrics.steps > 0 && dailyMetrics.steps < 4000 {
            signals.append("steps-low")
        }
        if workoutHistory.count >= 4 {
            let recent = workoutHistory.prefix(3).map(\.duration).reduce(0, +)
            let prior = workoutHistory.dropFirst(3).prefix(3).map(\.duration).reduce(0, +)
            if recent > prior && prior > 0 {
                signals.append("load-spike")
            }
        }

        var compoundFlags: [String] = []
        let signalSet = Set(signals)
        if signalSet.contains("sleep-debt") && signalSet.contains("load-spike") {
            compoundFlags.append("recovery-debt-under-load")
        }
        if signalSet.contains("hrv-suppressed") && overall < 60 {
            compoundFlags.append("autonomic-stress")
        }

        let coverage = coveragePct(dailyMetrics: dailyMetrics, sleepData: sleepData)
        let templates = offlineTemplates(
            readinessOverall: overall,
            compoundFlags: compoundFlags,
            signals: signals
        )
        let brief = "Readiness \(overall)/100. \(compoundFlags.first ?? signals.first ?? "stable"). Training context loaded."

        return DataConclusions(
            generatedAt: Date(),
            coveragePct: coverage,
            coachingBrief: brief,
            compoundFlags: compoundFlags,
            offlineTemplates: templates,
            readinessOverall: overall
        )
    }

    static func coveragePct(dailyMetrics: DailyMetrics, sleepData: [SleepData]) -> Double {
        var present = 0
        let total = 8
        if dailyMetrics.steps > 0 { present += 1 }
        if dailyMetrics.activeCalories > 0 { present += 1 }
        if dailyMetrics.hrv > 0 { present += 1 }
        if dailyMetrics.restingHR > 0 { present += 1 }
        if dailyMetrics.deepSleep > 0 { present += 1 }
        if dailyMetrics.totalSleep > 0 { present += 1 }
        if !sleepData.isEmpty { present += 1 }
        if dailyMetrics.restingHR > 0 { present += 1 }
        return Double(present) / Double(total)
    }

    private static func offlineTemplates(
        readinessOverall: Int,
        compoundFlags: [String],
        signals: [String]
    ) -> OfflineTemplates {
        let chat: String
        let dashboard: String
        let mood: String

        if compoundFlags.contains("recovery-debt-under-load") {
            chat = "Recovery is lagging under rising load — prioritize sleep and reduce intensity today."
            dashboard = "Recovery debt detected — ease training load."
            mood = "stressed"
        } else if readinessOverall >= 80 {
            chat = "Metrics look strong — good day to push performance if planned."
            dashboard = "High readiness — training window open."
            mood = "energized"
        } else if readinessOverall >= 60 {
            chat = "Readiness is moderate — train with controlled volume and monitor recovery."
            dashboard = "Moderate readiness — train smart, not maximal."
            mood = "steady"
        } else {
            chat = "Recovery signals are low — favor mobility, sleep, and nutrition today."
            dashboard = "Low readiness — recovery focus recommended."
            mood = signals.contains("hrv-suppressed") ? "stressed" : "steady"
        }

        return OfflineTemplates(
            chat: chat,
            dashboard: dashboard,
            mood: mood,
            widget: "Readiness \(readinessOverall)"
        )
    }
}