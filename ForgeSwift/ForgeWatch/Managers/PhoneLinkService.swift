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

    private let secureStore: SecureStore = KeychainStore()

    /// Clears secrets earlier builds wrote to UserDefaults in the clear.
    ///
    /// Deliberately not `SecureStoreMigration.sensitiveKeys`. That list is the
    /// iOS app's and includes `forge.watch.context.profile`, which ContextEngine
    /// reads straight back out of the shared suite — migrating it would move the
    /// user's lifestyle profile into the Keychain, reset them to `.general` on
    /// the next launch, and have the didSet write it to the suite again for the
    /// following launch to move once more. Only keys whose readers on this
    /// platform have been pointed at the Keychain belong here.
    ///
    /// Idempotent, so calling it on every launch is fine.
    static func migrateStoredSecrets(store: SecureStore = KeychainStore()) {
        let keys = Array(CompanionConfig.secretKeys)
        SecureStoreMigration.run(keys: keys, from: .standard, to: store)
        if let suite = UserDefaults(suiteName: WatchSnapshotStore.appGroupID) {
            SecureStoreMigration.run(keys: keys, from: suite, to: store)
        }
    }

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
        // Which half of this payload is a secret is a security decision, so it
        // is made in ForgeCore where it is tested, not inline here. Workout
        // payloads are the watch's own, travelling the other way; parse returns
        // nil for them rather than reading our own echo as configuration.
        guard let config = CompanionConfig.parse(message) else { return }
        let suite = UserDefaults(suiteName: WatchSnapshotStore.appGroupID)

        for (key, value) in config.secrets {
            // WatchConnectivity delivered this over an encrypted link; writing
            // it into UserDefaults on arrival would undo that. UserDefaults is
            // an unencrypted plist in the container and it rides along in
            // backups, so a stolen backup is a stolen session. Removing the old
            // copies matters as much as the write: a token refreshed into the
            // Keychain while a stale one stays in the plist has moved nothing.
            try? secureStore.set(value, forKey: key)
            suite?.removeObject(forKey: key)
            UserDefaults.standard.removeObject(forKey: key)
        }

        for (key, value) in config.preferences {
            suite?.set(value, forKey: key)
            UserDefaults.standard.set(value, forKey: key)
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
