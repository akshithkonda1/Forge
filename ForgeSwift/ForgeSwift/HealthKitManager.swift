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

// MARK: - HealthKit Manager

@MainActor
class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()
    
    private let healthStore = HKHealthStore()
    @Published var isAuthorized = false
    
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
        HKWorkoutType.workoutType()
    ]
    
    // Types to write (for tracking workouts created in the app)
    private let writeTypes: Set<HKSampleType> = [
        HKQuantityType(.activeEnergyBurned),
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
        let query = HKSampleQuery(
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
