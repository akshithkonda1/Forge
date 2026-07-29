import Foundation
import WatchConnectivity
import ForgeCore

// MARK: - PhoneLinkService
//
// Thin WCSession wrapper that:
//  1) Streams WorkoutLiveState → iPhone (Live Activity / Dynamic Island)
//  2) Receives companion config (base URL, user id, first name) from iPhone
//     so Xcode simulator pairs work even when App Groups do not share.
//
// Transport policy for workouts:
//  - `sendMessage` when the phone is reachable (low latency, in-session)
//  - `updateApplicationContext` as the always-works fallback (latest wins)

final class PhoneLinkService: NSObject, WCSessionDelegate {

    static let shared = PhoneLinkService()

    static let workoutStateKey = WorkoutLinkKeys.state
    static let workoutEndedKey = WorkoutLinkKeys.ended

    /// Posted on the main queue when companion config is applied.
    static let companionConfigDidUpdate = Notification.Name("forge.watch.companionConfigDidUpdate")

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
                self.pushMergedApplicationContext(payload)
            }
        } else {
            pushMergedApplicationContext(payload)
        }
    }

    func sendWorkoutEnded() {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated else { return }
        let payload: [String: Any] = [Self.workoutEndedKey: true]
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(payload, replyHandler: nil) { _ in
                self.pushMergedApplicationContext(payload)
            }
        } else {
            pushMergedApplicationContext(payload)
        }
    }

    /// Preserve companion config keys when streaming workout state so
    /// ARIA base URL / name survive a long session.
    private func pushMergedApplicationContext(_ payload: [String: Any]) {
        var merged = WCSession.default.applicationContext
        for (k, v) in payload { merged[k] = v }
        // Ending clears live state so the phone doesn't re-open a stale activity.
        if payload[Self.workoutEndedKey] != nil {
            merged.removeValue(forKey: Self.workoutStateKey)
        } else if payload[Self.workoutStateKey] != nil {
            merged.removeValue(forKey: Self.workoutEndedKey)
        }
        try? WCSession.default.updateApplicationContext(merged)
    }

    // MARK: Inbound companion config (from iPhone)

    private func ingest(_ message: [String: Any]) {
        // Workout payloads are iPhone-bound; ignore if present.
        if message[Self.workoutStateKey] != nil || message[Self.workoutEndedKey] != nil {
            return
        }

        let config: [String: String]? = {
            if let nested = message["forge.companion.config"] as? [String: String] {
                return nested
            }
            var flat: [String: String] = [:]
            for key in ["forge.aria.baseURL", "forge.aria.userId", "forge.aria.authToken",
                        "forge.user.firstName", "forge.companion.syncedAt"] {
                if let v = message[key] as? String { flat[key] = v }
            }
            return flat.isEmpty ? nil : flat
        }()

        guard let config else { return }
        let suite = UserDefaults(suiteName: WatchSnapshotStore.appGroupID)
        for (k, v) in config {
            suite?.set(v, forKey: k)
            UserDefaults.standard.set(v, forKey: k)
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.companionConfigDidUpdate, object: nil)
        }
    }

    // MARK: WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        // Apply any context that was queued while the session was offline.
        if activationState == .activated, !session.receivedApplicationContext.isEmpty {
            ingest(session.receivedApplicationContext)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        ingest(applicationContext)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        ingest(message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        ingest(userInfo)
    }

    #if os(watchOS)
    // watchOS does not require sessionDidBecomeInactive / Deactivate.
    #endif
}
