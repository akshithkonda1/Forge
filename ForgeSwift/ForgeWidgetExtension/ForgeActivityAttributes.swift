import Foundation
import ActivityKit

struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var exerciseName: String
        var currentSet: Int
        var totalSets: Int
        var restSecondsRemaining: Int
        var isResting: Bool
        var elapsedSeconds: Int
        var heartRate: Int
        var hrZoneLabel: String
    }

    var workoutName: String
}
