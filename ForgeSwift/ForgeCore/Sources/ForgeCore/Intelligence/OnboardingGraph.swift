import Foundation

/// The onboarding interview graph after #168.
///
/// Forward path is `freeTime → coaching → conditions → ready`. Conditions sits
/// at the end on purpose; sending it back to coaching is the death loop #168
/// closed. Sleep seeding and the header fraction live here too, because the
/// app coordinator is MainActor / HealthKit / SwiftUI and cannot compile on
/// Linux — this file is the piece `swift test` can actually lock.
public enum OnboardingGraph {

    public enum Step: String, CaseIterable, Sendable, Equatable {
        case intro, name, health, details, goals, experience, workouts
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

    /// The interview the header and progress bar count. Legacy theme/context
    /// screens are collapsed into `freeTime` and must not inflate the fraction.
    public static let activeSteps: [Step] = [
        .intro, .name, .health, .details, .goals, .experience,
        .workouts, .sleep, .freeTime, .coaching, .conditions, .ready,
    ]

    public static let sleepVarianceHabitId = "sleep_variance"

    public static func next(after action: Action) -> Step {
        switch action {
        case .confirmInterests: return .coaching
        case .selectCoachingStyle: return .conditions
        case .confirmConditions: return .ready
        }
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
        guard let idx = activeSteps.firstIndex(of: step) else { return 0 }
        return Double(idx) / Double(max(1, activeSteps.count - 1))
    }

    public static func displayIndex(for step: Step) -> Int {
        (activeSteps.firstIndex(of: step) ?? 0) + 1
    }

    public static var displayCount: Int { activeSteps.count }

    /// Start is a no-op unless both gates hold. `canFinish` already includes
    /// the terms checkbox today; requiring `hasAgreedToTerms` here means a
    /// future edit that drops it from `canFinish` still cannot complete.
    public static func allowsFinish(canFinish: Bool, hasAgreedToTerms: Bool) -> Bool {
        canFinish && hasAgreedToTerms
    }
}
