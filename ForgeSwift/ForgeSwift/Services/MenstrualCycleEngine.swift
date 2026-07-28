import Foundation

/// Multi-signal menstrual cycle inference.
///
/// Accuracy strategy (lifestyle coaching — **not** contraception or medical diagnosis):
/// 1. Cluster flow days → period episodes
/// 2. Personal cycle length = robust median of inter-start intervals (outlier-clipped)
/// 3. Ovulation hierarchy: LH surge → BBT biphasic shift (3-over-6) → peak fertile mucus →
///    fallback `cycleLength − lutealLength`
/// 4. Phases from real boundaries, not a fixed 28-day cookie-cutter alone
/// 5. Next period = distribution from recent cycle lengths (median ± MAD band)
/// 6. Confidence from data density, regularity, and corroborating signals
enum MenstrualCycleEngine {

    static let disclaimer = """
    Cycle insights are lifestyle estimates for training, recovery, and personal timing. \
    They are not medical diagnosis or a fertility treatment. Forge’s tracker is not itself \
    a contraceptive method — ARIA may discuss sexual-health and contraception materials as \
    lifestyle education; use clinician-approved methods for pregnancy prevention. \
    Always verify health decisions with a qualified professional.

    \(CyclePrivacy.shortPromise)
    """

    // MARK: Public

    static func evaluate(
        logs: [CycleDayLog],
        settings: MenstrualTrackingSettings,
        asOf: Date = Date(),
        recentHRV: Int? = nil,
        baselineHRV: Int? = nil,
        restingHR: Int? = nil
    ) -> MenstrualCycleSnapshot {
        let dayKey = CycleDayKey.key(for: asOf)
        guard settings.enabled else {
            var s = MenstrualCycleSnapshot.empty
            s.asOfDayKey = dayKey
            s.disclaimer = disclaimer
            return s
        }

        let sorted = logs.sorted { $0.dayKey < $1.dayKey }
        let episodes = buildPeriodEpisodes(from: sorted)
        let plausibleRange = settings.condition.plausibleCycleLengthRange
        let cycleLengths = interStartLengths(episodes, plausibleRange: plausibleRange)
        let periodLengths = episodes.map(\.dayCount)

        let lutealDays = settings.effectiveLutealDays
        let medianCycle = settings.averageCycleOverride.map(Double.init)
            ?? recencyWeightedMedian(
                cycleLengths.map(Double.init),
                fallback: 28,
                plausibleRange: plausibleRange
            )
        let madCycle = medianAbsoluteDeviation(cycleLengths.map(Double.init), center: medianCycle)
        // A bleed is 3–7 days. Clamping here keeps the "how long is my period" model and
        // the "am I still bleeding" model from ever disagreeing.
        let medianPeriod = Double(
            CycleBiology.clampPeriodDays(
                Int((settings.averagePeriodOverride.map(Double.init)
                    ?? robustMedian(periodLengths.map(Double.init), fallback: Double(CycleBiology.defaultPeriodDays))
                ).rounded())
            )
        )

        let lastStart = episodes.last?.startDayKey
        let dayInCycle: Int? = {
            guard let lastStart,
                  let delta = CycleDayKey.daysBetween(lastStart, dayKey) else { return nil }
            return max(1, delta + 1)
        }()

        // MARK: Period lifecycle
        //
        // A confirmed end belongs to the *current* episode only. If the user has since
        // started a new period, the old confirmation is stale and must be ignored — that
        // is what previously let a finished flag suppress a genuinely active bleed.
        let confirmedEnd: String? = {
            guard let confirmed = settings.confirmedPeriodEndDayKey, let lastStart else { return nil }
            guard let offset = CycleDayKey.daysBetween(lastStart, confirmed), offset >= 0 else { return nil }
            // Also ignore a confirmation that is somehow in the future.
            guard let fromToday = CycleDayKey.daysBetween(confirmed, dayKey), fromToday >= 0 else { return nil }
            return confirmed
        }()
        let periodEndConfirmed = confirmedEnd != nil
        // Effective end of this bleed: the user's confirmation wins; otherwise the last
        // logged bleeding day of the current episode.
        let currentPeriodEnd: String? = confirmedEnd ?? episodes.last?.endDayKey
        let currentPeriodDayCount: Int? = {
            guard let lastStart, let end = currentPeriodEnd,
                  let span = CycleDayKey.daysBetween(lastStart, end) else { return nil }
            return max(1, span + 1)
        }()
        let daysSincePeriodEnd: Int? = currentPeriodEnd
            .flatMap { CycleDayKey.daysBetween($0, dayKey) }
            .flatMap { $0 >= 0 ? $0 : nil }

        let ovulation = estimateOvulation(
            logs: sorted,
            lastPeriodStart: lastStart,
            cycleLength: medianCycle,
            lutealDays: lutealDays,
            asOfDayKey: dayKey
        )

        // Today's own log — never a stale earlier day. Falling back to "the most recent
        // log at or before today" used to report bleeding (and force the menstruation
        // phase) for the rest of the cycle after the last logged bleed day.
        let todayLog = sorted.last(where: { $0.dayKey == dayKey })
        // Recent context is still useful for symptom-driven recovery bias, but it must
        // not drive the bleeding flag.
        let recentLog = todayLog ?? sorted.last(where: { $0.dayKey <= dayKey })
        let insideOpenEpisode = episodes.last.map { $0.startDayKey <= dayKey && $0.endDayKey >= dayKey } == true
        // A confirmed end is final and takes effect immediately. Tapping "Period finished"
        // has to change what the app says today — waiting for the median bleed length to
        // elapse is precisely the behaviour that made the confirmation feel ignored.
        // Only a *new* period start reopens bleeding (which clears the confirmation).
        let bleedIsOver = periodEndConfirmed && (daysSincePeriodEnd ?? -1) >= 0
        let bleedingToday = !bleedIsOver && (todayLog?.flow.isBleeding == true || insideOpenEpisode)

        // Perimenopause: ovulation/fertile labelling is unreliable, so it must not leak
        // through the phase either — otherwise the Live Activity, watch complication and
        // ARIA context all announce a fertile window the rest of the UI suppresses.
        let suppressFertile = settings.condition.suppressesFertileWindow
        let fertileStartDay = suppressFertile
            ? nil
            : ovulation.map { max(1, $0.dayInCycle - CycleBiology.fertileDaysBeforeOvulation) }
        let fertileEndDay = suppressFertile
            ? nil
            : ovulation.map { $0.dayInCycle + CycleBiology.fertileDaysAfterOvulation }
        let phase = resolvePhase(
            dayInCycle: dayInCycle,
            periodLength: medianPeriod,
            // The fix for "I said my period finished but the app still says I'm
            // menstruating": a confirmed end ends the menstruation phase outright, and
            // an unconfirmed one is bounded by the *actual* logged bleed, not the median.
            bleedIsOver: bleedIsOver,
            confirmedPeriodDays: currentPeriodDayCount,
            ovulationDay: suppressFertile ? nil : ovulation?.dayInCycle,
            fertileStart: fertileStartDay,
            fertileEnd: fertileEndDay,
            bleedingToday: bleedingToday,
            hormonal: settings.usesHormonalContraception,
            suppressFertileLabels: suppressFertile
        )

        let ensemble = ensembleCycleLength(
            lengths: cycleLengths,
            recencyMedian: medianCycle,
            ovulation: ovulation,
            lutealDays: lutealDays,
            dayInCycle: dayInCycle,
            plausibleRange: plausibleRange
        )

        let nextPeriod = predictNextPeriod(
            lastStart: lastStart,
            lengths: cycleLengths,
            median: ensemble.median,
            mad: madCycle + Double(max(0, settings.overdueWidenDays)) + ensemble.extraSpread,
            calibrationOffsetDays: settings.calibrationOffsetDays
        )

        let nextOvuKey: String? = {
            guard let lastStart, let ovuDay = ovulation?.dayInCycle else { return nil }
            if let dic = dayInCycle, dic > ovuDay {
                let nextStart = nextPeriod?.medianDayKey ?? CycleDayKey.addDays(lastStart, Int(medianCycle.rounded()))
                guard let ns = nextStart else { return nil }
                return CycleDayKey.addDays(ns, ovuDay - 1)
            }
            return CycleDayKey.addDays(lastStart, (ovulation?.dayInCycle ?? 14) - 1)
        }()

        // Conditions like PCOS and perimenopause inherently produce irregular cycles —
        // use a much wider threshold so the flag only fires for truly unexpected variance.
        let irregularThreshold: Double = settings.condition.suppressesIrregularityFlag ? 10 : 4
        let irregularRangeThreshold = settings.condition.suppressesIrregularityFlag ? 18 : 10
        let irregular = madCycle >= irregularThreshold
            || (cycleLengths.count >= 3 && (cycleLengths.max()! - cycleLengths.min()!) >= irregularRangeThreshold)
        let hasLH = ovulation?.method == "lh_surge"
        let hasBBT = ovulation?.method == "bbt_shift"

        let periodConf = computePeriodTimingConfidence(
            cyclesObserved: cycleLengths.count,
            mad: madCycle,
            hormonal: settings.usesHormonalContraception,
            calibrated: abs(settings.calibrationOffsetDays) > 0.2,
            overdue: settings.overdueWidenDays > 0
        )
        let ovuConf = ovulation?.confidence
            ?? (settings.usesHormonalContraception ? 0.2 : 0.35)
        let confidence = min(0.95, 0.55 * periodConf + 0.45 * ovuConf)

        let dataQuality: String = {
            if cycleLengths.count >= 6 && periodConf >= 0.75 && (hasLH || hasBBT) { return "high" }
            if cycleLengths.count >= 6 && periodConf >= 0.7 { return "high" }
            if cycleLengths.count >= 3 && periodConf >= 0.5 { return "good" }
            if cycleLengths.count >= 1 { return "learning" }
            if !sorted.isEmpty { return "partial" }
            return "no_data"
        }()

        let recoveryBias = phase == .menstruation
            || phase == .luteal && (dayInCycle ?? 0) >= Int(medianCycle - 4)
            || (recentLog?.symptoms.contains(.cramps) == true)
            || (recentLog?.symptoms.contains(.fatigue) == true)
            // Logged pain is a first-class recovery signal, not decoration.
            || ((todayLog?.painScale ?? 0) >= 5)

        var insights = buildInsights(
            phase: phase,
            dayInCycle: dayInCycle,
            medianCycle: medianCycle,
            mad: madCycle,
            ovulation: ovulation,
            irregular: irregular,
            cycles: cycleLengths.count,
            hormonal: settings.usesHormonalContraception,
            condition: settings.condition
        )
        insights.insert(
            "Timing method: \(ensemble.summary). Windows use robust personal history — not a single false-precision day.",
            at: 0
        )

        if let hrv = recentHRV, let base = baselineHRV, base > 0, phase == .luteal {
            let dip = Double(base - hrv) / Double(base)
            if dip >= 0.12 {
                insights.append("HRV is ~\(Int(dip * 100))% under your baseline — common in late luteal; don't over-read it as pure under-recovery.")
            }
        }
        if let rhr = restingHR, phase == .luteal, rhr >= 65 {
            insights.append("Resting HR often ticks up in luteal. Pair with how you feel before adding load.")
        }

        // Pain trend across the last three logged episodes — the reason the pain slider exists.
        let recentPain = sorted.suffix(90).compactMap(\.painScale).filter { $0 > 0 }
        if recentPain.count >= 3 {
            let peak = recentPain.max() ?? 0
            let mean = Double(recentPain.reduce(0, +)) / Double(recentPain.count)
            insights.append(
                "Pain logged on \(recentPain.count) recent days · average \(String(format: "%.1f", mean))/10, peak \(peak)/10."
            )
            if peak >= 8 || mean >= 6 {
                insights.append("Pain at this level, cycle after cycle, is worth raising with a clinician — Forge can track it but cannot assess it.")
            }
        }

        // Perimenopause: fertile window predictions are unreliable — suppress them.
        let fertileStart = suppressFertile ? nil : ovulation.map { max(1, $0.dayInCycle - 5) }
        let fertileEnd = suppressFertile ? nil : ovulation.map { $0.dayInCycle + 1 }
        let fertileScore = suppressFertile ? nil : computeFertileScore(
            dayInCycle: dayInCycle,
            ovulationDay: ovulation?.dayInCycle,
            fertileStart: fertileStart,
            fertileEnd: fertileEnd,
            ovulationConfidence: ovuConf,
            ovulationMethod: ovulation?.method,
            hormonal: settings.usesHormonalContraception,
            cyclesObserved: cycleLengths.count,
            mad: madCycle
        )
        if let fertileScore, fertileScore >= 70, !suppressFertile {
            insights.append(
                "Fertile Score \(fertileScore)/100 — multi-signal confidence that you are in or near the fertile window (lifestyle timing, not contraception)."
            )
        }

        // Real calendar dates for the fertile window, so the UI and ARIA can say
        // "Fri 8 – Wed 13" instead of only "days 10–16 of your cycle".
        let fertileWindowStartKey = lastStart.flatMap { start in
            fertileStartDay.flatMap { CycleDayKey.addDays(start, $0 - 1) }
        }
        let fertileWindowEndKey = lastStart.flatMap { start in
            fertileEndDay.flatMap { CycleDayKey.addDays(start, $0 - 1) }
        }
        let daysUntilNextPeriod = nextPeriod.flatMap { CycleDayKey.daysBetween(dayKey, $0.medianDayKey) }

        let stage = resolveStage(
            phase: phase,
            bleedingToday: bleedingToday,
            dayInCycle: dayInCycle,
            fertileStart: fertileStartDay,
            fertileEnd: fertileEndDay,
            ovulationDay: suppressFertile ? nil : ovulation?.dayInCycle,
            suppressFertile: suppressFertile,
            hormonal: settings.usesHormonalContraception
        )
        let stageNarrative = narrative(
            stage: stage,
            periodDayCount: currentPeriodDayCount,
            daysSincePeriodEnd: daysSincePeriodEnd,
            periodEndConfirmed: periodEndConfirmed,
            daysUntilNextPeriod: daysUntilNextPeriod,
            fertileStartKey: fertileWindowStartKey,
            fertileEndKey: fertileWindowEndKey,
            dayInCycle: dayInCycle
        )
        if !stageNarrative.isEmpty {
            insights.insert(stageNarrative, at: 0)
        }

        return MenstrualCycleSnapshot(
            asOfDayKey: dayKey,
            trackingEnabled: true,
            phase: phase,
            dayInCycle: dayInCycle,
            cycleLengthMedian: medianCycle,
            cycleLengthMAD: madCycle,
            periodLengthMedian: medianPeriod,
            cyclesObserved: cycleLengths.count,
            ovulationDayInCycle: suppressFertile ? nil : ovulation?.dayInCycle,
            ovulationMethod: suppressFertile ? nil : ovulation?.method,
            fertileStartDayInCycle: fertileStart,
            fertileEndDayInCycle: fertileEnd,
            nextPeriod: nextPeriod,
            nextOvulationDayKey: suppressFertile ? nil : nextOvuKey,
            confidence: confidence,
            dataQuality: dataQuality,
            recommendRecoveryBias: recoveryBias,
            trainingNote: phase.trainingBias,
            readinessNote: readinessNote(for: phase, recoveryBias: recoveryBias),
            insights: insights,
            disclaimer: disclaimer,
            lastPeriodStartDayKey: lastStart,
            isCurrentlyBleeding: bleedingToday,
            irregularityFlag: irregular,
            accuracyMAE: nil,
            accuracySampleCount: 0,
            accuracyGrade: "learning",
            calibrationOffsetDays: settings.calibrationOffsetDays,
            periodTimingConfidence: periodConf,
            ovulationConfidence: ovuConf,
            learnedLutealDays: settings.learnedLutealDays,
            predictionMethodSummary: ensemble.summary,
            condition: settings.condition == .none ? nil : settings.condition,
            wristTemperatureAvailable: false,
            fertileScore: fertileScore,
            stage: stage,
            currentPeriodEndDayKey: currentPeriodEnd,
            periodEndConfirmed: periodEndConfirmed,
            currentPeriodDayCount: currentPeriodDayCount,
            daysSincePeriodEnd: daysSincePeriodEnd,
            daysUntilNextPeriod: daysUntilNextPeriod,
            fertileWindowStartDayKey: suppressFertile ? nil : fertileWindowStartKey,
            fertileWindowEndDayKey: suppressFertile ? nil : fertileWindowEndKey,
            stageNarrative: stageNarrative
        )
    }

    // MARK: Fertile Score (0…100)

    /// Multi-signal fertile-window confidence for UI, Live Activity, and ARIA.
    /// Lifestyle timing aid only — never presented as contraception.
    static func computeFertileScore(
        dayInCycle: Int?,
        ovulationDay: Int?,
        fertileStart: Int?,
        fertileEnd: Int?,
        ovulationConfidence: Double,
        ovulationMethod: String?,
        hormonal: Bool,
        cyclesObserved: Int,
        mad: Double
    ) -> Int? {
        guard !hormonal else { return nil }
        guard let dayInCycle, let ovulationDay else { return nil }

        let start = fertileStart ?? max(1, ovulationDay - 5)
        let end = fertileEnd ?? (ovulationDay + 1)

        // Distance from peak ovulation day: peak = 1.0, linear falloff outside window to 0.
        let distance = abs(dayInCycle - ovulationDay)
        let windowHalf = max(1, max(ovulationDay - start, end - ovulationDay))
        let proximity: Double
        if dayInCycle >= start && dayInCycle <= end {
            proximity = max(0.35, 1.0 - (Double(distance) / Double(windowHalf + 1)) * 0.55)
        } else if distance <= 3 {
            proximity = max(0.08, 0.32 - Double(distance - windowHalf) * 0.08)
        } else {
            proximity = 0.04
        }

        let methodBoost: Double = {
            switch ovulationMethod {
            case "lh_surge": return 1.0
            case "bbt_shift": return 0.88
            case "peak_mucus", "mucus": return 0.72
            default: return 0.55
            }
        }()

        let historyBoost = min(1.0, 0.55 + 0.08 * Double(min(cyclesObserved, 6)))
        let regularity = mad <= 2 ? 1.0 : mad <= 4 ? 0.9 : mad <= 7 ? 0.75 : 0.55
        let conf = max(0.15, min(1.0, ovulationConfidence))

        let raw = 100.0 * proximity * methodBoost * historyBoost * regularity * (0.55 + 0.45 * conf)
        return Int(max(0, min(100, raw.rounded())))
    }

    // MARK: Episodes

    static func buildPeriodEpisodes(from logs: [CycleDayLog]) -> [PeriodEpisode] {
        // Prefer true bleeding clusters; spotting-only runs are weaker episode anchors.
        let bleedingDays = logs.filter { $0.flow.isBleeding }.map(\.dayKey).sorted()
        guard !bleedingDays.isEmpty else { return [] }

        var episodes: [PeriodEpisode] = []
        var run: [String] = [bleedingDays[0]]

        for i in 1..<bleedingDays.count {
            let prev = bleedingDays[i - 1]
            let cur = bleedingDays[i]
            let gap = CycleDayKey.daysBetween(prev, cur) ?? 99
            if gap <= 2 {
                run.append(cur)
            } else {
                if let ep = makeEpisodeIfValid(run, logs: logs) {
                    episodes.append(ep)
                }
                run = [cur]
            }
        }
        if let ep = makeEpisodeIfValid(run, logs: logs) {
            episodes.append(ep)
        }
        return episodes
    }

    /// Spotting-only isolated days don't open a new cycle; need light+ or multi-day bleed.
    private static func makeEpisodeIfValid(_ days: [String], logs: [CycleDayLog]) -> PeriodEpisode? {
        let flows = days.compactMap { d in logs.first(where: { $0.dayKey == d })?.flow }
        let peak = flows.max(by: { $0.sortWeight < $1.sortWeight }) ?? .unspecified
        let hasRealFlow = flows.contains { $0 == .light || $0 == .medium || $0 == .heavy }
        let multiDaySpotting = days.count >= 2 && flows.contains(where: { $0.isBleeding })
        guard hasRealFlow || multiDaySpotting else { return nil }

        // True start: first medium/heavy if present within first 2 days; else first bleeding day.
        let start: String = {
            let ordered = days.sorted()
            for key in ordered.prefix(2) {
                if let f = logs.first(where: { $0.dayKey == key })?.flow,
                   f == .medium || f == .heavy {
                    return key
                }
            }
            for key in ordered {
                if let f = logs.first(where: { $0.dayKey == key })?.flow, f.isBleeding, f != .spotting {
                    return key
                }
            }
            return ordered.first!
        }()
        let end = days.sorted().last!
        let count = (CycleDayKey.daysBetween(start, end) ?? 0) + 1
        return PeriodEpisode(
            id: start,
            startDayKey: start,
            endDayKey: end,
            peakFlow: peak,
            dayCount: max(1, count)
        )
    }

    private static func interStartLengths(
        _ episodes: [PeriodEpisode],
        plausibleRange: ClosedRange<Int> = 18...45
    ) -> [Int] {
        guard episodes.count >= 2 else { return [] }
        var lengths: [Int] = []
        for i in 1..<episodes.count {
            if let d = CycleDayKey.daysBetween(episodes[i - 1].startDayKey, episodes[i].startDayKey),
               plausibleRange.contains(d) {
                lengths.append(d)
            }
        }
        return lengths
    }

    // MARK: Ovulation

    private struct OvulationEstimate {
        var dayInCycle: Int
        var method: String
        var confidence: Double
    }

    private static func estimateOvulation(
        logs: [CycleDayLog],
        lastPeriodStart: String?,
        cycleLength: Double,
        lutealDays: Int,
        asOfDayKey: String
    ) -> OvulationEstimate? {
        guard let start = lastPeriodStart else {
            let fallback = max(10, Int(cycleLength.rounded()) - lutealDays)
            return OvulationEstimate(dayInCycle: fallback, method: "population_fallback", confidence: 0.25)
        }

        let cycleLogs = logs.filter { $0.dayKey >= start && $0.dayKey <= asOfDayKey }

        // Ovulation on day 60 of a cycle is not a signal, it is a mislogged test. Every
        // branch below clamps into a physiologically sane band before it is trusted.
        let maxOvulationDay = max(21, Int(cycleLength.rounded()) + 7)
        func clampDay(_ day: Int) -> Int { max(6, min(maxOvulationDay, day)) }

        // 1) LH / OPK
        if let lh = cycleLogs.last(where: { $0.ovulationTest?.indicatesNearOvulation == true }),
           let day = CycleDayKey.daysBetween(start, lh.dayKey) {
            // LH surge day + ~24h → ovulation day ≈ surge day index + 1
            return OvulationEstimate(dayInCycle: clampDay(day + 2), method: "lh_surge", confidence: 0.9)
        }

        // 2) BBT 3-over-6 shift
        if let bbtDay = detectBBTShift(cycleLogs: cycleLogs, start: start) {
            return OvulationEstimate(dayInCycle: clampDay(bbtDay), method: "bbt_shift", confidence: 0.8)
        }

        // 3) Peak egg-white / watery mucus
        if let mucusDay = cycleLogs
            .filter({ ($0.mucus?.fertilityScore ?? 0) >= 4 })
            .max(by: { ($0.mucus?.fertilityScore ?? 0) < ($1.mucus?.fertilityScore ?? 0) }),
           let day = CycleDayKey.daysBetween(start, mucusDay.dayKey) {
            return OvulationEstimate(dayInCycle: clampDay(day + 1), method: "peak_mucus", confidence: 0.65)
        }

        // 4) Personalized calendar: cycle − luteal
        let calc = max(10, min(Int(cycleLength.rounded()) - max(10, min(16, lutealDays)), Int(cycleLength.rounded()) - 10))
        return OvulationEstimate(dayInCycle: calc, method: "calendar_minus_luteal", confidence: 0.45)
    }

    /// Classic fertility-awareness: 3 consecutive temps higher than prior 6 coverline.
    private static func detectBBTShift(cycleLogs: [CycleDayLog], start: String) -> Int? {
        let series: [(day: Int, t: Double)] = cycleLogs.compactMap { log in
            guard let t = log.bbtCelsius, t > 35.0, t < 38.5,
                  let d = CycleDayKey.daysBetween(start, log.dayKey) else { return nil }
            return (d + 1, t)
        }.sorted { $0.day < $1.day }

        guard series.count >= 9 else { return nil }

        for i in 6..<(series.count - 2) {
            let cover = series[(i - 6)..<i].map(\.t)
            let coverMax = cover.max() ?? 0
            let next3 = series[i..<(i + 3)].map(\.t)
            // Shift if all 3 exceed coverline max by ≥0.1°C (slightly relaxed for wrist-adjacent noise)
            if next3.allSatisfy({ $0 >= coverMax + 0.10 }) {
                // Ovulation typically day before sustained rise
                return max(1, series[i].day - 1)
            }
        }
        return nil
    }

    // MARK: Phase

    private static func resolvePhase(
        dayInCycle: Int?,
        periodLength: Double,
        bleedIsOver: Bool = false,
        confirmedPeriodDays: Int? = nil,
        ovulationDay: Int?,
        fertileStart: Int?,
        fertileEnd: Int?,
        bleedingToday: Bool,
        hormonal: Bool,
        suppressFertileLabels: Bool = false
    ) -> MenstrualPhase {
        if bleedingToday { return .menstruation }
        guard let day = dayInCycle else { return .unknown }

        // A confirmed finish ends the menstruation phase immediately. While it is still
        // running, the personal median covers days the user simply hasn't logged yet —
        // but it can never claim a *shorter* bleed than what has actually been recorded.
        let bleedDays = max(
            confirmedPeriodDays ?? 0,
            CycleBiology.clampPeriodDays(Int(periodLength.rounded()))
        )
        if !bleedIsOver, day <= bleedDays { return .menstruation }

        if hormonal {
            // Hormonal contraception: phases are less meaningful — keep simple bleed vs non-bleed.
            return .follicular
        }

        if suppressFertileLabels {
            // Perimenopause: never claim a fertile window or ovulation day. Report the
            // broad pre/post half of the cycle instead of an unfounded mid-cycle label.
            return day <= bleedDays + 9 ? .follicular : .luteal
        }

        if let ovu = ovulationDay {
            if day == ovu { return .ovulation }
            if let fs = fertileStart, let fe = fertileEnd, day >= fs, day <= fe {
                return day == ovu ? .ovulation : .fertileWindow
            }
            if day < (fertileStart ?? ovu - 5) { return .follicular }
            if day > (fertileEnd ?? ovu + 1) { return .luteal }
        }

        // Fallback calendar windows on a personalized cycle
        if day <= 11 { return .follicular }
        if day <= 16 { return .fertileWindow }
        return .luteal
    }

    // MARK: Cycle stage

    /// The lifecycle position, which is what the UI and partner coaching actually key
    /// off. `MenstrualPhase` alone could not express "the bleed is over" — it only had
    /// `.menstruation` versus everything else.
    private static func resolveStage(
        phase: MenstrualPhase,
        bleedingToday: Bool,
        dayInCycle: Int?,
        fertileStart: Int?,
        fertileEnd: Int?,
        ovulationDay: Int?,
        suppressFertile: Bool,
        hormonal: Bool
    ) -> CycleStage {
        if bleedingToday { return .period }
        guard let day = dayInCycle else { return .unknown }
        if phase == .menstruation { return .period }
        if phase == .unknown { return .unknown }

        // With fertile labelling suppressed (perimenopause) or ovulation suppressed
        // (hormonal contraception) there is no honest fertile stage to report.
        if suppressFertile || hormonal {
            return phase == .luteal ? .premenstrual : .postPeriod
        }

        if let ovulationDay, day == ovulationDay { return .ovulation }
        if let fertileStart, let fertileEnd, day >= fertileStart, day <= fertileEnd { return .fertile }
        if let fertileStart, day < fertileStart { return .postPeriod }
        return .premenstrual
    }

    /// One honest sentence describing where the cycle is. Shared by the UI, the partner
    /// brief and ARIA so all three tell the same story.
    private static func narrative(
        stage: CycleStage,
        periodDayCount: Int?,
        daysSincePeriodEnd: Int?,
        periodEndConfirmed: Bool,
        daysUntilNextPeriod: Int?,
        fertileStartKey: String?,
        fertileEndKey: String?,
        dayInCycle: Int?
    ) -> String {
        func window() -> String? {
            guard let s = fertileStartKey, let e = fertileEndKey else { return nil }
            return "\(CycleDayKey.shortDisplay(s))–\(CycleDayKey.shortDisplay(e))"
        }
        func nextPeriodClause() -> String {
            guard let days = daysUntilNextPeriod else { return "" }
            if days < 0 { return " Next period is \(-days) day\(days == -1 ? "" : "s") past the mid-estimate." }
            if days == 0 { return " Next period is estimated for today." }
            if days == 1 { return " Next period is estimated for tomorrow." }
            return " Next period is about \(days) days out."
        }

        switch stage {
        case .period:
            if let day = dayInCycle {
                return "Day \(day) of your period.\(nextPeriodClause())"
            }
            return "On your period."
        case .postPeriod:
            let lengthClause = periodDayCount.map { " Your period ran \($0) day\($0 == 1 ? "" : "s")." } ?? ""
            let sinceClause: String = {
                guard let since = daysSincePeriodEnd else { return "" }
                if since == 0 { return " It finished today." }
                if since == 1 { return " It finished yesterday." }
                return " It finished \(since) days ago."
            }()
            let confirmClause = periodEndConfirmed ? "" : " (Tap Period finished to confirm.)"
            let fertileClause = window().map { " Fertile window opens around \($0)." } ?? ""
            return "Period over — back to your normal rhythm.\(lengthClause)\(sinceClause)\(fertileClause)\(confirmClause)"
        case .fertile:
            let w = window().map { " Window: \($0)." } ?? ""
            return "Fertile window is open.\(w)\(nextPeriodClause())"
        case .ovulation:
            return "Estimated ovulation day.\(nextPeriodClause())"
        case .premenstrual:
            return "Post-ovulation stretch before your next period.\(nextPeriodClause())"
        case .unknown:
            return ""
        }
    }

    // MARK: Prediction

    private static func predictNextPeriod(
        lastStart: String?,
        lengths: [Int],
        median: Double,
        mad: Double,
        calibrationOffsetDays: Double = 0
    ) -> CyclePredictionRange? {
        guard let lastStart else { return nil }
        let med = Int((median + calibrationOffsetDays).rounded())
        let spread = max(1, Int(ceil(mad * 1.5)))
        var low = med - spread
        var high = med + spread
        if lengths.count >= 4 {
            let sorted = lengths.sorted()
            let cal = Int(calibrationOffsetDays.rounded())
            low = sorted[max(0, sorted.count / 10)] + cal
            high = sorted[min(sorted.count - 1, (sorted.count * 9) / 10)] + cal
        }
        // Ensure window contains median
        low = min(low, med - 1)
        high = max(high, med + 1)
        guard let earliest = CycleDayKey.addDays(lastStart, low),
              let medianKey = CycleDayKey.addDays(lastStart, med),
              let latest = CycleDayKey.addDays(lastStart, high) else { return nil }
        return CyclePredictionRange(earliestDayKey: earliest, medianDayKey: medianKey, latestDayKey: latest)
    }

    // MARK: Recency + ensemble

    /// Exponential recency weights (half-life ~4 cycles).
    private static func recencyWeightedMedian(
        _ values: [Double],
        fallback: Double,
        plausibleRange: ClosedRange<Int> = 18...45
    ) -> Double {
        guard !values.isEmpty else { return fallback }
        if values.count == 1 { return values[0] }
        let lo = Double(plausibleRange.lowerBound)
        let hi = Double(plausibleRange.upperBound)
        let clipped = values.map { min(hi, max(lo, $0)) }
        // Weighted percentile-50 via duplicate expansion of recent samples
        var expanded: [Double] = []
        for (i, v) in clipped.enumerated() {
            let age = clipped.count - 1 - i
            let w = max(1, Int((pow(0.5, Double(age) / 4.0) * 8).rounded()))
            expanded.append(contentsOf: Array(repeating: v, count: w))
        }
        return robustMedian(expanded, fallback: fallback)
    }

    private struct EnsembleResult {
        var median: Double
        var extraSpread: Double
        var summary: String
    }

    private static func ensembleCycleLength(
        lengths: [Int],
        recencyMedian: Double,
        ovulation: OvulationEstimate?,
        lutealDays: Int,
        dayInCycle: Int?,
        plausibleRange: ClosedRange<Int> = 18...45
    ) -> EnsembleResult {
        var candidates: [Double] = [recencyMedian]
        var parts = ["recency-weighted median"]

        if let last = lengths.last {
            candidates.append(Double(last))
            parts.append("last cycle")
        }
        if lengths.count >= 3 {
            candidates.append(robustMedian(lengths.map(Double.init), fallback: recencyMedian))
            parts.append("robust median")
        }
        // High-signal: if ovulation observed this cycle and we're still pre-period, project luteal end
        if let ovu = ovulation, ovu.method == "lh_surge" || ovu.method == "bbt_shift",
           let dic = dayInCycle, dic >= ovu.dayInCycle {
            let projected = Double(ovu.dayInCycle + lutealDays - 1)
            if plausibleRange.contains(Int(projected)) {
                candidates.append(projected)
                parts.append("ovu+\(lutealDays)d luteal")
            }
        }

        let blend = robustMedian(candidates, fallback: recencyMedian)
        let spreadExtra = candidates.count >= 3
            ? medianAbsoluteDeviation(candidates, center: blend) * 0.35
            : 0
        return EnsembleResult(
            median: blend,
            extraSpread: spreadExtra,
            summary: parts.joined(separator: " · ")
        )
    }

    private static func computePeriodTimingConfidence(
        cyclesObserved: Int,
        mad: Double,
        hormonal: Bool,
        calibrated: Bool,
        overdue: Bool
    ) -> Double {
        var c = 0.18
        c += min(0.4, Double(cyclesObserved) * 0.07)
        if mad <= 1.5 { c += 0.18 }
        else if mad <= 3 { c += 0.1 }
        else if mad >= 6 { c -= 0.12 }
        if calibrated { c += 0.05 }
        if overdue { c -= 0.12 }
        if hormonal { c = min(c, 0.5) }
        return max(0.05, min(0.95, c))
    }

    // MARK: Stats

    private static func robustMedian(_ values: [Double], fallback: Double) -> Double {
        guard !values.isEmpty else { return fallback }
        let s = values.sorted()
        // Trim extreme 10% each side when n≥6
        let trimmed: [Double]
        if s.count >= 6 {
            let k = max(1, s.count / 10)
            trimmed = Array(s[k..<(s.count - k)])
        } else {
            trimmed = s
        }
        let m = trimmed.count / 2
        if trimmed.count % 2 == 0 {
            return (trimmed[m - 1] + trimmed[m]) / 2
        }
        return trimmed[m]
    }

    private static func medianAbsoluteDeviation(_ values: [Double], center: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let devs = values.map { abs($0 - center) }.sorted()
        let m = devs.count / 2
        if devs.count % 2 == 0 {
            return (devs[m - 1] + devs[m]) / 2
        }
        return devs[m]
    }

    private static func readinessNote(for phase: MenstrualPhase, recoveryBias: Bool) -> String {
        switch phase {
        case .menstruation:
            return "Period days: interpret fatigue with compassion — readiness dips can be hormonal, not laziness."
        case .luteal:
            return recoveryBias
                ? "Late luteal: expect slightly lower HRV / higher RHR for some people. Bias quality over max intent."
                : "Luteal: keep standards high but leave a rep in the tank if recovery markers soft."
        case .follicular, .fertileWindow, .ovulation:
            return "Often a resilient window — still respect readiness and pain signals."
        case .unknown:
            return "Not enough cycle signal yet — biometrics lead."
        }
    }

    private static func buildInsights(
        phase: MenstrualPhase,
        dayInCycle: Int?,
        medianCycle: Double,
        mad: Double,
        ovulation: OvulationEstimate?,
        irregular: Bool,
        cycles: Int,
        hormonal: Bool,
        condition: CycleCondition = .none
    ) -> [String] {
        var lines: [String] = []
        if let day = dayInCycle {
            lines.append("Day \(day) of an estimated \(Int(medianCycle.rounded()))-day cycle.")
        }
        if let ovu = ovulation, !condition.suppressesFertileWindow {
            lines.append("Ovulation estimate: day \(ovu.dayInCycle) (\(ovu.method.replacingOccurrences(of: "_", with: " "))).")
        }
        if cycles >= 3 {
            lines.append("Personal cycle median from \(cycles) observed cycles (±\(String(format: "%.1f", mad)) days MAD).")
        } else if cycles == 0 {
            lines.append("Log period starts to personalize length — accuracy climbs after 2–3 cycles.")
        }
        if irregular {
            lines.append("Variability is elevated — predictions show a wider window on purpose.")
        }
        switch condition {
        case .pcos:
            lines.append("PCOS mode: long and variable cycles are counted as real history, not thrown out as errors, and the irregularity flag stays quiet unless variance is extreme.")
        case .perimenopause:
            lines.append("Perimenopause mode: fertile-window and ovulation labels are withheld because they are not reliable here — period timing stays a range, not a date.")
        case .endometriosis:
            lines.append("Endometriosis mode: pain and pelvic symptoms are weighted into recovery guidance. Pain that disrupts daily life is worth raising with a clinician.")
        case .thyroid:
            lines.append("Thyroid mode: BBT baselines shift with thyroid status and medication timing — take temperature before any morning dose.")
        case .other, .none:
            break
        }
        if hormonal {
            lines.append("Hormonal contraception noted: phase labels are simplified; bleed vs non-bleed drives coaching.")
        }
        lines.append(phase.trainingBias)
        return lines
    }

    // MARK: ARIA / plan helpers

    /// Intensity multiplier for plan engine (1.0 = neutral). Coaching bias only.
    static func intensityMultiplier(for snapshot: MenstrualCycleSnapshot) -> Double {
        guard snapshot.trackingEnabled else { return 1.0 }
        switch snapshot.phase {
        case .menstruation:
            return snapshot.recommendRecoveryBias ? 0.75 : 0.85
        case .luteal:
            return snapshot.recommendRecoveryBias ? 0.85 : 0.92
        case .follicular:
            return 1.05
        case .fertileWindow, .ovulation:
            return 1.08
        case .unknown:
            return 1.0
        }
    }

    /// Soft readiness adjustment: luteal/period fatigue is partly expected.
    static func readinessInterpretationBonus(for snapshot: MenstrualCycleSnapshot) -> Int {
        guard snapshot.trackingEnabled else { return 0 }
        switch snapshot.phase {
        case .menstruation: return 3
        case .luteal where snapshot.recommendRecoveryBias: return 4
        case .luteal: return 2
        default: return 0
        }
    }
}
