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

@MainActor
enum WorkoutLiveActivityManager {
    private static var activity: Activity<WorkoutActivityAttributes>?

    static func start(workoutName: String, exerciseName: String, totalSets: Int) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        end()

        let attributes = WorkoutActivityAttributes(workoutName: workoutName)
        let state = WorkoutActivityAttributes.ContentState(
            exerciseName: exerciseName,
            currentSet: 1,
            totalSets: totalSets,
            restSecondsRemaining: 0,
            isResting: false,
            elapsedSeconds: 0,
            heartRate: 0,
            hrZoneLabel: "Rest"
        )

        do {
            activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
        } catch {
            print("Live Activity start failed: \(error)")
        }
    }

    static func update(_ state: WorkoutActivityAttributes.ContentState) {
        guard let activity else { return }
        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    static func end() {
        guard let activity else { return }
        let final = activity.content.state
        Task {
            await activity.end(.init(state: final, staleDate: nil), dismissalPolicy: .immediate)
        }
        self.activity = nil
    }
}
