import SwiftUI

// MARK: - Mindfulness practices
//
// Practices are defined as data (phase sequences with durations) so the
// BreathingOrb, the haptic scheduler, and the voice guidance all read the
// same source of truth. All timings are slow (>= 1s per phase) — an
// epilepsy-safety invariant: nothing in a session may pulse faster than
// the user's own breath.

public enum BreathPhaseKind: String, Codable, Sendable {
    case inhale
    case quickInhale   // the physiological sigh's second, short sip of air
    case holdIn
    case exhale
    case holdOut
    case rest          // open awareness segments (body scan, presence)

    public var instruction: String {
        switch self {
        case .inhale:      return "Breathe in"
        case .quickInhale: return "Sip in a little more"
        case .holdIn:      return "Hold"
        case .exhale:      return "Long breath out"
        case .holdOut:     return "Rest empty"
        case .rest:        return "Just notice"
        }
    }

    /// Whether the orb grows (inhale), shrinks (exhale) or stays (holds/rest).
    public var orbDirection: Double {
        switch self {
        case .inhale, .quickInhale: return 1
        case .exhale:               return -1
        case .holdIn, .holdOut, .rest: return 0
        }
    }
}

public struct BreathPhase: Codable, Sendable, Equatable {
    public let kind: BreathPhaseKind
    public let duration: TimeInterval

    public init(_ kind: BreathPhaseKind, _ duration: TimeInterval) {
        self.kind = kind
        self.duration = duration
    }
}

public struct BreathingPattern: Codable, Sendable, Equatable {
    public let phases: [BreathPhase]

    public init(phases: [BreathPhase]) {
        self.phases = phases
    }

    public var cycleDuration: TimeInterval {
        phases.reduce(0) { $0 + $1.duration }
    }

    /// Resolves the active phase and 0...1 progress within it for a given
    /// point in the session. Pure function — drives Canvas rendering.
    public func phase(at elapsed: TimeInterval) -> (phase: BreathPhase, progress: Double) {
        guard cycleDuration > 0, let first = phases.first else {
            return (BreathPhase(.rest, 1), 0)
        }
        let t = elapsed.truncatingRemainder(dividingBy: cycleDuration)
        var cursor: TimeInterval = 0
        for phase in phases {
            if t < cursor + phase.duration {
                return (phase, (t - cursor) / phase.duration)
            }
            cursor += phase.duration
        }
        return (first, 0)
    }
}

public enum PracticeType: String, Codable, CaseIterable, Identifiable, Sendable {
    case physiologicalSigh
    case boxBreathing
    case focusReset
    case bodyScan
    case windDown
    case morningGrounding
    case stressRelease

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .physiologicalSigh: return "Physiological Sigh"
        case .boxBreathing:      return "Box Breathing"
        case .focusReset:        return "Focus Reset"
        case .bodyScan:          return "Body Scan"
        case .windDown:          return "Wind-Down"
        case .morningGrounding:  return "Morning Grounding"
        case .stressRelease:     return "Stress Release"
        }
    }

    public var symbolName: String {
        switch self {
        case .physiologicalSigh: return "wind"
        case .boxBreathing:      return "square.dashed"
        case .focusReset:        return "scope"
        case .bodyScan:          return "figure.mind.and.body"
        case .windDown:          return "moon.zzz.fill"
        case .morningGrounding:  return "sunrise.fill"
        case .stressRelease:     return "leaf.fill"
        }
    }

    public var accentColor: Color {
        switch self {
        case .physiologicalSigh: return ForgePalette.teal
        case .boxBreathing:      return ForgePalette.steel
        case .focusReset:        return ForgePalette.steelLight
        case .bodyScan:          return ForgePalette.violet
        case .windDown:          return ForgePalette.indigo
        case .morningGrounding:  return ForgePalette.amber
        case .stressRelease:     return ForgePalette.jade
        }
    }

    public var pattern: BreathingPattern {
        switch self {
        case .physiologicalSigh:
            // Double inhale, long exhale — fastest known downshift lever.
            return BreathingPattern(phases: [
                BreathPhase(.inhale, 4),
                BreathPhase(.quickInhale, 1.5),
                BreathPhase(.exhale, 7),
                BreathPhase(.holdOut, 1.5),
            ])
        case .boxBreathing:
            return BreathingPattern(phases: [
                BreathPhase(.inhale, 4),
                BreathPhase(.holdIn, 4),
                BreathPhase(.exhale, 4),
                BreathPhase(.holdOut, 4),
            ])
        case .focusReset:
            // Slightly extended exhale keeps it calming without drowsiness.
            return BreathingPattern(phases: [
                BreathPhase(.inhale, 4),
                BreathPhase(.holdIn, 2),
                BreathPhase(.exhale, 6),
            ])
        case .bodyScan:
            return BreathingPattern(phases: [
                BreathPhase(.inhale, 5),
                BreathPhase(.exhale, 7),
                BreathPhase(.rest, 8),
            ])
        case .windDown:
            // 4-7-8-inspired, softened for comfort on the wrist.
            return BreathingPattern(phases: [
                BreathPhase(.inhale, 4),
                BreathPhase(.holdIn, 6),
                BreathPhase(.exhale, 8),
            ])
        case .morningGrounding:
            return BreathingPattern(phases: [
                BreathPhase(.inhale, 4),
                BreathPhase(.holdIn, 3),
                BreathPhase(.exhale, 5),
                BreathPhase(.rest, 3),
            ])
        case .stressRelease:
            return BreathingPattern(phases: [
                BreathPhase(.inhale, 4),
                BreathPhase(.exhale, 8),
            ])
        }
    }

    /// Durations offered in the picker, in seconds. 90s options make the
    /// "fits between coding blocks" promise real.
    public var offeredDurations: [TimeInterval] {
        switch self {
        case .physiologicalSigh: return [90, 180, 300]
        case .focusReset:        return [90, 180, 300]
        case .boxBreathing:      return [180, 300, 600]
        case .stressRelease:     return [180, 300, 600]
        case .morningGrounding:  return [180, 300]
        case .bodyScan:          return [300, 600]
        case .windDown:          return [240, 300, 600]
        }
    }

    public var defaultDuration: TimeInterval { offeredDurations.first ?? 180 }
}

// MARK: - Recommendation & session records

public struct MindfulnessRecommendation: Codable, Sendable, Equatable {
    public var practice: PracticeType
    public var duration: TimeInterval
    /// Max two sentences, supportive, explains "why this helps right now".
    public var reason: String
    /// Which signal produced this (for debugging and ARIA context), e.g.
    /// "desk-block-90m", "low-readiness-morning".
    public var trigger: String

    public init(practice: PracticeType, duration: TimeInterval, reason: String, trigger: String) {
        self.practice = practice
        self.duration = duration
        self.reason = reason
        self.trigger = trigger
    }

    public var durationLabel: String {
        duration < 120
            ? "\(Int(duration))-second"
            : "\(Int(duration / 60))-minute"
    }
}

/// Zero-judgment skip reasons. Skipping is data, never failure.
public enum SkipReason: String, Codable, CaseIterable, Identifiable, Sendable {
    case tooBusy
    case notFeelingIt
    case alreadyDidOne
    case laterToday

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .tooBusy:       return "Too busy right now"
        case .notFeelingIt:  return "Not feeling it"
        case .alreadyDidOne: return "Already did one"
        case .laterToday:    return "Maybe later today"
        }
    }

    /// The response the user sees after skipping — always warm, never guilt.
    public var acknowledgement: String {
        switch self {
        case .tooBusy:       return "Understood — protecting your time is healthy too. I'll keep this handy."
        case .notFeelingIt:  return "Fair enough. It'll be here when it feels right."
        case .alreadyDidOne: return "Nice — that one counts. Enjoy the calm."
        case .laterToday:    return "Sounds good. I'll gently resurface it later."
        }
    }
}

public struct MindfulnessSessionRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var practice: PracticeType
    public var startedAt: Date
    public var endedAt: Date
    public var completed: Bool
    public var skipReason: SkipReason?

    public init(
        id: UUID = UUID(),
        practice: PracticeType,
        startedAt: Date,
        endedAt: Date,
        completed: Bool,
        skipReason: SkipReason? = nil
    ) {
        self.id = id
        self.practice = practice
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.completed = completed
        self.skipReason = skipReason
    }

    public var minutes: Double {
        endedAt.timeIntervalSince(startedAt) / 60.0
    }
}
