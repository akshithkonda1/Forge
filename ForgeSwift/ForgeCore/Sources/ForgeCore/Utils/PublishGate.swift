import Foundation

// ============================================================
// MARK: - Deciding whether something is worth uploading
// ============================================================

/// Decides whether a value has changed enough to be worth writing to a remote
/// store, and remembers what was last written.
///
/// It exists because the obvious wiring is wrong. "Publish the digest whenever
/// the cycle recomputes" sounds right and is a battery and rate-limit problem:
/// `recompute()` runs on every app foreground, every logged day, every HealthKit
/// sync and every readiness refresh — dozens of times a day. What it produces is
/// a four-field redacted digest that changes maybe once.
///
/// So the gate keys on **content**, not on the event. A recompute that produces
/// a byte-identical value writes nothing. Because the digest carries its own
/// `asOfDayKey`, a genuinely new day always differs and therefore always
/// publishes — freshness falls out of equality rather than needing its own timer.
///
/// Generic over the value, and in ForgeCore, because this is the one piece of
/// the publish path that is pure logic and can therefore be tested in CI. The
/// CloudKit call around it cannot.
public struct PublishGate<Value: Codable & Equatable> {

    public enum Decision: Equatable {
        /// Content differs from the last successful publish. Go.
        case publish
        /// Byte-identical to what is already up there.
        case skipUnchanged
        /// Changed, but the last write was too recent. Carries how long until
        /// the caller may try again, so a caller can schedule rather than spin.
        case skipTooSoon(retryAfter: TimeInterval)
    }

    private let lastValueKey: String
    private let lastDateKey: String
    private let minimumInterval: TimeInterval
    private let defaults: UserDefaults?

    /// - Parameters:
    ///   - key: Storage prefix. Two gates must not share one.
    ///   - minimumInterval: Floor between successful publishes. Guards against a
    ///     burst — logging four days in a row in one sitting changes the digest
    ///     four times, and only the last one matters.
    ///   - defaults: Where the watermark lives. Persisted rather than in-memory
    ///     so relaunching the app does not re-upload identical content.
    public init(key: String,
                minimumInterval: TimeInterval = 60,
                defaults: UserDefaults? = .standard) {
        self.lastValueKey = "\(key).lastValue"
        self.lastDateKey = "\(key).lastDate"
        self.minimumInterval = minimumInterval
        self.defaults = defaults
    }

    // ------------------------------------------------------------

    public func decide(_ value: Value, now: Date = Date()) -> Decision {
        guard let defaults else {
            // No storage means no memory of what was published, and publishing
            // twice is safer than never publishing at all.
            return .publish
        }

        if let data = defaults.data(forKey: lastValueKey),
           let previous = try? JSONDecoder().decode(Value.self, from: data),
           previous == value {
            return .skipUnchanged
        }

        let last = defaults.object(forKey: lastDateKey) as? Date
        if let last {
            let elapsed = now.timeIntervalSince(last)
            // A clock that moved backwards (timezone change, manual set) would
            // otherwise produce a negative elapsed and lock the gate shut for
            // however far back it jumped.
            if elapsed >= 0 && elapsed < minimumInterval {
                return .skipTooSoon(retryAfter: minimumInterval - elapsed)
            }
        }
        return .publish
    }

    /// Record a **successful** publish. Never call this after a failure: the
    /// watermark is what makes the next attempt skip, so recording a write that
    /// did not land would drop the change until the value happened to move again.
    public func recordPublished(_ value: Value, at date: Date = Date()) {
        guard let defaults, let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: lastValueKey)
        defaults.set(date, forKey: lastDateKey)
    }

    /// Forget everything. Called when sharing stops, so that re-sharing later
    /// publishes immediately instead of matching a watermark from a share the
    /// user has since revoked — the record it referred to no longer exists.
    public func reset() {
        defaults?.removeObject(forKey: lastValueKey)
        defaults?.removeObject(forKey: lastDateKey)
    }

    /// What was last successfully published, if anything. Lets a caller show
    /// "last updated" without a network round trip.
    public var lastPublishedAt: Date? {
        defaults?.object(forKey: lastDateKey) as? Date
    }
}
