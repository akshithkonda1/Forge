import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

// ============================================================
// MARK: - Partner support glance
// ============================================================

/// What a supporter's Watch, Lock Screen, and morning notification may show.
///
/// Deliberately **not** a `PartnerCycleDigest`. The digest already withholds
/// fertility, flow, and logs; a wrist glance and a lock-screen banner can
/// still over-share if they repeat "on their period" or a day count. This
/// type keeps one thoughtfulness bit and a lock-safe line. The longer
/// headline is stored for the Home Screen widget (behind the lock) and the
/// in-app Support pane.
///
/// Built on the owner's device from the digest, written to the App Group on
/// the supporter's phone after CloudKit accept. Watch and widgets only
/// decode this struct.
public struct PartnerSupportGlance: Codable, Sendable, Equatable {
    public var firstName: String
    public var extraThoughtfulnessHelps: Bool
    /// Digest headline. Home Screen widget only — never the lock-screen line.
    public var headline: String
    public var asOfDayKey: String
    public var isPaused: Bool
    public var updatedAt: Date

    public init(
        firstName: String,
        extraThoughtfulnessHelps: Bool,
        headline: String,
        asOfDayKey: String,
        isPaused: Bool,
        updatedAt: Date = Date()
    ) {
        self.firstName = firstName
        self.extraThoughtfulnessHelps = extraThoughtfulnessHelps
        self.headline = headline
        self.asOfDayKey = asOfDayKey
        self.isPaused = isPaused
        self.updatedAt = updatedAt
    }

    /// Safe on a lock screen and a gym glance. Never names a period, a phase,
    /// or a day count.
    public var lockScreenLine: String {
        if isPaused || isStale { return "No recent update" }
        return extraThoughtfulnessHelps
            ? "A little extra care lands well today."
            : "Everyday support is enough."
    }

    public var circularLabel: String {
        if isPaused || isStale { return "—" }
        return extraThoughtfulnessHelps ? "Kind" : "OK"
    }

    public var notificationTitle: String {
        let name = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "How to show up" }
        return "How to show up for \(name)"
    }

    public var notificationBody: String {
        "\(lockScreenLine) Open Forge for the rest."
    }

    public var ageInDays: Int? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        guard let day = f.date(from: asOfDayKey) else { return nil }
        let cal = Calendar.current
        return cal.dateComponents(
            [.day],
            from: cal.startOfDay(for: day),
            to: cal.startOfDay(for: Date())
        ).day
    }

    public static let stalenessThresholdDays = 3
    public var isStale: Bool { (ageInDays ?? .max) >= Self.stalenessThresholdDays }

    public static var gallerySample: PartnerSupportGlance {
        PartnerSupportGlance(
            firstName: "Sam",
            extraThoughtfulnessHelps: true,
            headline: "A little extra care lands well today.",
            asOfDayKey: "2099-01-01",
            isPaused: false
        )
    }
}

public enum PartnerSupportGlanceStore {
    public static let appGroupID = WatchSnapshotStore.appGroupID
    private static let key = "forge.partner.support.glance.v1"

    public static func load() -> PartnerSupportGlance? {
        guard
            let defaults = UserDefaults(suiteName: appGroupID),
            let data = defaults.data(forKey: key)
        else { return nil }
        return try? JSONDecoder().decode(PartnerSupportGlance.self, from: data)
    }

    public static func save(_ glance: PartnerSupportGlance, reloadWidgets: Bool = true) {
        guard
            let defaults = UserDefaults(suiteName: appGroupID),
            let data = try? JSONEncoder().encode(glance)
        else { return }
        defaults.set(data, forKey: key)
        reload(reloadWidgets)
    }

    public static func clear(reloadWidgets: Bool = true) {
        UserDefaults(suiteName: appGroupID)?.removeObject(forKey: key)
        reload(reloadWidgets)
    }

    private static func reload(_ reloadWidgets: Bool) {
        #if canImport(WidgetKit)
        if reloadWidgets {
            WidgetCenter.shared.reloadTimelines(ofKind: "SupportGlanceWidget")
            WidgetCenter.shared.reloadTimelines(ofKind: "SupportComplication")
        }
        #endif
    }
}
