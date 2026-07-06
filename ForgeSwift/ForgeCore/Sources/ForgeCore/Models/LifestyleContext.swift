import SwiftUI

// MARK: - Lifestyle context modes
//
// The watch is context-first: what Forge suggests depends on where the
// user is in their day, not just their biometrics. Modes are set manually
// in v1 (Phase 2) and progressively auto-detected (motion in Phase 2,
// location/geofences + calendar in Phase 4).

public enum LifestyleMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case deskCoding
    case deepFocus
    case gym
    case commute
    case homeRecovery
    case outdoor
    case windDown

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .deskCoding:   return "Desk / Coding"
        case .deepFocus:    return "Deep Focus"
        case .gym:          return "Gym"
        case .commute:      return "Commute"
        case .homeRecovery: return "Home Recovery"
        case .outdoor:      return "Outdoor"
        case .windDown:     return "Wind-Down"
        }
    }

    public var symbolName: String {
        switch self {
        case .deskCoding:   return "laptopcomputer"
        case .deepFocus:    return "brain.head.profile"
        case .gym:          return "dumbbell.fill"
        case .commute:      return "tram.fill"
        case .homeRecovery: return "house.fill"
        case .outdoor:      return "leaf.fill"
        case .windDown:     return "moon.stars.fill"
        }
    }

    public var accentColor: Color {
        switch self {
        case .deskCoding:   return ForgePalette.steel
        case .deepFocus:    return ForgePalette.indigo
        case .gym:          return ForgePalette.ember
        case .commute:      return ForgePalette.amber
        case .homeRecovery: return ForgePalette.jade
        case .outdoor:      return ForgePalette.success
        case .windDown:     return ForgePalette.violet
        }
    }

    /// Short supportive framing shown when the mode becomes active.
    public var activationMessage: String {
        switch self {
        case .deskCoding:   return "Focus mode on. I'll guard your energy between blocks."
        case .deepFocus:    return "Deep work protected. I'll stay out of the way unless your body needs a nudge."
        case .gym:          return "Let's make this session count — at the effort that's right for today."
        case .commute:      return "Transition time. A good moment to arrive settled, not rushed."
        case .homeRecovery: return "Recovery is training too. Ease in."
        case .outdoor:      return "Fresh air earns compound interest. Enjoy it."
        case .windDown:     return "Day's done. Let's land the plane gently."
        }
    }
}

/// A user's self-described lifestyle, used to tailor language and defaults.
/// Stored in UserDefaults for v1; syncs with the backend profile later.
public enum LifestyleProfile: String, Codable, CaseIterable, Sendable {
    case coder
    case deskWorker
    case deepSleeper
    case irregularSchedule
    case general

    public var displayName: String {
        switch self {
        case .coder:             return "Coder"
        case .deskWorker:        return "Desk worker"
        case .deepSleeper:       return "Deep sleeper"
        case .irregularSchedule: return "Irregular schedule"
        case .general:           return "General"
        }
    }
}
