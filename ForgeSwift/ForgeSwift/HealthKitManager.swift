import Foundation
import HealthKit
import ForgeCore

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
    let water: Double // glasses (display). Source of truth is milliliters from HealthKit.
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

struct MindfulDay: Identifiable, Codable {
    var id = UUID()
    let date: Date
    let minutes: Double
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

// MARK: - Structured Health records (allergies, meds, conditions, shots, labs, procedures)

enum StructuredHealthKind: String, CaseIterable, Codable, Identifiable {
    case allergy, medication, condition, immunization, lab, procedure

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allergy: return "Allergies"
        case .medication: return "Medications"
        case .condition: return "Conditions"
        case .immunization: return "Immunizations"
        case .lab: return "Lab results"
        case .procedure: return "Procedures"
        }
    }

    var symbol: String {
        switch self {
        case .allergy: return "exclamationmark.triangle.fill"
        case .medication: return "pills.fill"
        case .condition: return "heart.text.square.fill"
        case .immunization: return "cross.case.fill"
        case .lab: return "testtube.2"
        case .procedure: return "stethoscope"
        }
    }

    init?(identifier: HKClinicalTypeIdentifier) {
        switch identifier {
        case .allergyRecord: self = .allergy
        case .medicationRecord: self = .medication
        case .conditionRecord: self = .condition
        case .immunizationRecord: self = .immunization
        case .labResultRecord: self = .lab
        case .procedureRecord: self = .procedure
        default: return nil
        }
    }
}

struct StructuredHealthItem: Identifiable, Codable, Hashable {
    let id: String
    let kind: StructuredHealthKind
    let name: String
    let date: Date
    let source: String
}

struct ClinicalRecordsSummary: Identifiable, Codable {
    var id = UUID()
    let items: [StructuredHealthItem]
    let totalRecordCount: Int
    let recordCountsByType: [String: Int]
    let recentRecordNames: [String]
    let connectedSourceNames: [String]
    let hasData: Bool

    func items(for kind: StructuredHealthKind) -> [StructuredHealthItem] {
        items.filter { $0.kind == kind }
    }

    /// Names only, capped so the prompt stays small.
    func ariaDomain(limit: Int = 12) -> ARIAContextPayload.ClinicalDataDomain {
        func names(_ kind: StructuredHealthKind) -> [String] {
            Array(items(for: kind).map(\.name).prefix(limit))
        }
        return ARIAContextPayload.ClinicalDataDomain(
            allergies: names(.allergy),
            medications: names(.medication),
            conditions: names(.condition),
            immunizations: names(.immunization),
            labResults: names(.lab),
            procedures: names(.procedure)
        )
    }

    /// Compact lines for the local trainer path. Not persisted.
    func ariaConstraintLines(limit: Int = 8) -> [String] {
        StructuredHealthKind.allCases.flatMap { kind in
            items(for: kind).prefix(limit).map { "clinical:\(kind.rawValue):\($0.name)" }
        }
    }
}

// MARK: - Meal Log

struct MealLog: Identifiable, Codable {
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

// MARK: - Hydration samples (HealthKit is the ledger)

struct WaterLog: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let milliliters: Double
    let sourceName: String
    let isForge: Bool
}

struct DailyWaterTotal: Identifiable, Equatable {
    var id: Date { date }
    let date: Date
    let milliliters: Double
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
    @Published var mindfulTrend: [MindfulDay] = []
    @Published var cycleSummary: CycleHealthSummary?
    @Published var clinicalSummary: ClinicalRecordsSummary?
    
    @Published private(set) var loggedMeals: [MealLog] = []
    /// Today's dietary-water samples, newest first. HealthKit is the ledger —
    /// Forge-authored drinks and Watch/other-app drinks live in the same list.
    @Published private(set) var todayWaterLogs: [WaterLog] = []
    @Published private(set) var weeklyWaterMilliliters: [DailyWaterTotal] = []
    @Published private(set) var todayWaterMilliliters: Double = 0

    private var observerQueries: [HKObserverQuery] = []
    private var liveRefreshTask: Task<Void, Never>?
    private var isObserving = false
    private var lastTodayStatsAt: Date?
    private var lastWeeklyTrendsAt: Date?
    private var lastMindfulTrendAt: Date?
    private var lastClinicalAt: Date?
    private static let statsTTL: TimeInterval = 60
    private static let trendTTL: TimeInterval = 180
    private static let clinicalTTL: TimeInterval = 600
    private let mealsStorageKey = "HealthKitManager.loggedMeals"
    private let mealsStorageDateKey = "HealthKitManager.loggedMealsDate"
    static let forgeWaterMetadataKey = "com.forge.hydration"
    
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

    // Types to read for coaching, recovery, profile prefill, nutrition, and activity trends.
    // Structured Health records only — never clinical notes or insurance coverage.
    private var readTypes: Set<HKObjectType> {
        coreReadTypes
            .union(sensitiveLifestyleReadTypes)
            .union(HealthKitManager.structuredHealthRecordTypes)
    }

    /// Allergies, meds, conditions, immunizations, labs, procedures.
    /// Not notes. Not coverage. Those are PHI we will not ingest.
    private static let structuredHealthRecordIdentifiers: [HKClinicalTypeIdentifier] = [
        .allergyRecord,
        .medicationRecord,
        .conditionRecord,
        .immunizationRecord,
        .labResultRecord,
        .procedureRecord,
    ]

    private static let structuredHealthRecordTypes: Set<HKObjectType> = Set(
        structuredHealthRecordIdentifiers.compactMap { HKObjectType.clinicalType(forIdentifier: $0) }
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
        coreWriteTypes.union([
            HKCategoryType(.sexualActivity),
            HKCategoryType(.mindfulSession),
            HKCategoryType(.menstrualFlow),
            HKQuantityType(.basalBodyTemperature),
        ])
    }
    
    private init() {
        loadPersistedMeals()
    }

    private func loadPersistedMeals() {
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
        if isAuthorized { startBidirectionalSync() }
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
            read: readTypes.subtracting(HealthKitManager.structuredHealthRecordTypes),
            requestedKey: expandedAuthorizationRequestedKey
        )
    }

    var hasStructuredRecordsAccess: Bool {
        UserDefaults.standard.bool(forKey: clinicalAuthorizationRequestedKey)
    }

    func requestClinicalRecordsAuthorization() async throws {
        try await requestHealthKitAuthorization(
            toShare: [],
            read: HealthKitManager.structuredHealthRecordTypes,
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
            startBidirectionalSync()
        } catch {
            authorizationErrorMessage = error.localizedDescription
            isAuthorized = false
            throw error
        }
    }

    /// Distinct HealthKit source names this phone has already seen.
    /// Feeds the device shelf so a wearable that writes to Apple Health can
    /// appear without a catalog update.
    func knownHealthSources() async -> [String] {
        guard isHealthDataAvailable() else { return [] }

        let types: [HKSampleType] = [
            HKQuantityType(.heartRate),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.dietaryWater),
            HKCategoryType(.sleepAnalysis),
            HKObjectType.workoutType(),
        ]

        var names = Set<String>()
        for type in types {
            names.formUnion(await sourceNames(for: type))
        }
        return names.sorted()
    }

    private func sourceNames(for sampleType: HKSampleType) async -> Set<String> {
        await withCheckedContinuation { continuation in
            let query = HKSourceQuery(sampleType: sampleType, samplePredicate: nil) { _, sources, _ in
                continuation.resume(returning: Set((sources ?? []).map(\.name)))
            }
            healthStore.execute(query)
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
    
    func logMeal(_ meal: MealLog) async throws {
        guard isAuthorized else { return }
        
        loggedMeals.append(meal)
        persistMeals()
        
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
        try await logWater(milliliters: HydrationEngine.milliliters(fromFluidOunces: ounces))
    }

    func logWater(milliliters: Double) async throws {
        guard isAuthorized else { throw HealthKitError.authorizationDenied }
        guard milliliters > 0 else { return }
        guard let waterType = HKQuantityType.quantityType(forIdentifier: .dietaryWater) else {
            throw HealthKitError.saveFailed
        }

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
        guard let waterType = HKQuantityType.quantityType(forIdentifier: .dietaryWater) else {
            throw HealthKitError.saveFailed
        }
        let deleted: Int = await withCheckedContinuation { continuation in
            healthStore.deleteObjects(
                of: waterType,
                predicate: HKQuery.predicateForObject(with: log.id)
            ) { success, count, _ in
                continuation.resume(returning: success ? count : 0)
            }
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
    }

    func fetchTodayWaterLogs() async {
        guard isAuthorized,
              let waterType = HKQuantityType.quantityType(forIdentifier: .dietaryWater) else {
            todayWaterLogs = []
            return
        }
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

    /// Live HealthKit → Forge. Observer queries fire when Apple Health, Watch,
    /// or another app writes a type we also write, then we re-read the ledger.
    func startBidirectionalSync() {
        guard isAuthorized, !isObserving else { return }
        isObserving = true

        let observed: [HKSampleType] = [
            HKQuantityType(.dietaryWater),
            HKQuantityType(.dietaryEnergyConsumed),
            HKQuantityType(.dietaryProtein),
            HKQuantityType(.dietaryCarbohydrates),
            HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned),
            HKCategoryType(.sleepAnalysis),
            HKWorkoutType.workoutType(),
        ]

        for type in observed {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, _ in
                Task { @MainActor in
                    self?.scheduleLiveRefresh()
                }
                completion()
            }
            healthStore.execute(query)
            observerQueries.append(query)
            healthStore.enableBackgroundDelivery(for: type, frequency: .immediate) { _, _ in }
        }
    }

    private func scheduleLiveRefresh() {
        liveRefreshTask?.cancel()
        liveRefreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await refreshHydration()
        }
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
    
    // MARK: - Structured Health records (no notes)

    func fetchClinicalRecordsSummary() async -> ClinicalRecordsSummary {
        if let lastClinicalAt, let clinicalSummary,
           Date().timeIntervalSince(lastClinicalAt) < Self.clinicalTTL {
            return clinicalSummary
        }
        let recordBuckets = await withTaskGroup(of: (StructuredHealthKind, [StructuredHealthItem]).self) { group in
            for identifier in Self.structuredHealthRecordIdentifiers {
                group.addTask { [healthStore] in
                    guard let kind = StructuredHealthKind(identifier: identifier),
                          let type = HKObjectType.clinicalType(forIdentifier: identifier) else {
                        return (.allergy, [])
                    }
                    let records = await Self.fetchClinicalRecords(type: type, healthStore: healthStore)
                    let items = records.map { record in
                        StructuredHealthItem(
                            id: record.uuid.uuidString,
                            kind: kind,
                            name: record.displayName,
                            date: record.endDate,
                            source: record.sourceRevision.source.name
                        )
                    }
                    return (kind, items)
                }
            }

            var buckets: [(StructuredHealthKind, [StructuredHealthItem])] = []
            for await bucket in group {
                buckets.append(bucket)
            }
            return buckets
        }

        let items = recordBuckets.flatMap(\.1).sorted { $0.date > $1.date }
        let counts = Dictionary(uniqueKeysWithValues: recordBuckets.map { ($0.0.rawValue, $0.1.count) })
        let summary = ClinicalRecordsSummary(
            items: items,
            totalRecordCount: items.count,
            recordCountsByType: counts,
            recentRecordNames: Array(items.prefix(8).map(\.name)),
            connectedSourceNames: Array(Set(items.map(\.source))).sorted(),
            hasData: !items.isEmpty
        )
        clinicalSummary = summary
        lastClinicalAt = Date()
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

    /// Full multi-signal menstrual bundle for the high-accuracy cycle engine.
    func fetchMenstrualHealthBundle(days: Int = 400) async -> MenstrualHealthKitBundle {
        guard HKHealthStore.isHealthDataAvailable() else {
            return MenstrualHealthKitBundle(flowSamples: [], bbtSamples: [], ovulationTests: [], mucusSamples: [])
        }
        let calendar = Calendar.current
        let end = Date()
        let start = calendar.date(byAdding: .day, value: -days, to: end) ?? end
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        async let flowSamples = fetchCategorySamples(.menstrualFlow, predicate: predicate, limit: HKObjectQueryNoLimit)
        async let mucusSamples = fetchCategorySamples(.cervicalMucusQuality, predicate: predicate, limit: HKObjectQueryNoLimit)
        async let ovuSamples = fetchCategorySamples(.ovulationTestResult, predicate: predicate, limit: HKObjectQueryNoLimit)
        async let bbtSamples = fetchQuantitySamples(.basalBodyTemperature, unit: .degreeCelsius(), predicate: predicate, limit: HKObjectQueryNoLimit)

        let flow = await flowSamples
        let mucus = await mucusSamples
        let ovu = await ovuSamples
        let bbt = await bbtSamples

        let flowMapped: [(date: Date, flow: MenstrualFlowLevel)] = flow.compactMap { sample in
            guard let value = HKCategoryValueMenstrualFlow(rawValue: sample.value) else { return nil }
            let level: MenstrualFlowLevel
            switch value {
            case .none: level = .none
            case .light: level = .light
            case .medium: level = .medium
            case .heavy: level = .heavy
            case .unspecified: level = .unspecified
            @unknown default: level = .unspecified
            }
            // Skip pure none samples unless marked cycle start
            if level == .none { return nil }
            return (sample.startDate, level)
        }

        let mucusMapped: [(date: Date, quality: CervicalMucusQuality)] = mucus.compactMap { sample in
            guard let value = HKCategoryValueCervicalMucusQuality(rawValue: sample.value) else { return nil }
            let q: CervicalMucusQuality
            switch value {
            case .dry: q = .dry
            case .sticky: q = .sticky
            case .creamy: q = .creamy
            case .watery: q = .watery
            case .eggWhite: q = .eggWhite
            @unknown default: q = .unknown
            }
            return (sample.startDate, q)
        }

        let ovuMapped: [(date: Date, result: OvulationTestResult)] = ovu.compactMap { sample in
            guard let value = HKCategoryValueOvulationTestResult(rawValue: sample.value) else { return nil }
            let r: OvulationTestResult
            switch value {
            case .negative: r = .negative
            case .luteinizingHormoneSurge: r = .lhSurge
            case .indeterminate: r = .indeterminate
            case .estrogenSurge: r = .estrogenSurge
            case .positive: r = .positive
            @unknown default: r = .unknown
            }
            return (sample.startDate, r)
        }

        let bbtMapped: [(date: Date, celsius: Double)] = bbt.map { ($0.date, $0.value) }

        return MenstrualHealthKitBundle(
            flowSamples: flowMapped,
            bbtSamples: bbtMapped,
            ovulationTests: ovuMapped,
            mucusSamples: mucusMapped
        )
    }

    /// Writes one day of menstrual flow to Apple Health.
    ///
    /// `isCycleStart` must be true only for the *first* bleeding day of an episode.
    /// Marking every bleeding day as a cycle start told Health that a 5-day period was
    /// five separate one-day cycles, which wrecked Health's own cycle predictions.
    func saveMenstrualFlow(dayKey: String, flow: MenstrualFlowLevel, isCycleStart: Bool = false) async {
        guard isAuthorized,
              let dayStart = CycleDayKey.startOfDay(from: dayKey) else { return }
        let type = HKCategoryType(.menstrualFlow)
        let value: HKCategoryValueMenstrualFlow
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
            HKMetadataKeyMenstrualCycleStart: isCycleStart
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
            // Best-effort write; logging stays local even if HK write fails.
            print("Menstrual flow HK save failed: \(error.localizedDescription)")
        }
    }

    private func fetchQuantitySamples(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        predicate: NSPredicate?,
        limit: Int
    ) async -> [(date: Date, value: Double)] {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return [] }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: limit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                let mapped = (samples as? [HKQuantitySample] ?? []).map {
                    (date: $0.startDate, value: $0.quantity.doubleValue(for: unit))
                }
                continuation.resume(returning: mapped)
            }
            healthStore.execute(query)
        }
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

struct SleepNightSample {
    let date: String
    let totalHours: Double
    let deepMinutes: Int
    let remMinutes: Int
    let lightMinutes: Int
    let awakeMinutes: Int
    /// Bounds of the asleep stretch. Nil when a night arrived as a bare
    /// duration with no stage samples to bound — some third-party writers do
    /// exactly that.
    var onset: Date? = nil
    var wake: Date? = nil
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
    case saveFailed
}
