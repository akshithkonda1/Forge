import Foundation

public enum SleepNudgePolicy: Sendable {
    public static let maxPerDay = 2
    public static let maxPhoneScheduleAge: TimeInterval = 24 * 3600
    public static let quietWeekDefaultsKey = "forge.sleep.quietWeek"
    public static let phoneWindDownScheduledKey = "forge.sleep.phoneWindDownScheduled"
    public static let phoneWindDownScheduledAtKey = "forge.sleep.phoneWindDownScheduledAt"
    /// Watch `WindDownScheduler` identifier. Third in priority: the fallback.
    public static let watchWindDownIdentifier = "forge.watch.winddown"

    /// wind-down > caffeine > watch. `allowed` ranks requested ids this way
    /// before applying `maxPerDay`.
    public static let rankedIdentifiers: [String] = [
        SleepWindDownNotice.phoneIdentifier,
        SleepWindDownNotice.caffeineIdentifier,
        watchWindDownIdentifier,
    ]

    /// Empty during a quiet week; otherwise the first `maxPerDay` requested
    /// identifiers in priority order.
    public static func allowed(_ requested: [String], quietWeek: Bool) -> [String] {
        if quietWeek { return [] }
        var seen = Set<String>()
        let ranked = rankedIdentifiers.filter { requested.contains($0) && seen.insert($0).inserted }
        let rest = requested.filter { !rankedIdentifiers.contains($0) && seen.insert($0).inserted }
        return Array((ranked + rest).prefix(maxPerDay))
    }

    /// Watch fallback. Fail-open when the phone flag is missing or stale —
    /// we cannot trust that the phone actually scheduled. Skip only when
    /// the phone sent an explicit, fresh `true`. Quiet week and a past
    /// `windDownStart` still skip. Ranking and `maxPerDay` stay in `allowed()`.
    public static func watchMayFire(
        windDownStart: Date,
        now: Date,
        quietWeek: Bool,
        phoneWindDownScheduled: Bool?,
        phoneScheduledAt: Date?,
        maxPhoneScheduleAge: TimeInterval = SleepNudgePolicy.maxPhoneScheduleAge
    ) -> Bool {
        guard windDownStart > now else { return false }
        if quietWeek { return false }
        if phoneWindDownScheduled == true,
           let phoneScheduledAt,
           now.timeIntervalSince(phoneScheduledAt) <= maxPhoneScheduleAge {
            return false
        }
        return true
    }

    public static func isQuietWeek(defaults: UserDefaults? = nil) -> Bool {
        store(defaults).bool(forKey: quietWeekDefaultsKey)
    }

    public static func setQuietWeek(_ on: Bool, defaults: UserDefaults? = nil) {
        store(defaults).set(on, forKey: quietWeekDefaultsKey)
    }

    public static func isPhoneWindDownScheduled(defaults: UserDefaults? = nil) -> Bool {
        store(defaults).bool(forKey: phoneWindDownScheduledKey)
    }

    public static func setPhoneWindDownScheduled(_ on: Bool, at: Date = Date(), defaults: UserDefaults? = nil) {
        let defaults = store(defaults)
        defaults.set(on, forKey: phoneWindDownScheduledKey)
        if on {
            defaults.set(at, forKey: phoneWindDownScheduledAtKey)
        } else {
            defaults.removeObject(forKey: phoneWindDownScheduledAtKey)
        }
    }

    public static func phoneWindDownScheduledAt(defaults: UserDefaults? = nil) -> Date? {
        store(defaults).object(forKey: phoneWindDownScheduledAtKey) as? Date
    }

    /// Quiet-week / phone-wind-down flags from a WatchConnectivity payload.
    /// Nested `forge.companion.config` strings win; top-level Bool/String
    /// siblings are the fallback. Missing keys stay nil so old payloads
    /// do not clear Watch snapshot fields.
    public static func nudgeFlags(
        from message: [String: Any]
    ) -> (quietWeek: Bool?, phoneWindDownScheduled: Bool?, phoneScheduledAt: Date?) {
        let nested = message[CompanionConfig.nestedKey] as? [String: String]
        func read(_ key: String) -> Bool? {
            if let nested, let raw = nested[key] {
                return boolFlag(raw)
            }
            return boolFlag(message[key])
        }
        func readDate(_ key: String) -> Date? {
            if let nested, let raw = nested[key] {
                return dateFlag(raw)
            }
            if let date = message[key] as? Date { return date }
            if let raw = message[key] as? String { return dateFlag(raw) }
            return nil
        }
        return (
            read(quietWeekDefaultsKey),
            read(phoneWindDownScheduledKey),
            readDate(phoneWindDownScheduledAtKey)
        )
    }

    public static func boolFlag(_ value: Any?) -> Bool? {
        if let flag = value as? Bool { return flag }
        if let raw = value as? String {
            switch raw.lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no": return false
            default: return nil
            }
        }
        if let number = value as? NSNumber { return number.boolValue }
        return nil
    }

    static func dateFlag(_ value: Any?) -> Date? {
        if let date = value as? Date { return date }
        if let raw = value as? String {
            let formatter = ISO8601DateFormatter()
            return formatter.date(from: raw)
        }
        return nil
    }

    /// App Group suite used by Forge iOS, the widget extension, and Watch
    /// (`group.com.forge.ForgeSwift` in entitlements). Falls back to
    /// `.standard` when the suite cannot be opened.
    private static func store(_ defaults: UserDefaults?) -> UserDefaults {
        defaults ?? UserDefaults(suiteName: WatchSnapshotStore.appGroupID) ?? .standard
    }
}
