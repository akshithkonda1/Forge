import Foundation
import HealthKit

// MARK: - Health Data Snapshot

struct HealthDataSnapshot: Identifiable {
    let id = UUID()
    let restingHeartRate: Int?
    let activeCalories: Int?
    let steps: Int?
    let sleepHours: Double?
    let hrv: Double?
    let vo2Max: Double?
    let workoutCount: Int?
    let lastWorkoutDate: Date?
    let timestamp: Date = Date()
    
    var hasData: Bool {
        restingHeartRate != nil || activeCalories != nil || steps != nil || sleepHours != nil || hrv != nil || vo2Max != nil
    }
}

// MARK: - Daily Health Stats (Extended for Lifestyle View)

struct DailyHealthStats: Identifiable, Codable {
    var id = UUID()
    let date: Date
    let steps: Int
    let activeCalories: Int
    let basalCalories: Int
    let totalCalories: Int
    let distanceWalkingRunningMeters: Double
    let distanceCyclingMeters: Double
    let distanceSwimmingMeters: Double
    let flightsClimbed: Double
    let exerciseMinutes: Double
    let standMinutes: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let fiber: Double
    let sugar: Double
    let sodium: Double
    let caffeine: Double
    let water: Double // glasses
    let sleepHours: Double
    let restingHeartRate: Double
    let walkingHeartRateAverage: Double
    let heartRateRecoveryOneMinute: Double
    let hrv: Double // Heart Rate Variability in ms
    let vo2Max: Double
    let oxygenSaturation: Double
    let respiratoryRate: Double
    let bodyTemperature: Double
    let bloodPressureSystolic: Double
    let bloodPressureDiastolic: Double
    let walkingSpeed: Double
    let runningSpeed: Double
    let cyclingSpeed: Double
    let runningPower: Double
    let cyclingPower: Double
    
    static var `default`: DailyHealthStats {
        DailyHealthStats(
            date: Date(),
            steps: 0,
            activeCalories: 0,
            basalCalories: 0,
            totalCalories: 0,
            distanceWalkingRunningMeters: 0,
            distanceCyclingMeters: 0,
            distanceSwimmingMeters: 0,
            flightsClimbed: 0,
            exerciseMinutes: 0,
            standMinutes: 0,
            protein: 0,
            carbs: 0,
            fat: 0,
            fiber: 0,
            sugar: 0,
            sodium: 0,
            caffeine: 0,
            water: 0,
            sleepHours: 0,
            restingHeartRate: 0,
            walkingHeartRateAverage: 0,
            heartRateRecoveryOneMinute: 0,
            hrv: 0,
            vo2Max: 0,
            oxygenSaturation: 0,
            respiratoryRate: 0,
            bodyTemperature: 0,
            bloodPressureSystolic: 0,
            bloodPressureDiastolic: 0,
            walkingSpeed: 0,
            runningSpeed: 0,
            cyclingSpeed: 0,
            runningPower: 0,
            cyclingPower: 0
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

// MARK: - Cycle Health Summary

struct CycleHealthSummary: Identifiable, Codable {
    var id = UUID()
    let lastPeriodStart: Date?
    let currentCycleDay: Int?
    let periodDaysInLast90: Int
    let lastFlowLevel: String?
    let hasRecentSpotting: Bool
    let hasCycleDeviation: Bool
    let latestOvulationTestResult: String?
    let latestProgesteroneTestResult: String?
    let latestPregnancyTestResult: String?
    let latestBasalBodyTemperature: Double?
    let menopausalState: String?
    let sexualActivityCountLast90Days: Int
    let lastSexualActivityDate: Date?
    let lastSexualActivityProtectionUsed: Bool?
    let isPregnant: Bool
    let isLactating: Bool
    let hasData: Bool
}

// MARK: - Clinical Records Summary

struct ClinicalRecordsSummary: Identifiable, Codable {
    var id = UUID()
    let totalRecordCount: Int
    let recordCountsByType: [String: Int]
    let recentRecordNames: [String]
    let connectedSourceNames: [String]
    let hasData: Bool
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
    @Published var authorizationErrorMessage: String?
    
    private let authorizationRequestedKey = "HealthKitAuthorizationRequested"
    private let expandedAuthorizationRequestedKey = "HealthKitExpandedAuthorizationRequested"
    private let clinicalAuthorizationRequestedKey = "HealthKitClinicalAuthorizationRequested"
    
    // Published health data for real-time updates
    @Published var todayStats: DailyHealthStats?
    @Published var weeklyTrends: [WeeklyHealthTrend] = []
    @Published var cycleSummary: CycleHealthSummary?
    @Published var clinicalSummary: ClinicalRecordsSummary?
    
    // In-memory storage for nutrition data (could be persisted to UserDefaults or Core Data)
    private var todayMeals: [MealLog] = []
    private var todayWaterIntake: Double = 0 // in ounces
    
    // Types requested by the primary onboarding flow. Keep this prompt focused and reliable.
    private let coreReadTypes: Set<HKObjectType> = [
        HKCharacteristicType(.dateOfBirth),
        HKCharacteristicType(.biologicalSex),
        HKCharacteristicType(.bloodType),
        HKCharacteristicType(.activityMoveMode),
        HKQuantityType(.heartRate),
        HKQuantityType(.restingHeartRate),
        HKQuantityType(.walkingHeartRateAverage),
        HKQuantityType(.heartRateRecoveryOneMinute),
        HKQuantityType(.heartRateVariabilitySDNN),
        HKQuantityType(.oxygenSaturation),
        HKQuantityType(.respiratoryRate),
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.basalEnergyBurned),
        HKQuantityType(.appleExerciseTime),
        HKQuantityType(.appleStandTime),
        HKQuantityType(.stepCount),
        HKQuantityType(.flightsClimbed),
        HKQuantityType(.distanceWalkingRunning),
        HKQuantityType(.distanceCycling),
        HKQuantityType(.distanceSwimming),
        HKQuantityType(.swimmingStrokeCount),
        HKQuantityType(.walkingSpeed),
        HKQuantityType(.walkingStepLength),
        HKQuantityType(.runningSpeed),
        HKQuantityType(.runningPower),
        HKQuantityType(.runningStrideLength),
        HKQuantityType(.cyclingSpeed),
        HKQuantityType(.cyclingPower),
        HKQuantityType(.vo2Max),
        HKCategoryType(.sleepAnalysis),
        HKCategoryType(.mindfulSession),
        HKCategoryType(.highHeartRateEvent),
        HKCategoryType(.lowHeartRateEvent),
        HKCategoryType(.irregularHeartRhythmEvent),
        HKQuantityType(.bodyMass),
        HKQuantityType(.leanBodyMass),
        HKQuantityType(.bodyFatPercentage),
        HKQuantityType(.height),
        HKQuantityType(.bodyMassIndex),
        HKQuantityType(.dietaryProtein),
        HKQuantityType(.dietaryCarbohydrates),
        HKQuantityType(.dietaryFatTotal),
        HKQuantityType(.dietaryFiber),
        HKQuantityType(.dietarySugar),
        HKQuantityType(.dietarySodium),
        HKQuantityType(.dietaryCaffeine),
        HKQuantityType(.dietaryEnergyConsumed),
        HKQuantityType(.dietaryWater),
        HKWorkoutType.workoutType(),
        HKObjectType.activitySummaryType()
    ]

    // Sensitive lifestyle types stay opt-in so the first HealthKit connection stays stable.
    private let sensitiveLifestyleReadTypes: Set<HKObjectType> = [
        HKQuantityType(.bodyTemperature),
        HKQuantityType(.bloodPressureSystolic),
        HKQuantityType(.bloodPressureDiastolic),
        HKCategoryType(.menstrualFlow),
        HKCategoryType(.intermenstrualBleeding),
        HKCategoryType(.infrequentMenstrualCycles),
        HKCategoryType(.irregularMenstrualCycles),
        HKCategoryType(.persistentIntermenstrualBleeding),
        HKCategoryType(.prolongedMenstrualPeriods),
        HKQuantityType(.basalBodyTemperature),
        HKCategoryType(.cervicalMucusQuality),
        HKCategoryType(.ovulationTestResult),
        HKCategoryType(.progesteroneTestResult),
        HKCategoryType(.sexualActivity),
        HKCategoryType(.contraceptive),
        HKCategoryType(.pregnancy),
        HKCategoryType(.pregnancyTestResult),
        HKCategoryType(.lactation)
    ]

    // Types to read for coaching, recovery, profile prefill, nutrition, clinical context, and activity trends.
    private var readTypes: Set<HKObjectType> {
        coreReadTypes
            .union(sensitiveLifestyleReadTypes)
            .union(HealthKitManager.clinicalRecordTypes)
    }
    
    private static let clinicalRecordIdentifiers: [HKClinicalTypeIdentifier] = [
        .allergyRecord,
        .clinicalNoteRecord,
        .conditionRecord,
        .immunizationRecord,
        .labResultRecord,
        .medicationRecord,
        .procedureRecord,
        .vitalSignRecord,
        .coverageRecord
    ]
    
    private static let clinicalRecordTypes: Set<HKObjectType> = Set(
        clinicalRecordIdentifiers.compactMap { HKObjectType.clinicalType(forIdentifier: $0) }
    )
    
    // Types to write during the primary onboarding prompt.
    private let coreWriteTypes: Set<HKSampleType> = [
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.dietaryProtein),
        HKQuantityType(.dietaryCarbohydrates),
        HKQuantityType(.dietaryFatTotal),
        HKQuantityType(.dietaryEnergyConsumed),
        HKQuantityType(.dietaryWater),
        HKWorkoutType.workoutType()
    ]

    // Expanded write types for sensitive lifestyle logging.
    private var writeTypes: Set<HKSampleType> {
        coreWriteTypes.union([HKCategoryType(.sexualActivity)])
    }
    
    private init() {}
    
    // MARK: - Authorization
    
    func isHealthDataAvailable() -> Bool {
        return HKHealthStore.isHealthDataAvailable()
    }
    
    func checkAuthorizationStatus() async -> Bool {
        guard isHealthDataAvailable() else {
            isAuthorized = false
            return false
        }
        
        let hasRequestedAuthorization = UserDefaults.standard.bool(forKey: authorizationRequestedKey)
        let canWriteAnyRequestedType = writeTypes.contains { type in
            healthStore.authorizationStatus(for: type) == .sharingAuthorized
        }
        
        // HealthKit intentionally hides read authorization status. Once the request has been
        // presented, read queries safely return empty results for denied types.
        isAuthorized = hasRequestedAuthorization || canWriteAnyRequestedType
        return isAuthorized
    }
    
    func requestAuthorization() async throws {
        try await requestHealthKitAuthorization(
            toShare: coreWriteTypes,
            read: coreReadTypes,
            requestedKey: authorizationRequestedKey
        )
    }

    func requestExpandedLifestyleAuthorization() async throws {
        try await requestHealthKitAuthorization(
            toShare: writeTypes,
            read: readTypes.subtracting(HealthKitManager.clinicalRecordTypes),
            requestedKey: expandedAuthorizationRequestedKey
        )
    }

    func requestClinicalRecordsAuthorization() async throws {
        try await requestHealthKitAuthorization(
            toShare: [],
            read: HealthKitManager.clinicalRecordTypes,
            requestedKey: clinicalAuthorizationRequestedKey
        )
    }

    private func requestHealthKitAuthorization(
        toShare shareTypes: Set<HKSampleType>,
        read readTypes: Set<HKObjectType>,
        requestedKey: String
    ) async throws {
        guard isHealthDataAvailable() else {
            authorizationErrorMessage = "Health data is not available on this device."
            throw HealthKitError.notAvailable
        }
        
        do {
            try await healthStore.requestAuthorization(toShare: shareTypes, read: readTypes)
            UserDefaults.standard.set(true, forKey: requestedKey)
            if requestedKey != authorizationRequestedKey {
                UserDefaults.standard.set(true, forKey: authorizationRequestedKey)
            }
            authorizationErrorMessage = nil
            isAuthorized = true
        } catch {
            authorizationErrorMessage = error.localizedDescription
            isAuthorized = false
            throw error
        }
    }
    
    // MARK: - Fetch Recent Snapshot
    
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
        
        // Calculate total calories from meals
        let loggedCalories = todayMeals.reduce(0) { $0 + Int($1.calories) }
        let protein = todayMeals.reduce(0.0) { $0 + $1.protein } + (performanceValues.5?.protein ?? 0)
        let carbs = todayMeals.reduce(0.0) { $0 + $1.carbs } + (performanceValues.5?.carbs ?? 0)
        let fat = todayMeals.reduce(0.0) { $0 + $1.fat } + (performanceValues.5?.fat ?? 0)
        
        todayStats = DailyHealthStats(
            date: Date(),
            steps: activityValues.0 ?? 0,
            activeCalories: activityValues.1 ?? 0,
            basalCalories: Int(activityValues.2 ?? 0),
            totalCalories: loggedCalories + (performanceValues.5?.calories ?? 0),
            distanceWalkingRunningMeters: activityValues.3 ?? 0,
            distanceCyclingMeters: activityValues.4 ?? 0,
            distanceSwimmingMeters: activityValues.5 ?? 0,
            flightsClimbed: activityValues.6 ?? 0,
            exerciseMinutes: activityValues.7 ?? 0,
            standMinutes: activityValues.8 ?? 0,
            protein: protein,
            carbs: carbs,
            fat: fat,
            fiber: performanceValues.5?.fiber ?? 0,
            sugar: performanceValues.5?.sugar ?? 0,
            sodium: performanceValues.5?.sodium ?? 0,
            caffeine: performanceValues.5?.caffeine ?? 0,
            water: (performanceValues.6 ?? 0) / 8.0 + todayWaterIntake / 8.0, // Convert ounces to glasses
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
        return await fetchDietaryValue(.dietaryWater, unit: .fluidOunceUS(), from: startOfDay, to: now)
    }
    
    private func fetchDietaryValue(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async -> Double? {
        await fetchCumulativeQuantity(identifier, unit: unit, from: start, to: end)
    }
    
    private func fetchCumulativeQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async -> Double? {
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
                continuation.resume(returning: sum.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }
    
    private func fetchAverageQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, statistics, _ in
                guard let average = statistics?.averageQuantity() else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: average.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }
    
    private func fetchMostRecentQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
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
                continuation.resume(returning: sample.quantity.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }
    
    private func fetchCategorySamples(_ identifier: HKCategoryTypeIdentifier, predicate: NSPredicate?, limit: Int) async -> [HKCategorySample] {
        let type = HKCategoryType(identifier)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: limit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            healthStore.execute(query)
        }
    }
    
    private func fetchMostRecentCategoryValue(_ identifier: HKCategoryTypeIdentifier) async -> String? {
        let samples = await fetchCategorySamples(identifier, predicate: nil, limit: 1)
        guard let value = samples.first?.value else { return nil }
        return categoryLabel(identifier: identifier, rawValue: value)
    }
    
    private func categoryLabel(identifier: HKCategoryTypeIdentifier, rawValue: Int) -> String? {
        switch identifier {
        case .menstrualFlow:
            return menstrualFlowLabel(rawValue: rawValue)
        case .ovulationTestResult:
            guard let value = HKCategoryValueOvulationTestResult(rawValue: rawValue) else { return nil }
            switch value {
            case .negative: return "Negative"
            case .luteinizingHormoneSurge: return "LH Surge"
            case .indeterminate: return "Indeterminate"
            case .estrogenSurge: return "Estrogen Surge"
            case .positive: return "Positive"
            @unknown default: return nil
            }
        case .pregnancyTestResult:
            guard let value = HKCategoryValuePregnancyTestResult(rawValue: rawValue) else { return nil }
            switch value {
            case .negative: return "Negative"
            case .positive: return "Positive"
            case .indeterminate: return "Indeterminate"
            @unknown default: return nil
            }
        case .progesteroneTestResult:
            guard let value = HKCategoryValueProgesteroneTestResult(rawValue: rawValue) else { return nil }
            switch value {
            case .negative: return "Negative"
            case .positive: return "Positive"
            case .indeterminate: return "Indeterminate"
            @unknown default: return nil
            }
        default:
            return nil
        }
    }
    
    private func menstrualFlowLabel(rawValue: Int) -> String? {
        guard let value = HKCategoryValueMenstrualFlow(rawValue: rawValue) else { return nil }
        switch value {
        case .unspecified: return "Unspecified"
        case .none: return "None"
        case .light: return "Light"
        case .medium: return "Medium"
        case .heavy: return "Heavy"
        @unknown default: return nil
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
    
    // MARK: - Clinical Records
    
    func fetchClinicalRecordsSummary() async -> ClinicalRecordsSummary {
        let recordBuckets = await withTaskGroup(of: (String, [HKClinicalRecord]).self) { group in
            for identifier in Self.clinicalRecordIdentifiers {
                group.addTask { [healthStore] in
                    guard let type = HKObjectType.clinicalType(forIdentifier: identifier) else {
                        return (identifier.rawValue, [])
                    }
                    let records = await Self.fetchClinicalRecords(type: type, healthStore: healthStore)
                    return (identifier.rawValue, records)
                }
            }
            
            var buckets: [(String, [HKClinicalRecord])] = []
            for await bucket in group {
                buckets.append(bucket)
            }
            return buckets
        }
        
        let allRecords = recordBuckets.flatMap { $0.1 }
        let counts = Dictionary(uniqueKeysWithValues: recordBuckets.map { ($0.0, $0.1.count) })
        let recentNames = allRecords
            .sorted { $0.endDate > $1.endDate }
            .prefix(8)
            .map { $0.displayName }
        let sourceNames = Set(allRecords.map { $0.sourceRevision.source.name }).sorted()
        
        let summary = ClinicalRecordsSummary(
            totalRecordCount: allRecords.count,
            recordCountsByType: counts,
            recentRecordNames: Array(recentNames),
            connectedSourceNames: sourceNames,
            hasData: !allRecords.isEmpty
        )
        clinicalSummary = summary
        return summary
    }
    
    private nonisolated static func fetchClinicalRecords(type: HKClinicalType, healthStore: HKHealthStore) async -> [HKClinicalRecord] {
        await withCheckedContinuation { continuation in
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 20,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKClinicalRecord]) ?? [])
            }
            healthStore.execute(query)
        }
    }
    
    // MARK: - Cycle Health
    
    func fetchCycleSummary() async -> CycleHealthSummary {
        let calendar = Calendar.current
        let now = Date()
        let ninetyDaysAgo = calendar.date(byAdding: .day, value: -90, to: now) ?? now
        let predicate = HKQuery.predicateForSamples(withStart: ninetyDaysAgo, end: now, options: .strictStartDate)
        
        async let flowSamples = fetchCategorySamples(.menstrualFlow, predicate: predicate, limit: HKObjectQueryNoLimit)
        async let spottingSamples = fetchCategorySamples(.intermenstrualBleeding, predicate: predicate, limit: HKObjectQueryNoLimit)
        async let infrequentCycles = fetchCategorySamples(.infrequentMenstrualCycles, predicate: predicate, limit: 1)
        async let irregularCycles = fetchCategorySamples(.irregularMenstrualCycles, predicate: predicate, limit: 1)
        async let persistentSpotting = fetchCategorySamples(.persistentIntermenstrualBleeding, predicate: predicate, limit: 1)
        async let prolongedPeriods = fetchCategorySamples(.prolongedMenstrualPeriods, predicate: predicate, limit: 1)
        async let ovulationResult = fetchMostRecentCategoryValue(.ovulationTestResult)
        async let progesteroneResult = fetchMostRecentCategoryValue(.progesteroneTestResult)
        async let pregnancyResult = fetchMostRecentCategoryValue(.pregnancyTestResult)
        async let basalTemperature = fetchMostRecentQuantity(.basalBodyTemperature, unit: .degreeFahrenheit())
        async let sexualActivitySamples = fetchCategorySamples(.sexualActivity, predicate: predicate, limit: HKObjectQueryNoLimit)
        async let pregnancySamples = fetchCategorySamples(.pregnancy, predicate: predicate, limit: 1)
        async let lactationSamples = fetchCategorySamples(.lactation, predicate: predicate, limit: 1)
        
        let flow = await flowSamples
        let spotting = await spottingSamples
        let cycleDeviationValues = await (infrequentCycles, irregularCycles, persistentSpotting, prolongedPeriods)
        let reproductiveValues = await (ovulationResult, progesteroneResult, pregnancyResult, basalTemperature, sexualActivitySamples, pregnancySamples, lactationSamples)
        
        let periodSamples = flow.filter { sample in
            guard let value = HKCategoryValueMenstrualFlow(rawValue: sample.value) else { return false }
            return value != .none
        }
        let cycleStart = periodSamples.first { sample in
            sample.metadata?[HKMetadataKeyMenstrualCycleStart] as? Bool == true
        }?.startDate ?? periodSamples.first?.startDate
        let currentCycleDay = cycleStart.map { max(calendar.dateComponents([.day], from: $0, to: now).day ?? 0, 0) + 1 }
        let lastFlowLevel = periodSamples.first.flatMap { menstrualFlowLabel(rawValue: $0.value) }
        let sexualActivity = reproductiveValues.4
        let lastSexualActivity = sexualActivity.first
        let hasCycleDeviation = !cycleDeviationValues.0.isEmpty || !cycleDeviationValues.1.isEmpty || !cycleDeviationValues.2.isEmpty || !cycleDeviationValues.3.isEmpty
        let hasData = !flow.isEmpty || !spotting.isEmpty || hasCycleDeviation || reproductiveValues.0 != nil || reproductiveValues.1 != nil || reproductiveValues.2 != nil || reproductiveValues.3 != nil || !sexualActivity.isEmpty || !reproductiveValues.5.isEmpty || !reproductiveValues.6.isEmpty
        
        let summary = CycleHealthSummary(
            lastPeriodStart: cycleStart,
            currentCycleDay: currentCycleDay,
            periodDaysInLast90: periodSamples.count,
            lastFlowLevel: lastFlowLevel,
            hasRecentSpotting: !spotting.isEmpty,
            hasCycleDeviation: hasCycleDeviation,
            latestOvulationTestResult: reproductiveValues.0,
            latestProgesteroneTestResult: reproductiveValues.1,
            latestPregnancyTestResult: reproductiveValues.2,
            latestBasalBodyTemperature: reproductiveValues.3,
            menopausalState: nil,
            sexualActivityCountLast90Days: sexualActivity.count,
            lastSexualActivityDate: lastSexualActivity?.startDate,
            lastSexualActivityProtectionUsed: lastSexualActivity?.metadata?[HKMetadataKeySexualActivityProtectionUsed] as? Bool,
            isPregnant: !reproductiveValues.5.isEmpty,
            isLactating: !reproductiveValues.6.isEmpty,
            hasData: hasData
        )
        cycleSummary = summary
        return summary
    }
    
    // MARK: - Detailed Profile Data
    
    func fetchUserProfile() async -> UserHealthProfile? {
        async let age = fetchAge()
        async let biologicalSex = fetchBiologicalSex()
        async let bloodType = fetchBloodType()
        async let weight = fetchMostRecentWeight()
        async let height = fetchHeight()
        async let bmi = fetchMostRecentQuantity(.bodyMassIndex, unit: .count())
        async let leanMass = fetchMostRecentQuantity(.leanBodyMass, unit: .gramUnit(with: .kilo))
        async let bodyFat = fetchMostRecentQuantity(.bodyFatPercentage, unit: .percent())
        async let restingHR = fetchMostRecentRestingHeartRate()
        async let vo2Max = fetchMostRecentVO2Max()
        async let avgHRV = fetchAverageHRV()
        
        let profileValues = await (age, biologicalSex, bloodType, weight, height, bmi, leanMass, bodyFat, restingHR, vo2Max, avgHRV)
        let expandedRequested = UserDefaults.standard.bool(forKey: expandedAuthorizationRequestedKey)
        let clinicalRequested = UserDefaults.standard.bool(forKey: clinicalAuthorizationRequestedKey)
        let cycle = expandedRequested ? await fetchCycleSummary() : nil
        let clinical = clinicalRequested ? await fetchClinicalRecordsSummary() : nil
        
        return UserHealthProfile(
            age: profileValues.0,
            biologicalSex: profileValues.1,
            bloodType: profileValues.2,
            weightKg: profileValues.3,
            heightCm: profileValues.4,
            bodyMassIndex: profileValues.5,
            leanBodyMassKg: profileValues.6,
            bodyFatPercentage: profileValues.7,
            restingHeartRate: profileValues.8,
            vo2Max: profileValues.9,
            averageHRV: profileValues.10,
            cycleSummary: cycle?.hasData == true ? cycle : nil,
            clinicalSummary: clinical?.hasData == true ? clinical : nil
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
    
    private func fetchBiologicalSex() async -> String? {
        do {
            switch try healthStore.biologicalSex().biologicalSex {
            case .female: return "Female"
            case .male: return "Male"
            case .other: return "Other"
            case .notSet: return nil
            @unknown default: return nil
            }
        } catch {
            return nil
        }
    }
    
    private func fetchBloodType() async -> String? {
        do {
            switch try healthStore.bloodType().bloodType {
            case .aPositive: return "A+"
            case .aNegative: return "A-"
            case .bPositive: return "B+"
            case .bNegative: return "B-"
            case .abPositive: return "AB+"
            case .abNegative: return "AB-"
            case .oPositive: return "O+"
            case .oNegative: return "O-"
            case .notSet: return nil
            @unknown default: return nil
            }
        } catch {
            return nil
        }
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
                    return SleepNightSample(
                        date: date,
                        totalHours: totalHours,
                        deepMinutes: Int(deep / 60),
                        remMinutes: Int(rem / 60),
                        lightMinutes: Int(light / 60),
                        awakeMinutes: Int(awake / 60)
                    )
                }
                continuation.resume(returning: nights.sorted { $0.date > $1.date })
            }
            healthStore.execute(query)
        }
    }
}

struct SleepNightSample {
    let date: String
    let totalHours: Double
    let deepMinutes: Int
    let remMinutes: Int
    let lightMinutes: Int
    let awakeMinutes: Int
}

// MARK: - Supporting Types

struct UserHealthProfile {
    let age: Int?
    let biologicalSex: String?
    let bloodType: String?
    let weightKg: Double?
    let heightCm: Double?
    let bodyMassIndex: Double?
    let leanBodyMassKg: Double?
    let bodyFatPercentage: Double?
    let restingHeartRate: Int?
    let vo2Max: Double?
    let averageHRV: Double?
    let cycleSummary: CycleHealthSummary?
    let clinicalSummary: ClinicalRecordsSummary?
    
    var hasData: Bool {
        age != nil || biologicalSex != nil || bloodType != nil || weightKg != nil || heightCm != nil || bodyMassIndex != nil || leanBodyMassKg != nil || bodyFatPercentage != nil || restingHeartRate != nil || vo2Max != nil || averageHRV != nil || cycleSummary?.hasData == true || clinicalSummary?.hasData == true
    }
}

enum HealthKitError: Error {
    case notAvailable
    case authorizationDenied
    case dataUnavailable
}
