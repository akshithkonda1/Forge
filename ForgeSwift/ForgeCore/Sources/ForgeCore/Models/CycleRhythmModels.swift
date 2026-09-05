import Foundation

// MARK: - Discretion

/// What lock screens, widgets, and Home may say about the owner's cycle.
public enum CycleDiscretionMode: String, Codable, CaseIterable, Sendable, Identifiable, Hashable {
    /// Hide the surface. Padlock / em dash. No phase, no day, no Live Activity.
    case stealth
    /// Lock-safe kindness only. Never names a period or fertile window.
    case kind
    /// Full phase + day on surfaces the owner chose to install.
    case clinical

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .stealth: return "Stealth"
        case .kind: return "Kind"
        case .clinical: return "Clinical"
        }
    }

    public var detail: String {
        switch self {
        case .stealth:
            return "Home, Watch, and lock screen stay silent. Open Cycle Health to see your log."
        case .kind:
            return "Surfaces say “take it easy” — never period, fertile, or a day count."
        case .clinical:
            return "Phase and day on widgets you install. Still never sent to Forge servers."
        }
    }

    public var lockSafeLine: String {
        switch self {
        case .stealth: return ""
        case .kind: return "Take it easy"
        case .clinical: return ""
        }
    }

    public var lockScreenSafe: Bool { self != .clinical }

    public func notificationTitle(clinical: String) -> String {
        switch self {
        case .stealth: return "Forge"
        case .kind: return "A Forge reminder"
        case .clinical: return clinical
        }
    }

    public func notificationBody(clinical: String, kind: String) -> String {
        switch self {
        case .stealth: return "Open Forge when you have a moment."
        case .kind: return kind
        case .clinical: return clinical
        }
    }
}

public enum CycleDiscretionPolicy {
    public struct WatchFields: Equatable {
        public var phase: String?
        public var dayInCycle: Int?
        public var daysUntilNext: Int?
        public var lockLine: String?

        public init(phase: String?, dayInCycle: Int?, daysUntilNext: Int?, lockLine: String?) {
            self.phase = phase
            self.dayInCycle = dayInCycle
            self.daysUntilNext = daysUntilNext
            self.lockLine = lockLine
        }
    }

    public static func watchFields(
        mode: CycleDiscretionMode,
        phaseRaw: String?,
        dayInCycle: Int?,
        daysUntilNext: Int?
    ) -> WatchFields {
        switch mode {
        case .stealth:
            return WatchFields(phase: nil, dayInCycle: nil, daysUntilNext: nil, lockLine: nil)
        case .kind:
            return WatchFields(phase: nil, dayInCycle: nil, daysUntilNext: nil, lockLine: CycleDiscretionMode.kind.lockSafeLine)
        case .clinical:
            return WatchFields(phase: phaseRaw, dayInCycle: dayInCycle, daysUntilNext: daysUntilNext, lockLine: nil)
        }
    }
}

// MARK: - Lifestyle training goals (ARIA)

/// What the owner asked ARIA to design training around. Distinct from
/// `CycleGoal` (TTC / family planning) — this is the running/lifting life.
public enum CycleLifestyleGoal: String, Codable, CaseIterable, Sendable, Identifiable, Hashable {
    case none
    case running
    case endurance
    case strength
    case mixed

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .none: return "No training goal"
        case .running: return "Running"
        case .endurance: return "Endurance"
        case .strength: return "Strength"
        case .mixed: return "Mixed training"
        }
    }

    public var icon: String {
        switch self {
        case .none: return "minus.circle"
        case .running: return "figure.run"
        case .endurance: return "bicycle"
        case .strength: return "dumbbell.fill"
        case .mixed: return "figure.mixed.cardio"
        }
    }
}

/// How sessions should change while bleeding. The owner sets this once;
/// ARIA translates it into today's miles/sets. Default is easy — the
/// “I love running, I hate running on my period” case.
public enum CyclePeriodTrainingStyle: String, Codable, CaseIterable, Sendable, Identifiable, Hashable {
    case pause, easy, reduce, maintain

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .pause: return "Skip workouts"
        case .easy: return "Easy only"
        case .reduce: return "Shorter / lighter"
        case .maintain: return "Keep my usual"
        }
    }

    public var runningCopy: String {
        switch self {
        case .pause: return "No run days while bleeding — walk or rest."
        case .easy: return "Easy miles only. Skip the long run and anything that feels like a test."
        case .reduce: return "Cut volume roughly in half. Keep the habit, drop the heroics."
        case .maintain: return "Usual load if it feels available — stop if pain or dizziness shows up."
        }
    }
}

public struct CycleTrainingPrescription: Equatable, Sendable {
    public var goal: String
    public var phase: String
    public var headline: String
    public var volumeLine: String
    public var intensityLine: String
    public var returnLine: String
    public var disclaimer: String

    public init(
        goal: String,
        phase: String,
        headline: String,
        volumeLine: String,
        intensityLine: String,
        returnLine: String,
        disclaimer: String = CycleGoalCoach.disclaimer
    ) {
        self.goal = goal
        self.phase = phase
        self.headline = headline
        self.volumeLine = volumeLine
        self.intensityLine = intensityLine
        self.returnLine = returnLine
        self.disclaimer = disclaimer
    }
}

/// On-device translation of a lifestyle goal + current phase + learned prefs
/// into what to actually do. Not a training plan from a coach's spreadsheet —
/// a phase-aware volume cap the owner can take to a run.
public enum CycleGoalCoach {

    public static let disclaimer =
        "Lifestyle coaching from your logs and preferences — not medical advice, not a race plan, not contraception."

    public static func prescribe(
        goal: CycleLifestyleGoal,
        phaseRaw: String,
        isBleeding: Bool,
        periodFinishedRecently: Bool,
        preferLighterTraining: Bool,
        recoveryBias: Double,
        highAccuracy: Bool,
        periodStyle: CyclePeriodTrainingStyle = .easy
    ) -> CycleTrainingPrescription {
        let light = preferLighterTraining || recoveryBias >= 0.55 || isBleeding
        let tight = highAccuracy && light

        if goal == .none {
            return CycleTrainingPrescription(
                goal: goal.rawValue,
                phase: phaseRaw,
                headline: "No training goal set — ARIA will ask.",
                volumeLine: "Tell ARIA what you want to be good at (running, lifting, mixed) and it will shape volume to this phase.",
                intensityLine: isBleeding
                    ? "If you train today, keep it optional and easy."
                    : "Use readiness as the main dial until a goal is set.",
                returnLine: periodFinishedRecently
                    ? "Bleed is over — ease back in rather than jumping to a peak session."
                    : "Set a running or strength goal when you are ready."
            )
        }

        if isBleeding || phaseRaw == "menstruation" {
            return bleedingPrescription(
                goal: goal,
                tight: tight,
                recoveryBias: recoveryBias,
                style: periodStyle
            )
        }
        if periodFinishedRecently || phaseRaw == "follicular" {
            return rebuildPrescription(goal: goal, justFinished: periodFinishedRecently)
        }
        if phaseRaw == "luteal" {
            return lutealPrescription(goal: goal, light: light)
        }
        return peakPrescription(goal: goal)
    }

    private static func bleedingPrescription(
        goal: CycleLifestyleGoal,
        tight: Bool,
        recoveryBias: Double,
        style: CyclePeriodTrainingStyle
    ) -> CycleTrainingPrescription {
        let miles = tight || recoveryBias >= 0.7 ? "2–4 easy miles max" : "3–5 easy miles, walk breaks welcome"
        let runningVolume: String
        switch style {
        case .pause:
            runningVolume = "No run today. Walk, stretch, or rest. Your usual miles wait until the bleed eases."
        case .easy:
            runningVolume = "Today: \(miles). If you hate running on your period, a walk counts. Do not force yesterday's long-run pace."
        case .reduce:
            runningVolume = "Cut the run roughly in half versus your usual. Flat route, conversational pace."
        case .maintain:
            runningVolume = "You can try your usual run if it feels available. Heat, iron, and an easy abort still matter."
        }
        switch goal {
        case .running, .endurance:
            return CycleTrainingPrescription(
                goal: goal.rawValue,
                phase: "menstruation",
                headline: "On your period: \(style.runningCopy)",
                volumeLine: runningVolume,
                intensityLine: style == .pause
                    ? "Rest is a valid session. No make-up miles."
                    : "Easy only. No intervals, no race pace, no “make up” miles.",
                returnLine: "When the bleed ends, rebuild toward your usual mileage over several days — not the next morning."
            )
        case .strength:
            return CycleTrainingPrescription(
                goal: goal.rawValue,
                phase: "menstruation",
                headline: "On your period: \(style.runningCopy)",
                volumeLine: style == .pause
                    ? "Take the session off. Load waits until the bleed eases."
                    : "Cut volume ~30–50%. Skip a set you do not want.",
                intensityLine: "Leave heavy singles. Warm up longer. Heat helps.",
                returnLine: "After the bleed, progressive overload can come back. Do not jump to a max in the first session."
            )
        case .mixed:
            return CycleTrainingPrescription(
                goal: goal.rawValue,
                phase: "menstruation",
                headline: "On your period: \(style.runningCopy)",
                volumeLine: style == .pause
                    ? "Pick rest, or an easy walk. Do not stack cardio and lifting."
                    : "Cap cardio at an easy 20–40 minutes. Strength stays light.",
                intensityLine: "No stacked hard days. One quality stimulus is enough.",
                returnLine: "When it ends, return to your normal mix in a balanced way — not both a long run and a heavy lift the first day back."
            )
        case .none:
            return CycleTrainingPrescription(
                goal: goal.rawValue,
                phase: "menstruation",
                headline: "On your period: rest is a valid session.",
                volumeLine: "Optional easy movement only.",
                intensityLine: "No intensity push.",
                returnLine: "Resume your usual plan after the bleed, gradually."
            )
        }
    }

    private static func rebuildPrescription(goal: CycleLifestyleGoal, justFinished: Bool) -> CycleTrainingPrescription {
        let ramp = justFinished
            ? "Bleed just finished. Add volume in steps over 3–5 days."
            : "Follicular phase is usually a strong window — build, don't dump a week of missed work into one day."
        switch goal {
        case .running, .endurance:
            return CycleTrainingPrescription(
                goal: goal.rawValue,
                phase: justFinished ? "postPeriod" : "follicular",
                headline: justFinished ? "Period finished — rebuild the run." : "Good window to add miles.",
                volumeLine: ramp + " If your usual long run is 8 miles, start at 4–6, then back to normal.",
                intensityLine: "Strides and easy pace first. Save the workout for once energy is actually back.",
                returnLine: "Your normal balanced mileage is the destination, not a punishment for resting."
            )
        case .strength:
            return CycleTrainingPrescription(
                goal: goal.rawValue,
                phase: justFinished ? "postPeriod" : "follicular",
                headline: justFinished ? "Period finished — load can climb." : "Strong window for progressive overload.",
                volumeLine: ramp,
                intensityLine: "Technique first session back, then working sets.",
                returnLine: "Normal programming resumes once you feel it — ask your body, not the calendar alone."
            )
        default:
            return CycleTrainingPrescription(
                goal: goal.rawValue,
                phase: justFinished ? "postPeriod" : "follicular",
                headline: justFinished ? "Period finished — ease back to your mix." : "Energy is usually climbing.",
                volumeLine: ramp,
                intensityLine: "One quality session, not two stacked.",
                returnLine: "Return to your normal balanced week."
            )
        }
    }

    private static func lutealPrescription(goal: CycleLifestyleGoal, light: Bool) -> CycleTrainingPrescription {
        let cap = light ? "Trim volume 10–20% and drop a hard session if RPE is inflated." : "Hold volume; watch heat and sleep."
        return CycleTrainingPrescription(
            goal: goal.rawValue,
            phase: "luteal",
            headline: "Luteal: same sport, slightly kinder math.",
            volumeLine: cap,
            intensityLine: goal == .running || goal == .endurance
                ? "Keep quality shorter. Humidity and heat cost more here."
                : "Quality over ego. Extra rest between sets is allowed.",
            returnLine: "Next period will ask for a smaller day again — that swing is the plan, not a failure."
        )
    }

    private static func peakPrescription(goal: CycleLifestyleGoal) -> CycleTrainingPrescription {
        CycleTrainingPrescription(
            goal: goal.rawValue,
            phase: "peak",
            headline: "Higher-energy window — use it if you feel it.",
            volumeLine: goal == .running || goal == .endurance
                ? "Longer run or a workout is on the table if sleep was decent."
                : "A stronger session is available. Warm up thoroughly (joints can feel looser).",
            intensityLine: "Still not a license to ignore pain. Form over load.",
            returnLine: "This is not ovulation coaching for anyone else — it is your training dial."
        )
    }
}

// MARK: - 12-month clinician archive

/// One calendar month of *tracking evidence* — counts and medians, never notes,
/// never fertile windows, never sexual activity. Built to hand to a clinician.
public struct CycleMonthlyDigest: Codable, Equatable, Sendable, Identifiable {
    public var monthKey: String
    public var daysLogged: Int
    public var bleedingDays: Int
    public var cycleStarts: Int
    public var medianCycleDays: Double?
    public var medianPeriodDays: Double?
    public var cycleLengthMin: Int?
    public var cycleLengthMax: Int?
    public var averagePain: Double?
    public var painDays: Int
    public var symptomCounts: [String: Int]
    public var predictionMAE: Double?
    public var predictionSamples: Int
    public var highAccuracyMode: Bool
    public var lifestyleGoal: String?

    public var id: String { monthKey }

    public init(
        monthKey: String,
        daysLogged: Int,
        bleedingDays: Int,
        cycleStarts: Int,
        medianCycleDays: Double? = nil,
        medianPeriodDays: Double? = nil,
        cycleLengthMin: Int? = nil,
        cycleLengthMax: Int? = nil,
        averagePain: Double? = nil,
        painDays: Int = 0,
        symptomCounts: [String: Int] = [:],
        predictionMAE: Double? = nil,
        predictionSamples: Int = 0,
        highAccuracyMode: Bool = false,
        lifestyleGoal: String? = nil
    ) {
        self.monthKey = monthKey
        self.daysLogged = daysLogged
        self.bleedingDays = bleedingDays
        self.cycleStarts = cycleStarts
        self.medianCycleDays = medianCycleDays
        self.medianPeriodDays = medianPeriodDays
        self.cycleLengthMin = cycleLengthMin
        self.cycleLengthMax = cycleLengthMax
        self.averagePain = averagePain
        self.painDays = painDays
        self.symptomCounts = symptomCounts
        self.predictionMAE = predictionMAE
        self.predictionSamples = predictionSamples
        self.highAccuracyMode = highAccuracyMode
        self.lifestyleGoal = lifestyleGoal
    }
}

public enum CycleRhythmReport {

    public static let forbiddenClinicianTerms = [
        "fertile", "ovulat", "conceive", "sexual", "bbt", "mucus", "lh surge",
    ]

    /// Plain-text packet the owner can share with a gynecologist. Generated
    /// on-device. Does not include fertile timing or private notes.
    public static func clinicianText(
        months: [CycleMonthlyDigest],
        generatedDayKey: String,
        typicalCycle: Double?,
        typicalPeriod: Double?,
        mae: Double?,
        maeSamples: Int
    ) -> String {
        let sorted = months.sorted { $0.monthKey < $1.monthKey }
        let daysLogged = sorted.reduce(0) { $0 + $1.daysLogged }
        let bleeding = sorted.reduce(0) { $0 + $1.bleedingDays }
        let starts = sorted.reduce(0) { $0 + $1.cycleStarts }
        let rangeMins = sorted.compactMap(\.cycleLengthMin)
        let rangeMaxs = sorted.compactMap(\.cycleLengthMax)
        let painVals = sorted.compactMap(\.averagePain)
        let avgPain = painVals.isEmpty ? nil : painVals.reduce(0, +) / Double(painVals.count)

        var symptomTotals: [String: Int] = [:]
        for month in sorted {
            for (k, v) in month.symptomCounts {
                symptomTotals[k, default: 0] += v
            }
        }
        let topSymptoms = symptomTotals.sorted { $0.value > $1.value }.prefix(8)

        var lines: [String] = [
            "FORGE CYCLE VAULT — 12-MONTH TRACKING SUMMARY",
            "Generated on this iPhone · \(generatedDayKey)",
            "Lifestyle tracking evidence — not a diagnosis, not birth control.",
            "Share only with a clinician you trust. Forge does not hold a copy.",
            "",
            "OVERVIEW",
            "Months included: \(sorted.count)",
            "Days logged: \(daysLogged)",
            "Bleeding days: \(bleeding)",
            "Period starts recorded: \(starts)",
        ]
        if let typicalCycle {
            lines.append("Typical cycle length: \(formatDays(typicalCycle))")
        }
        if let lo = rangeMins.min(), let hi = rangeMaxs.max() {
            lines.append("Cycle length range (logged): \(lo)–\(hi) days")
        }
        if let typicalPeriod {
            lines.append("Typical bleed length: \(formatDays(typicalPeriod))")
        }
        if let avgPain {
            lines.append(String(format: "Average pain when logged: %.1f / 10", avgPain))
        }
        if let mae, maeSamples > 0 {
            lines.append(String(format: "Period-start prediction error (MAE): %.1f days over %d confirms", mae, maeSamples))
        }
        if !topSymptoms.isEmpty {
            lines.append("")
            lines.append("MOST-LOGGED SYMPTOMS (counts, no notes)")
            for (name, count) in topSymptoms {
                lines.append("- \(name): \(count)")
            }
        }
        lines.append("")
        lines.append("MONTH BY MONTH")
        if sorted.isEmpty {
            lines.append("No monthly archives yet. Keep logging — a month seals into the vault automatically.")
        } else {
            for m in sorted {
                var row = "\(m.monthKey)  logged \(m.daysLogged)d  bleed \(m.bleedingDays)d  starts \(m.cycleStarts)"
                if let p = m.averagePain {
                    row += String(format: "  pain %.1f", p)
                }
                if let cyc = m.medianCycleDays {
                    row += String(format: "  cycle ~%.0f", cyc)
                }
                lines.append(row)
            }
        }
        lines.append("")
        lines.append("NOT IN THIS REPORT")
        lines.append("Private notes, supporter names, and conception-timing fields are withheld. This pack is bleeding days, cycle length, pain, and symptom counts only.")
        lines.append(CycleGoalCoach.disclaimer)
        return lines.joined(separator: "\n")
    }

    private static func formatDays(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.05 {
            return "\(Int(value.rounded())) days"
        }
        return String(format: "%.1f days", value)
    }
}
