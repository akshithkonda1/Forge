import Foundation

// ============================================================
// MARK: - Life Context brief (the Scout-style handoff)
// ============================================================
//
// Privacy contract
// ----------------
// What ARIA sees: this brief — "Friday: dinner plan, high confidence; this
// week: 2 travel mentions, 1 stress signal" — and `life_context:` tags with
// the same content. Kinds, Forge's own labels, day names, confidence bands and
// counts. No summaries, no names, no numbers beyond counts and day offsets.
// The same discipline as the Scout handoff: the least ARIA needs to coach,
// never the material it came from. On-device ARIA only —
// `AriaOnDeviceHealthPolicy` strips the brief and every `life_context:` tag
// before a remote request.
// What stays on-device: the facts themselves (in `MessageContextStore`).

public enum LifeContextBrief {

    /// How far ahead dated facts are listed by day.
    public static let horizonDays = 7
    /// Most dated items one brief names.
    public static let maxUpcoming = 5

    private static let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    /// The brief, or nil when there is nothing to say.
    public static func render(_ facts: [LifeContextFact], now: Date, calendar: Calendar = .current) -> String? {
        let upcoming = upcomingFacts(facts, now: now, calendar: calendar)
        var segments = upcoming.map { item in
            "\(dayName(delta: item.delta, date: item.fact.date ?? now, calendar: calendar)): "
                + "\(phrase(for: item.fact)), \(item.fact.confidenceBand.rawValue) confidence"
        }
        let counted = weekCounts(facts, excluding: Set(upcoming.map(\.fact.sourceHash)), now: now)
        if !counted.isEmpty {
            segments.append("this week: " + counted.map { "\($0.count) \($0.kind.briefNoun(count: $0.count))" }
                .joined(separator: ", "))
        }
        return segments.isEmpty ? nil : segments.joined(separator: "; ")
    }

    /// `life_context:<kind>:<label>:d<days>` for dated facts in the horizon and
    /// `life_context:week:<kind>:<count>` for the rest of this week's facts.
    public static func ariaTags(_ facts: [LifeContextFact], now: Date, calendar: Calendar = .current) -> [String] {
        let upcoming = upcomingFacts(facts, now: now, calendar: calendar)
        var tags = upcoming.map { item in
            "life_context:\(item.fact.kind.rawValue):\(slug(item.fact.label)):d\(item.delta)"
        }
        let counted = weekCounts(facts, excluding: Set(upcoming.map(\.fact.sourceHash)), now: now)
        tags.append(contentsOf: counted.map { "life_context:week:\($0.kind.rawValue):\($0.count)" })
        return tags
    }

    // MARK: Pieces

    struct Upcoming {
        let fact: LifeContextFact
        let delta: Int
    }

    static func upcomingFacts(_ facts: [LifeContextFact], now: Date, calendar: Calendar) -> [Upcoming] {
        let today = calendar.startOfDay(for: now)
        let items = facts.compactMap { fact -> Upcoming? in
            guard let date = fact.date else { return nil }
            let delta = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day ?? -1
            guard (0..<horizonDays).contains(delta) else { return nil }
            return Upcoming(fact: fact, delta: delta)
        }
        let sorted = items.sorted { a, b in
            let da = a.fact.date ?? now
            let db = b.fact.date ?? now
            if da != db { return da < db }
            return a.fact.sourceHash < b.fact.sourceHash
        }
        return Array(sorted.prefix(maxUpcoming))
    }

    static func weekCounts(
        _ facts: [LifeContextFact],
        excluding listed: Set<String>,
        now: Date
    ) -> [(kind: LifeContextFact.Kind, count: Int)] {
        let since = now.addingTimeInterval(-7 * 86_400)
        let recent = facts.filter { $0.observedAt >= since && $0.observedAt <= now && !listed.contains($0.sourceHash) }
        return LifeContextFact.Kind.allCases.compactMap { kind -> (kind: LifeContextFact.Kind, count: Int)? in
            let count = recent.filter { $0.kind == kind }.count
            return count > 0 ? (kind, count) : nil
        }
    }

    static func dayName(delta: Int, date: Date, calendar: Calendar) -> String {
        switch delta {
        case 0: return "Today"
        case 1: return "Tomorrow"
        default:
            let weekday = calendar.component(.weekday, from: date)
            return weekdayNames[(weekday - 1 + 7) % 7]
        }
    }

    /// "dinner plan", "wedding", "flight", "work deadline".
    static func phrase(for fact: LifeContextFact) -> String {
        let label = safeLabel(fact.label)
        switch fact.kind {
        case .plan: return "\(label) plan"
        case .travel: return label == "hotel" ? "hotel stay" : label
        default: return label
        }
    }

    /// Labels are Forge's own words, but a fact can come back from storage, so
    /// anything that is not short lowercase words is replaced, never echoed.
    static func safeLabel(_ label: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz ")
        guard !label.isEmpty, label.count <= 24,
              label.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return "item" }
        return label
    }

    static func slug(_ label: String) -> String {
        safeLabel(label).replacingOccurrences(of: " ", with: "_")
    }
}
