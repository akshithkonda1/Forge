import Foundation

/// Deterministic Test-Ready Health stream.
///
/// Same idea as SimRunner's 30-day persona: sleep stages, HRV, resting HR,
/// steps, calories, water, and a few sessions. On the iOS 27 simulator the
/// app writes this into HealthKit every launch, then reads it back through
/// the normal HealthKit path. Never sent to AWS. Never written on a
/// physical phone.
public struct FakeHealthWorkout: Sendable, Equatable {
    public var name: String
    public var type: ForgeWorkoutType
    public var durationMinutes: Int
    public var intensity: String
    public var volume: Int

    public init(
        name: String,
        type: ForgeWorkoutType,
        durationMinutes: Int,
        intensity: String,
        volume: Int
    ) {
        self.name = name
        self.type = type
        self.durationMinutes = durationMinutes
        self.intensity = intensity
        self.volume = volume
    }
}

public struct FakeHealthDay: Sendable, Equatable {
    public var dayStart: Date
    public var isoDate: String
    public var night: SleepNight
    public var sleepScore: Int
    public var hrvMs: Int
    public var restingHR: Int
    public var steps: Int
    public var activeCalories: Int
    public var hydrationMl: Double
    public var workout: FakeHealthWorkout?

    public init(
        dayStart: Date,
        isoDate: String,
        night: SleepNight,
        sleepScore: Int,
        hrvMs: Int,
        restingHR: Int,
        steps: Int,
        activeCalories: Int,
        hydrationMl: Double,
        workout: FakeHealthWorkout?
    ) {
        self.dayStart = dayStart
        self.isoDate = isoDate
        self.night = night
        self.sleepScore = sleepScore
        self.hrvMs = hrvMs
        self.restingHR = restingHR
        self.steps = steps
        self.activeCalories = activeCalories
        self.hydrationMl = hydrationMl
        self.workout = workout
    }
}

public struct FakeHealthPack: Sendable, Equatable {
    public static let dayCount = 30
    public static let defaultSeed = 0xF0A6E

    /// Newest night first — same order the iOS `sleepData` array uses.
    public var days: [FakeHealthDay]
    public var generatedAt: Date
    public var seed: Int

    public init(days: [FakeHealthDay], generatedAt: Date, seed: Int) {
        self.days = days
        self.generatedAt = generatedAt
        self.seed = seed
    }

    public var today: FakeHealthDay? { days.first }

    public var readinessInputs: ReadinessInputs {
        guard let today else { return ReadinessInputs() }
        let baselineHRV = days.prefix(7).map(\.hrvMs).reduce(0, +) / max(1, min(7, days.count))
        let baselineRHR = days.prefix(7).map(\.restingHR).reduce(0, +) / max(1, min(7, days.count))
        return ReadinessInputs(
            hrvMs: Double(today.hrvMs),
            hrvBaselineMs: Double(baselineHRV),
            restingHR: Double(today.restingHR),
            restingHRBaseline: Double(baselineRHR),
            sleepMinutes: today.night.totalMinutes,
            sleepNeedMinutes: 8 * 60,
            deepSleepMinutes: today.night.deepMinutes,
            remSleepMinutes: today.night.remMinutes,
            yesterdayStrain: today.workout == nil ? 0.25 : 0.55
        )
    }

    /// Simulator Test-Ready path: write the pack into HealthKit after the
    /// user connects Apple Health (first integration), then on every later
    /// authorized launch. Never before Connect. Never on a physical phone.
    public static func shouldSeedHealthKit(
        debugBuild: Bool,
        testReady: Bool,
        isSimulator: Bool,
        healthAuthorized: Bool
    ) -> Bool {
        debugBuild && testReady && isSimulator && healthAuthorized
    }

    /// In-memory fallback when HealthKit cannot be written (Device Hub on a
    /// real phone with an empty store). Real HealthKit samples always win.
    public static func shouldInstall(
        debugBuild: Bool,
        testReady: Bool,
        hasRealHealthSignal: Bool
    ) -> Bool {
        debugBuild && testReady && !hasRealHealthSignal
    }

    public static func generate(
        now: Date = Date(),
        calendar: Calendar = .current,
        days: Int = dayCount,
        seed: Int = defaultSeed
    ) -> FakeHealthPack {
        var rng = SplitMix64(seed: UInt64(truncatingIfNeeded: seed))
        let count = max(7, days)
        let todayStart = calendar.startOfDay(for: now)
        var built: [FakeHealthDay] = []
        built.reserveCapacity(count)

        for offset in 0..<count {
            let dayStart = calendar.date(byAdding: .day, value: -offset, to: todayStart) ?? todayStart
            built.append(makeDay(offset: offset, dayStart: dayStart, calendar: calendar, rng: &rng))
        }
        return FakeHealthPack(days: built, generatedAt: now, seed: seed)
    }

    // MARK: - Day synthesis

    private static func makeDay(
        offset: Int,
        dayStart: Date,
        calendar: Calendar,
        rng: inout SplitMix64
    ) -> FakeHealthDay {
        // A few deliberately short / late nights so ARIA has a debt story.
        let shortNight = offset == 3 || offset == 10
        let lateNight = offset == 6
        let hardSessionYesterday = offset == 1 || offset == 8

        let asleepMinutes: Int
        if shortNight {
            asleepMinutes = 5 * 60 + rng.int(20...50)
        } else if lateNight {
            asleepMinutes = 6 * 60 + rng.int(10...35)
        } else {
            asleepMinutes = 7 * 60 + rng.int(5...50)
        }

        var onsetHour = 23
        var onsetMinute = rng.int(0...40)
        if lateNight {
            onsetHour = 0
            onsetMinute = rng.int(10...35)
        } else if shortNight {
            onsetHour = 0
            onsetMinute = rng.int(5...25)
        }

        let onsetDay = (onsetHour >= 18)
            ? (calendar.date(byAdding: .day, value: -1, to: dayStart) ?? dayStart)
            : dayStart
        var onsetParts = calendar.dateComponents([.year, .month, .day], from: onsetDay)
        onsetParts.hour = onsetHour
        onsetParts.minute = onsetMinute
        let onset = calendar.date(from: onsetParts) ?? dayStart.addingTimeInterval(-8 * 3600)

        let night = SleepNight(segments: nightSegments(onset: onset, asleepMinutes: asleepMinutes, rng: &rng))
        let sleepScore = scoreNight(night)

        var hrv = 52 + rng.int(-6...8)
        var rhr = 58 + rng.int(-4...5)
        if shortNight || hardSessionYesterday {
            hrv -= rng.int(8...14)
            rhr += rng.int(3...7)
        }
        hrv = min(95, max(28, hrv))
        rhr = min(78, max(48, rhr))

        let workout = session(offset: offset)
        var steps = 7_400 + rng.int(-1_800...2_600)
        var calories = 380 + rng.int(-80...140)
        if let workout {
            steps += workout.type == .cardio || workout.type == .hiit ? 2_400 : 900
            calories += workout.durationMinutes * 6
        }
        if offset == 0 {
            // "Today so far" — not a finished day.
            steps = min(steps, 8_600)
        }

        let hydration = Double(1_180 + rng.int(0...900))
        return FakeHealthDay(
            dayStart: dayStart,
            isoDate: isoDate(dayStart, calendar: calendar),
            night: night,
            sleepScore: sleepScore,
            hrvMs: hrv,
            restingHR: rhr,
            steps: max(2_000, steps),
            activeCalories: max(120, calories),
            hydrationMl: hydration,
            workout: workout
        )
    }

    private static func session(offset: Int) -> FakeHealthWorkout? {
        // Mon / Wed / Fri strength, Saturday conditioning, Sunday mobility.
        // `offset` 0 is today; weekday is taken from the generated calendar day
        // via a stable 7-day rotation so tests do not depend on "what day is it".
        switch offset % 7 {
        case 0:
            // Today is still open — ARIA writes the session from this pack's sleep/HRV.
            return nil
        case 2:
            return FakeHealthWorkout(
                name: "Lower Body Strength",
                type: .strength,
                durationMinutes: 62,
                intensity: "high",
                volume: 22_400
            )
        case 4:
            return FakeHealthWorkout(
                name: "Push / Pull",
                type: .strength,
                durationMinutes: 50,
                intensity: "moderate",
                volume: 16_800
            )
        case 5:
            return FakeHealthWorkout(
                name: "Zone 2 + strides",
                type: .cardio,
                durationMinutes: 40,
                intensity: "moderate",
                volume: 0
            )
        case 6:
            return offset == 6 ? FakeHealthWorkout(
                name: "Mobility & Recovery",
                type: .mobility,
                durationMinutes: 25,
                intensity: "low",
                volume: 0
            ) : nil
        default:
            return nil
        }
    }

    private static func nightSegments(
        onset: Date,
        asleepMinutes: Int,
        rng: inout SplitMix64
    ) -> [SleepStageSegment] {
        var cursor = onset
        var remaining = Double(asleepMinutes)
        var segments: [SleepStageSegment] = []
        var cycle = 0
        while remaining > 12 {
            let core = min(remaining, Double(rng.int(38...52)))
            segments.append(segment(&cursor, minutes: core, .core))
            remaining -= core
            guard remaining > 8 else { break }

            let deep = min(remaining, Double(rng.int(14...24)))
            segments.append(segment(&cursor, minutes: deep, .deep))
            remaining -= deep
            guard remaining > 8 else { break }

            let rem = min(remaining, Double(rng.int(12...22)))
            segments.append(segment(&cursor, minutes: rem, .rem))
            remaining -= rem

            if cycle % 2 == 1, remaining > 20 {
                let wake = Double(rng.int(4...8))
                segments.append(segment(&cursor, minutes: wake, .awake))
            }
            cycle += 1
            if cycle > 8 { break }
        }
        if remaining > 4 {
            segments.append(segment(&cursor, minutes: remaining, .core))
        }
        return segments
    }

    private static func segment(
        _ cursor: inout Date,
        minutes: Double,
        _ stage: SleepStage
    ) -> SleepStageSegment {
        let start = cursor
        let end = start.addingTimeInterval(minutes * 60)
        cursor = end
        return SleepStageSegment(start: start, end: end, stage: stage)
    }

    private static func scoreNight(_ night: SleepNight) -> Int {
        let hours = night.totalMinutes / 60
        let duration = min(100, (hours / 8) * 100)
        let deep = min(100, (night.deepMinutes / 90) * 100)
        let rem = min(100, (night.remMinutes / 90) * 100)
        let awakePenalty = min(20, night.awakeMinutes * 0.4)
        return min(100, max(40, Int(((duration * 0.45) + (deep * 0.3) + (rem * 0.25) - awakePenalty).rounded())))
    }

    private static func isoDate(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

// MARK: - SplitMix64

private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func int(_ range: ClosedRange<Int>) -> Int {
        let span = UInt64(range.upperBound - range.lowerBound) + 1
        return range.lowerBound + Int(next() % span)
    }
}
