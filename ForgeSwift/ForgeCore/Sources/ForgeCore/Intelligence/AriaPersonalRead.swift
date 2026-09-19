import Foundation

/// One coaching picture from the engines that already live in ForgeCore.
///
/// Dummy and local ARIA used to pick last-night hours and a population
/// readiness score. This fold is what they should actually coach from:
/// personal sleep depth, personal HRV, QoL, aging, swarm, and the ledger.
public struct AriaPersonalRead: Equatable, Sendable {
    public var sleepDepth: SleepDepthResult?
    public var sleepWeak: Bool
    public var hrvMs: Double?
    public var hrvBaselineMs: Double?
    public var hrvBelowPersonal: Bool
    public var keepLight: Bool
    public var companionLine: String?
    public var qolLine: String?
    public var agingLine: String?
    public var swarmLine: String?
    public var swarmProtect: Bool

    public init(
        sleepDepth: SleepDepthResult? = nil,
        sleepWeak: Bool = false,
        hrvMs: Double? = nil,
        hrvBaselineMs: Double? = nil,
        hrvBelowPersonal: Bool = false,
        keepLight: Bool = false,
        companionLine: String? = nil,
        qolLine: String? = nil,
        agingLine: String? = nil,
        swarmLine: String? = nil,
        swarmProtect: Bool = false
    ) {
        self.sleepDepth = sleepDepth
        self.sleepWeak = sleepWeak
        self.hrvMs = hrvMs
        self.hrvBaselineMs = hrvBaselineMs
        self.hrvBelowPersonal = hrvBelowPersonal
        self.keepLight = keepLight
        self.companionLine = companionLine
        self.qolLine = qolLine
        self.agingLine = agingLine
        self.swarmLine = swarmLine
        self.swarmProtect = swarmProtect
    }

    public var sleepBand: String {
        if sleepWeak { return "weak" }
        if let score = sleepDepth?.score {
            if score >= 80 { return "strong" }
            if score < 55 { return "weak" }
            return "ok"
        }
        return "unknown"
    }

    /// Grounding line ARIA can speak without dumping sensors.
    public var spokenGround: String? {
        if let companionLine, !companionLine.isEmpty { return companionLine }
        if let flag = sleepDepth?.headline { return flag }
        if hrvBelowPersonal { return "HRV is under your own baseline — not a population cutoff." }
        if swarmProtect, let swarmLine { return swarmLine }
        if let qolLine { return qolLine }
        return nil
    }

    public static func evaluate(
        nightHours: Double?,
        deepMinutes: Double?,
        remMinutes: Double?,
        awakeMinutes: Double?,
        hrvMs: Double?,
        readiness: Int,
        chronologicalAge: Double?,
        vo2Max: Double?,
        restingHR: Double?,
        swarm: AriaSwarmPicture? = nil,
        defaults: UserDefaults = .standard
    ) -> AriaPersonalRead {
        var sleepDepth: SleepDepthResult?
        if let hours = nightHours, hours > 0 {
            let metrics = SleepNightMetrics(
                totalHours: hours,
                deepMinutes: deepMinutes ?? 0,
                remMinutes: remMinutes ?? 0,
                efficiencyPercent: SleepNightMetrics.efficiencyPercent(
                    asleepHours: hours,
                    awakeMinutes: awakeMinutes ?? 0
                ),
                wakeConsistency: 80
            )
            let targets = SleepChronotypeTargets(
                targetHours: 8,
                deepGoalMinutes: 90,
                remGoalMinutes: 90
            )
            sleepDepth = SleepDepthScorer.score(
                metrics: metrics,
                targets: targets,
                baselines: SleepDepthBaselineStore.load(defaults: defaults)
            )
        }

        let hrvBaselines = BodyModelHRVBaselineStore.load(defaults: defaults)
        let hrvBaseline = hrvBaselines.baselineMs(.sdnn)
        let hrvBelow: Bool
        if let hrv = hrvMs, let base = hrvBaseline, base > 0 {
            hrvBelow = hrv < base * 0.92
        } else {
            hrvBelow = false
        }

        let sleepWeak = (nightHours ?? 9) < 6.5
            || (sleepDepth?.score ?? 100) < 55
            || !(sleepDepth?.unusualFlags.isEmpty ?? true)

        let qol = QualityOfLifeLivingStore.load(defaults: defaults)
        let qolLine: String? = qol == nil ? nil : QualityOfLifeLivingStore.coachingLine(defaults: defaults)
        let qolProtect = (qol?.overall ?? 100) < 55

        let aging = AgingSnapshot.evaluate(
            chronologicalAge: chronologicalAge,
            vo2Max: vo2Max,
            hrv: hrvMs,
            restingHR: restingHR,
            sleepHours: nightHours
        )
        let agingLine = aging.hasComparison ? aging.trainingHint : nil

        let swarmProtect = swarm.map { $0.stance.lowercased().contains("protect") || $0.stance.lowercased().contains("easy") } ?? false
        let swarmLine = swarm.flatMap { picture in
            let line = picture.headline.trimmingCharacters(in: .whitespacesAndNewlines)
            return line.isEmpty ? nil : line
        }

        let companion = AriaKnowledgeLedgerStore.load(defaults: defaults)
            .facts
            .sorted { $0.createdAt > $1.createdAt }
            .first(where: { $0.category == .weSpokeAbout || $0.category == .goals })
            .map(\.summary)

        let keepLight = sleepWeak || hrvBelow || qolProtect || swarmProtect || readiness < 55

        return AriaPersonalRead(
            sleepDepth: sleepDepth,
            sleepWeak: sleepWeak,
            hrvMs: hrvMs,
            hrvBaselineMs: hrvBaseline,
            hrvBelowPersonal: hrvBelow,
            keepLight: keepLight,
            companionLine: companion,
            qolLine: qolLine,
            agingLine: agingLine,
            swarmLine: swarmLine,
            swarmProtect: swarmProtect
        )
    }
}
