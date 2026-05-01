import Foundation
import HealthKit

// MARK: - Health Data Snapshot

struct HealthDataSnapshot: Identifiable {
    let id = UUID()
    let restingHeartRate: Int?
    let activeCalories: Int?
    let steps: Int?
    let sleepHours: Double?
    let workoutCount: Int?
    let lastWorkoutDate: Date?
    let timestamp: Date = Date()
    
    var hasData: Bool {
        restingHeartRate != nil || activeCalories != nil || steps != nil || sleepHours != nil
    }
}

// MARK: - Daily Health Stats (Extended for Lifestyle View)

struct DailyHealthStats: Identifiable, Codable {
    var id = UUID()
    let date: Date
    let steps: Int
    let activeCalories: Int
    let totalCalories: Int
    let protein: Double
    let carbs: Double
    let fat: Double
    let water: Double // glasses
    let sleepHours: Double
    let restingHeartRate: Double
    let hrv: Double // Heart Rate Variability in ms
    
    static var `default`: DailyHealthStats {
        DailyHealthStats(
            date: Date(),
            steps: 0,
            activeCalories: 0,
            totalCalories: 0,
            protein: 0,
            carbs: 0,
            fat: 0,
            water: 0,
            sleepHours: 0,
            restingHeartRate: 0,
            hrv: 0
        )
    }
}

// MARK: - Weekly Health Trend

struct WeeklyHealthTrend: Identifiable, Codable {
    var id = UUID()
    let date: Date
    let steps: Int
    let activeCalories: Int
    let sleepHours: Double
    let avgHRV: Double
}

// MARK: - Meal Log

struct MealLog: Codable {
    var id = UUID()
    let name: String
    let date: Date
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    
    init(name: String, calories: Double, protein: Double, carbs: Double, fat: Double, date: Date = Date()) {
        self.name = name
        self.date = date
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }
}

// MARK: - HealthKit Manager

@MainActor
class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()
    
    private let healthStore = HKHealthStore()
    @Published var isAuthorized = false
    
    // Published health data for real-time updates
    @Published var todayStats: DailyHealthStats?
    @Published var weeklyTrends: [WeeklyHealthTrend] = []
    
    // In-memory storage for nutrition data (could be persisted to UserDefaults or Core Data)
    private var todayMeals: [MealLog] = []
    private var todayWaterIntake: Double = 0 // in ounces
    
    // Types to read
    private let readTypes: Set<HKSampleType> = [
        HKQuantityType(.heartRate),
        HKQuantityType(.restingHeartRate),
        HKQuantityType(.heartRateVariabilitySDNN),
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.stepCount),
        HKQuantityType(.distanceWalkingRunning),
        HKQuantityType(.vo2Max),
        HKCategoryType(.sleepAnalysis),
        HKQuantityType(.bodyMass),
        HKQuantityType(.height),
        HKQuantityType(.bodyMassIndex),
        HKQuantityType(.dietaryProtein),
        HKQuantityType(.dietaryCarbohydrates),
        HKQuantityType(.dietaryFatTotal),
        HKQuantityType(.dietaryEnergyConsumed),
        HKQuantityType(.dietaryWater),
        HKWorkoutType.workoutType()
    ]
    
    // Types to write (for tracking workouts and nutrition)
    private let writeTypes: Set<HKSampleType> = [
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.dietaryProtein),
        HKQuantityType(.dietaryCarbohydrates),
        HKQuantityType(.dietaryFatTotal),
        HKQuantityType(.dietaryEnergyConsumed),
        HKQuantityType(.dietaryWater),
        HKWorkoutType.workoutType()
    ]
    
    private init() {}
    
    // MARK: - Authorization
    
    func isHealthDataAvailable() -> Bool {
        return HKHealthStore.isHealthDataAvailable()
    }
    
    func checkAuthorizationStatus() async -> Bool {
        guard isHealthDataAvailable() else { return false }
        
        // Check if we have authorization for key types
        let status = healthStore.authorizationStatus(for: HKQuantityType(.heartRate))
        isAuthorized = status == .sharingAuthorized
        return isAuthorized
    }
    
    func requestAuthorization() async throws {
        guard isHealthDataAvailable() else {
            throw HealthKitError.notAvailable
        }
        
        try await healthStore.requestAuthorization(toShare: writeTypes, read: readTypes)
        isAuthorized = true
    }
    
    // MARK: - Fetch Recent Snapshot
    
    func fetchRecentSnapshot() async -> HealthDataSnapshot? {
        guard isAuthorized else { return nil }
        
        async let restingHR = fetchMostRecentRestingHeartRate()
        async let calories = fetchTodayActiveCalories()
        async let steps = fetchTodaySteps()
        async let sleep = fetchLastNightSleep()
        async let workouts = fetchRecentWorkouts()
        
        let (hr, cal, st, sl, wo) = await (restingHR, calories, steps, sleep, workouts)
        
        return HealthDataSnapshot(
            restingHeartRate: hr,
            activeCalories: cal,
            steps: st,
            sleepHours: sl,
            workoutCount: wo.count,
            lastWorkoutDate: wo.first?.startDate
        )
    }
    
    // MARK: - Individual Data Fetchers
    
    private func fetchMostRecentRestingHeartRate() async -> Int? {
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
        let workoutType = HKWorkoutType.workoutType()
        
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: sevenDaysAgo, end: Date(), options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: 10,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            healthStore.execute(query)
        }
    }
    
    // MARK: - Lifestyle-Specific Data Fetchers
    
    func fetchTodayStats() async {
        guard isAuthorized else {
            todayStats = .default
            return
        }
        
        // Fetch all today's data in parallel
        async let steps = fetchTodaySteps()
        async let activeCalories = fetchTodayActiveCalories()
        async let sleep = fetchLastNightSleep()
        async let restingHR = fetchTodayRestingHeartRate()
        async let hrv = fetchTodayHRV()
        async let nutrition = fetchTodayNutrition()
        async let water = fetchTodayWater()
        
        let (stepsValue, caloriesValue, sleepValue, hrValue, hrvValue, nutritionValue, waterValue) = 
            await (steps, activeCalories, sleep, restingHR, hrv, nutrition, water)
        
        // Calculate total calories from meals
        let totalCalories = todayMeals.reduce(0) { $0 + Int($1.calories) }
        let protein = todayMeals.reduce(0.0) { $0 + $1.protein } + (nutritionValue?.protein ?? 0)
        let carbs = todayMeals.reduce(0.0) { $0 + $1.carbs } + (nutritionValue?.carbs ?? 0)
        let fat = todayMeals.reduce(0.0) { $0 + $1.fat } + (nutritionValue?.fat ?? 0)
        
        todayStats = DailyHealthStats(
            date: Date(),
            steps: stepsValue ?? 0,
            activeCalories: caloriesValue ?? 0,
            totalCalories: totalCalories + (nutritionValue?.calories ?? 0),
            protein: protein,
            carbs: carbs,
            fat: fat,
            water: (waterValue ?? 0) / 8.0 + todayWaterIntake / 8.0, // Convert ounces to glasses
            sleepHours: sleepValue ?? 0,
            restingHeartRate: Double(hrValue ?? 0),
            hrv: hrvValue ?? 0
        )
    }
    
    func fetchWeeklyTrends() async {
        guard isAuthorized else {
            weeklyTrends = []
            return
        }
        
        var trends: [WeeklyHealthTrend] = []
        let calendar = Calendar.current
        
        // Fetch data for last 7 days
        for dayOffset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
            let startOfDay = calendar.startOfDay(for: date)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? date
            
            async let steps = fetchSteps(from: startOfDay, to: endOfDay)
            async let calories = fetchActiveCalories(from: startOfDay, to: endOfDay)
            async let sleep = fetchSleep(from: startOfDay, to: endOfDay)
            async let hrv = fetchAverageHRV(from: startOfDay, to: endOfDay)
            
            let (stepsValue, caloriesValue, sleepValue, hrvValue) = await (steps, calories, sleep, hrv)
            
            trends.append(WeeklyHealthTrend(
                date: startOfDay,
                steps: stepsValue ?? 0,
                activeCalories: caloriesValue ?? 0,
                sleepHours: sleepValue ?? 0,
                avgHRV: hrvValue ?? 0
            ))
        }
        
        weeklyTrends = trends.reversed() // Oldest first
    }
    
    // MARK: - Nutrition Logging
    
    func logMeal(_ meal: MealLog) async throws {
        guard isAuthorized else { return }
        
        todayMeals.append(meal)
        
        // Write to HealthKit
        let now = Date()
        var samples: [HKQuantitySample] = []
        
        // Calories
        if let calorieType = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed) {
            let calorieQuantity = HKQuantity(unit: .kilocalorie(), doubleValue: meal.calories)
            let calorieSample = HKQuantitySample(type: calorieType, quantity: calorieQuantity, start: now, end: now)
            samples.append(calorieSample)
        }
        
        // Protein
        if let proteinType = HKQuantityType.quantityType(forIdentifier: .dietaryProtein) {
            let proteinQuantity = HKQuantity(unit: .gram(), doubleValue: meal.protein)
            let proteinSample = HKQuantitySample(type: proteinType, quantity: proteinQuantity, start: now, end: now)
            samples.append(proteinSample)
        }
        
        // Carbs
        if let carbType = HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates) {
            let carbQuantity = HKQuantity(unit: .gram(), doubleValue: meal.carbs)
            let carbSample = HKQuantitySample(type: carbType, quantity: carbQuantity, start: now, end: now)
            samples.append(carbSample)
        }
        
        // Fat
        if let fatType = HKQuantityType.quantityType(forIdentifier: .dietaryFatTotal) {
            let fatQuantity = HKQuantity(unit: .gram(), doubleValue: meal.fat)
            let fatSample = HKQuantitySample(type: fatType, quantity: fatQuantity, start: now, end: now)
            samples.append(fatSample)
        }
        
        try await healthStore.save(samples)
        
        // Refresh today's stats
        await fetchTodayStats()
    }
    
    func logWater(ounces: Double) async throws {
        guard isAuthorized else { return }
        
        todayWaterIntake += ounces
        
        // Write to HealthKit
        if let waterType = HKQuantityType.quantityType(forIdentifier: .dietaryWater) {
            let waterQuantity = HKQuantity(unit: .fluidOunceUS(), doubleValue: ounces)
            let waterSample = HKQuantitySample(
                type: waterType,
                quantity: waterQuantity,
                start: Date(),
                end: Date()
            )
            
            try await healthStore.save(waterSample)
        }
        
        // Refresh today's stats
        await fetchTodayStats()
    }
    
    // MARK: - Helper Methods for Specific Time Ranges
    
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
    
    private func fetchTodayNutrition() async -> (calories: Int, protein: Double, carbs: Double, fat: Double)? {
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        
        async let calories = fetchDietaryValue(.dietaryEnergyConsumed, unit: .kilocalorie(), from: startOfDay, to: now)
        async let protein = fetchDietaryValue(.dietaryProtein, unit: .gram(), from: startOfDay, to: now)
        async let carbs = fetchDietaryValue(.dietaryCarbohydrates, unit: .gram(), from: startOfDay, to: now)
        async let fat = fetchDietaryValue(.dietaryFatTotal, unit: .gram(), from: startOfDay, to: now)
        
        let (cal, pro, car, f) = await (calories, protein, carbs, fat)
        
        if cal != nil || pro != nil || car != nil || f != nil {
            return (Int(cal ?? 0), pro ?? 0, car ?? 0, f ?? 0)
        }
        return nil
    }
    
    private func fetchTodayWater() async -> Double? {
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        return await fetchDietaryValue(.dietaryWater, unit: .fluidOunceUS(), from: startOfDay, to: now)
    }
    
    private func fetchDietaryValue(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        
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
                let value = sum.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            healthStore.execute(query)
        }
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
    
    private func fetchAverageHRV(from start: Date, to end: Date) async -> Double? {
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
    
    // MARK: - Detailed Profile Data
    
    func fetchUserProfile() async -> UserHealthProfile? {
        async let age = fetchAge()
        async let weight = fetchMostRecentWeight()
        async let height = fetchHeight()
        async let vo2Max = fetchMostRecentVO2Max()
        async let avgHRV = fetchAverageHRV()
        
        let (ageValue, weightValue, heightValue, vo2MaxValue, hrvValue) = await (age, weight, height, vo2Max, avgHRV)
        
        return UserHealthProfile(
            age: ageValue,
            weightKg: weightValue,
            heightCm: heightValue,
            vo2Max: vo2MaxValue,
            averageHRV: hrvValue
        )
    }
    
    private func fetchAge() async -> Int? {
        do {
            let birthdayComponents = try healthStore.dateOfBirthComponents()
            let now = Date()
            let calendar = Calendar.current
            if let birthDate = calendar.date(from: birthdayComponents) {
                let components = calendar.dateComponents([.year], from: birthDate, to: now)
                return components.year
            }
        } catch {}
        return nil
    }
    
    private func fetchMostRecentWeight() async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return nil }
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        
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
                let kg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
                continuation.resume(returning: kg)
            }
            healthStore.execute(query)
        }
    }
    
    private func fetchHeight() async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .height) else { return nil }
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        
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
                let cm = sample.quantity.doubleValue(for: .meterUnit(with: .centi))
                continuation.resume(returning: cm)
            }
            healthStore.execute(query)
        }
    }
    
    private func fetchMostRecentVO2Max() async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .vo2Max) else { return nil }
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        
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
                let vo2 = sample.quantity.doubleValue(for: HKUnit.literUnit(with: .milli).unitDivided(by: .gramUnit(with: .kilo).unitMultiplied(by: .minute())))
                continuation.resume(returning: vo2)
            }
            healthStore.execute(query)
        }
    }
    
    private func fetchAverageHRV() async -> Double? {
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
}

// MARK: - Supporting Types

struct UserHealthProfile {
    let age: Int?
    let weightKg: Double?
    let heightCm: Double?
    let vo2Max: Double?
    let averageHRV: Double?
    
    var hasData: Bool {
        age != nil || weightKg != nil || heightCm != nil || vo2Max != nil || averageHRV != nil
    }
}

enum HealthKitError: Error {
    case notAvailable
    case authorizationDenied
    case dataUnavailable
}
