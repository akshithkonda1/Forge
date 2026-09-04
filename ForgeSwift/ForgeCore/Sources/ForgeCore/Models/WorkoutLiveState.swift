import Foundation

// MARK: - WorkoutLiveState
//
// One Codable snapshot of an in-flight workout, shared by:
//  - WatchSnapshotStore → ActiveWorkoutComplication (watch face)
//  - PhoneLinkService → WCSession payload (watch → iPhone)
//  - ForgeWorkoutActivityAttributes.ContentState (iPhone Live Activity)
// Keeping one struct means the wrist, the lock screen, and the Dynamic
// Island can never disagree about the session.

public struct WorkoutLiveState: Codable, Sendable, Equatable, Hashable {

    public enum Phase: String, Codable, Sendable {
        case countdown
        case active
        case resting
        case paused
        case ended
    }

    public var workoutType: ForgeWorkoutType
    public var phase: Phase
    public var startedAt: Date
    public var elapsedSeconds: TimeInterval
    public var heartRate: Double?
    public var zoneNumber: Int?
    public var activeCalories: Double?

    // Structured-plan cursor (nil for open workouts)
    public var currentExerciseName: String?
    public var currentExerciseIndex: Int?
    public var totalExercises: Int?
    public var currentSetIndex: Int?
    public var totalSetsInExercise: Int?
    public var restSecondsRemaining: Int?

    public init(
        workoutType: ForgeWorkoutType,
        phase: Phase,
        startedAt: Date,
        elapsedSeconds: TimeInterval = 0,
        heartRate: Double? = nil,
        zoneNumber: Int? = nil,
        activeCalories: Double? = nil,
        currentExerciseName: String? = nil,
        currentExerciseIndex: Int? = nil,
        totalExercises: Int? = nil,
        currentSetIndex: Int? = nil,
        totalSetsInExercise: Int? = nil,
        restSecondsRemaining: Int? = nil
    ) {
        self.workoutType = workoutType
        self.phase = phase
        self.startedAt = startedAt
        self.elapsedSeconds = elapsedSeconds
        self.heartRate = heartRate
        self.zoneNumber = zoneNumber
        self.activeCalories = activeCalories
        self.currentExerciseName = currentExerciseName
        self.currentExerciseIndex = currentExerciseIndex
        self.totalExercises = totalExercises
        self.currentSetIndex = currentSetIndex
        self.totalSetsInExercise = totalSetsInExercise
        self.restSecondsRemaining = restSecondsRemaining
    }

    public var elapsedLabel: String {
        let total = Int(elapsedSeconds.rounded())
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// WatchConnectivity payload keys shared by the watch's PhoneLinkService
/// and the iPhone's WorkoutActivityCoordinator — one definition, no drift.
public enum WorkoutLinkKeys {
    public static let state = "forge.workout.liveState"
    public static let ended = "forge.workout.ended"
}
