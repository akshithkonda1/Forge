import Foundation

// ============================================================
// MARK: - Moving what should never have been in a plist
// ============================================================

/// One-time move of sensitive values out of `UserDefaults` and into a
/// `SecureStore`.
///
/// The operation that matters here is the *delete*. Copying a session token into
/// the Keychain and leaving the original behind changes nothing at all — the
/// plaintext is still in the container, still in the backup, still readable. So
/// a key counts as migrated only once the `UserDefaults` copy is gone, and a
/// failed write leaves the original in place rather than destroying data the app
/// still needs.
public enum SecureStoreMigration {

    /// Keys that carry health, identity, or precise-location data.
    ///
    /// Everything here was previously written to `UserDefaults` in the clear. The
    /// list is explicit rather than a prefix match because most `forge.*` keys are
    /// ordinary preferences — a chosen tab, a toggle — and sweeping those into the
    /// Keychain would be slower for no benefit while making the Keychain the app's
    /// general settings store.
    public static let sensitiveKeys: [String] = [
        // Session and identity
        "forge.aria.authToken",
        "forge.aria.userId",
        // Reproductive health — the most consequential of these
        "forge.cycle.sharing.digest",
        "forge.menstrual.quiet.sync.at",
        // Health profiles
        "forge.user.profile.v1",
        "forge.sleep.userProfile",
        "forge.watch.context.profile",
        // Precise location
        "forge.lifestyle.lastLat",
        "forge.lifestyle.lastLon",
    ]

    public struct Report: Equatable {
        /// Keys moved and then removed from `UserDefaults` on this run.
        public var migrated: [String] = []
        /// Keys that were not present — the normal case on a fresh install and on
        /// every launch after the first.
        public var absent: [String] = []
        /// Keys whose secure write failed. The `UserDefaults` copy is deliberately
        /// left alone so the next launch can retry.
        public var failed: [String] = []

        public var didChangeAnything: Bool { !migrated.isEmpty }
    }

    /// Move each key, newest wins, and delete the original only on success.
    ///
    /// Idempotent: a second run finds nothing and reports every key absent, so it
    /// is safe to call unconditionally on launch.
    @discardableResult
    public static func run(keys: [String] = sensitiveKeys,
                           from defaults: UserDefaults,
                           to store: SecureStore) -> Report {
        var report = Report()

        for key in keys {
            guard let object = defaults.object(forKey: key) else {
                report.absent.append(key)
                continue
            }

            guard let encoded = encode(object) else {
                // An unencodable value is not something to silently drop: leave
                // it where it is and record it, so the failure is visible rather
                // than looking like a successful migration.
                report.failed.append(key)
                continue
            }

            do {
                // If the secure store already holds this key, the value there is
                // authoritative — it was written by a build that already migrated.
                // Overwriting it with a stale plist copy would move backwards.
                if try store.data(forKey: key) == nil {
                    try store.set(encoded, forKey: key)
                }
                defaults.removeObject(forKey: key)
                report.migrated.append(key)
            } catch {
                report.failed.append(key)
            }
        }

        return report
    }

    /// Encode any property-list value — the defaults database holds strings,
    /// numbers, dates, dictionaries and data, and location arrives as a `Double`.
    static func encode(_ object: Any) -> Data? {
        if let data = object as? Data { return data }
        if let string = object as? String { return string.data(using: .utf8) }
        return try? PropertyListSerialization.data(
            fromPropertyList: object, format: .binary, options: 0
        )
    }

    /// Read back a value the migration wrote, in the same shape it went in.
    public static func decodeDouble(_ data: Data) -> Double? {
        if let text = String(data: data, encoding: .utf8), let value = Double(text) {
            return value
        }
        let plist = try? PropertyListSerialization.propertyList(
            from: data, options: [], format: nil
        )
        return (plist as? NSNumber)?.doubleValue
    }
}
