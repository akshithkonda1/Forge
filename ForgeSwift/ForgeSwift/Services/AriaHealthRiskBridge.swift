import Foundation
import HealthKit
import UserNotifications
import ForgeCore

/// iPhone presenter for Watch / HealthKit vitals. Evaluation is pure and
/// on-device. Notifications are local. Quiet mode stays quiet.
enum AriaHealthRiskBridge {

    static let destination = "forge://aria/check"
    static let pendingOpenerKey = "forge.aria.healthCheck.pendingOpener"

    static func consumePendingChatOpener() -> String? {
        let value = UserDefaults.standard.string(forKey: pendingOpenerKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.removeObject(forKey: pendingOpenerKey)
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    @MainActor
    static func consider(
        _ payload: WatchVitalsPayload,
        quietMode: Bool
    ) {
        WatchVitalsInbox.save(payload)
        let findings = AriaHealthRiskMonitor.evaluate(payload.asReading())
        guard let finding = AriaHealthRiskMonitor.primary(findings) else { return }
        UserDefaults.standard.set(finding.chatOpener, forKey: pendingOpenerKey)
        guard !quietMode else { return }

        let key = AriaHealthRiskCooldown.storageKey(for: finding.kind)
        let last = UserDefaults.standard.object(forKey: key) as? Date
        guard AriaHealthRiskCooldown.shouldNotify(lastNotified: last) else { return }

        Task {
            let center = UNUserNotificationCenter.current()
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                guard granted else { return }
            } catch {
                print("AriaHealthRiskBridge: notification authorization failed: \(error.localizedDescription)")
                return
            }
            let content = UNMutableNotificationContent()
            content.title = finding.title
            content.body = finding.body
            content.sound = .default
            content.userInfo = ["destination": destination]
            let request = UNNotificationRequest(
                identifier: "forge.notif.aria.risk.\(finding.kind.rawValue)",
                content: content,
                trigger: nil
            )
            try? await center.add(request)
            UserDefaults.standard.set(Date(), forKey: key)
        }
    }

    @MainActor
    static func evaluateFromHealthKit(quietMode: Bool) async {
        let store = HealthKitManager.shared.healthStore
        async let body = ForgeHealthQueries.latestBodyTemperatureFahrenheit(store: store)
        async let wrist = ForgeHealthQueries.latestSleepingWristTemperatureDeviationCelsius(store: store)
        async let rhr = ForgeHealthQueries.latestRestingHR(store: store)
        async let rhrBase = ForgeHealthQueries.restingHRBaseline(store: store)
        async let hrv = ForgeHealthQueries.latestHRV(store: store)
        async let hrvBase = ForgeHealthQueries.hrvBaseline(store: store)
        async let workout = ForgeHealthQueries.lastWorkout(store: store)

        let bodyTemp = await body
        let wristTemp = await wrist
        let resting = await rhr
        let restingBase = await rhrBase
        let hrvSample = await hrv
        let hrvBaseValue = await hrvBase
        let lastWorkout = await workout

        var sampledAt = Date()
        if let bodyTemp { sampledAt = bodyTemp.date }
        if let wristTemp, wristTemp.date > sampledAt { sampledAt = wristTemp.date }

        let hours: Double?
        if let lastWorkout {
            hours = Date().timeIntervalSince(lastWorkout.endDate) / 3600
        } else {
            hours = nil
        }

        let payload = WatchVitalsPayload(
            sampledAt: sampledAt,
            bodyTemperatureF: bodyTemp?.value,
            wristTemperatureDeviationC: wristTemp?.value,
            restingHeartRate: resting,
            restingHeartRateBaseline: restingBase,
            hrvMs: hrvSample?.value,
            hrvBaselineMs: hrvBaseValue,
            hoursSinceLastWorkout: hours,
            source: "iphone"
        )
        guard payload.hasAnySignal else { return }
        consider(payload, quietMode: quietMode)
    }
}
