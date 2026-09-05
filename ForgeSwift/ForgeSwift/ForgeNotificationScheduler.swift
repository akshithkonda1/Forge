import Foundation
import UserNotifications
import ForgeCore

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
        static let weeklyAriaReview = "forge.notification.aria.weekly"
        // Cycle health
        static let cycleBBTReminder = "forge.notif.cycle.bbt"
        static let cycleOPKWindow = "forge.notif.cycle.opk"
        static let cycleFertileWindow = "forge.notif.cycle.fertile"
        static let cyclePeriodReminder = "forge.notif.cycle.period"
        static let cyclePhaseTransition = "forge.notif.cycle.phase"
        /// Local, on the supporter's phone. Body is lock-safe — never a phase.
        static let partnerSupport = "forge.notif.partner.support"
    }

    static func sync(
        settings: AppNotificationSettings,
        briefEnabled: Bool,
        brief: BriefNotificationSettings
    ) async {
        do { try await center.requestAuthorization(options: [.alert, .sound, .badge]) } catch {}

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

        // Weekly evaluation is its own loop — not tied to the daily brief toggle.
        await scheduleWeekly(
            id: ID.weeklyAriaReview,
            weekday: 1, hour: 10, minute: 0,
            title: "ARIA weekly evaluation",
            body: "Five questions. ARIA files the answers as standing context for the week ahead.",
            destination: "forge://aria/weekly"
        )
    }

    private static func removeAllForgeNotifications() async {
        let ids = [
            ID.workout, ID.recovery, ID.weeklySummary,
            ID.lifestyleHydration, ID.lifestyleLunch, ID.lifestyleDinner, ID.lifestyleSleep,
            ID.briefMorning, ID.briefEvening, ID.weeklyAriaReview,
            ID.cycleBBTReminder, ID.cycleOPKWindow, ID.cycleFertileWindow,
            ID.cyclePeriodReminder, ID.cyclePhaseTransition,
        ]
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    // MARK: - Cycle notifications

    static func syncCycleNotifications(
        settings: MenstrualTrackingSettings,
        snapshot: MenstrualCycleSnapshot
    ) async {
        let cycleIds = [
            ID.cycleBBTReminder, ID.cycleOPKWindow, ID.cycleFertileWindow,
            ID.cyclePeriodReminder, ID.cyclePhaseTransition,
        ]
        center.removePendingNotificationRequests(withIdentifiers: cycleIds)
        center.removeDeliveredNotifications(withIdentifiers: cycleIds)

        guard settings.enabled else { return }
        if settings.discretionMode == .stealth { return }

        let kind = settings.discretionMode == .kind

        // 1. Daily BBT reminder at user-configured hour
        if settings.bbtReminderEnabled {
            await scheduleDaily(
                id: ID.cycleBBTReminder,
                hour: settings.bbtReminderHour,
                minute: 0,
                title: kind ? "Morning log" : "Log your BBT",
                body: kind
                    ? "A quiet morning reading when you have a moment."
                    : "Take your temperature before getting up — consistency improves your cycle accuracy."
            )
        }

        // 2. OPK window alert — 3 days before predicted ovulation
        if settings.highAccuracyMode, !kind,
           let ovulationDayKey = snapshot.nextOvulationDayKey,
           let ovulationDate = CycleDayKey.date(from: ovulationDayKey) {
            let opkStart = Calendar.current.date(byAdding: .day, value: -3, to: ovulationDate) ?? ovulationDate
            if opkStart > Date() {
                await scheduleOnce(
                    id: ID.cycleOPKWindow,
                    date: opkStart,
                    title: "Ovulation test window open",
                    body: "Your predicted ovulation is in ~3 days. Start LH testing now for best results."
                )
            }
        }

        // 3. Fertile window alert — 2 days before window opens
        if settings.fertileWindowAlertEnabled, !kind,
           let nextPeriodMedian = snapshot.nextPeriod.flatMap({ CycleDayKey.date(from: $0.medianDayKey) }) {
            let luteal = settings.typicalLutealDays
            let ovulationDate = Calendar.current.date(byAdding: .day, value: -luteal, to: nextPeriodMedian) ?? nextPeriodMedian
            let fertileOpen = Calendar.current.date(byAdding: .day, value: -5, to: ovulationDate) ?? ovulationDate
            let alertDate = Calendar.current.date(byAdding: .day, value: -2, to: fertileOpen) ?? fertileOpen
            if alertDate > Date() {
                await scheduleOnce(
                    id: ID.cycleFertileWindow,
                    date: alertDate,
                    title: "Fertile window opening soon",
                    body: "Your fertile window is predicted to open in ~2 days."
                )
            }
        }

        // 4. Period reminder — 1 day before predicted start
        if settings.periodReminderEnabled {
            guard let nextPeriod = snapshot.nextPeriod,
                  let nextPeriodDate = CycleDayKey.date(from: nextPeriod.medianDayKey) else { return }
            let reminderDate = Calendar.current.date(byAdding: .day, value: -1, to: nextPeriodDate) ?? nextPeriodDate
            if reminderDate > Date() {
                await scheduleOnce(
                    id: ID.cyclePeriodReminder,
                    date: reminderDate,
                    title: kind ? "Take it easy tomorrow" : "Period predicted tomorrow",
                    body: kind
                        ? "A little extra care may land well. Open Forge for the rest."
                        : "Your period is expected to start around tomorrow (\(nextPeriod.earliestDayKey) – \(nextPeriod.latestDayKey))."
                )
            }
        }
    }

    /// Morning “how to help” on the supporter's phone. Uses the lock-safe line
    /// so a lock screen never names a period. Cleared when the share is empty,
    /// paused, or stale.
    static func syncPartnerSupport(_ glance: PartnerSupportGlance?) async {
        center.removePendingNotificationRequests(withIdentifiers: [ID.partnerSupport])
        center.removeDeliveredNotifications(withIdentifiers: [ID.partnerSupport])
        guard let glance, !glance.isPaused, !glance.isStale else { return }
        do { try await center.requestAuthorization(options: [.alert, .sound, .badge]) } catch {}
        await scheduleDaily(
            id: ID.partnerSupport,
            hour: 8, minute: 0,
            title: glance.notificationTitle,
            body: glance.notificationBody,
            destination: ForgeWidgetLink.support.absoluteString
        )
    }

    private static func scheduleDaily(
        id: String,
        hour: Int,
        minute: Int,
        title: String,
        body: String,
        destination: String? = nil
    ) async {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let destination {
            content.userInfo = ["destination": destination]
        }
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try? await center.add(request)
    }

    private static func scheduleWeekly(
        id: String,
        weekday: Int,
        hour: Int,
        minute: Int,
        title: String,
        body: String,
        destination: String? = nil
    ) async {
        var components = DateComponents()
        components.weekday = weekday
        components.hour = hour
        components.minute = minute
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let destination {
            content.userInfo = ["destination": destination]
        }
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
