import Foundation
import UserNotifications
import ForgeCore

/// Wrist-side presenter for `AriaHealthRiskMonitor`. Same copy as iPhone;
/// HealthKit samples never leave the watch except the compact vitals
/// payload PhoneLinkService already sends.
enum WatchHealthRiskBridge {

    static func consider(_ payload: WatchVitalsPayload) {
        let findings = AriaHealthRiskMonitor.evaluate(payload.asReading())
        guard let finding = AriaHealthRiskMonitor.primary(findings) else { return }
        let key = AriaHealthRiskCooldown.storageKey(for: finding.kind)
        let last = UserDefaults.standard.object(forKey: key) as? Date
        guard AriaHealthRiskCooldown.shouldNotify(lastNotified: last) else { return }

        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            } else if settings.authorizationStatus == .denied {
                return
            }

            let content = UNMutableNotificationContent()
            content.title = finding.title
            content.body = finding.body
            content.sound = .default
            content.userInfo = ["destination": "forgewatch://home"]
            let request = UNNotificationRequest(
                identifier: "forge.watch.risk.\(finding.kind.rawValue)",
                content: content,
                trigger: nil
            )
            try? await center.add(request)
            UserDefaults.standard.set(Date(), forKey: key)
        }
    }
}
