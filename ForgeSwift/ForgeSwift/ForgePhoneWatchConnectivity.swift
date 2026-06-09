import Foundation
import WatchConnectivity

@MainActor
final class ForgePhoneWatchConnectivity: NSObject, ObservableObject {
    static let shared = ForgePhoneWatchConnectivity()

    @Published private(set) var isWatchReachable = false
    @Published private(set) var isWatchAppInstalled = false

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func notifyWorkoutStarted(name: String) {
        ForgeWatchVitalsBridge.setPhoneWorkoutActive(true, workoutName: name)
        send(["command": "startWorkout", "workoutName": name])
    }

    func notifyWorkoutEnded() {
        ForgeWatchVitalsBridge.setPhoneWorkoutActive(false)
        send(["command": "endWorkout"])
    }

    private func send(_ payload: [String: Any]) {
        guard WCSession.default.activationState == .activated else { return }
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        } else {
            try? WCSession.default.updateApplicationContext(payload)
        }
    }

    private func ingestVitalsPayload(_ data: Data) {
        guard let snapshot = try? JSONDecoder().decode(ForgeLiveVitalsSnapshot.self, from: data) else {
            return
        }
        ForgeWatchVitalsBridge.publish(snapshot)
    }
}

extension ForgePhoneWatchConnectivity: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            isWatchReachable = session.isReachable
            isWatchAppInstalled = session.isWatchAppInstalled
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            isWatchReachable = session.isReachable
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let data = message["vitals"] as? Data else { return }
        Task { @MainActor in
            ingestVitalsPayload(data)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["vitals"] as? Data else { return }
        Task { @MainActor in
            ingestVitalsPayload(data)
        }
    }
}