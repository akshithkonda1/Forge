import Foundation

// MARK: - ContextRules
//
// The ContextEngine's decision rules as pure functions, extracted so the
// proactive-trigger behavior is unit-testable without CoreMotion or
// CoreLocation. The watch engine supplies signals; these decide.

public enum ContextRules {

    /// The flagship trigger: 90+ minutes in a desk/focus mode, once per block.
    public static func deskBlockNudgeDue(
        mode: LifestyleMode?,
        minutesInMode: Double?,
        alreadyFiredThisBlock: Bool
    ) -> Bool {
        guard let mode, mode == .deskCoding || mode == .deepFocus,
              let minutes = minutesInMode, minutes >= 90,
              !alreadyFiredThisBlock else { return false }
        return true
    }

    /// Evening wind-down suggestion, timed by the predictor when it has
    /// learned the rhythm, 21:00 otherwise. Never re-suggests over an
    /// existing suggestion or when already winding down.
    public static func eveningWindDownDue(
        now: Date,
        predictedWindDown: Date?,
        currentMode: LifestyleMode?,
        pendingSuggestion: LifestyleMode?,
        calendar: Calendar = .current
    ) -> Bool {
        guard currentMode != .windDown, pendingSuggestion != .windDown else { return false }
        if let predictedWindDown {
            return now >= predictedWindDown
        }
        return calendar.component(.hour, from: now) >= 21
    }

    /// Motion heuristic: mostly still during working hours with no mode
    /// set → probably a desk block. Offer, don't assume.
    public static func deskModeLikely(
        stationaryShare: Double,
        hour: Int,
        currentMode: LifestyleMode?,
        pendingSuggestion: LifestyleMode?
    ) -> Bool {
        currentMode == nil
            && pendingSuggestion == nil
            && stationaryShare > 0.8
            && (9..<19).contains(hour)
    }

    /// Gym-place corroboration: proximity alone is the car park; elevated
    /// heart rate there means training.
    public static func gymSuggestionAllowed(recentHeartRate: Double?) -> Bool {
        guard let bpm = recentHeartRate else { return false }
        return bpm >= 100
    }
}
