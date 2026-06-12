import Foundation
import HealthKit

@MainActor
final class ForgeWatchWorkoutSessionManager: NSObject, ObservableObject {
    static let shared = ForgeWatchWorkoutSessionManager()

    @Published private(set) var isActive = false
    @Published private(set) var heartRate = 0
    @Published private(set) var spO2 = 0
    @Published private(set) var elapsedSeconds = 0
    @Published private(set) var workoutName = "Forge Workout"
    @Published private(set) var startedByPhone = false
    @Published private(set) var lastError: String?

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var elapsedTask: Task<Void, Never>?
    private var spO2Query: HKAnchoredObjectQuery?
    private var isStarting = false

    private override init() {
        super.init()
    }

    func startWorkout(name: String, fromPhone: Bool = false) async {
        // `isStarting` is latched synchronously before the first `await` so a
        // concurrent trigger (phone command + view sync + user tap) can't pass
        // the guard while this call is suspended and spawn a second session.
        guard !isActive, !isStarting else { return }
        guard HKHealthStore.isHealthDataAvailable() else { return }
        isStarting = true
        defer { isStarting = false }
        lastError = nil

        do {
            try await requestAuthorization()
        } catch {
            lastError = "Health access needed to start a workout."
            return
        }

        workoutName = name.isEmpty ? "Forge Workout" : name
        startedByPhone = fromPhone
        elapsedSeconds = 0

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)

            session.delegate = self
            builder.delegate = self

            self.session = session
            self.builder = builder

            session.startActivity(with: Date())
            try await builder.beginCollection(at: Date())

            isActive = true
            startElapsedTimer()
            startSpO2Stream()
            publishVitals()
            ForgeWatchConnectivityManager.shared.sendVitalsToPhone()
        } catch {
            lastError = "Couldn't start the workout. Try again."
            cleanupSession()
        }
    }

    func endWorkout() async {
        guard isActive else { return }

        elapsedTask?.cancel()
        elapsedTask = nil
        stopSpO2Stream()

        if let builder, let session {
            session.end()
            do {
                try await builder.endCollection(at: Date())
                try await builder.finishWorkout()
            } catch {
                // Best-effort finish; vitals already streamed live.
            }
        }

        resetState()
    }

    /// Tears down a workout that failed mid-session so the UI doesn't stay stuck
    /// "active", and surfaces the reason to the user.
    private func handleSessionFailure(_ error: Error) {
        guard isActive || isStarting else { return }
        lastError = "Workout stopped: \(error.localizedDescription)"
        resetState()
    }

    /// Stops all live streams and returns the manager to an idle state.
    /// Shared by the normal end path and the failure path.
    private func resetState() {
        elapsedTask?.cancel()
        elapsedTask = nil
        stopSpO2Stream()
        cleanupSession()
        heartRate = 0
        spO2 = 0
        elapsedSeconds = 0
        isActive = false
        startedByPhone = false

        ForgeWatchVitalsBridge.publish(.empty)
        ForgeWatchConnectivityManager.shared.sendVitalsToPhone()
    }

    private func requestAuthorization() async throws {
        let readTypes: Set<HKObjectType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.oxygenSaturation),
            HKQuantityType(.activeEnergyBurned),
            HKObjectType.workoutType(),
        ]
        let shareTypes: Set<HKSampleType> = [HKObjectType.workoutType()]
        try await healthStore.requestAuthorization(toShare: shareTypes, read: readTypes)
    }

    private func startElapsedTimer() {
        elapsedTask?.cancel()
        elapsedTask = Task {
            while !Task.isCancelled, isActive {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                elapsedSeconds += 1
            }
        }
    }

    private func startSpO2Stream() {
        guard let spO2Type = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation) else { return }
        let predicate = HKQuery.predicateForSamples(
            withStart: Date().addingTimeInterval(-300),
            end: nil,
            options: .strictStartDate
        )

        let query = HKAnchoredObjectQuery(
            type: spO2Type,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, _ in
            Task { @MainActor in
                self?.consumeSpO2(samples: samples)
            }
        }

        query.updateHandler = { [weak self] _, samples, _, _, _ in
            Task { @MainActor in
                self?.consumeSpO2(samples: samples)
            }
        }

        spO2Query = query
        healthStore.execute(query)
    }

    private func stopSpO2Stream() {
        if let spO2Query {
            healthStore.stop(spO2Query)
        }
        spO2Query = nil
    }

    private func consumeSpO2(samples: [HKSample]?) {
        guard let quantitySamples = samples as? [HKQuantitySample],
              let sample = quantitySamples.last else { return }
        let percent = Int((sample.quantity.doubleValue(for: HKUnit.percent()) * 100).rounded())
        guard percent > 0, percent <= 100 else { return }
        spO2 = percent
        publishVitals()
        ForgeWatchConnectivityManager.shared.sendVitalsToPhone()
    }

    private func publishVitals() {
        let snapshot = ForgeLiveVitalsSnapshot(
            heartRate: heartRate > 0 ? heartRate : nil,
            spO2: spO2 > 0 ? spO2 : nil,
            isWorkoutActive: isActive,
            workoutName: workoutName,
            source: "watch",
            updatedAt: Date().timeIntervalSince1970
        )
        ForgeWatchVitalsBridge.publish(snapshot)
    }

    private func cleanupSession() {
        session = nil
        builder = nil
    }
}

extension ForgeWatchWorkoutSessionManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            if toState == .ended {
                isActive = false
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            handleSessionFailure(error)
        }
    }
}

extension ForgeWatchWorkoutSessionManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        guard collectedTypes.contains(HKQuantityType(.heartRate)) else { return }
        Task { @MainActor in
            guard let statistics = workoutBuilder.statistics(for: HKQuantityType(.heartRate)),
                  let quantity = statistics.mostRecentQuantity() else { return }
            let bpm = Int(quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())))
            guard bpm > 0 else { return }
            heartRate = bpm
            publishVitals()
            ForgeWatchConnectivityManager.shared.sendVitalsToPhone()
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}