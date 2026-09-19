import Foundation

/// One lifestyle hold ARIA can sort and coach around.
///
/// **Structured** (tags, prompts, ledger, speech): kind, bucket, when,
/// headline. **Unstructured** (`title`, `placeName`): stays on this phone.
/// Never copied into ingest tags, remote prompts, or knowledge summaries.
public struct LifestyleAsset: Sendable, Equatable, Identifiable {
    public enum Source: String, Sendable, Equatable {
        case memory
        case eventKit
        case spoken
    }

    public enum Bucket: String, Sendable, CaseIterable, Comparable {
        case wedding
        case travel
        case lifestyle
        case care
        case work

        public static func < (lhs: Bucket, rhs: Bucket) -> Bool {
            lhs.sortRank < rhs.sortRank
        }

        public var sortRank: Int {
            switch self {
            case .wedding: return 0
            case .travel: return 1
            case .lifestyle: return 2
            case .care: return 3
            case .work: return 4
            }
        }

        public var spokenLabel: String {
            switch self {
            case .wedding: return "weddings"
            case .travel: return "trips and flights"
            case .lifestyle: return "lifestyle events"
            case .care: return "appointments"
            case .work: return "work holds"
            }
        }

        public static func from(kind: FakeCalendarEvent.Kind) -> Bucket {
            switch kind {
            case .wedding: return .wedding
            case .flight, .travel: return .travel
            case .appointment: return .care
            case .work: return .work
            case .game, .dinner, .family, .social, .surprise: return .lifestyle
            }
        }
    }

    public var id: String
    public var kind: FakeCalendarEvent.Kind
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var daysUntil: Int
    public var source: Source
    /// On-device only.
    public var title: String
    /// On-device only.
    public var placeName: String

    public init(
        id: String = UUID().uuidString,
        kind: FakeCalendarEvent.Kind,
        start: Date,
        end: Date,
        isAllDay: Bool,
        daysUntil: Int,
        source: Source,
        title: String,
        placeName: String
    ) {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.daysUntil = daysUntil
        self.source = source
        self.title = title
        self.placeName = placeName
    }

    public var bucket: Bucket { Bucket.from(kind: kind) }
    public var isHeadline: Bool { kind.isHeadline }

    /// Kind + days-until. Never a title or a place.
    public var structuredSummary: String {
        if daysUntil <= 0 {
            return "\(kind.spokenLabel) today"
        }
        if daysUntil == 1 {
            return "\(kind.spokenLabel) tomorrow"
        }
        return "\(kind.spokenLabel) in \(daysUntil) days"
    }
}

/// Turns EventKit fields or a FakeCalendarPack into assets ARIA can sort.
public enum LifestyleAssetIndex: Sendable {
    /// This week (every kind) plus headlines in the next `withinDays`.
    public static let workingHorizonDays = 21

    public static func workingSet(
        from pack: FakeCalendarPack,
        now: Date = Date(),
        calendar: Calendar = .current,
        withinDays: Int = workingHorizonDays
    ) -> [LifestyleAsset] {
        let window = FakeCalendarPack.weekWindow(containing: now, calendar: calendar)
        let start = calendar.startOfDay(for: now)
        let horizonEnd = calendar.date(byAdding: .day, value: withinDays + 1, to: start) ?? now
        let picked = pack.events.filter { event in
            FakeCalendarPack.overlapsWindow(event, start: window.start, end: window.end)
                || (event.kind.isHeadline && event.start >= start && event.start < horizonEnd)
        }
        return sort(picked.map { from(event: $0, now: now, calendar: calendar, source: .memory) })
    }

    public static func from(
        event: FakeCalendarEvent,
        now: Date = Date(),
        calendar: Calendar = .current,
        source: LifestyleAsset.Source = .memory
    ) -> LifestyleAsset {
        LifestyleAsset(
            kind: event.kind,
            start: event.start,
            end: event.end,
            isAllDay: event.isAllDay,
            daysUntil: max(0, FakeCalendarPack.dayOffset(of: event, from: now, calendar: calendar)),
            source: source,
            title: event.title,
            placeName: event.placeName
        )
    }

    /// EventKit (or any calendar row): structured kind from Forge markers,
    /// else from the unstructured title. Title/place stay on-device.
    public static func fromCalendarFields(
        title: String?,
        placeName: String?,
        start: Date,
        end: Date,
        isAllDay: Bool,
        notes: String?,
        url: URL?,
        source: LifestyleAsset.Source = .eventKit,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> LifestyleAsset? {
        let kind = FakeCalendarPack.kind(fromNotes: notes)
            ?? FakeCalendarPack.kind(fromURL: url)
            ?? classify(title: title ?? "", notes: notes)
        guard let kind else { return nil }
        let day = calendar.startOfDay(for: now)
        let eventDay = calendar.startOfDay(for: start)
        let days = calendar.dateComponents([.day], from: day, to: eventDay).day ?? 0
        return LifestyleAsset(
            kind: kind,
            start: start,
            end: end,
            isAllDay: isAllDay,
            daysUntil: max(0, days),
            source: source,
            title: title ?? "",
            placeName: placeName ?? ""
        )
    }

    /// Unstructured title/notes → structured kind. Conservative on purpose.
    public static func classify(title: String, notes: String? = nil) -> FakeCalendarEvent.Kind? {
        let blob = (title + " " + (notes ?? "")).lowercased()
        guard !blob.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if matches(blob, ["wedding", "bridal", "ceremony", "reception"]) { return .wedding }
        if matches(blob, ["flight", "airport", "depart", "boarding"]) { return .flight }
        if matches(blob, ["trip", "vacation", "hotel", "travel", "getaway"]) { return .travel }
        if matches(blob, ["kickoff", "kick-off"]) || titleGame(blob) { return .game }
        if matches(blob, ["dinner"]) { return .dinner }
        if matches(blob, ["birthday", "family dinner", "brunch with"]) { return .family }
        if matches(blob, ["dentist", "doctor", "appointment", "physical", "checkup", "check-up"]) {
            return .appointment
        }
        if matches(blob, ["standup", "stand-up", "1:1", "1-1", "sync", "all-hands", "sprint"]) {
            return .work
        }
        if matches(blob, ["drinks", "party", "hangout", "hang out"]) { return .social }
        return nil
    }

    public static func sort(_ assets: [LifestyleAsset]) -> [LifestyleAsset] {
        assets.sorted { a, b in
            if a.isHeadline != b.isHeadline { return a.isHeadline && !b.isHeadline }
            if a.daysUntil != b.daysUntil { return a.daysUntil < b.daysUntil }
            if a.bucket != b.bucket { return a.bucket < b.bucket }
            return a.kind < b.kind
        }
    }

    public static func grouped(_ assets: [LifestyleAsset]) -> [(LifestyleAsset.Bucket, [LifestyleAsset])] {
        let order = LifestyleAsset.Bucket.allCases.sorted()
        return order.compactMap { bucket in
            let items = sort(assets.filter { $0.bucket == bucket })
            return items.isEmpty ? nil : (bucket, items)
        }
    }

    public static func ingestTags(from assets: [LifestyleAsset]) -> [String] {
        var tags: [String] = []
        var nearest: [FakeCalendarEvent.Kind: Int] = [:]
        for asset in assets where asset.isHeadline {
            if let existing = nearest[asset.kind], existing <= asset.daysUntil { continue }
            nearest[asset.kind] = asset.daysUntil
        }
        tags.append(contentsOf: nearest.keys.sorted().map {
            "calendar:horizon:\($0.rawValue):\(nearest[$0] ?? 0)"
        })
        return FakeCalendarPack.sanitizeTags(tags)
    }

    /// Headlines ARIA can name without reading titles.
    public static func spokenInventory(_ assets: [LifestyleAsset]) -> String? {
        let headlines = sort(assets.filter(\.isHeadline))
        guard !headlines.isEmpty else { return nil }
        let unique = headlines.reduce(into: [FakeCalendarEvent.Kind: LifestyleAsset]()) { acc, asset in
            if acc[asset.kind] == nil { acc[asset.kind] = asset }
        }
        let parts = FakeCalendarEvent.Kind.allCases.compactMap { unique[$0]?.structuredSummary }
        guard !parts.isEmpty else { return nil }
        return "You've got \(list(parts)) on the calendar. I keep the titles on the phone."
    }

    public static func titlesStayOnDevice(_ assets: [LifestyleAsset]) -> Bool {
        let tags = ingestTags(from: assets).joined(separator: " ")
        let spoken = spokenInventory(assets) ?? ""
        let haystack = tags + " " + spoken
        for asset in assets {
            if leaks(asset.title, in: haystack) { return false }
            if leaks(asset.placeName, in: haystack) { return false }
        }
        return true
    }

    private static func leaks(_ value: String, in haystack: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 else { return false }
        return haystack.localizedCaseInsensitiveContains(trimmed)
    }

    private static func matches(_ blob: String, _ needles: [String]) -> Bool {
        needles.contains { blob.contains($0) }
    }

    private static func titleGame(_ blob: String) -> Bool {
        blob.contains(" vs ") || blob.contains(" vs. ") || blob.hasPrefix("game")
            || blob.contains(" game")
    }

    private static func list(_ labels: [String]) -> String {
        if labels.count == 1 { return labels[0] }
        if labels.count == 2 { return "\(labels[0]) and \(labels[1])" }
        return labels.dropLast().joined(separator: ", ") + ", and " + labels.last!
    }
}
