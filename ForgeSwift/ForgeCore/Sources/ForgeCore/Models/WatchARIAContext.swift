import Foundation

// MARK: - WatchARIAContext
//
// A deliberately lightweight subset of the iOS `ARIAContextPayload`,
// sized for the wrist: everything the on-device suggestion engine and
// the (future) `/watch/aria/suggest` backend endpoint need, nothing more.
// Field names align with the iOS payload's domains so the backend can
// share scoring/triage logic with SimRunner.

public struct WatchARIAContext: Codable, Sendable, Equatable {
    public var timestamp: Date

    // Readiness snapshot (locally calculated or synced)
    public var readinessOverall: Int?
    public var readinessConfidence: Double?

    // Recent HRV trend over the last 1-4h: negative = dipping.
    public var hrvRecentMs: Double?
    public var hrvTrendMs: Double?

    // Last night
    public var sleepMinutes: Double?
    public var deepSleepMinutes: Double?
    public var remSleepMinutes: Double?
    public var sleepQualityScore: Int?

    // Lifestyle context
    public var lifestyleMode: LifestyleMode?
    public var minutesInCurrentMode: Double?
    public var lifestyleProfile: LifestyleProfile?

    // Training load
    public var hoursSinceLastWorkout: Double?
    public var lastWorkoutType: String?
    public var yesterdayStrain: Double?

    // Mindfulness history (today)
    public var mindfulMinutesToday: Double?
    public var sessionsCompletedToday: Int?

    // One-tap sleep factors the user logged for last night / today.
    public var sleepFactors: [SleepFactor]?

    public init(timestamp: Date = Date()) {
        self.timestamp = timestamp
    }

    // MARK: Convenience signals used by the suggestion engine

    public var hourOfDay: Int {
        Calendar.current.component(.hour, from: timestamp)
    }

    public var isMorning: Bool { (5..<11).contains(hourOfDay) }
    public var isEvening: Bool { hourOfDay >= 20 || hourOfDay < 4 }

    public var hrvIsDipping: Bool {
        guard let trend = hrvTrendMs else { return false }
        return trend <= -5
    }

    public var inLongDeskBlock: Bool {
        guard let mode = lifestyleMode, let minutes = minutesInCurrentMode else { return false }
        return (mode == .deskCoding || mode == .deepFocus) && minutes >= 90
    }

    public var justFinishedWorkout: Bool {
        guard let hours = hoursSinceLastWorkout else { return false }
        return hours <= 0.75
    }
}
