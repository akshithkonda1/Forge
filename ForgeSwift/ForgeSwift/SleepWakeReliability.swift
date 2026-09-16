import AVFoundation
import Foundation
import UserNotifications
import ForgeCore

/// Public Apple APIs this wake path is allowed to use.
///
/// AlarmKit and Critical Alerts are real SDK surfaces, but they are **not**
/// in the Forge entitlements tree (`ForgeSwift.entitlements` has HealthKit,
/// CloudKit, MusicKit — not `com.apple.developer.alarmkit` or
/// `com.apple.developer.usernotifications.critical-alerts`). Requesting those
/// without the entitlement fails at runtime, so this wake stays on
/// UserNotifications + AVAudioSession + background audio, which already ship.
enum SleepAlarmAppleAPI: Sendable {
    static var authorizationOptions: UNAuthorizationOptions { [.alert, .sound, .badge] }
    static var interruptionLevel: UNNotificationInterruptionLevel { .timeSensitive }
    static var notificationSound: UNNotificationSound { .default }
    static var playbackSession: ForgePlaybackSession { .alarm }
    static var backgroundAudioMode: String { "audio" }

    /// Minimum repeating interval Apple accepts on `UNTimeIntervalNotificationTrigger`.
    static var failsafePingSeconds: TimeInterval { 60 }
}

/// Armed vs fail-closed. Never a quiet no-op: if the wake cannot fire, the
/// Sleep / Wake tab says so in lifestyle-coach language (not a sleep clinic).
enum SleepAlarmDelivery: Equatable, Sendable {
    case unknown
    case armed(pending: Int, timeSensitive: Bool)
    case notificationsOff
    case quietDelivery
    case scheduleIncomplete(expected: Int, pending: Int)
    case authorizationFailed(String)

    var isFailClosed: Bool {
        switch self {
        case .armed, .unknown: return false
        default: return true
        }
    }

    var needsAttention: Bool {
        if case .armed(_, let timeSensitive) = self { return !timeSensitive }
        return isFailClosed
    }

    /// One-line Sleep header / banner. Lifestyle coach, never a medical claim.
    var headline: String {
        switch self {
        case .unknown:
            return "Checking that this wake can actually fire."
        case .armed(_, true):
            return "Wake is armed. Hard alarm still stands."
        case .armed(_, false):
            return "Wake is scheduled, but Focus can silence it. Time Sensitive is off."
        case .notificationsOff:
            return "Notifications are off, so this wake cannot fire."
        case .quietDelivery:
            return "Notifications are quiet-delivery only, so this wake can miss."
        case .scheduleIncomplete:
            return "Wake did not fully schedule. It will not fail quietly."
        case .authorizationFailed:
            return "iPhone refused notification permission. Wake cannot fire."
        }
    }

    var cue: String {
        switch self {
        case .unknown:
            return "Forge is confirming UserNotifications can deliver the hard alarm."
        case .armed(let pending, true):
            return "\(pending) pending wake notice\(pending == 1 ? "" : "s"). Rising tone, then a backup if you're still down."
        case .armed(let pending, false):
            return "\(pending) pending. Settings → Focus → allow Time Sensitive for Forge, or the hard alarm can stay silent."
        case .notificationsOff:
            return "Settings → Notifications → Forge. Alerts and Sounds have to be on or the morning never starts."
        case .quietDelivery:
            return "Provisional delivery is too quiet for a wake. Allow alerts in Settings → Notifications → Forge."
        case .scheduleIncomplete(let expected, let pending):
            return "Expected \(expected) pending wakes, iPhone kept \(pending). Open Wake and save the alarm again."
        case .authorizationFailed(let reason):
            return reason
        }
    }
}

/// Volume ramp, then a piercing backup, then haptics. Repeat strugglers skip
/// the polite climb. Lifestyle framing: harder to sleep through — not a treatment.
enum SleepWakeEscalation: Sendable {
    enum Stage: String, Equatable, Sendable {
        case primary
        case backup
        case insistent
    }

    /// Backup two-tone (A5 + E6). Distinct from every picker sound.
    static let backupFrequencies: (Double, Double) = (880, 1_319.51)

    static func stage(
        elapsed: TimeInterval,
        rampSeconds: Double,
        struggling: Bool
    ) -> Stage {
        let backupAt = struggling ? 8 : max(rampSeconds, 20)
        let insistentAt = struggling ? 20 : backupAt + 25
        if elapsed >= insistentAt { return .insistent }
        if elapsed >= backupAt { return .backup }
        return .primary
    }

    static func hapticCadenceSeconds(stage: Stage, faulted: Bool) -> TimeInterval? {
        if faulted { return 0.9 }
        switch stage {
        case .primary: return nil
        case .backup: return 1.6
        case .insistent: return 1.0
        }
    }

    static func ramp(
        gradualVolume: Bool,
        struggling: Bool,
        selected: VolumeRampCurve
    ) -> VolumeRampCurve {
        if struggling { return .instant }
        if gradualVolume { return selected }
        return .instant
    }
}

/// Why the rising tone is not in the room. Honesty, never a silent `return`.
enum SleepWakeAudioFault: Equatable, Sendable {
    case none
    case sessionActivateFailed
    case engineStartFailed
    case sessionDropped
    case formatUnavailable

    var isFailClosed: Bool { self != .none }

    var coachLine: String {
        switch self {
        case .none:
            return ""
        case .sessionActivateFailed:
            return "The audio session did not activate. Haptic is the backup — this wake will not go quiet."
        case .engineStartFailed:
            return "The wake engine did not start. Haptic is the backup — hold I'm up, then try Test wake."
        case .sessionDropped:
            return "iPhone dropped the audio session mid-wake. Trying again; haptic keeps going until you hold I'm up."
        case .formatUnavailable:
            return "This iPhone could not build the wake tone. Haptic is the backup so the morning still lands."
        }
    }
}

enum SleepAlarmScheduleMath: Sendable {
    /// Repeating hard + optional smart, one request per weekday. Snooze / live /
    /// failsafe pings are session-only and do not count here.
    static func expectedPendingCount(in alarms: [ForgeAlarm]) -> Int {
        alarms.reduce(0) { sum, alarm in
            guard alarm.isEnabled else { return sum }
            let days = alarm.days.isEmpty ? 7 : Set(alarm.days).count
            return sum + days * (alarm.isSmartWake ? 2 : 1)
        }
    }

    static func isStandingWakeNotification(_ identifier: String) -> Bool {
        guard SleepWakeEngine.isWakeNotification(identifier) else { return false }
        if identifier.contains(".failsafe.") { return false }
        if identifier.contains(".snooze.") { return false }
        if identifier.contains(".live.") { return false }
        return true
    }

    static func delivery(
        authorization: UNAuthorizationStatus,
        timeSensitive: UNNotificationSetting,
        expected: Int,
        pending: Int,
        addFailures: Int,
        authError: String?
    ) -> SleepAlarmDelivery {
        if let authError, authorization != .authorized {
            return .authorizationFailed(authError)
        }
        switch authorization {
        case .denied:
            return .notificationsOff
        case .provisional, .ephemeral:
            return .quietDelivery
        case .notDetermined:
            return .notificationsOff
        case .authorized:
            break
        @unknown default:
            return .notificationsOff
        }
        if addFailures > 0 || (expected > 0 && pending < expected) {
            return .scheduleIncomplete(expected: expected, pending: pending)
        }
        return .armed(pending: pending, timeSensitive: timeSensitive != .disabled)
    }
}
