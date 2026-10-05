import Foundation

// ============================================================
// MARK: - User working model
// ============================================================

/// How this person tends to work — not a clinical profile.
///
/// Competing coaches score *today*. This reads habits, feel check-ins,
/// consistency, and load, then names a tendency ARIA can actually steer
/// with: overreaching, weekend drop-off, rebuilding, protecting, or
/// holding a rhythm. Lifestyle language only. Never a diagnosis.
public enum UserWorkingModel {

    public struct Input: Sendable {
        /// Consecutive qualifying habit days (HabitStreak).
        public var habitStreakDays: Int
        /// Today's check-off share, 0...1. Nil when no habits are tracked.
        public var todayHabitCompletion: Double?
        /// Weekly feel check-in, 0...10 (WeeklyMoodScale / ledger).
        public var weeklyMood0to10: Double?
        /// Acute:chronic workload ratio when history is long enough.
        public var acwr: Double?
        /// Recent night scores, oldest → newest, 0...100.
        public var sleepScores: [Int]
        /// Today's readiness, 0...100.
        public var readinessToday: Int?
        /// Days in the recent window that stacked heavy strain on thin recovery.
        public var highStrainLowRecoveryDays: Int
        /// Weekday vs weekend sleep-score average. Nil when history is short.
        public var weekdaySleepAvg: Double?
        public var weekendSleepAvg: Double?

        public init(
            habitStreakDays: Int = 0,
            todayHabitCompletion: Double? = nil,
            weeklyMood0to10: Double? = nil,
            acwr: Double? = nil,
            sleepScores: [Int] = [],
            readinessToday: Int? = nil,
            highStrainLowRecoveryDays: Int = 0,
            weekdaySleepAvg: Double? = nil,
            weekendSleepAvg: Double? = nil
        ) {
            self.habitStreakDays = max(0, habitStreakDays)
            self.todayHabitCompletion = todayHabitCompletion.map { max(0, min(1, $0)) }
            self.weeklyMood0to10 = weeklyMood0to10.map { max(0, min(10, $0)) }
            self.acwr = acwr
            self.sleepScores = sleepScores
            self.readinessToday = readinessToday
            self.highStrainLowRecoveryDays = max(0, highStrainLowRecoveryDays)
            self.weekdaySleepAvg = weekdaySleepAvg
            self.weekendSleepAvg = weekendSleepAvg
        }
    }

    public enum Tendency: String, Sendable {
        case overreacher
        case protector
        case weekendDrop = "weekend_drop"
        case rebuilding
        case steady
        case unknown
    }

    /// How ARIA should talk to *this* person. Not a treatment plan.
    public enum Stance: String, Sendable {
        case capHeroics = "cap_heroics"
        case holdTheLine = "hold_the_line"
        case rebuildTrust = "rebuild_trust"
        case keepRhythm = "keep_rhythm"
    }

    public enum PredictedFeel: String, Sendable {
        case available
        case mixed
        case flat
    }

    public enum Confidence: String, Sendable {
        case low, medium, high
    }

    public struct Driver: Sendable, Identifiable {
        public var id: String { title }
        public var title: String
        public var detail: String

        public init(title: String, detail: String) {
            self.title = title
            self.detail = detail
        }
    }

    public struct Snapshot: Sendable {
        public var tendency: Tendency
        public var stance: Stance
        public var predictedFeel: PredictedFeel
        public var confidence: Confidence
        public var drivers: [Driver]
        public var steeringLine: String

        public var ariaTags: [String] {
            [
                "working:\(tendency.rawValue):\(stance.rawValue)",
                "working:feel:\(predictedFeel.rawValue)",
                "working:confidence:\(confidence.rawValue)",
            ]
        }
    }

    public static func snapshot(
        _ input: Input,
        tomorrowPosture: ReadinessForecastEngine.Posture? = nil
    ) -> Snapshot {
        var drivers: [Driver] = []
        var known = 0
        var total = 6

        if input.habitStreakDays > 0 || input.todayHabitCompletion != nil {
            known += 1
            if input.habitStreakDays >= 4 {
                drivers.append(Driver(
                    title: "Habit rhythm",
                    detail: "\(input.habitStreakDays)-day streak holding"
                ))
            } else if input.habitStreakDays <= 1 {
                drivers.append(Driver(
                    title: "Habit rhythm",
                    detail: "Streak is thin — showing up small is the win"
                ))
            }
        }

        if let mood = input.weeklyMood0to10 {
            known += 1
            if mood <= 4 {
                drivers.append(Driver(
                    title: "Week has felt heavy",
                    detail: "Feel check-in \(Int(mood.rounded()))/10"
                ))
            } else if mood >= 7 {
                drivers.append(Driver(
                    title: "Week has felt solid",
                    detail: "Feel check-in \(Int(mood.rounded()))/10"
                ))
            }
        }

        if let acwr = input.acwr {
            known += 1
            if acwr >= 1.5 {
                drivers.append(Driver(
                    title: "Load spiking",
                    detail: String(format: "This week is %.1fx your usual", acwr)
                ))
            } else if acwr < 0.8 {
                drivers.append(Driver(
                    title: "Load dip",
                    detail: String(format: "This week is %.1fx your usual", acwr)
                ))
            }
        }

        if !input.sleepScores.isEmpty { known += 1 }
        if input.readinessToday != nil { known += 1 }

        let weekendDrop = isWeekendDrop(input)
        if input.weekdaySleepAvg != nil || input.weekendSleepAvg != nil {
            known += 1
            if weekendDrop {
                drivers.append(Driver(
                    title: "Weekend drop",
                    detail: "Weekdays hold; weekends run thinner"
                ))
            }
        } else {
            total -= 1
        }

        if input.highStrainLowRecoveryDays >= 3 {
            drivers.append(Driver(
                title: "Pushing through",
                detail: "\(input.highStrainLowRecoveryDays) heavy days on thin recovery"
            ))
        }

        let tendency = classify(input, weekendDrop: weekendDrop)
        let stance = stance(for: tendency)
        let feel = predictedFeel(input, posture: tomorrowPosture, tendency: tendency)
        let coverage = Double(known) / Double(max(1, total))
        let confidence: Confidence
        switch coverage {
        case 0.8...: confidence = .high
        case 0.45..<0.8: confidence = .medium
        default: confidence = .low
        }

        return Snapshot(
            tendency: tendency,
            stance: stance,
            predictedFeel: feel,
            confidence: confidence,
            drivers: drivers,
            steeringLine: steeringLine(tendency: tendency, feel: feel)
        )
    }

    public static func parseTag(_ token: String) -> (Tendency, Stance)? {
        let parts = token.split(separator: ":").map(String.init)
        guard parts.count >= 3, parts[0] == "working" else { return nil }
        guard let tendency = Tendency(rawValue: parts[1]),
              let stance = Stance(rawValue: parts[2]) else { return nil }
        return (tendency, stance)
    }

    // MARK: - Internals

    private static func isWeekendDrop(_ input: Input) -> Bool {
        guard let week = input.weekdaySleepAvg, let end = input.weekendSleepAvg else {
            return false
        }
        return end <= week - 12
    }

    private static func classify(_ input: Input, weekendDrop: Bool) -> Tendency {
        if input.highStrainLowRecoveryDays >= 3 || (input.acwr ?? 0) >= 1.5 {
            return .overreacher
        }
        if weekendDrop {
            return .weekendDrop
        }
        if input.habitStreakDays <= 1,
           (input.todayHabitCompletion ?? 1) < 0.4 || (input.weeklyMood0to10 ?? 10) <= 4 {
            return .rebuilding
        }
        if input.habitStreakDays >= 5, (input.acwr ?? 1.0) < 0.8 {
            return .protector
        }
        if input.habitStreakDays >= 4,
           let acwr = input.acwr, (0.8..<1.4).contains(acwr),
           (input.weeklyMood0to10 ?? 6) >= 5 {
            return .steady
        }
        if input.habitStreakDays >= 4, input.acwr == nil, (input.weeklyMood0to10 ?? 6) >= 5 {
            return .steady
        }
        return .unknown
    }

    private static func stance(for tendency: Tendency) -> Stance {
        switch tendency {
        case .overreacher: return .capHeroics
        case .weekendDrop: return .holdTheLine
        case .rebuilding: return .rebuildTrust
        case .protector, .steady, .unknown: return .keepRhythm
        }
    }

    private static func predictedFeel(
        _ input: Input,
        posture: ReadinessForecastEngine.Posture?,
        tendency: Tendency
    ) -> PredictedFeel {
        if posture == .rest || posture == .protect { return .flat }
        if (input.weeklyMood0to10 ?? 6) <= 4 { return .flat }
        if tendency == .overreacher, (input.acwr ?? 0) >= 1.3 { return .flat }
        if posture == .push, (input.weeklyMood0to10 ?? 6) >= 6 { return .available }
        if (input.readinessToday ?? 70) >= 80, (input.weeklyMood0to10 ?? 6) >= 6 {
            return .available
        }
        return .mixed
    }

    private static func steeringLine(tendency: Tendency, feel: PredictedFeel) -> String {
        let feelBit: String
        switch feel {
        case .available: feelBit = "Tomorrow is likely to feel available."
        case .mixed: feelBit = "Tomorrow is likely a mixed-energy day."
        case .flat: feelBit = "Tomorrow is likely to feel flatter — keep the win small."
        }
        let tendencyBit: String
        switch tendency {
        case .overreacher:
            tendencyBit = "This person tends to push through a heavy week — cap heroics."
        case .weekendDrop:
            tendencyBit = "Weekdays hold and weekends slip — one tiny weekend anchor beats a Monday restart."
        case .rebuilding:
            tendencyBit = "They're finding the rhythm again — showing up small is the win."
        case .protector:
            tendencyBit = "They already protect recovery — don't talk them out of the easy session."
        case .steady:
            tendencyBit = "Their rhythm is holding — don't over-coach it."
        case .unknown:
            tendencyBit = "Still learning how this person works — stay specific and small."
        }
        return "\(tendencyBit) \(feelBit)"
    }
}

/// Combines tomorrow's forecast with how this person works so Home, Watch,
/// and ARIA call one function.
public enum PredictiveCoach {

    public struct Picture: Sendable {
        public var forecast: ReadinessForecastEngine.Forecast
        public var working: UserWorkingModel.Snapshot
        public var hobby: HobbyPathEngine.Snapshot
        public var budgets: TomorrowBudgets.Snapshot
        public var keepLight: Bool
        public var ariaTags: [String]
        public var steeringLine: String
    }

    public static func picture(
        forecastInput: ReadinessForecastEngine.Input,
        workingInput: UserWorkingModel.Input,
        socialEnergy0to10: Double? = nil,
        currentHobbies: [LivingHobby] = [],
        wakeHour: Double? = nil
    ) -> Picture {
        let forecast = ReadinessForecastEngine.forecast(forecastInput)
        let working = UserWorkingModel.snapshot(workingInput, tomorrowPosture: forecast.posture)
        let hobby = HobbyPathEngine.snapshot(
            socialEnergy0to10: socialEnergy0to10,
            currentHobbies: currentHobbies,
            working: working,
            tomorrowPosture: forecast.posture,
            wakeHour: wakeHour
        )
        let budgets = TomorrowBudgets.snapshot(
            posture: forecast.posture,
            stance: working.stance,
            peopleEnergy: hobby.peopleEnergy
        )
        return Picture(
            forecast: forecast,
            working: working,
            hobby: hobby,
            budgets: budgets,
            keepLight: forecast.posture.keepLight || working.stance == .capHeroics,
            ariaTags: forecast.ariaTags + working.ariaTags + hobby.ariaTags + budgets.ariaTags,
            steeringLine: "\(working.steeringLine) \(forecast.steeringLine) \(hobby.coachingLine) \(hobby.windowLine) \(budgets.coachingLine)"
        )
    }
}
