import Foundation
import UserNotifications
import ForgeCore

// MARK: - WindDownScheduler
//
// One gentle local notification at tonight's predicted wind-down start.
// Exactly one pending at a time (rescheduling replaces), copy is an
// invitation rather than an alarm, and tapping it opens the app where
// the evening suggestion (wind-down practice) is already front and
// center via the suggestion engine's evening rule.

enum WindDownScheduler {

    private static let identifier = "forge.watch.winddown"

    /// Returns true if the reminder is scheduled.
    @discardableResult
    static func schedule(plan: WindDownPlan) async -> Bool {
        let center = UNUserNotificationCenter.current()

        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            guard granted else { return false }
        case .denied:
            return false
        default:
            break
        }

        guard plan.windDownStart > Date() else { return false }

        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = "Wind-down window"
        content.body = "Tonight's window is opening. A few slow breaths now tilts the night your way — no pressure, just a good moment."
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: plan.windDownStart
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }
}
