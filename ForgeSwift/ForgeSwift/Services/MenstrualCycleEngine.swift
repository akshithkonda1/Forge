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
    Cycle insights are lifestyle estimates for training and recovery awareness — \
    not medical diagnosis, not birth control, and not a fertility treatment. \
    Always verify with a clinician for health decisions.

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
        let cycleLengths = interStartLengths(episodes)
        let periodLengths = episodes.map(\.dayCount)

        let medianCycle = settings.averageCycleOverride.map(Double.init)
            ?? robustMedian(cycleLengths.map(Double.init), fallback: 28)
        let madCycle = medianAbsoluteDeviation(cycleLengths.map(Double.init), center: medianCycle)
        let medianPeriod = settings.averagePeriodOverride.map(Double.init)
            ?? robustMedian(periodLengths.map(Double.init), fallback: 5)

        let lastStart = episodes.last?.startDayKey
        let dayInCycle: Int? = {
            guard let lastStart,
                  let delta = CycleDayKey.daysBetween(lastStart, dayKey) else { return nil }
            return max(1, delta + 1)
        }()

        let ovulation = estimateOvulation(
            logs: sorted,
            lastPeriodStart: lastStart,
            cycleLength: medianCycle,
            lutealDays: settings.typicalLutealDays,
            asOfDayKey: dayKey
        )

        let todayLog = sorted.last(where: { $0.dayKey == dayKey })
            ?? sorted.last(where: { $0.dayKey <= dayKey })
        let bleedingToday = todayLog?.flow.isBleeding == true
            || (dayInCycle != nil && dayInCycle! <= Int(medianPeriod.rounded())
                && episodes.last.map { $0.startDayKey <= dayKey && $0.endDayKey >= dayKey } == true)

        let phase = resolvePhase(
            dayInCycle: dayInCycle,
            periodLength: medianPeriod,
            ovulationDay: ovulation?.dayInCycle,
            fertileStart: ovulation.map { max(1, $0.dayInCycle - 5) },
            fertileEnd: ovulation.map { $0.dayInCycle + 1 },
            bleedingToday: bleedingToday,
            hormonal: settings.usesHormonalContraception
        )

        let nextPeriod = predictNextPeriod(
            lastStart: lastStart,
            lengths: cycleLengths,
            median: medianCycle,
            mad: madCycle,
            calibrationOffsetDays: settings.calibrationOffsetDays
        )

        let nextOvuKey: String? = {
            guard let lastStart, let ovuDay = ovulation?.dayInCycle else { return nil }
            // If we're past ovulation this cycle, project next cycle
            if let dic = dayInCycle, dic > ovuDay {
                let nextStart = nextPeriod?.medianDayKey ?? CycleDayKey.addDays(lastStart, Int(medianCycle.rounded()))
                guard let ns = nextStart else { return nil }
                return CycleDayKey.addDays(ns, ovuDay - 1)
            }
            return CycleDayKey.addDays(lastStart, (ovulation?.dayInCycle ?? 14) - 1)
        }()

        let irregular = madCycle >= 4 || (cycleLengths.count >= 3 && (cycleLengths.max()! - cycleLengths.min()!) >= 10)
        let confidence = computeConfidence(
            cyclesObserved: cycleLengths.count,
            mad: madCycle,
            hasLH: ovulation?.method == "lh_surge",
            hasBBT: ovulation?.method == "bbt_shift",
            hasMucus: ovulation?.method == "peak_mucus",
            hormonal: settings.usesHormonalContraception,
            logsCount: sorted.count
        )

        let dataQuality: String = {
            if cycleLengths.count >= 6 && confidence >= 0.75 { return "high" }
            if cycleLengths.count >= 3 && confidence >= 0.5 { return "good" }
            if cycleLengths.count >= 1 { return "learning" }
            if !sorted.isEmpty { return "partial" }
            return "no_data"
        }()

        let recoveryBias = phase == .menstruation
            || phase == .luteal && (dayInCycle ?? 0) >= Int(medianCycle - 4)
            || (todayLog?.symptoms.contains(.cramps) == true)
            || (todayLog?.symptoms.contains(.fatigue) == true)

        var insights = buildInsights(
            phase: phase,
            dayInCycle: dayInCycle,
            medianCycle: medianCycle,
            mad: madCycle,
            ovulation: ovulation,
            irregular: irregular,
            cycles: cycleLengths.count,
            hormonal: settings.usesHormonalContraception
        )

        // Physiological context (coaching, not diagnosis)
        if let hrv = recentHRV, let base = baselineHRV, base > 0, phase == .luteal {
            let dip = Double(base - hrv) / Double(base)
            if dip >= 0.12 {
                insights.append("HRV is ~\(Int(dip * 100))% under your baseline — common in late luteal; don't over-read it as pure under-recovery.")
            }
        }
        if let rhr = restingHR, phase == .luteal, rhr >= 65 {
            insights.append("Resting HR often ticks up in luteal. Pair with how you feel before adding load.")
        }

        // Slight confidence lift when calibration has enough feedback-driven offset history.
        let calibratedConfidence = min(0.95, confidence + (abs(settings.calibrationOffsetDays) > 0.25 ? 0.03 : 0))

        return MenstrualCycleSnapshot(
            asOfDayKey: dayKey,
            trackingEnabled: true,
            phase: phase,
            dayInCycle: dayInCycle,
            cycleLengthMedian: medianCycle,
            cycleLengthMAD: madCycle,
            periodLengthMedian: medianPeriod,
            cyclesObserved: cycleLengths.count,
            ovulationDayInCycle: ovulation?.dayInCycle,
            ovulationMethod: ovulation?.method,
            fertileStartDayInCycle: ovulation.map { max(1, $0.dayInCycle - 5) },
            fertileEndDayInCycle: ovulation.map { $0.dayInCycle + 1 },
            nextPeriod: nextPeriod,
            nextOvulationDayKey: nextOvuKey,
            confidence: calibratedConfidence,
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
            calibrationOffsetDays: settings.calibrationOffsetDays
        )
    }

    // MARK: Episodes

    static func buildPeriodEpisodes(from logs: [CycleDayLog]) -> [PeriodEpisode] {
        let bleedingDays = logs.filter { $0.flow.isBleeding }.map(\.dayKey).sorted()
        guard !bleedingDays.isEmpty else { return [] }

        var episodes: [PeriodEpisode] = []
        var run: [String] = [bleedingDays[0]]

        for i in 1..<bleedingDays.count {
            let prev = bleedingDays[i - 1]
            let cur = bleedingDays[i]
            let gap = CycleDayKey.daysBetween(prev, cur) ?? 99
            // Allow 1 gap day (spotting pause) inside a period
            if gap <= 2 {
                run.append(cur)
            } else {
                episodes.append(makeEpisode(run, logs: logs))
                run = [cur]
            }
        }
        episodes.append(makeEpisode(run, logs: logs))
        return episodes
    }

    private static func makeEpisode(_ days: [String], logs: [CycleDayLog]) -> PeriodEpisode {
        let peak = days.compactMap { d in logs.first(where: { $0.dayKey == d })?.flow }
            .max(by: { $0.sortWeight < $1.sortWeight }) ?? .unspecified
        let start = days.first!
        let end = days.last!
        let count = (CycleDayKey.daysBetween(start, end) ?? 0) + 1
        return PeriodEpisode(
            id: start,
            startDayKey: start,
            endDayKey: end,
            peakFlow: peak,
            dayCount: max(1, count)
        )
    }

    private static func interStartLengths(_ episodes: [PeriodEpisode]) -> [Int] {
        guard episodes.count >= 2 else { return [] }
        var lengths: [Int] = []
        for i in 1..<episodes.count {
            if let d = CycleDayKey.daysBetween(episodes[i - 1].startDayKey, episodes[i].startDayKey),
               d >= 18, d <= 45 {
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

        // 1) LH / OPK
        if let lh = cycleLogs.last(where: { $0.ovulationTest?.indicatesNearOvulation == true }),
           let day = CycleDayKey.daysBetween(start, lh.dayKey) {
            return OvulationEstimate(dayInCycle: day + 1 + 1, method: "lh_surge", confidence: 0.9)
            // LH surge day + ~24h → ovulation day ≈ day+1 from surge day index
        }

        // 2) BBT 3-over-6 shift
        if let bbtDay = detectBBTShift(cycleLogs: cycleLogs, start: start) {
            return OvulationEstimate(dayInCycle: bbtDay, method: "bbt_shift", confidence: 0.8)
        }

        // 3) Peak egg-white / watery mucus
        if let mucusDay = cycleLogs
            .filter({ ($0.mucus?.fertilityScore ?? 0) >= 4 })
            .max(by: { ($0.mucus?.fertilityScore ?? 0) < ($1.mucus?.fertilityScore ?? 0) }),
           let day = CycleDayKey.daysBetween(start, mucusDay.dayKey) {
            return OvulationEstimate(dayInCycle: day + 1, method: "peak_mucus", confidence: 0.65)
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
        ovulationDay: Int?,
        fertileStart: Int?,
        fertileEnd: Int?,
        bleedingToday: Bool,
        hormonal: Bool
    ) -> MenstrualPhase {
        if bleedingToday { return .menstruation }
        guard let day = dayInCycle else { return .unknown }

        let periodEnd = max(3, Int(periodLength.rounded()))
        if day <= periodEnd { return .menstruation }

        if hormonal {
            // Hormonal contraception: phases are less meaningful — keep simple bleed vs non-bleed.
            return .follicular
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

    // MARK: Prediction

    private static func predictNextPeriod(
        lastStart: String?,
        lengths: [Int],
        median: Double,
        mad: Double,
        calibrationOffsetDays: Double = 0
    ) -> CyclePredictionRange? {
        guard let lastStart else { return nil }
        // Apply feedback-learned offset so predictions auto-correct toward actual starts.
        let med = Int((median + calibrationOffsetDays).rounded())
        let spread = max(1, Int(ceil(mad * 1.5)))
        // Use empirical percentiles when enough cycles
        var low = med - spread
        var high = med + spread
        if lengths.count >= 4 {
            let sorted = lengths.sorted()
            let cal = Int(calibrationOffsetDays.rounded())
            low = sorted[max(0, sorted.count / 10)] + cal
            high = sorted[min(sorted.count - 1, (sorted.count * 9) / 10)] + cal
        }
        guard let earliest = CycleDayKey.addDays(lastStart, low),
              let medianKey = CycleDayKey.addDays(lastStart, med),
              let latest = CycleDayKey.addDays(lastStart, high) else { return nil }
        return CyclePredictionRange(earliestDayKey: earliest, medianDayKey: medianKey, latestDayKey: latest)
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

    private static func computeConfidence(
        cyclesObserved: Int,
        mad: Double,
        hasLH: Bool,
        hasBBT: Bool,
        hasMucus: Bool,
        hormonal: Bool,
        logsCount: Int
    ) -> Double {
        var c = 0.15
        c += min(0.35, Double(cyclesObserved) * 0.06)
        if mad <= 1.5 { c += 0.15 }
        else if mad <= 3 { c += 0.08 }
        else if mad >= 6 { c -= 0.1 }
        if hasLH { c += 0.2 }
        else if hasBBT { c += 0.15 }
        else if hasMucus { c += 0.08 }
        if logsCount >= 40 { c += 0.08 }
        if hormonal { c = min(c, 0.55) } // suppress overconfidence on suppressed ovulation
        return max(0, min(0.95, c))
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
        hormonal: Bool
    ) -> [String] {
        var lines: [String] = []
        if let day = dayInCycle {
            lines.append("Day \(day) of an estimated \(Int(medianCycle.rounded()))-day cycle.")
        }
        if let ovu = ovulation {
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
