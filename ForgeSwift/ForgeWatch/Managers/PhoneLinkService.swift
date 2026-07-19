import Foundation
import WatchConnectivity
import ForgeCore

// MARK: - PhoneLinkService
//
// Thin WCSession wrapper that streams WorkoutLiveState to the iPhone so
// the companion app can drive the Live Activity (lock screen + Dynamic
// Island). Transport policy:
//  - `sendMessage` when the phone is reachable (low latency, in-session)
//  - `updateApplicationContext` as the always-works fallback (latest
//    state wins — exactly the semantics a live summary wants)
// Payload is the shared Codable struct; no bespoke dictionaries to drift.

final class PhoneLinkService: NSObject, WCSessionDelegate {

    static let shared = PhoneLinkService()

    static let workoutStateKey = WorkoutLinkKeys.state
    static let workoutEndedKey = WorkoutLinkKeys.ended

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func send(_ state: WorkoutLiveState) {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated,
              let data = try? JSONEncoder().encode(state) else { return }
        let payload: [String: Any] = [Self.workoutStateKey: data]
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(payload, replyHandler: nil) { _ in
                // Reachability raced — fall back so the phone still converges.
                try? WCSession.default.updateApplicationContext(payload)
            }
        } else {
            try? WCSession.default.updateApplicationContext(payload)
        }
    }

    func sendWorkoutEnded() {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated else { return }
        let payload: [String: Any] = [Self.workoutEndedKey: true]
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(payload, replyHandler: nil) { _ in
                try? WCSession.default.updateApplicationContext(payload)
            }
        } else {
            try? WCSession.default.updateApplicationContext(payload)
        }
    }

    // MARK: WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        // Nothing to do — sends check activationState at call time.
    }
}
