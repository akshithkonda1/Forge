import Foundation
import UserNotifications

/// Idempotent notification scheduling driven by Settings toggles.
@MainActor
enum ForgeNotificationScheduler {
    private static let center = UNUserNotificationCenter.current()

    enum ID {
        static let workout = "forge.notification.workout"
        static let recovery = "forge.notification.recovery"
        static let weeklySummary = "forge.notification.weeklySummary"
        static let lifestyleHydration = "forge.notification.lifestyle.hydration"
        static let lifestyleLunch = "forge.notification.lifestyle.lunch"
        static let lifestyleDinner = "forge.notification.lifestyle.dinner"
        static let lifestyleSleep = "forge.notification.lifestyle.sleep"
        static let briefMorning = "forge.notification.brief.morning"
        static let briefEvening = "forge.notification.brief.evening"
        // Cycle health
        static let cycleBBTReminder = "forge.notif.cycle.bbt"
        static let cycleOPKWindow = "forge.notif.cycle.opk"
        static let cycleFertileWindow = "forge.notif.cycle.fertile"
        static let cyclePeriodReminder = "forge.notif.cycle.period"
        static let cyclePhaseTransition = "forge.notif.cycle.phase"
    }

    static func sync(
        settings: AppNotificationSettings,
        briefEnabled: Bool,
        brief: BriefNotificationSettings
    ) async {
        try? await center.requestAuthorization(options: [.alert, .sound, .badge])

        await removeAllForgeNotifications()

        if settings.workoutReminders {
            await scheduleWeekly(
                id: ID.workout,
                weekday: 2, hour: 7, minute: 0,
                title: "Training Day",
                body: "Your scheduled workout is today. Open Forge to start strong."
            )
        }

        if settings.recoveryAlerts {
            await scheduleDaily(
                id: ID.recovery,
                hour: 9, minute: 30,
                title: "Recovery Check",
                body: "Review your HRV and sleep before deciding on intensity today."
            )
        }

        if settings.weeklySummary {
            await scheduleWeekly(
                id: ID.weeklySummary,
                weekday: 1, hour: 18, minute: 0,
                title: "Weekly Summary",
                body: "Your Forge week in review is ready."
            )
        }

        if settings.lifestyleReminders {
            await scheduleInterval(
                id: ID.lifestyleHydration,
                hours: 2,
                title: "Hydration Check",
                body: "Time for water — stay on track with your lifestyle goals."
            )
            await scheduleDaily(
                id: ID.lifestyleLunch,
                hour: 12, minute: 0,
                title: "Lunch Reminder",
                body: "Log your meal to keep protein and calories accurate."
            )
            await scheduleDaily(
                id: ID.lifestyleDinner,
                hour: 18, minute: 30,
                title: "Dinner Reminder",
                body: "Plan a protein-forward dinner to close your macro gap."
            )
            await scheduleDaily(
                id: ID.lifestyleSleep,
                hour: 21, minute: 0,
                title: "Wind Down",
                body: "Start your bedtime routine for better recovery tomorrow."
            )
        }

        if briefEnabled {
            await scheduleDaily(
                id: ID.briefMorning,
                hour: brief.morningHour, minute: brief.morningMinute,
                title: "ARIA Morning Brief",
                body: "Your personalized morning coaching brief is ready."
            )
            await scheduleDaily(
                id: ID.briefEvening,
                hour: brief.eveningHour, minute: brief.eveningMinute,
                title: "ARIA Evening Brief",
                body: "Review today's signals and tomorrow's focus."
            )
        }
    }

    private static func removeAllForgeNotifications() async {
        let ids = [
            ID.workout, ID.recovery, ID.weeklySummary,
            ID.lifestyleHydration, ID.lifestyleLunch, ID.lifestyleDinner, ID.lifestyleSleep,
            ID.briefMorning, ID.briefEvening,
            ID.cycleBBTReminder, ID.cycleOPKWindow, ID.cycleFertileWindow,
            ID.cyclePeriodReminder, ID.cyclePhaseTransition,
        ]
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    private static func scheduleDaily(id: String, hour: Int, minute: Int, title: String, body: String) async {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try? await center.add(request)
    }

    private static func scheduleWeekly(id: String, weekday: Int, hour: Int, minute: Int, title: String, body: String) async {
        var components = DateComponents()
        components.weekday = weekday
        components.hour = hour
        components.minute = minute
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try? await center.add(request)
    }

    private static func scheduleOnce(id: String, date: Date, title: String, body: String) async {
        guard date > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try? await center.add(request)
    }

    private static func scheduleInterval(id: String, hours: Int, title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(hours * 3600), repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try? await center.add(request)
    }
}