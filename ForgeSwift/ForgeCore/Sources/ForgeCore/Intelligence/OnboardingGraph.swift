import Foundation

/// The onboarding interview graph after the friend-first six beats.
///
/// Visible path is `intro → name → health → freeTime → coaching → ready`
/// (Meet, Name, Health, Habits, Tone, First chat). Collapsed screens stay
/// on `Step` for migration — they are not in `activeSteps` and normalize
/// onto the six beats. `confirmConditions → ready` still never returns to
/// coaching (the #168 death loop). Sleep seeding and the header fraction
/// live here because the app coordinator is MainActor / HealthKit / SwiftUI
/// and cannot compile on Linux — this file is the piece `swift test` locks.
public enum OnboardingGraph {

    public enum Step: String, CaseIterable, Sendable, Equatable {
        case intro, name, health, details, goals, experience, workouts
        case schedule
        case sleep, freeTime, coaching, conditions, ready
        /// Kept for migration. Not in `activeSteps`.
        case trainingTheme, lifeContext
    }

    /// SleepRhythmBand on the app side must match these raw values.
    /// There is no `.inconsistent` — the case is `.irregular`.
    public enum SleepBand: String, CaseIterable, Sendable, Equatable {
        case earlyBird, average, nightOwl, irregular
    }

    public enum Action: String, Sendable, Equatable {
        case confirmInterests
        case selectCoachingStyle
        case confirmConditions
    }

    /// The interview the header and progress bar count. Six friend-first
    /// beats only — collapsed screens must not inflate the fraction.
    public static let activeSteps: [Step] = [
        .intro, .name, .health, .freeTime, .coaching, .ready,
    ]

    public static let sleepVarianceHabitId = "sleep_variance"

    /// Map a persisted or leftover step onto the six visible beats.
    public static func normalized(_ step: Step) -> Step {
        switch step {
        case .intro, .name, .health, .freeTime, .coaching, .ready:
            return step
        case .details:
            return .health
        case .goals, .experience, .workouts, .schedule, .sleep, .trainingTheme, .lifeContext:
            return .freeTime
        case .conditions:
            return .coaching
        }
    }

    public static func next(after action: Action) -> Step {
        switch action {
        case .confirmInterests: return .coaching
        case .selectCoachingStyle: return .ready
        case .confirmConditions: return .ready
        }
    }

    /// Walks `activeSteps` backward. Intro has no predecessor. Name is the
    /// first answerable screen, so back from Name is also nil — leaving the
    /// interview is sign-out, not a silent return to the auto-played intro.
    /// Collapsed leftover screens normalize onto the six beats first.
    public static func previous(of step: Step) -> Step? {
        let beat = normalized(step)
        guard let idx = activeSteps.firstIndex(of: beat), idx > 1 else {
            return nil
        }
        return activeSteps[idx - 1]
    }

    public static func seedsSleepVariance(_ band: SleepBand) -> Bool {
        switch band {
        case .nightOwl, .irregular: return true
        case .earlyBird, .average: return false
        }
    }

    public static func seedsSleepVariance(bandRawValue: String) -> Bool {
        guard let band = SleepBand(rawValue: bandRawValue) else { return false }
        return seedsSleepVariance(band)
    }

    /// 0...1 over `activeSteps`, never `Step.allCases` (that still lists the
    /// two collapsed screens and would leave Ready short of a full bar).
    public static func progress(at step: Step) -> Double {
        let beat = normalized(step)
        guard let idx = activeSteps.firstIndex(of: beat) else { return 0 }
        return Double(idx) / Double(max(1, activeSteps.count - 1))
    }

    public static func displayIndex(for step: Step) -> Int {
        (activeSteps.firstIndex(of: normalized(step)) ?? 0) + 1
    }

    public static var displayCount: Int { activeSteps.count }

    /// Start is a no-op unless both gates hold. `canFinish` already includes
    /// the terms checkbox today; requiring `hasAgreedToTerms` here means a
    /// future edit that drops it from `canFinish` still cannot complete.
    public static func allowsFinish(canFinish: Bool, hasAgreedToTerms: Bool) -> Bool {
        canFinish && hasAgreedToTerms
    }
}
