import Foundation
import ActivityKit
import WatchConnectivity
import ForgeCore

// MARK: - WorkoutActivityCoordinator (iOS app target)
//
// Receives WorkoutLiveState from the watch (PhoneLinkService) over
// WatchConnectivity and drives the lock-screen / Dynamic Island Live
// Activity. State arrives either as low-latency messages (phone
// reachable) or via application context (latest-wins fallback), so the
// handler is idempotent: start if needed, update otherwise, end on the
// ended signal or an .ended phase.

final class WorkoutActivityCoordinator: NSObject, WCSessionDelegate {

    static let shared = WorkoutActivityCoordinator()

    private var activity: Activity<ForgeWorkoutActivityAttributes>?

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    // MARK: Payload handling

    private func handle(_ payload: [String: Any]) {
        if payload[WorkoutLinkKeys.ended] != nil {
            Task { await self.endActivity() }
            return
        }
        guard
            let data = payload[WorkoutLinkKeys.state] as? Data,
            let state = try? JSONDecoder().decode(WorkoutLiveState.self, from: data)
        else { return }

        Task { await self.apply(state) }
    }

    @MainActor
    private func apply(_ state: WorkoutLiveState) async {
        if state.phase == .ended {
            await endActivity()
            return
        }
        let content = ActivityContent(
            state: ForgeWorkoutActivityAttributes.ContentState(live: state),
            staleDate: Date().addingTimeInterval(90)
        )
        if let activity {
            await activity.update(content)
        } else {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            activity = try? Activity.request(
                attributes: ForgeWorkoutActivityAttributes(startedAt: state.startedAt),
                content: content
            )
        }
    }

    @MainActor
    private func endActivity() async {
        guard let activity else { return }
        let finalContent = ActivityContent(
            state: activity.content.state,
            staleDate: Date()
        )
        await activity.end(finalContent, dismissalPolicy: .after(Date().addingTimeInterval(10 * 60)))
        self.activity = nil
    }

    // MARK: WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        // Catch up on any state that arrived while we weren't running.
        let context = session.receivedApplicationContext
        if !context.isEmpty {
            handle(context)
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(message)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handle(applicationContext)
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // Standard practice after a watch switch: reactivate.
        session.activate()
    }
}
