import Foundation
import HealthKit
import Observation
import ForgeCore

// MARK: - WatchHealthKitManager
//
// The watch-side sibling of the iOS HealthKitManager: a focused subset
// (readiness inputs, sleep, mindful minutes, live HR) built on the shared
// ForgeHealthQueries helpers so both platforms compute identical numbers.
//
// Privacy stance: everything here is read → computed → rendered on-device.
// Compact vitals may cross WatchConnectivity to the paired iPhone's on-device
// inbox so ARIA can see a wrist reading before Apple Health has synced.
// Nothing is warehoused on Forge. Deeper coaching (`ARIAWatchService`) is
// still opt-in + token-gated.

/// HealthKit permits one `HKWorkoutSession` per process. The gym workout and
/// the mindful HR tap both want one — this gate makes them take turns.
///
/// MainActor-isolated because it is shared mutable state. Every reader and
/// writer already lives on the main actor (WorkoutSessionManager and
/// WatchHealthKitManager are both @MainActor), so this costs nothing today and
/// is the difference between compiling and not under Swift 6, where a mutable
/// `static var` without isolation is an error rather than a warning.
@MainActor
enum WatchHKLiveSession {
    static var workoutRunning = false
    static weak var health: WatchHealthKitManager?
}

@MainActor
@Observable
final class WatchHealthKitManager {

    private let store = HKHealthStore()

    /// True once the authorization sheet has completed. Individual reads
    /// may still be denied — every fetch degrades to nil rather than
    /// guessing (readiness confidence reflects what we actually got).
    private(set) var isAuthorized = false
    private(set) var authorizationFailed = false

    private(set) var readiness: ReadinessScore?
    private(set) var sleepSummary: SleepNight?
    private(set) var recentNights: [SleepNight] = []
    private(set) var hrvRecentMs: Double?
    private(set) var hrvTrendMs: Double?
    private(set) var hrvBaselineMs: Double?
    private(set) var mindfulMinutesToday: Double = 0
    private(set) var hoursSinceLastWorkout: Double?
    private(set) var lastWorkoutType: String?
    private(set) var recentHeartRate: Double?
    private(set) var windDownPlan: WindDownPlan?
    private(set) var lastRefreshed: Date?
    private(set) var bodyTemperatureF: Double?
    private(set) var wristTemperatureDeviationC: Double?
    private(set) var restingHeartRate: Double?
    private(set) var restingHeartRateBaseline: Double?

    private var observerQueries: [HKObserverQuery] = []
    private var isObserving = false
    private var liveRefreshTask: Task<Void, Never>?

    // MARK: Authorization

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.appleExerciseTime),
            HKCategoryType(.sleepAnalysis),
            HKCategoryType(.mindfulSession),
            HKObjectType.workoutType(),
            // Water is read as well as written so a glass logged on the phone
            // counts on the wrist; body mass sizes HydrationEngine's target.
            HKQuantityType(.dietaryWater),
            HKQuantityType(.bodyMass),
            HKQuantityType(.bodyTemperature),
        ]
        types.insert(HKQuantityType(.appleSleepingWristTemperature))
        return types
    }

    private var writeTypes: Set<HKSampleType> {
        [
            HKCategoryType(.mindfulSession),
            HKObjectType.workoutType(), // needed by the live builder used for HR biofeedback
            HKQuantityType(.dietaryWater),
        ]
    }

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationFailed = true
            return
        }
        do {
            // Same iOS 26/27 rule as the phone: per-object types (vision Rx)
            // abort `requestAuthorization` instead of returning HKError.
            let read = Set(readTypes.filter { !$0.requiresPerObjectAuthorization() })
            try await store.requestAuthorization(toShare: writeTypes, read: read)
            isAuthorized = true
            startBackgroundObservers()
        } catch {
            authorizationFailed = true
        }
    }

    // MARK: Refresh

    /// Gathers all readiness inputs concurrently and recomputes the local
    /// score. Cheap enough to call on every foreground + context change.
    func refreshAll() async {
        guard isAuthorized else { return }

        async let sleep = ForgeHealthQueries.lastNightSleep(store: store)
        async let hrvLatest = ForgeHealthQueries.latestHRV(store: store)
        async let hrvBase = ForgeHealthQueries.hrvBaseline(store: store)
        async let hrvDelta = ForgeHealthQueries.hrvTrend(store: store)
        async let rhr = ForgeHealthQueries.latestRestingHR(store: store)
        async let rhrBase = ForgeHealthQueries.restingHRBaseline(store: store)
        async let mindful = ForgeHealthQueries.mindfulMinutes(store: store, since: Calendar.current.startOfDay(for: Date()))
        async let workout = ForgeHealthQueries.lastWorkout(store: store)
        async let nights = ForgeHealthQueries.recentSleepNights(store: store)
        async let recentHR = ForgeHealthQueries.latestHeartRate(store: store)
        async let bodyTemp = ForgeHealthQueries.latestBodyTemperatureFahrenheit(store: store)
        async let wristTemp = ForgeHealthQueries.latestSleepingWristTemperatureDeviationCelsius(store: store)

        sleepSummary = await sleep
        recentNights = await nights
        recentHeartRate = await recentHR
        if let bodyTemp = await bodyTemp {
            bodyTemperatureF = bodyTemp.value
        } else {
            bodyTemperatureF = nil
        }
        if let wristTemp = await wristTemp {
            wristTemperatureDeviationC = wristTemp.value
        } else {
            wristTemperatureDeviationC = nil
        }

        // Tonight's wind-down prediction from recent onsets + durations.
        windDownPlan = WindDownPredictor.plan(
            recentOnsets: recentNights.compactMap(\.start),
            recentSleepMinutes: recentNights.map(\.totalMinutes)
        )
        let latest = await hrvLatest
        hrvRecentMs = latest?.value
        hrvTrendMs = await hrvDelta
        let hrvBaseValue = await hrvBase
        hrvBaselineMs = hrvBaseValue
        mindfulMinutesToday = await mindful

        if let workout = await workout {
            hoursSinceLastWorkout = Date().timeIntervalSince(workout.endDate) / 3600
            lastWorkoutType = workout.workoutActivityType.forgeDisplayName
        } else {
            hoursSinceLastWorkout = nil
            lastWorkoutType = nil
        }

        let rhrValue = await rhr
        let rhrBaseValue = await rhrBase
        restingHeartRate = rhrValue
        restingHeartRateBaseline = rhrBaseValue

        let inputs = ReadinessInputs(
            hrvMs: latest?.value,
            hrvBaselineMs: hrvBaseValue,
            restingHR: rhrValue,
            restingHRBaseline: rhrBaseValue,
            sleepMinutes: sleepSummary?.totalMinutes,
            deepSleepMinutes: sleepSummary?.deepMinutes,
            remSleepMinutes: sleepSummary?.remMinutes
        )
        readiness = ReadinessCalculator.score(from: inputs)
        lastRefreshed = Date()
        publishSnapshot()
        startBackgroundObservers()
        pushVitalsAndEvaluateRisk()
    }

    private func publishSnapshot() {
        // Recommendation fields are owned by ARIAWatchService; only touch ours.
        WatchSnapshotStore.update { snapshot in
            snapshot.readinessOverall = readiness?.overall
            snapshot.readinessBand = readiness.map { $0.band }
            snapshot.readinessConfidence = readiness?.confidence
            snapshot.sleepQualityScore = readiness?.sleepQuality
            snapshot.sleepMinutes = sleepSummary?.totalMinutes
            snapshot.mindfulMinutesToday = mindfulMinutesToday
            snapshot.tonightWindDown = windDownPlan?.windDownStart
            snapshot.bodyTemperatureF = bodyTemperatureF
            snapshot.wristTemperatureDeviationC = wristTemperatureDeviationC
        }
    }

    private func currentVitalsPayload() -> WatchVitalsPayload {
        WatchVitalsPayload(
            sampledAt: lastRefreshed ?? Date(),
            bodyTemperatureF: bodyTemperatureF,
            wristTemperatureDeviationC: wristTemperatureDeviationC,
            restingHeartRate: restingHeartRate,
            restingHeartRateBaseline: restingHeartRateBaseline,
            hrvMs: hrvRecentMs,
            hrvBaselineMs: hrvBaselineMs,
            hoursSinceLastWorkout: hoursSinceLastWorkout,
            source: "watch"
        )
    }

    private func pushVitalsAndEvaluateRisk() {
        let payload = currentVitalsPayload()
        guard payload.hasAnySignal else { return }
        WatchVitalsInbox.save(payload)
        PhoneLinkService.shared.sendVitals(payload)
        WatchHealthRiskBridge.consider(payload)
    }

    /// HK background delivery so temperature / HRV checks still run when
    /// ForgeWatch is not on screen (complication + HealthKit wake).
    func startBackgroundObservers() {
        guard isAuthorized, !isObserving else { return }
        isObserving = true
        var observed: [HKSampleType] = [
            HKQuantityType(.bodyTemperature),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.restingHeartRate),
        ]
        observed.append(HKQuantityType(.appleSleepingWristTemperature))
        for type in observed {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, _ in
                Task { @MainActor in
                    self?.scheduleLiveRefresh()
                }
                completion()
            }
            store.execute(query)
            observerQueries.append(query)
            store.enableBackgroundDelivery(for: type, frequency: .immediate) { _, _ in }
        }
    }

    func stopBackgroundObservers() {
        liveRefreshTask?.cancel()
        liveRefreshTask = nil
        for query in observerQueries {
            store.stop(query)
        }
        observerQueries.removeAll()
        if isObserving {
            let types: [HKSampleType] = [
                HKQuantityType(.bodyTemperature),
                HKQuantityType(.heartRateVariabilitySDNN),
                HKQuantityType(.restingHeartRate),
                HKQuantityType(.appleSleepingWristTemperature),
            ]
            for type in types {
                store.disableBackgroundDelivery(for: type) { _, _ in }
            }
        }
        isObserving = false
    }

    private func scheduleLiveRefresh() {
        liveRefreshTask?.cancel()
        liveRefreshTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await refreshAll()
        }
    }

    // MARK: ARIA context assembly

    func makeARIAContext(
        mode: LifestyleMode?,
        minutesInMode: Double?,
        profile: LifestyleProfile,
        sessionsCompletedToday: Int,
        sleepFactors: [SleepFactor] = []
    ) -> WatchARIAContext {
        var context = WatchARIAContext()
        context.readinessOverall = readiness?.overall
        context.readinessConfidence = readiness?.confidence
        context.hrvRecentMs = hrvRecentMs
        context.hrvTrendMs = hrvTrendMs
        context.sleepMinutes = sleepSummary?.totalMinutes
        context.deepSleepMinutes = sleepSummary?.deepMinutes
        context.remSleepMinutes = sleepSummary?.remMinutes
        context.sleepQualityScore = readiness?.sleepQuality
        context.lifestyleMode = mode
        context.minutesInCurrentMode = minutesInMode
        context.lifestyleProfile = profile
        context.hoursSinceLastWorkout = hoursSinceLastWorkout
        context.lastWorkoutType = lastWorkoutType
        context.mindfulMinutesToday = mindfulMinutesToday
        context.sessionsCompletedToday = sessionsCompletedToday
        context.sleepFactors = sleepFactors.isEmpty ? nil : sleepFactors
        context.bodyTemperatureF = bodyTemperatureF
        context.wristTemperatureDeviationC = wristTemperatureDeviationC
        return context
    }

    // MARK: Mindful minutes

    func logMindfulSession(start: Date, end: Date) async throws {
        try await ForgeHealthQueries.saveMindfulSession(store: store, start: start, end: end)
        mindfulMinutesToday += end.timeIntervalSince(start) / 60
        publishSnapshot()
    }

    // MARK: Live heart-rate biofeedback
    //
    // Short mindfulness sessions need live HR, and on watchOS that means a
    // workout session (the same mechanism Breathe uses). We run a
    // .mindAndBody session purely as a sensor tap and DISCARD the workout
    // afterwards — only the Mindful Minutes category sample is saved.

    struct MindfulBiofeedback {
        let samples: [(date: Date, bpm: Double)]

        /// Positive = HR settled over the session (first vs last third).
        var settleBPM: Double? {
            guard samples.count >= 4 else { return nil }
            let third = max(1, samples.count / 3)
            let early = samples.prefix(third).map(\.bpm)
            let late = samples.suffix(third).map(\.bpm)
            let earlyMean = early.reduce(0, +) / Double(early.count)
            let lateMean = late.reduce(0, +) / Double(late.count)
            return earlyMean - lateMean
        }
    }

    private(set) var liveHeartRate: Double?
    private var captureSession: HKWorkoutSession?
    private var captureBuilder: HKLiveWorkoutBuilder?
    private var captureDelegate: MindfulCaptureDelegate?
    private var capturedSamples: [(date: Date, bpm: Double)] = []

    func beginMindfulHeartRateCapture() async {
        guard isAuthorized, captureSession == nil else { return }
        // HealthKit allows one HKWorkoutSession per process. A live workout
        // already owns it — stealing it would kill the gym session.
        guard !WatchHKLiveSession.workoutRunning else { return }
        WatchHKLiveSession.health = self
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .mindAndBody
        configuration.locationType = .indoor
        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            let delegate = MindfulCaptureDelegate { [weak self] date, bpm in
                Task { @MainActor [weak self] in
                    self?.liveHeartRate = bpm
                    self?.capturedSamples.append((date, bpm))
                }
            }
            builder.delegate = delegate
            captureDelegate = delegate
            captureSession = session
            captureBuilder = builder
            capturedSamples = []
            session.startActivity(with: Date())
            try await builder.beginCollection(at: Date())
        } catch {
            // Biofeedback is a bonus, never a blocker — session runs without it.
            captureSession = nil
            captureBuilder = nil
            captureDelegate = nil
        }
    }

    func endMindfulHeartRateCapture() async -> MindfulBiofeedback? {
        guard let session = captureSession, let builder = captureBuilder else { return nil }
        captureSession = nil
        captureBuilder = nil
        captureDelegate = nil
        liveHeartRate = nil

        session.end()
        try? await builder.endCollection(at: Date())
        builder.discardWorkout() // sensor tap only — no workout entry in Health

        let samples = capturedSamples
        capturedSamples = []
        return samples.isEmpty ? nil : MindfulBiofeedback(samples: samples)
    }
}

// MARK: - Live builder delegate (non-isolated, hops back to MainActor)

private final class MindfulCaptureDelegate: NSObject, HKLiveWorkoutBuilderDelegate {
    private let onHeartRate: (Date, Double) -> Void

    init(onHeartRate: @escaping (Date, Double) -> Void) {
        self.onHeartRate = onHeartRate
    }

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let heartRateType = HKQuantityType(.heartRate)
        guard
            collectedTypes.contains(heartRateType),
            let statistics = workoutBuilder.statistics(for: heartRateType),
            let quantity = statistics.mostRecentQuantity()
        else { return }
        let bpm = quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        onHeartRate(Date(), bpm)
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}

// MARK: - Workout type display names (tiny subset used in context strings)

private extension HKWorkoutActivityType {
    var forgeDisplayName: String {
        switch self {
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "Strength"
        case .running: return "Run"
        case .walking: return "Walk"
        case .cycling: return "Ride"
        case .highIntensityIntervalTraining: return "HIIT"
        case .yoga: return "Yoga"
        case .swimming: return "Swim"
        case .mindAndBody: return "Mind & Body"
        default: return "Workout"
        }
    }
}
