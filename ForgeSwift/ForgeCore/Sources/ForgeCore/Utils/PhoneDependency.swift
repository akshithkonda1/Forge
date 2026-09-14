import Foundation

// MARK: - PhoneDependency
//
// Capability policy for Forge Watch: the wrist runs independently for glanceable,
// on-device work, while actions that need the paired iPhone (ARIA chat handoff,
// deeper networked coaching, Live Activity mirroring expectations) are gated.
//
// Pure logic lives here so CI can test the policy without WCSession.

public enum WatchCapability: String, Sendable, CaseIterable, Equatable {
    /// Instant on-device greeting + practice suggestion + day brief.
    case standaloneAria
    /// Local mindfulness / reset session + local debrief.
    case localMindfulness
    /// Local workout start/run/end + local summary.
    case localWorkout
    /// Sleep glance, wind-down reminder, week history.
    case localSleepAndWeek
    /// Hydration logging + lifestyle context.
    case localLifestyle
    /// Networked deeper debrief upgrade (needs phone-synced auth + usually reachability).
    case deeperAriaDebrief
    /// Hand off to full ARIA chat / review on iPhone.
    case phoneAriaChat
    /// Expect Live Activity / Dynamic Island mirroring on iPhone.
    case liveActivityMirror
    /// Explicit "open on iPhone" / sync CTAs.
    case phoneSyncCTA
}

public enum CompanionAvailability: String, Sendable, Equatable {
    /// WCSession not activated yet (or unsupported).
    case unknown
    /// No companion installed / unpaired.
    case unavailable
    /// Companion exists but is not currently reachable.
    case linkedButUnreachable
    /// Companion is reachable right now.
    case reachable
}

public enum PhoneDependency: Sendable {

    /// Whether ``capability`` is allowed under the current companion state.
    ///
    /// - Standalone capabilities always allow — Watch independence is the default.
    /// - Phone-required capabilities need a reachable iPhone. Auth-gated network
    ///   upgrades additionally need ``hasAuthConfig``.
    public static func allows(
        _ capability: WatchCapability,
        availability: CompanionAvailability,
        hasAuthConfig: Bool
    ) -> Bool {
        switch capability {
        case .standaloneAria, .localMindfulness, .localWorkout,
             .localSleepAndWeek, .localLifestyle:
            return true

        case .deeperAriaDebrief:
            // Needs credentials pushed from the phone, and a reachable companion
            // so we don't imply a chat handoff that can't happen.
            return hasAuthConfig && availability == .reachable

        case .phoneAriaChat, .liveActivityMirror, .phoneSyncCTA:
            return availability == .reachable
        }
    }

    /// Short, calm copy for a gated control. Nil when the action is allowed.
    public static func explanation(
        for capability: WatchCapability,
        availability: CompanionAvailability,
        hasAuthConfig: Bool
    ) -> String? {
        guard !allows(capability, availability: availability, hasAuthConfig: hasAuthConfig) else {
            return nil
        }
        switch capability {
        case .deeperAriaDebrief:
            if !hasAuthConfig {
                return "Sign in on your iPhone to unlock deeper ARIA coaching."
            }
            return "Needs your iPhone nearby for deeper ARIA coaching."
        case .phoneAriaChat, .phoneSyncCTA:
            return "Needs your iPhone nearby."
        case .liveActivityMirror:
            return "Live Activity mirroring needs your iPhone nearby."
        case .standaloneAria, .localMindfulness, .localWorkout,
             .localSleepAndWeek, .localLifestyle:
            return nil
        }
    }

    /// Home / status banner when the watch is running without the phone.
    public static func independenceBanner(for availability: CompanionAvailability) -> String? {
        switch availability {
        case .reachable, .unknown:
            return nil
        case .linkedButUnreachable:
            return "Running on Watch — some actions need your iPhone nearby."
        case .unavailable:
            return "Running on Watch — pair Forge on iPhone for full ARIA."
        }
    }
}
