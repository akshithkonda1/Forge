import Foundation

// MARK: - Wellness score models (mirrors backend daily_scores + biological_age + cycle_context)

enum TrainingDecision: String, Codable, Equatable {
    case train
    case activeRest = "active_rest"
    case recover

    var label: String {
        switch self {
        case .train: return "Train"
        case .activeRest: return "Active Rest"
        case .recover: return "Recover"
        }
    }

    var icon: String {
        switch self {
        case .train: return "flame.fill"
        case .activeRest: return "figure.walk"
        case .recover: return "bed.double.fill"
        }
    }
}

enum CyclePhase: String, Codable, Equatable {
    case unknown, menstruation, follicular, ovulation, luteal

    var label: String {
        switch self {
        case .unknown: return "Unknown"
        case .menstruation: return "Menstruation"
        case .follicular: return "Follicular"
        case .ovulation: return "Ovulation"
        case .luteal: return "Luteal"
        }
    }

    var icon: String {
        switch self {
        case .unknown: return "circle.dashed"
        case .menstruation: return "drop.fill"
        case .follicular: return "leaf.fill"
        case .ovulation: return "sparkles"
        case .luteal: return "moon.fill"
        }
    }
}

struct StrainScoreBlock: Equatable {
    var score: Int
    var trend: String
    var baselineLoad: Int
    var todayLoad: Int
}

struct RecoveryScoreBlock: Equatable {
    var score: Int
    var hrv: Int?
    var trend: String
}

struct SleepScoreBlock: Equatable {
    var score: Int
    var sleepNeedMinutes: Int
    var totalSleepMinutes: Int
    var deepSleepMinutes: Int
}

struct CycleContext: Equatable {
    var phase: CyclePhase
    var dayInCycle: Int?
    var recommendRecovery: Bool
    var coachingNote: String?
    var hasData: Bool
    var lastEventAt: String?
}

struct CycleEvent: Identifiable, Equatable {
    var id: String
    var startedAt: Date
    var flow: String
}

struct BiologicalAge: Equatable {
    var chronologicalAge: Int
    var biologicalAge: Double
    var deltaYears: Double
    var drivers: [String]
    var generatedAt: Date
}

struct DailyScores: Equatable {
    var date: String
    var strain: StrainScoreBlock
    var recovery: RecoveryScoreBlock
    var sleep: SleepScoreBlock
    var trainingDecision: TrainingDecision
    var cycleContext: CycleContext
    var generatedAt: Date
}

// MARK: - Authoritative daily score computation (client-side; matches backend services)

enum DailyScoresEngine {
    private static func clamp(_ value: Double, low: Double = 0, high: Double = 100) -> Int {
        Int(max(low, min(high, round(value))))
    }

    static func compute(
        readiness: ReadinessData,
        dailyMetrics: DailyMetrics,
        sleepData: [SleepData],
        workoutHistory: [WorkoutHistory],
        compoundFlags: [String],
        cycleContext: CycleContext,
        date: String = ForgeDates.yyyyMMdd(from: Date())
    ) -> DailyScores {
        let strain = strainBlock(dailyMetrics: dailyMetrics, workoutHistory: workoutHistory)
        let recovery = recoveryBlock(readiness: readiness, dailyMetrics: dailyMetrics)
        let sleep = sleepBlock(dailyMetrics: dailyMetrics, sleepData: sleepData)
        let decision = trainingDecision(
            strain: strain.score,
            recovery: recovery.score,
            sleep: sleep.score,
            compoundFlags: compoundFlags,
            cycle: cycleContext
        )

        return DailyScores(
            date: date,
            strain: strain,
            recovery: recovery,
            sleep: sleep,
            trainingDecision: decision,
            cycleContext: cycleContext,
            generatedAt: Date()
        )
    }

    static func inferCyclePhase(from events: [CycleEvent]) -> CycleContext {
        guard let latest = events.sorted(by: { $0.startedAt > $1.startedAt }).first else {
            return CycleContext(
                phase: .unknown,
                dayInCycle: nil,
                recommendRecovery: false,
                coachingNote: nil,
                hasData: false,
                lastEventAt: nil
            )
        }

        let flow = latest.flow.lowercased()
        let dayInCycle = max(1, Calendar.current.dateComponents([.day], from: latest.startedAt, to: Date()).day ?? 0) + 1
        let iso = ISO8601DateFormatter().string(from: latest.startedAt)

        if flow.contains("heavy") || flow.contains("medium") || flow == "1" || flow == "2" || flow == "menstrual" {
            return CycleContext(
                phase: .menstruation,
                dayInCycle: dayInCycle,
                recommendRecovery: true,
                coachingNote: "Menstruation phase — prioritize recovery and technique over max effort.",
                hasData: true,
                lastEventAt: iso
            )
        }
        if flow.contains("light") || flow == "3" {
            return CycleContext(
                phase: .follicular,
                dayInCycle: dayInCycle,
                recommendRecovery: false,
                coachingNote: "Early cycle — energy often rises; good window for progressive training.",
                hasData: true,
                lastEventAt: iso
            )
        }
        if flow.contains("ovulation") || flow.contains("ovulatory") {
            return CycleContext(
                phase: .ovulation,
                dayInCycle: dayInCycle,
                recommendRecovery: false,
                coachingNote: "Ovulation window — peak power potential; monitor hydration and sleep.",
                hasData: true,
                lastEventAt: iso
            )
        }
        if dayInCycle > 21 {
            return CycleContext(
                phase: .luteal,
                dayInCycle: dayInCycle,
                recommendRecovery: dayInCycle > 24,
                coachingNote: "Luteal phase — consider moderating intensity if recovery markers dip.",
                hasData: true,
                lastEventAt: iso
            )
        }

        return CycleContext(
            phase: .follicular,
            dayInCycle: dayInCycle,
            recommendRecovery: false,
            coachingNote: nil,
            hasData: true,
            lastEventAt: iso
        )
    }

    static func computeBiologicalAge(
        profile: UserProfile,
        readiness: ReadinessData,
        dailyMetrics: DailyMetrics,
        sleepData: [SleepData]
    ) -> BiologicalAge {
        let chronological = max(18, min(80, profile.age ?? 30))
        let hrv = Double(dailyMetrics.hrv)
        let restingHR = Double(dailyMetrics.restingHR)
        let sleepScore = Double(sleepData.first?.score ?? readiness.sleepQuality)
        let steps = Double(dailyMetrics.steps)
        let recovery = Double(readiness.recoveryScore > 0 ? readiness.recoveryScore : readiness.overall)

        var adjustment = 0.0
        if hrv >= 50 { adjustment -= 2.5 }
        else if hrv > 0 && hrv < 35 { adjustment += 3.0 }

        if restingHR > 0 {
            if restingHR <= 58 { adjustment -= 1.5 }
            else if restingHR >= 72 { adjustment += 2.0 }
        }

        if sleepScore >= 80 { adjustment -= 2.0 }
        else if sleepScore > 0 && sleepScore < 60 { adjustment += 2.5 }

        if steps >= 8000 { adjustment -= 1.0 }
        else if steps > 0 && steps < 4000 { adjustment += 1.0 }

        if recovery >= 75 { adjustment -= 1.5 }
        else if recovery > 0 && recovery < 50 { adjustment += 2.0 }

        let biological = round(max(18, min(85, Double(chronological) + adjustment)) * 10) / 10
        let delta = round((biological - Double(chronological)) * 10) / 10

        var drivers: [String] = []
        if hrv >= 50 { drivers.append("strong_hrv") }
        if sleepScore >= 80 { drivers.append("quality_sleep") }
        if steps >= 8000 { drivers.append("active_lifestyle") }
        if delta > 1 { drivers.append("recovery_lag") }
        if delta < -1 { drivers.append("youthful_markers") }

        return BiologicalAge(
            chronologicalAge: chronological,
            biologicalAge: biological,
            deltaYears: delta,
            drivers: drivers,
            generatedAt: Date()
        )
    }

    // MARK: - Private blocks

    private static func strainBlock(
        dailyMetrics: DailyMetrics,
        workoutHistory: [WorkoutHistory]
    ) -> StrainScoreBlock {
        let recent = workoutHistory.prefix(3).map(\.duration).reduce(0, +)
        let prior = workoutHistory.dropFirst(3).prefix(3).map(\.duration).reduce(0, +)
        let currentLoad = Double(recent)
        let previousLoad = Double(prior)
        let steps = Double(dailyMetrics.steps)
        let calories = Double(dailyMetrics.activeCalories)

        let baseline = max(previousLoad, currentLoad * 0.85, 120)
        let exertion = currentLoad + (steps / 250) + (calories / 25)
        let pct = baseline > 0 ? clamp((exertion / baseline) * 55) : 0

        let trend: String
        if currentLoad > previousLoad * 1.15 && previousLoad > 0 { trend = "rising" }
        else if currentLoad < previousLoad * 0.85 && previousLoad > 0 { trend = "falling" }
        else { trend = "flat" }

        return StrainScoreBlock(
            score: pct,
            trend: trend,
            baselineLoad: Int(baseline.rounded()),
            todayLoad: Int(exertion.rounded())
        )
    }

    private static func recoveryBlock(
        readiness: ReadinessData,
        dailyMetrics: DailyMetrics
    ) -> RecoveryScoreBlock {
        var recovery = readiness.recoveryScore > 0 ? readiness.recoveryScore : readiness.overall
        let hrv = dailyMetrics.hrv
        var trend = "unknown"

        if hrv > 0 {
            if hrv < 35 { recovery = max(0, recovery - 10) }
            trend = hrv >= 50 ? "rising" : (hrv < 40 ? "falling" : "flat")
        }

        return RecoveryScoreBlock(
            score: clamp(Double(recovery)),
            hrv: hrv > 0 ? hrv : nil,
            trend: trend
        )
    }

    private static func sleepBlock(
        dailyMetrics: DailyMetrics,
        sleepData: [SleepData]
    ) -> SleepScoreBlock {
        let targetMinutes = 8 * 60
        let totalSleep = dailyMetrics.totalSleep > 0
            ? dailyMetrics.totalSleep
            : Int((sleepData.first?.totalHours ?? 0) * 60)
        let deepSleep = dailyMetrics.deepSleep > 0
            ? dailyMetrics.deepSleep
            : (sleepData.first?.deepMinutes ?? 0)
        var sleepScore = sleepData.first?.score ?? 0
        if sleepScore == 0 && totalSleep > 0 {
            sleepScore = clamp((Double(totalSleep) / Double(targetMinutes)) * 100)
        }
        let sleepNeed = totalSleep > 0 ? max(0, targetMinutes - totalSleep) : targetMinutes

        return SleepScoreBlock(
            score: clamp(Double(sleepScore)),
            sleepNeedMinutes: sleepNeed,
            totalSleepMinutes: totalSleep,
            deepSleepMinutes: deepSleep
        )
    }

    private static func trainingDecision(
        strain: Int,
        recovery: Int,
        sleep: Int,
        compoundFlags: [String],
        cycle: CycleContext
    ) -> TrainingDecision {
        if compoundFlags.contains("recovery-debt-under-load") || recovery < 45 {
            return .recover
        }
        if strain >= 75 && recovery < 60 {
            return .activeRest
        }
        if cycle.recommendRecovery {
            return .recover
        }
        if recovery >= 70 && sleep >= 65 && strain < 80 {
            return .train
        }
        if recovery >= 55 {
            return .activeRest
        }
        return .recover
    }
}