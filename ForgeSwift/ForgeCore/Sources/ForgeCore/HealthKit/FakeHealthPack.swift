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

/// Somewhere the person was, and for how long.
///
/// Coordinates are synthetic and jittered around a single arbitrary anchor —
/// they exist so map surfaces and "where do you usually eat" questions have
/// something shaped like real history to read, not so the location is
/// meaningful. Nothing here describes a real place or a real person.
public struct FakeLifestyleMarker: Sendable, Equatable {
    public enum Kind: String, Sendable, CaseIterable {
        case home, work, gym, restaurant, cafe, bar, park, market, travel
    }

    public var kind: Kind
    public var name: String
    public var arrival: Date
    public var minutes: Int
    public var latitude: Double
    public var longitude: Double

    public init(
        kind: Kind,
        name: String,
        arrival: Date,
        minutes: Int,
        latitude: Double,
        longitude: Double
    ) {
        self.kind = kind
        self.name = name
        self.arrival = arrival
        self.minutes = minutes
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// An evening that had something in it.
///
/// These are not decoration. A social event is generated *before* the night it
/// precedes and then drives that night's onset, duration and next-morning HRV,
/// so the biometrics and the calendar tell the same story. A late dinner with
/// four drinks that left sleep untouched would be worse than having no social
/// data at all: ARIA would learn to say things the numbers contradict.
public struct FakeSocialEvent: Sendable, Equatable {
    public enum Kind: String, Sendable, CaseIterable {
        case dinnerOut, drinks, party, familyTime, workEvent, dateNight, travelDay
    }

    public var kind: Kind
    public var title: String
    public var start: Date
    public var minutes: Int
    public var drinks: Int
    /// Ran past midnight. The single biggest driver of the night that follows.
    public var ranLate: Bool

    public init(
        kind: Kind,
        title: String,
        start: Date,
        minutes: Int,
        drinks: Int,
        ranLate: Bool
    ) {
        self.kind = kind
        self.title = title
        self.start = start
        self.minutes = minutes
        self.drinks = drinks
        self.ranLate = ranLate
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
    /// Where the day was spent, in order.
    public var markers: [FakeLifestyleMarker]
    /// What was on the evening that precedes this day's night. Usually empty.
    public var social: [FakeSocialEvent]

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
        workout: FakeHealthWorkout?,
        markers: [FakeLifestyleMarker] = [],
        social: [FakeSocialEvent] = []
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
        self.markers = markers
        self.social = social
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
        let plan = DayPlan(count: count, rng: &rng)
        var built: [FakeHealthDay] = []
        built.reserveCapacity(count)

        for offset in 0..<count {
            let dayStart = calendar.date(byAdding: .day, value: -offset, to: todayStart) ?? todayStart
            built.append(
                makeDay(offset: offset, dayStart: dayStart, calendar: calendar, plan: plan, rng: &rng)
            )
        }
        return FakeHealthPack(days: built, generatedAt: now, seed: seed)
    }

    // MARK: - Shape of the month

    /// Which days are rough, which evenings have something in them, and where
    /// the training week starts.
    ///
    /// This exists because the shape used to be hardcoded to the offset —
    /// `offset == 3 || offset == 10` was always the short nights, `offset % 7`
    /// was always the training week. The seed only ever jittered values *inside*
    /// a fixed story, so every run told the same month twice removed: same bad
    /// Tuesday, same rest day, same debt arc. Someone testing for an afternoon
    /// stops reading it and starts recognising it.
    ///
    /// The guarantees the tests depend on are structural here, not probabilistic
    /// — picked by shuffling a candidate list and taking a fixed count, rather
    /// than rolling per day and hoping. A per-day roll would satisfy
    /// `testStreamHasShortNightsAndWorkouts` on almost every seed and fail on a
    /// few, and since the app now re-seeds per session, "almost every" is a bug
    /// that ships and never reproduces.
    struct DayPlan {
        /// Never includes 0: today has to stay citable (`> 5h`, deep and REM
        /// both non-zero) for the pack to be worth anything on first launch.
        var shortNights: Set<Int> = []
        var lateNights: Set<Int> = []
        /// Offset into the 7-day training rotation, so the week does not always
        /// begin on the same day of the pack.
        var trainingPhase: Int = 0

        init(count: Int, rng: inout SplitMix64) {
            var candidates = Array(1..<max(2, count))
            // Fisher-Yates with the same rng, so the pick stays seed-determined.
            if candidates.count > 1 {
                for i in stride(from: candidates.count - 1, to: 0, by: -1) {
                    let j = rng.int(0...i)
                    candidates.swapAt(i, j)
                }
            }
            let shortCount = min(candidates.count, 3 + rng.int(0...2))
            shortNights = Set(candidates.prefix(shortCount))

            let remaining = candidates.dropFirst(shortCount)
            let lateCount = min(remaining.count, 2 + rng.int(0...2))
            lateNights = Set(remaining.prefix(lateCount))

            trainingPhase = rng.int(0...6)
        }
    }

    // MARK: - Day synthesis

    private static func makeDay(
        offset: Int,
        dayStart: Date,
        calendar: Calendar,
        plan: DayPlan,
        rng: inout SplitMix64
    ) -> FakeHealthDay {
        let weekday = calendar.component(.weekday, from: dayStart)   // 1 = Sunday
        let isWeekend = weekday == 1 || weekday == 7
        let workout = session(offset: offset, phase: plan.trainingPhase)

        // The evening that precedes this day's night. Generated first, because
        // everything below reads from it.
        let social = socialEvent(
            offset: offset,
            dayStart: dayStart,
            calendar: calendar,
            isWeekend: isWeekend,
            plannedLate: plan.lateNights.contains(offset),
            rng: &rng
        )

        let shortNight = plan.shortNights.contains(offset)
        let lateNight = plan.lateNights.contains(offset) || (social?.ranLate ?? false)
        let hardSessionYesterday = workout?.intensity == "high"

        var asleepMinutes: Int
        if shortNight {
            asleepMinutes = 5 * 60 + rng.int(20...50)
        } else if lateNight {
            asleepMinutes = 6 * 60 + rng.int(10...35)
        } else {
            asleepMinutes = 7 * 60 + rng.int(5...50)
        }
        // Drinks fragment sleep more reliably than they shorten it, but a big
        // night does both.
        if let social, social.drinks >= 3 {
            asleepMinutes -= rng.int(15...40)
        }
        // Today must stay citable no matter what the evening did.
        if offset == 0 { asleepMinutes = max(asleepMinutes, 5 * 60 + 25) }
        asleepMinutes = max(4 * 60 + 40, asleepMinutes)

        var onsetHour = 23
        var onsetMinute = rng.int(0...40)
        if lateNight {
            onsetHour = 0
            onsetMinute = rng.int(10...35)
        } else if shortNight {
            onsetHour = 0
            onsetMinute = rng.int(5...25)
        } else if isWeekend {
            onsetMinute = rng.int(20...55)
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
        // Alcohol is the clearest single-night signal in real HRV data, so it is
        // the clearest thing for ARIA to have an opinion about here.
        if let social {
            hrv -= social.drinks * rng.int(2...4)
            rhr += social.drinks >= 2 ? rng.int(2...5) : 0
            if social.ranLate { rhr += rng.int(1...3) }
        }
        hrv = min(95, max(28, hrv))
        rhr = min(78, max(48, rhr))

        var steps = 7_400 + rng.int(-1_800...2_600)
        var calories = 380 + rng.int(-80...140)
        if let workout {
            steps += workout.type == .cardio || workout.type == .hiit ? 2_400 : 900
            calories += workout.durationMinutes * 6
        }
        if isWeekend { steps += rng.int(-1_500...900) }
        if social?.kind == .travelDay { steps += rng.int(1_200...3_400) }
        if offset == 0 {
            // "Today so far" — not a finished day.
            steps = min(steps, 8_600)
        }

        var hydration = Double(1_180 + rng.int(0...900))
        if let social, social.drinks >= 2 { hydration -= Double(rng.int(80...260)) }

        let markers = dayMarkers(
            offset: offset,
            dayStart: dayStart,
            calendar: calendar,
            isWeekend: isWeekend,
            workout: workout,
            social: social,
            rng: &rng
        )

        return FakeHealthDay(
            dayStart: dayStart,
            isoDate: isoDate(dayStart, calendar: calendar),
            night: night,
            sleepScore: sleepScore,
            hrvMs: hrv,
            restingHR: rhr,
            steps: max(2_000, steps),
            activeCalories: max(120, calories),
            hydrationMl: max(600, hydration),
            workout: workout,
            markers: markers,
            social: social.map { [$0] } ?? []
        )
    }

    // MARK: - Evenings

    private static func socialEvent(
        offset: Int,
        dayStart: Date,
        calendar: Calendar,
        isWeekend: Bool,
        plannedLate: Bool,
        rng: inout SplitMix64
    ) -> FakeSocialEvent? {
        // Today's evening has not happened yet.
        guard offset > 0 else { return nil }
        let odds = plannedLate ? 100 : (isWeekend ? 55 : 18)
        guard rng.int(1...100) <= odds else { return nil }

        let kind: FakeSocialEvent.Kind = {
            if isWeekend {
                return [.dinnerOut, .drinks, .party, .dateNight, .familyTime][rng.int(0...4)]
            }
            return [.dinnerOut, .workEvent, .familyTime, .drinks, .travelDay][rng.int(0...4)]
        }()

        let title: String
        let drinks: Int
        switch kind {
        case .dinnerOut:  title = "Dinner out";        drinks = rng.int(0...2)
        case .drinks:     title = "Drinks with mates"; drinks = rng.int(2...5)
        case .party:      title = "Birthday party";    drinks = rng.int(2...6)
        case .dateNight:  title = "Date night";        drinks = rng.int(0...3)
        case .familyTime: title = "Family dinner";     drinks = rng.int(0...1)
        case .workEvent:  title = "Work dinner";       drinks = rng.int(0...3)
        case .travelDay:  title = "Travel day";        drinks = 0
        }

        let startHour = kind == .travelDay ? rng.int(6...10) : rng.int(18...21)
        let eveningDay = calendar.date(byAdding: .day, value: -1, to: dayStart) ?? dayStart
        var parts = calendar.dateComponents([.year, .month, .day], from: eveningDay)
        parts.hour = startHour
        parts.minute = rng.int(0...50)
        let start = calendar.date(from: parts) ?? dayStart

        let minutes = kind == .travelDay ? rng.int(180...520) : rng.int(70...260)
        let ranLate = plannedLate
            || (kind != .travelDay && startHour + (minutes / 60) >= 24)
            || drinks >= 4

        return FakeSocialEvent(
            kind: kind,
            title: title,
            start: start,
            minutes: minutes,
            drinks: drinks,
            ranLate: ranLate
        )
    }

    // MARK: - Places

    /// Synthetic anchor. Not a real address, and deliberately not derived from
    /// anything on the device — the pack must never look like it learned where
    /// someone actually lives.
    private static let anchorLatitude = 37.7840
    private static let anchorLongitude = -122.4070

    private static func jitter(_ base: Double, rng: inout SplitMix64) -> Double {
        base + Double(rng.int(-260...260)) / 10_000.0
    }

    private static func dayMarkers(
        offset: Int,
        dayStart: Date,
        calendar: Calendar,
        isWeekend: Bool,
        workout: FakeHealthWorkout?,
        social: FakeSocialEvent?,
        rng: inout SplitMix64
    ) -> [FakeLifestyleMarker] {
        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dayStart) ?? dayStart
        }
        func marker(_ kind: FakeLifestyleMarker.Kind, _ name: String, _ start: Date, _ minutes: Int) -> FakeLifestyleMarker {
            FakeLifestyleMarker(
                kind: kind,
                name: name,
                arrival: start,
                minutes: minutes,
                latitude: jitter(anchorLatitude, rng: &rng),
                longitude: jitter(anchorLongitude, rng: &rng)
            )
        }

        var out: [FakeLifestyleMarker] = [marker(.home, "Home", at(6, rng.int(10...50)), rng.int(60...150))]

        if !isWeekend, social?.kind != .travelDay {
            out.append(marker(.work, "Office", at(9, rng.int(0...40)), rng.int(300...520)))
            if rng.int(1...100) <= 45 {
                out.append(marker(.cafe, ["Blue Bottle", "Corner Coffee", "Sightglass"][rng.int(0...2)], at(8, rng.int(0...45)), rng.int(10...35)))
            }
        } else if social?.kind == .travelDay {
            out.append(marker(.travel, "Airport", at(rng.int(7...11)), rng.int(90...240)))
        } else {
            if rng.int(1...100) <= 55 {
                out.append(marker(.park, ["Riverside Park", "The Common", "Hill Trail"][rng.int(0...2)], at(rng.int(9...12)), rng.int(40...110)))
            }
            if rng.int(1...100) <= 40 {
                out.append(marker(.market, "Farmers Market", at(rng.int(10...13)), rng.int(25...70)))
            }
        }

        if workout != nil {
            out.append(marker(.gym, "Iron Works Gym", at(rng.int(17...19)), rng.int(45...80)))
        }

        if let social {
            let kind: FakeLifestyleMarker.Kind
            let name: String
            switch social.kind {
            case .drinks, .party:            kind = .bar;        name = ["The Alibi", "Third Rail", "Lucky's"][rng.int(0...2)]
            case .dinnerOut, .dateNight:     kind = .restaurant; name = ["Osteria", "Nopalito", "Kin Khao"][rng.int(0...2)]
            case .workEvent:                 kind = .restaurant; name = "Company dinner"
            case .familyTime:                kind = .home;       name = "Family's place"
            case .travelDay:                 kind = .travel;     name = "In transit"
            }
            out.append(marker(kind, name, social.start, social.minutes))
        }

        return out.sorted { $0.arrival < $1.arrival }
    }

    private static func session(offset: Int, phase: Int) -> FakeHealthWorkout? {
        // Mon / Wed / Fri strength, Saturday conditioning, Sunday mobility.
        // `offset` 0 is today; the week is a stable 7-day rotation so tests do
        // not depend on "what day is it", and `phase` shifts where that rotation
        // begins so the same pack index is not always the same session.
        //
        // Today (offset 0) stays open regardless of phase: ARIA writes that
        // session from this pack's own sleep and HRV.
        if offset == 0 { return nil }
        switch (offset + phase) % 7 {
        case 0:
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
            return offset % 14 == 6 ? FakeHealthWorkout(
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
