#if canImport(HealthKit)
import HealthKit

// MARK: - Shared HealthKit query helpers (iOS + watchOS)
//
// Thin, non-UI async wrappers used by WatchHealthKitManager and available
// to the iOS HealthKitManager for gradual adoption. All queries are
// read-only except `saveMindfulSession`.

public enum ForgeHealthQueries {

    // MARK: Reads

    /// Most recent HRV (SDNN) sample in milliseconds within `hours` back.
    public static func latestHRV(store: HKHealthStore, hoursBack: Double = 24) async -> (value: Double, date: Date)? {
        let samples = await quantitySamples(
            store: store,
            type: HKQuantityType(.heartRateVariabilitySDNN),
            start: Date().addingTimeInterval(-hoursBack * 3600),
            limit: 1,
            ascending: false
        )
        guard let sample = samples.first else { return nil }
        return (sample.quantity.doubleValue(for: .secondUnit(with: .milli)), sample.startDate)
    }

    /// Simple HRV trend: mean of samples in the recent window minus mean of
    /// the window before it. Negative result = dipping. Returns nil unless
    /// both windows have data — no fabricated trends.
    public static func hrvTrend(store: HKHealthStore, recentHours: Double = 4) async -> Double? {
        let now = Date()
        let recent = await quantitySamples(
            store: store,
            type: HKQuantityType(.heartRateVariabilitySDNN),
            start: now.addingTimeInterval(-recentHours * 3600),
            limit: HKObjectQueryNoLimit,
            ascending: false
        )
        let prior = await quantitySamples(
            store: store,
            type: HKQuantityType(.heartRateVariabilitySDNN),
            start: now.addingTimeInterval(-recentHours * 2 * 3600),
            end: now.addingTimeInterval(-recentHours * 3600),
            limit: HKObjectQueryNoLimit,
            ascending: false
        )
        guard !recent.isEmpty, !prior.isEmpty else { return nil }
        let unit = HKUnit.secondUnit(with: .milli)
        let recentMean = recent.map { $0.quantity.doubleValue(for: unit) }.mean
        let priorMean = prior.map { $0.quantity.doubleValue(for: unit) }.mean
        return recentMean - priorMean
    }

    /// 30-day HRV baseline (mean of daily samples). Used by the readiness
    /// calculator; nil when history is too thin (< 5 samples).
    public static func hrvBaseline(store: HKHealthStore, days: Int = 30) async -> Double? {
        let samples = await quantitySamples(
            store: store,
            type: HKQuantityType(.heartRateVariabilitySDNN),
            start: Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date(),
            limit: HKObjectQueryNoLimit,
            ascending: false
        )
        guard samples.count >= 5 else { return nil }
        let unit = HKUnit.secondUnit(with: .milli)
        return samples.map { $0.quantity.doubleValue(for: unit) }.mean
    }

    /// Most recent on-wrist heart rate sample (background cadence, not a
    /// live stream) — used for context cross-signals like gym detection.
    public static func latestHeartRate(store: HKHealthStore, minutesBack: Double = 20) async -> Double? {
        let samples = await quantitySamples(
            store: store,
            type: HKQuantityType(.heartRate),
            start: Date().addingTimeInterval(-minutesBack * 60),
            limit: 1,
            ascending: false
        )
        return samples.first?.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
    }

    public static func latestRestingHR(store: HKHealthStore) async -> Double? {
        let samples = await quantitySamples(
            store: store,
            type: HKQuantityType(.restingHeartRate),
            start: Calendar.current.date(byAdding: .day, value: -2, to: Date()) ?? Date(),
            limit: 1,
            ascending: false
        )
        return samples.first?.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
    }

    public static func restingHRBaseline(store: HKHealthStore, days: Int = 30) async -> Double? {
        let samples = await quantitySamples(
            store: store,
            type: HKQuantityType(.restingHeartRate),
            start: Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date(),
            limit: HKObjectQueryNoLimit,
            ascending: false
        )
        guard samples.count >= 5 else { return nil }
        let unit = HKUnit.count().unitDivided(by: .minute())
        return samples.map { $0.quantity.doubleValue(for: unit) }.mean
    }

    /// Last night's sleep (18:00 yesterday → now) with per-stage segments
    /// for the timeline visual. Aggregation lives in SleepNight (pure).
    public static func lastNightSleep(store: HKHealthStore) async -> SleepNight? {
        let calendar = Calendar.current
        let now = Date()
        guard let yesterdayEvening = calendar.date(
            bySettingHour: 18, minute: 0, second: 0,
            of: calendar.date(byAdding: .day, value: -1, to: now) ?? now
        ) else { return nil }

        let segments = await sleepSegments(store: store, from: yesterdayEvening, to: now)
        guard !segments.isEmpty else { return nil }
        let night = SleepNight(segments: segments)
        return night.totalMinutes > 0 ? night : nil
    }

    /// Recent nights (for the wind-down predictor: onsets + durations).
    public static func recentSleepNights(store: HKHealthStore, days: Int = 7) async -> [SleepNight] {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let segments = await sleepSegments(store: store, from: start, to: Date())
        return SleepNight.groupIntoNights(segments: segments)
            .filter { $0.totalMinutes > 0 }
    }

    private static func sleepSegments(store: HKHealthStore, from start: Date, to end: Date) async -> [SleepStageSegment] {
        let type = HKCategoryType(.sleepAnalysis)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let samples: [HKCategorySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type, predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }
        return samples.compactMap { sample in
            let stage: SleepStage?
            switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
            case .asleepDeep:                     stage = .deep
            case .asleepREM:                      stage = .rem
            case .asleepCore, .asleepUnspecified: stage = .core
            case .awake:                          stage = .awake
            default:                              stage = nil // inBed etc. — not stages
            }
            return stage.map { SleepStageSegment(start: sample.startDate, end: sample.endDate, stage: $0) }
        }
    }

    public static func mindfulMinutes(store: HKHealthStore, since start: Date) async -> Double {
        let type = HKCategoryType(.mindfulSession)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type, predicate: predicate,
                limit: HKObjectQueryNoLimit, sortDescriptors: nil
            ) { _, samples, _ in
                let minutes = (samples as? [HKCategorySample])?.reduce(0.0) {
                    $0 + $1.endDate.timeIntervalSince($1.startDate) / 60.0
                } ?? 0
                continuation.resume(returning: minutes)
            }
            store.execute(query)
        }
    }

    public static func lastWorkout(store: HKHealthStore, daysBack: Int = 3) async -> HKWorkout? {
        let predicate = HKQuery.predicateForSamples(
            withStart: Calendar.current.date(byAdding: .day, value: -daysBack, to: Date()),
            end: Date()
        )
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(), predicate: predicate,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, _ in
                continuation.resume(returning: samples?.first as? HKWorkout)
            }
            store.execute(query)
        }
    }

    // MARK: Writes

    /// Writes a Mindful Minutes sample. Same shape as the iOS
    /// HealthKitManager.logMindfulSession so both platforms' data merge
    /// cleanly in Health.
    /// Millilitres of water already logged today, from every source.
    ///
    /// Reads rather than tracking its own total so a glass logged on the
    /// iPhone, or by any other app writing to Health, counts on the wrist too.
    /// Two devices keeping separate tallies of the same day is how a user ends
    /// up being told they are behind on water they have already drunk.
    public static func waterToday(store: HKHealthStore, calendar: Calendar = .current) async -> Double {
        let type = HKQuantityType(.dietaryWater)
        let start = calendar.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, _ in
                let total = statistics?.sumQuantity()?.doubleValue(for: .literUnit(with: .milli)) ?? 0
                continuation.resume(returning: total)
            }
            store.execute(query)
        }
    }

    /// Writes a drink to Health, stamped at the moment it happened.
    public static func saveWater(
        store: HKHealthStore,
        milliliters: Double,
        at date: Date = Date()
    ) async throws {
        guard milliliters > 0 else { return }
        let sample = HKQuantitySample(
            type: HKQuantityType(.dietaryWater),
            quantity: HKQuantity(unit: .literUnit(with: .milli), doubleValue: milliliters),
            start: date,
            end: date
        )
        try await store.save(sample)
    }

    /// Body mass in kilograms, for HydrationEngine's target. Nil when the user
    /// has never recorded a weight — the engine falls back to a default rather
    /// than inventing one.
    public static func latestBodyMassKilograms(store: HKHealthStore) async -> Double? {
        let type = HKQuantityType(.bodyMass)
        return await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]
            ) { _, samples, _ in
                let kg = (samples?.first as? HKQuantitySample)?
                    .quantity.doubleValue(for: .gramUnit(with: .kilo))
                continuation.resume(returning: kg)
            }
            store.execute(query)
        }
    }

    public static func saveMindfulSession(store: HKHealthStore, start: Date, end: Date) async throws {
        guard end > start else { return }
        let sample = HKCategorySample(
            type: HKCategoryType(.mindfulSession),
            value: HKCategoryValue.notApplicable.rawValue,
            start: start,
            end: end
        )
        try await store.save(sample)
    }

    // MARK: Internals

    private static func quantitySamples(
        store: HKHealthStore,
        type: HKQuantityType,
        start: Date,
        end: Date = Date(),
        limit: Int,
        ascending: Bool
    ) async -> [HKQuantitySample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type, predicate: predicate, limit: limit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: ascending)]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            store.execute(query)
        }
    }
}

private extension Array where Element == Double {
    var mean: Double {
        isEmpty ? 0 : reduce(0, +) / Double(count)
    }
}
#endif
