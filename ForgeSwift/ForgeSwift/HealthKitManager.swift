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
    case allergy, medication, condition, immunization, lab, procedure, vital

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allergy: return "Allergies"
        case .medication: return "Medications"
        case .condition: return "Conditions"
        case .immunization: return "Immunizations"
        case .lab: return "Lab results"
        case .procedure: return "Procedures"
        case .vital: return "Clinical vitals"
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
        case .vital: return "waveform.path.ecg"
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
        default:
            if identifier.rawValue == "HKClinicalTypeIdentifierVitalSignRecord" {
                self = .vital
            } else {
                return nil
            }
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

    static let empty = ClinicalRecordsSummary(
        items: [],
        totalRecordCount: 0,
        recordCountsByType: [:],
        recentRecordNames: [],
        connectedSourceNames: [],
        hasData: false
    )

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
            procedures: names(.procedure),
            vitalSigns: names(.vital)
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
    
    let healthStore = HKHealthStore()
    @Published var isAuthorized = false
    @Published var authorizationErrorMessage: String?
    
    private let authorizationRequestedKey = "HealthKitAuthorizationRequested"
    let expandedAuthorizationRequestedKey = "HealthKitExpandedAuthorizationRequested"
    let clinicalAuthorizationRequestedKey = "HealthKitClinicalAuthorizationRequested"
    
    // Published health data for real-time updates
    @Published var todayStats: DailyHealthStats?
    @Published var weeklyTrends: [WeeklyHealthTrend] = []
    @Published var mindfulTrend: [MindfulDay] = []
    @Published var cycleSummary: CycleHealthSummary?
    @Published var clinicalSummary: ClinicalRecordsSummary?
    
    @Published var loggedMeals: [MealLog] = []
    /// Today's dietary-water samples, newest first. HealthKit is the ledger —
    /// Forge-authored drinks and Watch/other-app drinks live in the same list.
    @Published var todayWaterLogs: [WaterLog] = []
    @Published var weeklyWaterMilliliters: [DailyWaterTotal] = []
    @Published var todayWaterMilliliters: Double = 0
    /// Remembered Test-Ready water so a later empty HealthKit refresh does
    /// not wipe the ForgeCore pack on a simulator.
    var testReadyHydrationMilliliters: Double?

    private var observerQueries: [HKObserverQuery] = []
    private var liveRefreshTask: Task<Void, Never>?
    private var isObserving = false
    /// Last Test-Ready pack successfully written this process. Skip a rewrite
    /// that would stall launch with the same seed.
    var installedTestReadySeed: Int?
    /// True while a Test-Ready pack is being deleted/rewritten.
    var isReplacingTestReadyPack = false
    /// Why a Test-Ready HealthKit write failed. Nil when the pack is healthy.
    @Published var lastPackWriteError: String?
    var lastTodayStatsAt: Date?
    var lastWeeklyTrendsAt: Date?
    var lastMindfulTrendAt: Date?
    var lastClinicalAt: Date?
    static let statsTTL: TimeInterval = 60
    static let trendTTL: TimeInterval = 180
    static let clinicalTTL: TimeInterval = 600
    let mealsStorageKey = "HealthKitManager.loggedMeals"
    let mealsStorageDateKey = "HealthKitManager.loggedMealsDate"
    static let forgeWaterMetadataKey = "com.forge.hydration"
    /// Marks samples the Test-Ready pack wrote so we can delete and rewrite
    /// them every simulator launch without touching anyone else's data.
    static let testReadyPackMetadataKey = "com.forge.testReadyPack"
    static let testReadySessionNameKey = "com.forge.sessionName"
    static let testReadyIntensityKey = "com.forge.intensity"
    static let testReadyVolumeKey = "com.forge.volume"
    
    private var writeTypes: Set<HKSampleType> { HealthKitAuthorizationPlan.writeTypes }

    /// Allergies, meds, conditions, immunizations, labs, procedures, vitals.
    /// Not notes. Not coverage. Those are PHI we will not ingest.
    static var structuredHealthRecordIdentifiers: [HKClinicalTypeIdentifier] {
        HealthKitAuthorizationPlan.structuredClinicalIdentifiers
    }

    private static var structuredHealthRecordTypes: Set<HKObjectType> {
        HealthKitAuthorizationPlan.clinicalReadTypes
    }
    
    private init() {
        loadPersistedMeals()
    }

    
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
        if isAuthorized {
            startBidirectionalSync()
        } else {
            stopBidirectionalSync()
        }
        return isAuthorized
    }
    
    /// First connect, Medicine Allow, and lifestyle opt-in all use this.
    /// Clinical types are omitted on Simulator / devices without Health Records
    /// so the system sheet cannot abort the process.
    func requestAuthorization() async throws {
        try await requestFullAppleHealthAuthorization()
    }

    var canRequestStructuredRecords: Bool {
        isHealthDataAvailable() && healthStore.supportsHealthRecords()
    }

    var hasStructuredRecordsAccess: Bool {
        UserDefaults.standard.bool(forKey: clinicalAuthorizationRequestedKey)
    }

    func requestFullAppleHealthAuthorization() async throws {
        let includeClinical = canRequestStructuredRecords
        try await requestHealthKitAuthorization(
            toShare: writeTypes,
            read: HealthKitAuthorizationPlan.readTypes(includeClinical: includeClinical),
            requestedKey: authorizationRequestedKey
        )
        UserDefaults.standard.set(true, forKey: expandedAuthorizationRequestedKey)
        if includeClinical {
            UserDefaults.standard.set(true, forKey: clinicalAuthorizationRequestedKey)
        }
    }

    /// Extra share types the simulator Health pack needs (sleep, HRV, RHR,
    /// steps). Production onboarding does not ask to write these.
    func requestTestReadyPackAuthorization() async throws {
        let extra: Set<HKSampleType> = [
            HKCategoryType(.sleepAnalysis),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.stepCount),
            HKQuantityType(.bodyTemperature),
        ]
        try await requestHealthKitAuthorization(
            toShare: writeTypes.union(extra),
            read: HealthKitAuthorizationPlan.readTypes(includeClinical: false),
            requestedKey: authorizationRequestedKey
        )
        UserDefaults.standard.set(true, forKey: expandedAuthorizationRequestedKey)
    }

    func requestExpandedLifestyleAuthorization() async throws {
        try await requestFullAppleHealthAuthorization()
    }

    func requestClinicalRecordsAuthorization() async throws {
        guard canRequestStructuredRecords else {
            authorizationErrorMessage = "Health Records aren't available on this device."
            throw HealthKitError.notAvailable
        }
        try await requestFullAppleHealthAuthorization()
    }

    /// Pull Health into Forge the moment Allow succeeds — profile, records, tags.
    func applyConnectedHealthToForge() async {
        if canRequestStructuredRecords {
            lastClinicalAt = nil
            _ = await fetchClinicalRecordsSummary()
        }
        let profile = await fetchUserProfile()
        AriaContextStore.shared.applyMedicationLayer()
        AriaContextStore.shared.applyHealthConnectTags(
            bloodType: profile?.bloodType,
            hasClinical: hasStructuredRecordsAccess,
            clinicalCount: clinicalSummary?.totalRecordCount ?? 0
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

        let safeRead = HealthKitAuthorizationPlan.sanitizedReadTypes(
            readTypes,
            supportsHealthRecords: healthStore.supportsHealthRecords()
        )
        guard !safeRead.isEmpty else {
            authorizationErrorMessage = "Health data is not available on this device."
            throw HealthKitError.notAvailable
        }
        
        do {
            try await healthStore.requestAuthorization(toShare: shareTypes, read: safeRead)
            UserDefaults.standard.set(true, forKey: requestedKey)
            if requestedKey != authorizationRequestedKey {
                UserDefaults.standard.set(true, forKey: authorizationRequestedKey)
            }
            authorizationErrorMessage = nil
            isAuthorized = true
            startBidirectionalSync()
        } catch {
            authorizationErrorMessage = LifeIngestError.explain(
                error,
                doing: "Couldn't request Apple Health access"
            )
            isAuthorized = false
            throw error
        }
    }

    /// Distinct HealthKit source names this phone has already seen.
    /// Feeds the device shelf so a wearable that writes to Apple Health
    /// (Oura, Garmin, Watch, …) can appear without a catalog update.
    /// ARIA reads those samples on this iPhone. Forge does not scrape vendor accounts.
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
    
    
    
    
    
    
    
    

    
    

    /// Live HealthKit → Forge. Observer queries fire when Apple Health, Watch,
    /// or another app writes a type we also write, then we re-read the ledger.
    func startBidirectionalSync() {
        guard isAuthorized, !isObserving else { return }
        isObserving = true

        for type in Self.bidirectionalSampleTypes {
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

    func stopBidirectionalSync() {
        liveRefreshTask?.cancel()
        liveRefreshTask = nil
        for query in observerQueries {
            healthStore.stop(query)
        }
        observerQueries.removeAll()
        if isObserving {
            for type in Self.bidirectionalSampleTypes {
                healthStore.disableBackgroundDelivery(for: type) { _, _ in }
            }
        }
        isObserving = false
    }

    static let bidirectionalSampleTypes: [HKSampleType] = [
        HKQuantityType(.dietaryWater),
        HKQuantityType(.dietaryEnergyConsumed),
        HKQuantityType(.dietaryProtein),
        HKQuantityType(.dietaryCarbohydrates),
        HKQuantityType(.stepCount),
        HKQuantityType(.activeEnergyBurned),
        HKCategoryType(.sleepAnalysis),
        HKWorkoutType.workoutType(),
        HKQuantityType(.bodyTemperature),
        HKQuantityType(.appleSleepingWristTemperature),
        HKQuantityType(.heartRateVariabilitySDNN),
        HKQuantityType(.restingHeartRate),
    ]

    private func scheduleLiveRefresh() {
        liveRefreshTask?.cancel()
        liveRefreshTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await refreshHydration()
            await AriaHealthRiskBridge.evaluateFromHealthKit(
                quietMode: UserDefaults.standard.bool(forKey: "forge.quiet.mode.v1")
            )
        }
    }

    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    

    
    nonisolated static func safeClinicalName(_ record: HKClinicalRecord) -> String {
        let name = record.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Untitled record" : name
    }

    nonisolated static func fetchClinicalRecords(type: HKClinicalType, healthStore: HKHealthStore) async -> [HKClinicalRecord] {
        await withCheckedContinuation { continuation in
            let once = ClinicalQueryResumeOnce<[HKClinicalRecord]>()
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 40,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                once.finish((samples as? [HKClinicalRecord]) ?? []) { continuation.resume(returning: $0) }
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Cycle Health
    

    
    
    
    
    
    
    
    

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
    let dateOfBirth: Date?
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
        age != nil || dateOfBirth != nil || biologicalSex != nil || bloodType != nil || weightKg != nil || heightCm != nil || bodyMassIndex != nil || leanBodyMassKg != nil || bodyFatPercentage != nil || restingHeartRate != nil || vo2Max != nil || averageHRV != nil || cycleSummary?.hasData == true || clinicalSummary?.hasData == true
    }
}

/// HealthKit can invoke a query handler more than once. Resume the
/// continuation exactly once so a fetch or Test-Ready rewrite cannot crash
/// on that path. Shared by HealthKitManager and HealthKitManager+*.
final class ClinicalQueryResumeOnce<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func finish(_ value: T, _ resume: (T) -> Void) {
        lock.lock()
        if done {
            lock.unlock()
            return
        }
        done = true
        lock.unlock()
        resume(value)
    }
}

enum HealthKitError: Error, LocalizedError {
    case notAvailable
    case authorizationDenied
    case dataUnavailable
    case saveFailed
    case saveFailedReason(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Health data is not available on this device."
        case .authorizationDenied:
            return "Apple Health access was not granted."
        case .dataUnavailable:
            return "Apple Health had no samples to read."
        case .saveFailed:
            return "Couldn't save this sample to Apple Health."
        case .saveFailedReason(let reason):
            return reason
        }
    }
}
