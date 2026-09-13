import Foundation
import HealthKit
import ForgeCore

extension HealthKitManager {

    func loadPersistedMeals() {
        let calendar = Calendar.current
        let savedDay = UserDefaults.standard.object(forKey: mealsStorageDateKey) as? Date
        if let savedDay, calendar.isDateInToday(savedDay),
           let data = UserDefaults.standard.data(forKey: mealsStorageKey),
           let meals = try? JSONDecoder().decode([MealLog].self, from: data) {
            loggedMeals = meals
        } else {
            loggedMeals = []
            UserDefaults.standard.set(Date(), forKey: mealsStorageDateKey)
            UserDefaults.standard.removeObject(forKey: mealsStorageKey)
        }
    }

    private func persistMeals() {
        UserDefaults.standard.set(Date(), forKey: mealsStorageDateKey)
        if let data = try? JSONEncoder().encode(loggedMeals) {
            UserDefaults.standard.set(data, forKey: mealsStorageKey)
        }
    }
    
    // MARK: - Authorization

    func logMeal(_ meal: MealLog) async throws {
        guard isAuthorized else { return }
        
        loggedMeals.append(meal)
        persistMeals()
        
        // Write to HealthKit
        let now = Date()
        var samples: [HKQuantitySample] = []
        
        // Calories
        let calorieQuantity = HKQuantity(unit: .kilocalorie(), doubleValue: meal.calories)
        samples.append(HKQuantitySample(type: HKQuantityType(.dietaryEnergyConsumed), quantity: calorieQuantity, start: now, end: now))

        // Protein
        let proteinQuantity = HKQuantity(unit: .gram(), doubleValue: meal.protein)
        samples.append(HKQuantitySample(type: HKQuantityType(.dietaryProtein), quantity: proteinQuantity, start: now, end: now))

        // Carbs
        let carbQuantity = HKQuantity(unit: .gram(), doubleValue: meal.carbs)
        samples.append(HKQuantitySample(type: HKQuantityType(.dietaryCarbohydrates), quantity: carbQuantity, start: now, end: now))

        // Fat
        let fatQuantity = HKQuantity(unit: .gram(), doubleValue: meal.fat)
        samples.append(HKQuantitySample(type: HKQuantityType(.dietaryFatTotal), quantity: fatQuantity, start: now, end: now))
        
        try await healthStore.save(samples)
        
        // Refresh today's stats
        await fetchTodayStats()
    }

    func logWater(ounces: Double) async throws {
        try await logWater(milliliters: HydrationEngine.milliliters(fromFluidOunces: ounces))
    }

    func logWater(milliliters: Double) async throws {
        guard isAuthorized else { throw HealthKitError.authorizationDenied }
        guard milliliters > 0 else { return }
        let waterType = HKQuantityType(.dietaryWater)

        let now = Date()
        let quantity = HKQuantity(unit: .liter(), doubleValue: milliliters / 1_000)
        let sample = HKQuantitySample(
            type: waterType,
            quantity: quantity,
            start: now,
            end: now,
            metadata: [
                HKMetadataKeyWasUserEntered: true,
                Self.forgeWaterMetadataKey: "1",
            ]
        )
        try await healthStore.save(sample)
        await refreshHydration()
    }

    func deleteWaterLog(_ log: WaterLog) async throws {
        guard isAuthorized else { throw HealthKitError.authorizationDenied }
        let waterType = HKQuantityType(.dietaryWater)
        let deleted: Int
        do {
            deleted = try await healthStore.deleteObjects(
                of: waterType,
                predicate: HKQuery.predicateForObject(with: log.id)
            )
        } catch {
            throw HealthKitError.saveFailed
        }
        guard deleted > 0 else { throw HealthKitError.saveFailed }
        await refreshHydration()
    }

    func refreshHydration() async {
        await fetchTodayWaterLogs()
        await fetchWeeklyWater()
        await fetchTodayStats()
        todayWaterMilliliters = todayWaterLogs.reduce(0) { $0 + $1.milliliters }
        if todayWaterMilliliters == 0, let fromStats = todayStats {
            todayWaterMilliliters = HydrationEngine.milliliters(fromGlasses: fromStats.water)
        }
        if todayWaterMilliliters == 0, let seeded = testReadyHydrationMilliliters {
            installTestReadyHydration(milliliters: seeded)
        }
    }

    /// In-memory water for Device Hub / simulator. Not written to HealthKit.
    func installTestReadyHydration(milliliters: Double) {
        guard milliliters > 0 else { return }
        testReadyHydrationMilliliters = milliliters
        if todayWaterMilliliters == 0 {
            todayWaterMilliliters = milliliters
        }
        if todayWaterLogs.isEmpty {
            todayWaterLogs = [
                WaterLog(
                    id: UUID(uuidString: "F0A6E000-0000-4000-8000-000000000001") ?? UUID(),
                    date: Date(),
                    milliliters: milliliters,
                    sourceName: "Test-ready pack",
                    isForge: true
                )
            ]
        }
    }

    func fetchTodayWaterLogs() async {
        guard isAuthorized else {
            todayWaterLogs = []
            return
        }
        let waterType = HKQuantityType(.dietaryWater)
        let now = Date()
        let start = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: waterType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            healthStore.execute(query)
        }

        todayWaterLogs = samples.map { sample in
            let ml = sample.quantity.doubleValue(for: .liter()) * 1_000
            let forge = (sample.metadata?[Self.forgeWaterMetadataKey] as? String) == "1"
            let source = forge ? "Forge" : (sample.sourceRevision.source.name)
            return WaterLog(
                id: sample.uuid,
                date: sample.startDate,
                milliliters: ml,
                sourceName: source,
                isForge: forge
            )
        }
        todayWaterMilliliters = todayWaterLogs.reduce(0) { $0 + $1.milliliters }
    }

    func fetchWeeklyWater() async {
        guard isAuthorized else {
            weeklyWaterMilliliters = []
            return
        }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var days: [DailyWaterTotal] = []
        for offset in stride(from: 6, through: 0, by: -1) {
            guard let start = calendar.date(byAdding: .day, value: -offset, to: today),
                  let end = calendar.date(byAdding: .day, value: 1, to: start) else { continue }
            let liters = await fetchDietaryValue(.dietaryWater, unit: .liter(), from: start, to: end) ?? 0
            days.append(DailyWaterTotal(date: start, milliliters: liters * 1_000))
        }
        weeklyWaterMilliliters = days
    }

    func fetchMindfulMinutes(from start: Date, to end: Date) async -> Double {
        guard isAuthorized else { return 0 }
        let type = HKCategoryType(.mindfulSession)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                let minutes = (samples as? [HKCategorySample])?.reduce(0.0) { total, sample in
                    total + sample.endDate.timeIntervalSince(sample.startDate) / 60.0
                } ?? 0
                continuation.resume(returning: minutes)
            }
            healthStore.execute(query)
        }
    }

    func logMindfulSession(minutes: Double) async throws {
        guard isAuthorized, minutes > 0 else { return }
        let type = HKCategoryType(.mindfulSession)
        let end = Date()
        let start = end.addingTimeInterval(-minutes * 60)
        let sample = HKCategorySample(
            type: type,
            value: HKCategoryValue.notApplicable.rawValue,
            start: start,
            end: end
        )
        try await healthStore.save(sample)
    }

    func logSexualActivity(start: Date = Date(), end: Date = Date(), protectionUsed: Bool? = nil) async throws {
        guard isAuthorized else { return }
        
        let type = HKCategoryType(.sexualActivity)
        var metadata: [String: Any] = [:]
        if let protectionUsed {
            metadata[HKMetadataKeySexualActivityProtectionUsed] = protectionUsed
        }
        
        let sample = HKCategorySample(
            type: type,
            value: HKCategoryValue.notApplicable.rawValue,
            start: start,
            end: max(end, start),
            metadata: metadata.isEmpty ? nil : metadata
        )
        
        try await healthStore.save(sample)
        _ = await fetchCycleSummary()
    }
    
    // MARK: - Helper Methods for Specific Time Ranges

    /// Writes one day of menstrual flow to Apple Health.
    ///
    /// `isCycleStart` must be true only for the *first* bleeding day of an episode.
    /// Marking every bleeding day as a cycle start told Health that a 5-day period was
    /// five separate one-day cycles, which wrecked Health's own cycle predictions.
    func saveMenstrualFlow(dayKey: String, flow: MenstrualFlowLevel, isCycleStart: Bool = false) async {
        guard isAuthorized,
              let dayStart = CycleDayKey.startOfDay(from: dayKey) else { return }
        let type = HKCategoryType(.menstrualFlow)
        let value: HKCategoryValueVaginalBleeding
        switch flow {
        case .none: value = .none
        case .light, .spotting: value = .light
        case .medium: value = .medium
        case .heavy: value = .heavy
        case .unspecified: value = .unspecified
        }
        // Samples are day-long so re-reads land on the same calendar day in any timezone.
        let end = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)
            .map { $0.addingTimeInterval(-1) } ?? dayStart
        let metadata: [String: Any] = [
            HKMetadataKeyMenstrualCycleStart: isCycleStart,
            HKMetadataKeySyncIdentifier: "forge.cycle.flow.\(dayKey)",
            HKMetadataKeySyncVersion: 1
        ]
        let sample = HKCategorySample(
            type: type,
            value: value.rawValue,
            start: dayStart,
            end: end,
            metadata: metadata
        )
        do {
            try await healthStore.save(sample)
        } catch {
            print("Menstrual flow HK save failed: \(error.localizedDescription)")
        }
    }

    /// Writes one BBT reading to Apple Cycle Tracking. Sync identifier replaces the day's sample.
    func saveBasalBodyTemperature(dayKey: String, celsius: Double) async {
        guard isAuthorized,
              let dayStart = CycleDayKey.startOfDay(from: dayKey) else { return }
        let type = HKQuantityType(.basalBodyTemperature)
        let quantity = HKQuantity(unit: .degreeCelsius(), doubleValue: celsius)
        let sample = HKQuantitySample(
            type: type,
            quantity: quantity,
            start: dayStart,
            end: dayStart,
            metadata: [
                HKMetadataKeySyncIdentifier: "forge.cycle.bbt.\(dayKey)",
                HKMetadataKeySyncVersion: 1
            ]
        )
        do {
            try await healthStore.save(sample)
        } catch {
            print("BBT HK save failed: \(error.localizedDescription)")
        }
    }

    func saveOvulationTest(dayKey: String, result: OvulationTestResult) async {
        guard isAuthorized,
              let dayStart = CycleDayKey.startOfDay(from: dayKey) else { return }
        let type = HKCategoryType(.ovulationTestResult)
        let value: HKCategoryValueOvulationTestResult
        switch result {
        case .negative: value = .negative
        case .lhSurge: value = .luteinizingHormoneSurge
        case .estrogenSurge: value = .estrogenSurge
        case .positive: value = .luteinizingHormoneSurge
        case .indeterminate: value = .indeterminate
        case .unknown: return
        }
        let end = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)
            .map { $0.addingTimeInterval(-1) } ?? dayStart
        let sample = HKCategorySample(
            type: type,
            value: value.rawValue,
            start: dayStart,
            end: end,
            metadata: [
                HKMetadataKeySyncIdentifier: "forge.cycle.opk.\(dayKey)",
                HKMetadataKeySyncVersion: 1
            ]
        )
        do {
            try await healthStore.save(sample)
        } catch {
            print("OPK HK save failed: \(error.localizedDescription)")
        }
    }

    func saveCervicalMucus(dayKey: String, quality: CervicalMucusQuality) async {
        guard isAuthorized,
              let dayStart = CycleDayKey.startOfDay(from: dayKey),
              quality != .unknown else { return }
        let type = HKCategoryType(.cervicalMucusQuality)
        let value: HKCategoryValueCervicalMucusQuality
        switch quality {
        case .dry: value = .dry
        case .sticky: value = .sticky
        case .creamy: value = .creamy
        case .watery: value = .watery
        case .eggWhite: value = .eggWhite
        case .unknown: return
        }
        let end = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)
            .map { $0.addingTimeInterval(-1) } ?? dayStart
        let sample = HKCategorySample(
            type: type,
            value: value.rawValue,
            start: dayStart,
            end: end,
            metadata: [
                HKMetadataKeySyncIdentifier: "forge.cycle.mucus.\(dayKey)",
                HKMetadataKeySyncVersion: 1
            ]
        )
        do {
            try await healthStore.save(sample)
        } catch {
            print("Mucus HK save failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Train + Sleep session I/O

    func latestHeartRateBPM() async -> Int? {
        let bpm = await fetchMostRecentQuantity(
            .heartRate,
            unit: HKUnit.count().unitDivided(by: .minute())
        )
        guard let bpm, bpm > 30, bpm < 230 else { return nil }
        return Int(bpm.rounded())
    }

    func startLiveHeartRateUpdates(_ onBPM: @escaping @Sendable (Int) -> Void) {
        stopLiveHeartRateUpdates()
        let type = HKQuantityType(.heartRate)
        let unit = HKUnit.count().unitDivided(by: .minute())
        let query = HKAnchoredObjectQuery(
            type: type,
            predicate: nil,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { _, samples, _, _, _ in
            Self.emitHeartRate(samples, unit: unit, onBPM: onBPM)
        }
        query.updateHandler = { _, samples, _, _, _ in
            Self.emitHeartRate(samples, unit: unit, onBPM: onBPM)
        }
        healthStore.execute(query)
        liveHeartRateQuery = query
    }

    func stopLiveHeartRateUpdates() {
        if let liveHeartRateQuery {
            healthStore.stop(liveHeartRateQuery)
        }
        liveHeartRateQuery = nil
    }

    private nonisolated static func emitHeartRate(
        _ samples: [HKSample]?,
        unit: HKUnit,
        onBPM: @escaping @Sendable (Int) -> Void
    ) {
        guard let sample = samples?.last as? HKQuantitySample else { return }
        let bpm = Int(sample.quantity.doubleValue(for: unit).rounded())
        guard bpm > 30, bpm < 230 else { return }
        Task { @MainActor in onBPM(bpm) }
    }

    func saveTrainWorkout(
        startedAt: Date,
        endedAt: Date,
        name: String,
        energyKilocalories: Double
    ) async {
        guard isHealthDataAvailable(), isAuthorized else { return }
        let end = max(endedAt, startedAt.addingTimeInterval(60))
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: config, device: .local())
        do {
            try await builder.beginCollection(at: startedAt)
            if energyKilocalories > 0 {
                let energy = HKQuantity(unit: .kilocalorie(), doubleValue: energyKilocalories)
                let sample = HKQuantitySample(
                    type: HKQuantityType(.activeEnergyBurned),
                    quantity: energy,
                    start: startedAt,
                    end: end,
                    metadata: [
                        HKMetadataKeyWorkoutBrandName: "Forge",
                    ]
                )
                try await builder.addSamples([sample])
            }
            try await builder.addMetadata([
                HKMetadataKeyWorkoutBrandName: "Forge",
                HKMetadataKeyIndoorWorkout: true,
            ])
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
        } catch {
            print("Train Health write failed: \(error.localizedDescription)")
        }
    }

    func saveInBedWindow(startedAt: Date, endedAt: Date = Date()) async {
        guard isHealthDataAvailable(), isAuthorized else { return }
        let end = max(endedAt, startedAt.addingTimeInterval(60))
        let sample = HKCategorySample(
            type: HKCategoryType(.sleepAnalysis),
            value: HKCategoryValueSleepAnalysis.inBed.rawValue,
            start: startedAt,
            end: end,
            metadata: [HKMetadataKeyWasUserEntered: true]
        )
        do {
            try await healthStore.save(sample)
        } catch {
            print("Sleep in-bed Health write failed: \(error.localizedDescription)")
        }
    }

    /// Most recent user-entered or Watch in-bed sample in the last two days.
    /// Stages still come from `fetchRecentSleepSessions`; this is the window
    /// someone actually logged when Apple has not scored a night yet.
    func fetchLatestInBedWindow() async -> (start: Date, end: Date)? {
        guard isAuthorized else { return nil }
        let sleepType = HKCategoryType(.sleepAnalysis)
        let start = Calendar.current.date(byAdding: .day, value: -2, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, _ in
                let match = (samples as? [HKCategorySample])?
                    .first { $0.value == HKCategoryValueSleepAnalysis.inBed.rawValue }
                guard let match else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: (match.startDate, match.endDate))
            }
            healthStore.execute(query)
        }
    }
}
