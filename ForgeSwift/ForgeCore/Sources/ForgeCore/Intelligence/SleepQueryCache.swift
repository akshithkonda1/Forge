import Foundation

// MARK: - Anchored sleep query fingerprint + process cache
//
// iOS and Watch share ForgeHealthQueries' 16-day anchored window. A days:1
// probe must not overwrite the scored-night cache; callers compare this
// fingerprint before regrouping.

public enum SleepQueryFingerprint: Equatable, Sendable, Hashable {
    case sessions(count: Int, digest: String)

    public static func sessions(_ rows: [(date: String, hours: Double, wakeEpoch: TimeInterval)]) -> SleepQueryFingerprint {
        let digest = rows.map { "\($0.date):\($0.hours):\($0.wakeEpoch)" }.joined(separator: "|")
        return .sessions(count: rows.count, digest: digest)
    }

    public static func samples(count: Int, latestEndEpoch: TimeInterval, ids: [String]) -> SleepQueryFingerprint {
        .sessions(count: count, digest: "\(latestEndEpoch)|\(ids.joined(separator: ","))")
    }
}

public final class SleepQueryCache: @unchecked Sendable {
    public static let shared = SleepQueryCache()
    private let lock = NSLock()
    private var fingerprint: SleepQueryFingerprint?
    private var nights: [SleepNight] = []
    private var lastNight: SleepNight?

    public func nightsIfUnchanged(_ candidate: SleepQueryFingerprint) -> [SleepNight]? {
        lock.lock(); defer { lock.unlock() }
        guard fingerprint == candidate else { return nil }
        return nights
    }

    public func lastNightIfUnchanged(_ candidate: SleepQueryFingerprint) -> SleepNight? {
        lock.lock(); defer { lock.unlock() }
        guard fingerprint == candidate else { return nil }
        return lastNight
    }

    public func store(fingerprint: SleepQueryFingerprint, nights: [SleepNight], lastNight: SleepNight?) {
        lock.lock(); defer { lock.unlock() }
        self.fingerprint = fingerprint
        self.nights = nights
        self.lastNight = lastNight
    }

    public func invalidate() {
        lock.lock(); defer { lock.unlock() }
        fingerprint = nil
        nights = []
        lastNight = nil
    }
}
