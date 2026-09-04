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
// Nothing leaves the watch except what ARIAWatchService explicitly sends
// for deeper coaching (and that path is opt-in + token-gated).

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
    private(set) var mindfulMinutesToday: Double = 0
    private(set) var hoursSinceLastWorkout: Double?
    private(set) var lastWorkoutType: String?
    private(set) var recentHeartRate: Double?
    private(set) var windDownPlan: WindDownPlan?
    private(set) var lastRefreshed: Date?

    // MARK: Authorization

    private var readTypes: Set<HKObjectType> {
        [
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
        ]
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
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            isAuthorized = true
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

        sleepSummary = await sleep
        recentNights = await nights
        recentHeartRate = await recentHR

        // Tonight's wind-down prediction from recent onsets + durations.
        windDownPlan = WindDownPredictor.plan(
            recentOnsets: recentNights.compactMap(\.start),
            recentSleepMinutes: recentNights.map(\.totalMinutes)
        )
        let latest = await hrvLatest
        hrvRecentMs = latest?.value
        hrvTrendMs = await hrvDelta
        mindfulMinutesToday = await mindful

        if let workout = await workout {
            hoursSinceLastWorkout = Date().timeIntervalSince(workout.endDate) / 3600
            lastWorkoutType = workout.workoutActivityType.forgeDisplayName
        } else {
            hoursSinceLastWorkout = nil
            lastWorkoutType = nil
        }

        let inputs = ReadinessInputs(
            hrvMs: latest?.value,
            hrvBaselineMs: await hrvBase,
            restingHR: await rhr,
            restingHRBaseline: await rhrBase,
            sleepMinutes: sleepSummary?.totalMinutes,
            deepSleepMinutes: sleepSummary?.deepMinutes,
            remSleepMinutes: sleepSummary?.remMinutes
        )
        readiness = ReadinessCalculator.score(from: inputs)
        lastRefreshed = Date()
        publishSnapshot()
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
