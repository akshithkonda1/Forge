import Foundation
import UIKit
import UserNotifications

struct AppNotificationSettings: Codable, Equatable {
    var workoutReminders: Bool = true
    var recoveryAlerts: Bool = true
    var weeklySummary: Bool = false
    var lifestyleReminders: Bool = true
}

struct BriefNotificationSettings: Codable, Equatable {
    var enabled: Bool = true
    var morningHour: Int = 7
    var morningMinute: Int = 0
    var eveningHour: Int = 21
    var eveningMinute: Int = 30
}

enum BriefNotificationSlot: String {
    case morning = "forge.brief.morning"
    case evening = "forge.brief.evening"
}

/// Schedules proactive ARIA morning/evening local notifications and handles remote APNs.
@MainActor
final class ForgeNotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ForgeNotificationCoordinator()

    private let center = UNUserNotificationCenter.current()
    private var didConfigureDelegate = false
    var onBriefNotificationTapped: ((String) -> Void)?

    private override init() {
        super.init()
    }

    func configure() {
        guard !didConfigureDelegate else { return }
        center.delegate = self
        didConfigureDelegate = true
    }

    func registerForRemotePushIfNeeded() {
        configure()
        UIApplication.shared.registerForRemoteNotifications()
    }

    func handleDeviceToken(_ tokenData: Data) {
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        Task {
            try? await ForgeRepository.shared.registerPushDevice(token: token)
        }
    }

    func handleRemoteRegistrationFailure(_ error: Error) {
        print("APNs registration failed: \(error.localizedDescription)")
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        configure()
        let status = await authorizationStatus()
        if status == .authorized || status == .provisional {
            return true
        }
        if status == .denied {
            return false
        }
        return await withCheckedContinuation { continuation in
            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    func scheduleProactiveBriefs(
        morning: ARIABrief?,
        evening: ARIABrief?,
        settings: BriefNotificationSettings = ForgePersistence.loadBriefNotificationSettings()
    ) async {
        configure()
        guard settings.enabled else {
            cancelBriefNotifications()
            return
        }
        guard await requestAuthorizationIfNeeded() else { return }

        cancelBriefNotifications()

        if let morning {
            await schedule(
                slot: .morning,
                brief: morning,
                hour: settings.morningHour,
                minute: settings.morningMinute
            )
        }
        if let evening {
            await schedule(
                slot: .evening,
                brief: evening,
                hour: settings.eveningHour,
                minute: settings.eveningMinute
            )
        }
    }

    func deliverImmediateBrief(_ brief: ARIABrief) async {
        configure()
        guard await requestAuthorizationIfNeeded() else { return }

        let content = UNMutableNotificationContent()
        content.title = brief.title
        content.body = brief.notificationCopy
        content.sound = .default
        content.userInfo = ["briefFocus": brief.focus.rawValue, "source": "immediate"]

        let request = UNNotificationRequest(
            identifier: "forge.brief.immediate.\(brief.focus.rawValue)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        try? await center.add(request)
    }

    func cancelBriefNotifications() {
        center.removePendingNotificationRequests(
            withIdentifiers: [
                BriefNotificationSlot.morning.rawValue,
                BriefNotificationSlot.evening.rawValue,
                "forge.brief.immediate.post-workout",
                "forge.brief.immediate.morning",
                "forge.brief.immediate.evening",
            ]
        )
    }

    private func schedule(
        slot: BriefNotificationSlot,
        brief: ARIABrief,
        hour: Int,
        minute: Int
    ) async {
        var date = DateComponents()
        date.calendar = Calendar.current
        date.timeZone = TimeZone.current
        date.hour = max(0, min(23, hour))
        date.minute = max(0, min(59, minute))

        let content = UNMutableNotificationContent()
        content.title = brief.title
        content.body = brief.notificationCopy
        content.sound = .default
        content.userInfo = [
            "briefFocus": brief.focus.rawValue,
            "trainingDecision": brief.trainingDecision.rawValue,
        ]

        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        let request = UNNotificationRequest(identifier: slot.rawValue, content: content, trigger: trigger)
        try? await center.add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let focus = response.notification.request.content.userInfo["briefFocus"] as? String
        if let focus {
            Task { @MainActor in
                ForgeNotificationCoordinator.shared.onBriefNotificationTapped?(focus)
            }
        }
        completionHandler()
    }
}

/// Bridges UIApplicationDelegate callbacks into SwiftUI.
final class ForgeAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            ForgeNotificationCoordinator.shared.handleDeviceToken(deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            ForgeNotificationCoordinator.shared.handleRemoteRegistrationFailure(error)
        }
    }
}