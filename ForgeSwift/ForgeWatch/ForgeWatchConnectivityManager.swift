import Foundation
import WatchConnectivity

@MainActor
final class ForgeWatchConnectivityManager: NSObject, ObservableObject {
    static let shared = ForgeWatchConnectivityManager()

    @Published private(set) var isPhoneReachable = false

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func sendVitalsToPhone() {
        guard let snapshot = ForgeWatchVitalsBridge.latest(),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        sendMessage(["vitals": data])
        try? WCSession.default.updateApplicationContext(["vitals": data])
    }

    private func sendMessage(_ payload: [String: Any]) {
        guard WCSession.default.activationState == .activated else { return }
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
    }
}

extension ForgeWatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            isPhoneReachable = session.isReachable
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            isPhoneReachable = session.isReachable
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            handleCommand(message)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            handleCommand(applicationContext)
        }
    }

    private func handleCommand(_ message: [String: Any]) {
        guard let command = message["command"] as? String else { return }
        switch command {
        case "startWorkout":
            let name = message["workoutName"] as? String ?? ForgeWatchDashboardReader.workoutName
            Task { await ForgeWatchWorkoutSessionManager.shared.startWorkout(name: name, fromPhone: true) }
        case "endWorkout":
            Task { await ForgeWatchWorkoutSessionManager.shared.endWorkout() }
        default:
            break
        }
    }
}