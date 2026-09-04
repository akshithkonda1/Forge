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

    // MARK: Heart rate freshness

    /// How long a heart-rate reading stays usable as evidence about *now*.
    ///
    /// "Elevated heart rate at the gym place" is evidence of training in
    /// progress. The same number from three hours ago is evidence of a session
    /// already finished, and acting on it would suggest gym mode on the drive
    /// home.
    public static let heartRateFreshness: TimeInterval = 15 * 60

    /// The reading a background evaluation may reason from, or nil if it has
    /// gone stale.
    ///
    /// ContextEngine's evaluation loop has no HealthKit access of its own —
    /// HomeView hands it a reading on each foreground and refresh — so the
    /// engine remembers the last one and asks this whether it still counts.
    /// Before this existed the loop passed nil and `gymSuggestionAllowed`
    /// rejected it every time, so the place rule could only ever fire while
    /// Home was on screen.
    ///
    /// The comparison is absolute so a clock adjustment that stamps a reading
    /// slightly ahead of `now` does not read as infinitely fresh.
    public static func usableHeartRate(
        _ reading: HeartRateReading?,
        now: Date = Date(),
        freshness: TimeInterval = ContextRules.heartRateFreshness
    ) -> Double? {
        guard let reading,
              abs(now.timeIntervalSince(reading.takenAt)) <= freshness else { return nil }
        return reading.bpm
    }
}

/// A heart-rate sample with the time it was taken, so staleness is decidable.
public struct HeartRateReading: Equatable, Sendable {
    public var bpm: Double
    public var takenAt: Date

    public init(bpm: Double, takenAt: Date) {
        self.bpm = bpm
        self.takenAt = takenAt
    }
}
