import Foundation
import HealthKit
import ForgeCore

extension HealthKitManager {

    func fetchRecentSnapshot() async -> HealthDataSnapshot? {
        guard isAuthorized else { return nil }
        
        async let restingHR = fetchMostRecentRestingHeartRate()
        async let calories = fetchTodayActiveCalories()
        async let steps = fetchTodaySteps()
        async let sleep = fetchLastNightSleep()
        async let hrv = fetchTodayHRV()
        async let vo2Max = fetchMostRecentVO2Max()
        async let workouts = fetchRecentWorkouts()
        
        let (hr, cal, st, sl, hrvValue, vo2Value, wo) = await (restingHR, calories, steps, sleep, hrv, vo2Max, workouts)
        
        return HealthDataSnapshot(
            restingHeartRate: hr,
            activeCalories: cal,
            steps: st,
            sleepHours: sl,
            hrv: hrvValue,
            vo2Max: vo2Value,
            workoutCount: wo.count,
            lastWorkoutDate: wo.first?.startDate
        )
    }
    
    // MARK: - Individual Data Fetchers

    func fetchMostRecentRestingHeartRate() async -> Int? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else { return nil }
        
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        _ = HKSampleQuery(
            sampleType: type,
            predicate: nil,
            limit: 1,
            sortDescriptors: [sortDescriptor]
        ) { _, samples, _ in }
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                let value = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                continuation.resume(returning: Int(value))
            }
            healthStore.execute(query)
        }
    }

    private func fetchTodayActiveCalories() async -> Int? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return nil }
        
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, _ in
                guard let sum = statistics?.sumQuantity() else {
                    continuation.resume(returning: nil)
                    return
                }
                let calories = sum.doubleValue(for: .kilocalorie())
                continuation.resume(returning: Int(calories))
            }
            healthStore.execute(query)
        }
    }

    private func fetchTodaySteps() async -> Int? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return nil }
        
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, _ in
                guard let sum = statistics?.sumQuantity() else {
                    continuation.resume(returning: nil)
                    return
                }
                let steps = sum.doubleValue(for: .count())
                continuation.resume(returning: Int(steps))
            }
            healthStore.execute(query)
        }
    }

    private func fetchLastNightSleep() async -> Double? {
        let sleepType = HKCategoryType(.sleepAnalysis)
        
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let predicate = HKQuery.predicateForSamples(withStart: yesterday, end: now, options: .strictStartDate)
        
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: nil)
                    return
                }
                
                // Filter for actual sleep (not in bed)
                let sleepSamples = samples.filter { sample in
                    guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { return false }
                    return value == .asleepCore || value == .asleepDeep || value == .asleepREM || value == .asleepUnspecified
                }
                
                let totalSeconds = sleepSamples.reduce(0.0) { total, sample in
                    total + sample.endDate.timeIntervalSince(sample.startDate)
                }
                
                let hours = totalSeconds / 3600.0
                continuation.resume(returning: hours > 0 ? hours : nil)
            }
            healthStore.execute(query)
        }
    }

    private func fetchRecentWorkouts() async -> [HKWorkout] {
        await fetchWorkoutsForHistory(days: 7, limit: 10)
    }

    /// History path — enough days to cover the Test-Ready pack.
    func fetchWorkoutsForHistory(days: Int, limit: Int = HKObjectQueryNoLimit) async -> [HKWorkout] {
        let workoutType = HKWorkoutType.workoutType()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: limit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            healthStore.execute(query)
        }
    }
    
    // MARK: - Lifestyle-Specific Data Fetchers

    func fetchTodayStats(force: Bool = false) async {
        if !force, let lastTodayStatsAt, todayStats != nil,
           Date().timeIntervalSince(lastTodayStatsAt) < Self.statsTTL {
            return
        }
        guard isAuthorized else {
            todayStats = .default
            return
        }
        
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        
        // Fetch all today's data in parallel.
        async let steps = fetchTodaySteps()
        async let activeCalories = fetchTodayActiveCalories()
        async let basalCalories = fetchCumulativeQuantity(.basalEnergyBurned, unit: .kilocalorie(), from: startOfDay, to: now)
        async let walkingRunningDistance = fetchCumulativeQuantity(.distanceWalkingRunning, unit: .meter(), from: startOfDay, to: now)
        async let cyclingDistance = fetchCumulativeQuantity(.distanceCycling, unit: .meter(), from: startOfDay, to: now)
        async let swimmingDistance = fetchCumulativeQuantity(.distanceSwimming, unit: .meter(), from: startOfDay, to: now)
        async let flights = fetchCumulativeQuantity(.flightsClimbed, unit: .count(), from: startOfDay, to: now)
        async let exerciseMinutes = fetchCumulativeQuantity(.appleExerciseTime, unit: .minute(), from: startOfDay, to: now)
        async let standMinutes = fetchCumulativeQuantity(.appleStandTime, unit: .minute(), from: startOfDay, to: now)
        async let sleep = fetchLastNightSleep()
        async let restingHR = fetchTodayRestingHeartRate()
        async let walkingHR = fetchAverageQuantity(.walkingHeartRateAverage, unit: HKUnit.count().unitDivided(by: .minute()), from: startOfDay, to: now)
        async let heartRateRecovery = fetchMostRecentQuantity(.heartRateRecoveryOneMinute, unit: HKUnit.count().unitDivided(by: .minute()))
        async let hrv = fetchTodayHRV()
        async let vo2Max = fetchMostRecentVO2Max()
        async let oxygenSaturation = fetchAverageQuantity(.oxygenSaturation, unit: .percent(), from: startOfDay, to: now)
        async let respiratoryRate = fetchAverageQuantity(.respiratoryRate, unit: HKUnit.count().unitDivided(by: .minute()), from: startOfDay, to: now)
        async let bodyTemperature = fetchAverageQuantity(.bodyTemperature, unit: .degreeFahrenheit(), from: startOfDay, to: now)
        async let systolic = fetchAverageQuantity(.bloodPressureSystolic, unit: .millimeterOfMercury(), from: startOfDay, to: now)
        async let diastolic = fetchAverageQuantity(.bloodPressureDiastolic, unit: .millimeterOfMercury(), from: startOfDay, to: now)
        async let walkingSpeed = fetchAverageQuantity(.walkingSpeed, unit: .meter().unitDivided(by: .second()), from: startOfDay, to: now)
        async let runningSpeed = fetchAverageQuantity(.runningSpeed, unit: .meter().unitDivided(by: .second()), from: startOfDay, to: now)
        async let cyclingSpeed = fetchAverageQuantity(.cyclingSpeed, unit: .meter().unitDivided(by: .second()), from: startOfDay, to: now)
        async let runningPower = fetchAverageQuantity(.runningPower, unit: .watt(), from: startOfDay, to: now)
        async let cyclingPower = fetchAverageQuantity(.cyclingPower, unit: .watt(), from: startOfDay, to: now)
        async let nutrition = fetchTodayNutrition()
        async let water = fetchTodayWater()
        
        let activityValues = await (
            steps,
            activeCalories,
            basalCalories,
            walkingRunningDistance,
            cyclingDistance,
            swimmingDistance,
            flights,
            exerciseMinutes,
            standMinutes
        )
        let recoveryValues = await (
            sleep,
            restingHR,
            walkingHR,
            heartRateRecovery,
            hrv,
            vo2Max,
            oxygenSaturation,
            respiratoryRate,
            bodyTemperature,
            systolic,
            diastolic
        )
        let performanceValues = await (
            walkingSpeed,
            runningSpeed,
            cyclingSpeed,
            runningPower,
            cyclingPower,
            nutrition,
            water
        )
        
        // HealthKit is the ledger. Forge-logged meals and water are written
        // there first; adding the local copies on top double-counts every pour.
        
        todayStats = DailyHealthStats(
            date: Date(),
            steps: activityValues.0 ?? 0,
            activeCalories: activityValues.1 ?? 0,
            basalCalories: Int(activityValues.2 ?? 0),
            totalCalories: performanceValues.5?.calories ?? 0,
            distanceWalkingRunningMeters: activityValues.3 ?? 0,
            distanceCyclingMeters: activityValues.4 ?? 0,
            distanceSwimmingMeters: activityValues.5 ?? 0,
            flightsClimbed: activityValues.6 ?? 0,
            exerciseMinutes: activityValues.7 ?? 0,
            standMinutes: activityValues.8 ?? 0,
            protein: performanceValues.5?.protein ?? 0,
            carbs: performanceValues.5?.carbs ?? 0,
            fat: performanceValues.5?.fat ?? 0,
            fiber: performanceValues.5?.fiber ?? 0,
            sugar: performanceValues.5?.sugar ?? 0,
            sodium: performanceValues.5?.sodium ?? 0,
            caffeine: performanceValues.5?.caffeine ?? 0,
            water: HydrationEngine.glasses(fromMilliliters: performanceValues.6 ?? 0),
            sleepHours: recoveryValues.0 ?? 0,
            restingHeartRate: Double(recoveryValues.1 ?? 0),
            walkingHeartRateAverage: recoveryValues.2 ?? 0,
            heartRateRecoveryOneMinute: recoveryValues.3 ?? 0,
            hrv: recoveryValues.4 ?? 0,
            vo2Max: recoveryValues.5 ?? 0,
            oxygenSaturation: recoveryValues.6 ?? 0,
            respiratoryRate: recoveryValues.7 ?? 0,
            bodyTemperature: recoveryValues.8 ?? 0,
            bloodPressureSystolic: recoveryValues.9 ?? 0,
            bloodPressureDiastolic: recoveryValues.10 ?? 0,
            walkingSpeed: performanceValues.0 ?? 0,
            runningSpeed: performanceValues.1 ?? 0,
            cyclingSpeed: performanceValues.2 ?? 0,
            runningPower: performanceValues.3 ?? 0,
            cyclingPower: performanceValues.4 ?? 0
        )
        lastTodayStatsAt = Date()
    }

    func fetchWeeklyTrends() async {
        if let lastWeeklyTrendsAt, !weeklyTrends.isEmpty,
           Date().timeIntervalSince(lastWeeklyTrendsAt) < Self.trendTTL {
            return
        }
        guard isAuthorized else {
            weeklyTrends = []
            return
        }
        
        let calendar = Calendar.current
        let days: [(Date, Date)] = (0..<7).compactMap { dayOffset in
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { return nil }
            let startOfDay = calendar.startOfDay(for: date)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? date
            return (startOfDay, endOfDay)
        }
        var trends: [WeeklyHealthTrend] = []
        await withTaskGroup(of: WeeklyHealthTrend.self) { group in
            for (startOfDay, endOfDay) in days {
                group.addTask { @MainActor in
                    async let steps = self.fetchSteps(from: startOfDay, to: endOfDay)
                    async let calories = self.fetchActiveCalories(from: startOfDay, to: endOfDay)
                    async let sleep = self.fetchSleep(from: startOfDay, to: endOfDay)
                    async let hrv = self.fetchAverageHRV(from: startOfDay, to: endOfDay)
                    let (stepsValue, caloriesValue, sleepValue, hrvValue) = await (steps, calories, sleep, hrv)
                    return WeeklyHealthTrend(
                        date: startOfDay,
                        steps: stepsValue ?? 0,
                        activeCalories: caloriesValue ?? 0,
                        sleepHours: sleepValue ?? 0,
                        avgHRV: hrvValue ?? 0
                    )
                }
            }
            for await trend in group {
                trends.append(trend)
            }
        }
        
        weeklyTrends = trends.sorted { $0.date < $1.date }
        lastWeeklyTrendsAt = Date()
    }

    /// Per-day mindful minutes for the last 7 days (oldest first).
    func fetchMindfulTrend() async {
        if let lastMindfulTrendAt, !mindfulTrend.isEmpty,
           Date().timeIntervalSince(lastMindfulTrendAt) < Self.trendTTL {
            return
        }
        guard isAuthorized else {
            mindfulTrend = []
            return
        }

        let calendar = Calendar.current
        let days: [(Date, Date)] = (0..<7).compactMap { dayOffset in
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { return nil }
            let startOfDay = calendar.startOfDay(for: date)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? date
            return (startOfDay, endOfDay)
        }
        var collected: [MindfulDay] = []
        await withTaskGroup(of: MindfulDay.self) { group in
            for (startOfDay, endOfDay) in days {
                group.addTask { @MainActor in
                    let minutes = await self.fetchMindfulMinutes(from: startOfDay, to: endOfDay)
                    return MindfulDay(date: startOfDay, minutes: minutes)
                }
            }
            for await day in group {
                collected.append(day)
            }
        }
        mindfulTrend = collected.sorted { $0.date < $1.date }
        lastMindfulTrendAt = Date()
    }

    // MARK: - Nutrition Logging

    private func fetchTodayRestingHeartRate() async -> Int? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else { return nil }
        
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                let value = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                continuation.resume(returning: Int(value))
            }
            healthStore.execute(query)
        }
    }

    private func fetchTodayHRV() async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return nil }
        
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, statistics, _ in
                guard let avg = statistics?.averageQuantity() else {
                    continuation.resume(returning: nil)
                    return
                }
                let hrv = avg.doubleValue(for: .secondUnit(with: .milli))
                continuation.resume(returning: hrv)
            }
            healthStore.execute(query)
        }
    }

    private func fetchTodayNutrition() async -> (calories: Int, protein: Double, carbs: Double, fat: Double, fiber: Double, sugar: Double, sodium: Double, caffeine: Double)? {
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        
        async let calories = fetchDietaryValue(.dietaryEnergyConsumed, unit: .kilocalorie(), from: startOfDay, to: now)
        async let protein = fetchDietaryValue(.dietaryProtein, unit: .gram(), from: startOfDay, to: now)
        async let carbs = fetchDietaryValue(.dietaryCarbohydrates, unit: .gram(), from: startOfDay, to: now)
        async let fat = fetchDietaryValue(.dietaryFatTotal, unit: .gram(), from: startOfDay, to: now)
        async let fiber = fetchDietaryValue(.dietaryFiber, unit: .gram(), from: startOfDay, to: now)
        async let sugar = fetchDietaryValue(.dietarySugar, unit: .gram(), from: startOfDay, to: now)
        async let sodium = fetchDietaryValue(.dietarySodium, unit: .gramUnit(with: .milli), from: startOfDay, to: now)
        async let caffeine = fetchDietaryValue(.dietaryCaffeine, unit: .gramUnit(with: .milli), from: startOfDay, to: now)
        
        let nutritionValues = await (calories, protein, carbs, fat, fiber, sugar, sodium, caffeine)
        
        if nutritionValues.0 != nil || nutritionValues.1 != nil || nutritionValues.2 != nil || nutritionValues.3 != nil || nutritionValues.4 != nil || nutritionValues.5 != nil || nutritionValues.6 != nil || nutritionValues.7 != nil {
            return (
                Int(nutritionValues.0 ?? 0),
                nutritionValues.1 ?? 0,
                nutritionValues.2 ?? 0,
                nutritionValues.3 ?? 0,
                nutritionValues.4 ?? 0,
                nutritionValues.5 ?? 0,
                nutritionValues.6 ?? 0,
                nutritionValues.7 ?? 0
            )
        }
        return nil
    }

    private func fetchTodayWater() async -> Double? {
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        guard let liters = await fetchDietaryValue(.dietaryWater, unit: .liter(), from: startOfDay, to: now) else {
            return nil
        }
        return liters * 1_000
    }

    func fetchDietaryValue(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async -> Double? {
        await fetchCumulativeQuantity(identifier, unit: unit, from: start, to: end)
    }

    private func fetchSteps(from start: Date, to end: Date) async -> Int? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, _ in
                guard let sum = statistics?.sumQuantity() else {
                    continuation.resume(returning: nil)
                    return
                }
                let steps = sum.doubleValue(for: .count())
                continuation.resume(returning: Int(steps))
            }
            healthStore.execute(query)
        }
    }

    private func fetchActiveCalories(from start: Date, to end: Date) async -> Int? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, _ in
                guard let sum = statistics?.sumQuantity() else {
                    continuation.resume(returning: nil)
                    return
                }
                let calories = sum.doubleValue(for: .kilocalorie())
                continuation.resume(returning: Int(calories))
            }
            healthStore.execute(query)
        }
    }

    private func fetchSleep(from start: Date, to end: Date) async -> Double? {
        let sleepType = HKCategoryType(.sleepAnalysis)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let sleepSamples = samples.filter { sample in
                    guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { return false }
                    return value == .asleepCore || value == .asleepDeep || value == .asleepREM || value == .asleepUnspecified
                }
                
                let totalSeconds = sleepSamples.reduce(0.0) { total, sample in
                    total + sample.endDate.timeIntervalSince(sample.startDate)
                }
                
                let hours = totalSeconds / 3600.0
                continuation.resume(returning: hours > 0 ? hours : nil)
            }
            healthStore.execute(query)
        }
    }

    func fetchAverageHRV(from start: Date, to end: Date) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, statistics, _ in
                guard let avg = statistics?.averageQuantity() else {
                    continuation.resume(returning: nil)
                    return
                }
                let hrv = avg.doubleValue(for: .secondUnit(with: .milli))
                continuation.resume(returning: hrv)
            }
            healthStore.execute(query)
        }
    }
    
    // MARK: - Structured Health records (no notes)

    func fetchAverageHRV() async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return nil }
        
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: sevenDaysAgo, end: Date(), options: .strictStartDate)
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, statistics, _ in
                guard let avg = statistics?.averageQuantity() else {
                    continuation.resume(returning: nil)
                    return
                }
                let hrv = avg.doubleValue(for: .secondUnit(with: .milli))
                continuation.resume(returning: hrv)
            }
            healthStore.execute(query)
        }
    }

    func fetchRecentSleepSessions(days: Int) async -> [SleepNightSample] {
        let sleepType = HKCategoryType(.sleepAnalysis)
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample], !samples.isEmpty else {
                    continuation.resume(returning: [])
                    return
                }

                let grouped = Dictionary(grouping: samples) { sample -> String in
                    let day = Calendar.current.startOfDay(for: sample.endDate)
                    return ISO8601DateFormatter().string(from: day).prefix(10).description
                }

                let nights: [SleepNightSample] = grouped.compactMap { date, daySamples in
                    var deep: TimeInterval = 0
                    var rem: TimeInterval = 0
                    var light: TimeInterval = 0
                    var awake: TimeInterval = 0

                    for sample in daySamples {
                        let duration = sample.endDate.timeIntervalSince(sample.startDate)
                        switch sample.value {
                        case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                            deep += duration
                        case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                            rem += duration
                        case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
                            light += duration
                        case HKCategoryValueSleepAnalysis.awake.rawValue:
                            awake += duration
                        case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                            light += duration
                        default:
                            break
                        }
                    }

                    let totalHours = (deep + rem + light) / 3600
                    guard totalHours > 0 else { return nil }

                    // Sleep onset and final wake, from asleep samples only.
                    // Time in bed reading or lying awake is not sleep, and
                    // letting it into these bounds drags the mid-sleep point
                    // toward whenever the watch went on rather than whenever the
                    // person actually went under — which is the whole signal the
                    // circadian phase estimate rests on.
                    let asleepValues: Set<Int> = [
                        HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                        HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                        HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                        HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                    ]
                    let asleepSamples = daySamples.filter { asleepValues.contains($0.value) }

                    return SleepNightSample(
                        date: date,
                        totalHours: totalHours,
                        deepMinutes: Int(deep / 60),
                        remMinutes: Int(rem / 60),
                        lightMinutes: Int(light / 60),
                        awakeMinutes: Int(awake / 60),
                        onset: asleepSamples.map(\.startDate).min(),
                        wake: asleepSamples.map(\.endDate).max()
                    )
                }
                continuation.resume(returning: nights.sorted { $0.date > $1.date })
            }
            healthStore.execute(query)
        }
    }
}
