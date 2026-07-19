import Foundation
import HealthKit
import WatchKit
import Observation
import ForgeCore

// MARK: - WorkoutSessionManager
//
// The Workout Coordinator engine: HKWorkoutSession + HKLiveWorkoutBuilder
// lifecycle, live metrics, zone-aware coaching cues, structured-plan
// cursor with haptic rest timers, and the end-of-session debrief that
// hands off into a mindfulness reset. Unlike the mindful HR capture,
// this session's workout IS saved to Health via finishWorkout().

@MainActor
@Observable
final class WorkoutSessionManager {

    enum Phase: Equatable {
        case idle
        case countdown
        case active
        case resting
        case paused
        case summary
    }

    struct Summary: Equatable {
        var workoutType: ForgeWorkoutType
        var duration: TimeInterval
        var averageHeartRate: Double?
        var activeCalories: Double?
        var dominantZone: Int?
        var debrief: String
        var savedToHealth: Bool
    }

    private(set) var phase: Phase = .idle
    private(set) var workoutType: ForgeWorkoutType = .strength
    private(set) var plan: StructuredWorkout?
    private(set) var exerciseIndex = 0
    private(set) var setIndex = 0

    private(set) var elapsed: TimeInterval = 0
    private(set) var heartRate: Double?
    private(set) var currentZone: ForgeHRZone?
    private(set) var activeCalories: Double?
    private(set) var restRemaining: Int?
    /// Latest coaching cue — shown quietly under the metrics, never modal.
    private(set) var coachingCue: String?
    private(set) var summary: Summary?

    // HealthKit machinery (own store instance; auth was requested by
    // WatchHealthKitManager and covers these types).
    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var builderDelegate: WorkoutBuilderDelegate?

    private var ticker: Task<Void, Never>?
    private var restTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?
    private var hrSamples: [Double] = []
    private var zoneSeconds: [Int: Int] = [:]
    private var lastCueZone: Int?
    private var lastCueAt = Date.distantPast

    var currentExercise: WorkoutExercise? {
        guard let plan, exerciseIndex < plan.exercises.count else { return nil }
        return plan.exercises[exerciseIndex]
    }

    var planIsComplete: Bool {
        guard let plan else { return false }
        return exerciseIndex >= plan.exercises.count
    }

    // MARK: Start

    func start(type: ForgeWorkoutType, plan: StructuredWorkout? = nil) {
        guard phase == .idle || phase == .summary else { return }
        workoutType = type
        self.plan = plan
        exerciseIndex = 0
        setIndex = 0
        elapsed = 0
        heartRate = nil
        currentZone = nil
        activeCalories = nil
        coachingCue = nil
        summary = nil
        hrSamples = []
        zoneSeconds = [:]
        lastCueZone = nil
        lastCueAt = .distantPast

        phase = .countdown
        countdownTask = Task { [weak self] in
            // 3-2-1 with clicks; .start haptic when the session begins.
            for _ in 0..<3 {
                WKInterfaceDevice.current().play(.click)
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            await self?.beginSession()
        }
    }

    private func beginSession() async {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = workoutType.hkActivityType
        configuration.locationType = .indoor
        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            let delegate = WorkoutBuilderDelegate { [weak self] update in
                Task { @MainActor [weak self] in self?.apply(update) }
            }
            builder.delegate = delegate
            builderDelegate = delegate
            self.session = session
            self.builder = builder
            session.startActivity(with: Date())
            try await builder.beginCollection(at: Date())
            phase = .active
            WKInterfaceDevice.current().play(.start)
            startTicker()
        } catch {
            // Session couldn't start (auth, simulator quirks). Land back
            // in idle with a calm cue rather than a dead screen.
            phase = .idle
            coachingCue = "Couldn't start sensors just now — check Health permissions and try again."
        }
    }

    // MARK: Live updates

    private struct LiveUpdate {
        var heartRate: Double?
        var activeCalories: Double?
    }

    private func apply(_ update: LiveUpdate) {
        if let bpm = update.heartRate {
            heartRate = bpm
            hrSamples.append(bpm)
            let zone = ForgeHRZones.zone(for: Int(bpm))
            let previous = currentZone?.zone
            currentZone = zone
            maybeCoach(zone: zone, previousZone: previous)
        }
        if let calories = update.activeCalories {
            activeCalories = calories
        }
    }

    /// Zone-boundary coaching: one line + gentle haptic, throttled to
    /// once per 45s, anchored to the workout's target zone. Information,
    /// not commands — the user owns the effort.
    private func maybeCoach(zone: ForgeHRZone, previousZone: Int?) {
        guard phase == .active,
              zone.zone != previousZone,
              Date().timeIntervalSince(lastCueAt) > 45 else { return }
        lastCueAt = Date()
        lastCueZone = zone.zone

        let target = workoutType.targetZone
        if zone.zone == target {
            coachingCue = zone.coachingLine
        } else if zone.zone > target + 1 {
            coachingCue = "Running above the day's plan — easing off a touch keeps this sustainable. Your call."
        } else if zone.zone < target - 1, workoutType != .mobility, workoutType != .yoga {
            coachingCue = "Plenty in reserve if you want to build toward Zone \(target). No rush."
        } else {
            coachingCue = zone.coachingLine
        }
        WKInterfaceDevice.current().play(.click)
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func tick() {
        guard let builder else { return }
        elapsed = builder.elapsedTime
        if phase == .active || phase == .resting, let zone = currentZone {
            zoneSeconds[zone.zone, default: 0] += 1
        }
        publishLiveState()
    }

    // MARK: Structured plan cursor

    func completeSet() {
        guard let plan = plan, let exercise = currentExercise else { return }
        WKInterfaceDevice.current().play(.click)
        if setIndex + 1 < exercise.sets.count {
            setIndex += 1
            beginRest(seconds: exercise.restSeconds)
        } else if exerciseIndex + 1 < plan.exercises.count {
            exerciseIndex += 1
            setIndex = 0
            beginRest(seconds: exercise.restSeconds)
        } else {
            exerciseIndex = plan.exercises.count // plan complete
            coachingCue = "That's the whole plan — strong work. End whenever you're ready."
            WKInterfaceDevice.current().play(.success)
        }
        publishLiveState()
    }

    func skipRest() {
        restTask?.cancel()
        restTask = nil
        restRemaining = nil
        if phase == .resting { phase = .active }
    }

    private func beginRest(seconds: Int) {
        guard seconds > 0 else { return }
        phase = .resting
        restRemaining = seconds
        restTask?.cancel()
        restTask = Task { [weak self] in
            var remaining = seconds
            while remaining > 0, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                remaining -= 1
                await MainActor.run { [weak self] in
                    self?.restRemaining = remaining
                    if remaining <= 3, remaining > 0 {
                        WKInterfaceDevice.current().play(.click)
                    }
                }
            }
            await MainActor.run { [weak self] in
                guard let self, self.phase == .resting else { return }
                WKInterfaceDevice.current().play(.success)
                self.restRemaining = nil
                self.phase = .active
            }
        }
    }

    // MARK: Pause / resume / end

    func pause() {
        guard phase == .active || phase == .resting else { return }
        restTask?.cancel()
        restRemaining = nil
        session?.pause()
        phase = .paused
        WKInterfaceDevice.current().play(.stop)
        publishLiveState()
    }

    func resume() {
        guard phase == .paused else { return }
        session?.resume()
        phase = .active
        WKInterfaceDevice.current().play(.start)
        publishLiveState()
    }

    func end() async {
        guard phase != .idle, phase != .summary else { return }
        ticker?.cancel()
        restTask?.cancel()
        countdownTask?.cancel()
        restRemaining = nil

        var saved = false
        var duration = elapsed
        if let session, let builder {
            session.end()
            do {
                try await builder.endCollection(at: Date())
                let workout = try await builder.finishWorkout()
                duration = workout?.duration ?? elapsed
                saved = workout != nil
            } catch {
                saved = false
            }
        }
        session = nil
        builder = nil
        builderDelegate = nil

        let avgHR = hrSamples.isEmpty ? nil : hrSamples.reduce(0, +) / Double(hrSamples.count)
        let dominantZone = zoneSeconds.max(by: { $0.value < $1.value })?.key
        summary = Summary(
            workoutType: workoutType,
            duration: duration,
            averageHeartRate: avgHR,
            activeCalories: activeCalories,
            dominantZone: dominantZone,
            debrief: debriefText(dominantZone: dominantZone, duration: duration),
            savedToHealth: saved
        )
        phase = .summary
        WKInterfaceDevice.current().play(.success)

        // Clear the live complication + tell the iPhone the session ended.
        WatchSnapshotStore.update { $0.activeWorkout = nil }
        PhoneLinkService.shared.sendWorkoutEnded()
    }

    func dismissSummary() {
        summary = nil
        phase = .idle
        plan = nil
    }

    // MARK: Publishing (complication + iPhone Live Activity)

    private var lastPublish = Date.distantPast

    private func publishLiveState() {
        guard phase != .idle, phase != .summary else { return }
        // 1 Hz max — enough for a lock screen, kind to the battery.
        guard Date().timeIntervalSince(lastPublish) >= 1.0 else { return }
        lastPublish = Date()

        var state = WorkoutLiveState(
            workoutType: workoutType,
            phase: livePhase,
            startedAt: Date().addingTimeInterval(-elapsed),
            elapsedSeconds: elapsed,
            heartRate: heartRate,
            zoneNumber: currentZone?.zone,
            activeCalories: activeCalories
        )
        if let plan, let exercise = currentExercise {
            state.currentExerciseName = exercise.name
            state.currentExerciseIndex = exerciseIndex
            state.totalExercises = plan.exercises.count
            state.currentSetIndex = setIndex
            state.totalSetsInExercise = exercise.sets.count
            state.restSecondsRemaining = restRemaining
        }

        // Complications refresh via the snapshot; WidgetKit reload is
        // throttled to phase changes by passing reloadWidgets sparingly.
        WatchSnapshotStore.update(reloadWidgets: shouldReloadWidgets(for: state)) {
            $0.activeWorkout = state
        }
        PhoneLinkService.shared.send(state)
    }

    private var lastWidgetPhase: WorkoutLiveState.Phase?

    /// Reload complication timelines on phase transitions and once a
    /// minute — not on every 1 Hz tick.
    private func shouldReloadWidgets(for state: WorkoutLiveState) -> Bool {
        if state.phase != lastWidgetPhase {
            lastWidgetPhase = state.phase
            return true
        }
        return Int(state.elapsedSeconds) % 60 == 0
    }

    private var livePhase: WorkoutLiveState.Phase {
        switch phase {
        case .countdown: return .countdown
        case .active:    return .active
        case .resting:   return .resting
        case .paused:    return .paused
        case .idle, .summary: return .ended
        }
    }

    // MARK: Debrief copy

    private func debriefText(dominantZone: Int?, duration: TimeInterval) -> String {
        let minutes = max(1, Int(duration / 60))
        let target = workoutType.targetZone
        guard let dominantZone else {
            return "\(minutes) minutes moved — logged and banked. A short body-scan reset now helps it become recovery."
        }
        if dominantZone == target {
            return "\(minutes) minutes mostly in Zone \(dominantZone) — exactly the shape this session called for. A few reset minutes now locks in the gains."
        }
        if dominantZone < target {
            return "\(minutes) minutes at an easier effort than planned — still fully in the bank. Some days that's precisely the right read."
        }
        return "\(minutes) minutes running hotter than planned — you clearly had it today. The reset matters a little extra after intensity."
    }
}

// MARK: - Builder delegate (non-isolated, hops to MainActor)

private final class WorkoutBuilderDelegate: NSObject, HKLiveWorkoutBuilderDelegate {
    private let onUpdate: (WorkoutSessionManager.LiveUpdateProxy) -> Void

    init(onUpdate: @escaping (WorkoutSessionManager.LiveUpdateProxy) -> Void) {
        self.onUpdate = onUpdate
    }

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        var update = WorkoutSessionManager.LiveUpdateProxy()
        let hrType = HKQuantityType(.heartRate)
        if collectedTypes.contains(hrType),
           let quantity = workoutBuilder.statistics(for: hrType)?.mostRecentQuantity() {
            update.heartRate = quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        }
        let energyType = HKQuantityType(.activeEnergyBurned)
        if collectedTypes.contains(energyType),
           let quantity = workoutBuilder.statistics(for: energyType)?.sumQuantity() {
            update.activeCalories = quantity.doubleValue(for: .kilocalorie())
        }
        if update.heartRate != nil || update.activeCalories != nil {
            onUpdate(update)
        }
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}

extension WorkoutSessionManager {
    /// Cross-actor payload from the builder delegate.
    struct LiveUpdateProxy: Sendable {
        var heartRate: Double?
        var activeCalories: Double?
    }

    fileprivate func apply(_ proxy: LiveUpdateProxy) {
        apply(LiveUpdate(heartRate: proxy.heartRate, activeCalories: proxy.activeCalories))
    }
}
