import Foundation

/// Windows Explorer folders for what ARIA knows. Facts are dated and sourced.
/// Calendar titles, attendees, and places never belong here — kinds and
/// days-until only.
public enum AriaKnowledgeCategory: String, Codable, CaseIterable, Sendable {
    case appleHealth
    case weSpokeAbout
    case otherData
    case inferences

    public var title: String {
        switch self {
        case .appleHealth: return "Apple Health"
        case .weSpokeAbout: return "We spoke about"
        case .otherData: return "Other data"
        case .inferences: return "Inferences"
        }
    }

    public var systemImage: String {
        switch self {
        case .appleHealth: return "heart.fill"
        case .weSpokeAbout: return "bubble.left.and.bubble.right.fill"
        case .otherData: return "folder.fill"
        case .inferences: return "lightbulb.fill"
        }
    }
}

public struct AriaKnowledgeFact: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var category: AriaKnowledgeCategory
    public var kind: String
    public var summary: String
    public var source: String
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        category: AriaKnowledgeCategory,
        kind: String,
        summary: String,
        source: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.category = category
        self.kind = kind
        self.summary = summary
        self.source = source
        self.createdAt = createdAt
    }
}

public struct AriaKnowledgeLedger: Codable, Sendable, Equatable {
    public var facts: [AriaKnowledgeFact]

    public init(facts: [AriaKnowledgeFact] = []) {
        self.facts = facts
    }

    public func facts(in category: AriaKnowledgeCategory) -> [AriaKnowledgeFact] {
        facts
            .filter { $0.category == category }
            .sorted { $0.createdAt > $1.createdAt }
    }

    public mutating func file(_ fact: AriaKnowledgeFact, capPerFolder: Int = 40) {
        let trimmed = AriaInboundLifestyleStrip.sanitize(fact.summary)
        guard !trimmed.isEmpty else { return }
        facts.removeAll {
            $0.category == fact.category
                && $0.kind.caseInsensitiveCompare(fact.kind) == .orderedSame
                && $0.summary.caseInsensitiveCompare(trimmed) == .orderedSame
        }
        var next = fact
        next.summary = trimmed
        facts.insert(next, at: 0)
        var kept: [AriaKnowledgeFact] = []
        var counts: [AriaKnowledgeCategory: Int] = [:]
        for item in facts {
            let n = counts[item.category, default: 0]
            if n >= capPerFolder { continue }
            counts[item.category] = n + 1
            kept.append(item)
        }
        facts = kept
    }

    public func latestSummary(kind: String) -> String? {
        facts.first { $0.kind.caseInsensitiveCompare(kind) == .orderedSame }?.summary
    }

    public func latestWeeklyMood() -> Double? {
        guard let raw = latestSummary(kind: "weekly_mood") else { return nil }
        return Double(raw)
    }

    /// Drop a source's previous facts in one folder, then file the replacements.
    /// Used when a new Test-Ready Health pack lands so Apple Health stays current.
    public mutating func replace(
        category: AriaKnowledgeCategory,
        source: String,
        with incoming: [AriaKnowledgeFact]
    ) {
        facts.removeAll { $0.category == category && $0.source == source }
        for fact in incoming {
            file(fact)
        }
    }
}

/// On-device folder store. Shared by Life, You, and ARIA so the same facts
/// grade QoL and show up in conversation.
public enum AriaKnowledgeLedgerStore: Sendable {
    public static let defaultsKey = "forge.aria.knowledgeLedger.v1"

    public static func load(defaults: UserDefaults = .standard) -> AriaKnowledgeLedger {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(AriaKnowledgeLedger.self, from: data) else {
            return AriaKnowledgeLedger()
        }
        return decoded
    }

    public static func save(_ ledger: AriaKnowledgeLedger, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(ledger) {
            defaults.set(data, forKey: defaultsKey)
        }
    }

    @discardableResult
    public static func file(
        _ fact: AriaKnowledgeFact,
        defaults: UserDefaults = .standard
    ) -> AriaKnowledgeLedger {
        var ledger = load(defaults: defaults)
        ledger.file(fact)
        save(ledger, defaults: defaults)
        return ledger
    }

    public static func replace(
        category: AriaKnowledgeCategory,
        source: String,
        with incoming: [AriaKnowledgeFact],
        defaults: UserDefaults = .standard
    ) {
        var ledger = load(defaults: defaults)
        ledger.replace(category: category, source: source, with: incoming)
        save(ledger, defaults: defaults)
    }
}

/// Partner/cycle prefixes must never land in vault notes / user-add.
/// Same deny list as Python ``routes.aria._DENIED_LIFESTYLE``. Rowan contract:
/// user-add runs this strip. Sleep-stage % never belongs in Body notes either.
public enum AriaInboundLifestyleStrip: Sendable {
    /// Keep in lockstep with `DENIED_LIFESTYLE_PREFIXES` in nyx_eval_gates.py.
    public static let deniedPrefixes: [String] = [
        "partner_",
        "support_cycle:",
        "partner_name:",
        "partner_phase:",
        "partner_day:",
        "partner_cycle:",
        "cycle:fertile",
        "cycle:tww",
        "cycle:goal:trying",
        "cycle:bleeding",
        "cycle:condition",
    ]

    public static func isDeniedToken(_ token: String) -> Bool {
        let lower = token.lowercased()
        return deniedPrefixes.contains { lower.hasPrefix($0) }
    }

    public static func sanitize(_ raw: String) -> String {
        let pieces = raw.split { $0.isWhitespace || $0.isNewline }.map(String.init)
        let kept = pieces.filter { !isDeniedToken($0) }.joined(separator: " ")
        return stripSleepStagePercent(kept)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Drop `deep/REM/light sleep at N%` leftovers. Minutes and hour totals stay.
    public static func stripSleepStagePercent(_ raw: String) -> String {
        var text = raw
        let patterns = [
            #"\b(?:deep|rem|light)\s+sleep\s+at\s+\d+(?:\.\d+)?\s*%"#,
            #"\brem\s+is\s+light\s+at\s+\d+(?:\.\d+)?\s*%"#,
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
            }
        }
        while text.contains("  ") {
            text = text.replacingOccurrences(of: "  ", with: " ")
        }
        return text.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:—–-"))
    }
}

/// Chat → dated fact. "I have a wedding in 2 weeks" becomes days-until, never a venue.
public enum SpokenEventParser: Sendable {
    public static func daysUntilWedding(in text: String) -> Int? {
        let lower = text.lowercased()
        guard lower.contains("wedding") else { return nil }
        if lower.contains("today") || lower.contains("tonight") { return 0 }
        if lower.contains("tomorrow") { return 1 }
        if let weeks = firstNumber(in: lower, after: ["week", "weeks"]) {
            return max(1, weeks * 7)
        }
        if let days = firstNumber(in: lower, after: ["day", "days"]) {
            return max(0, days)
        }
        if lower.contains("in two weeks") || lower.contains("in 2 weeks") {
            return 14
        }
        return nil
    }

    private static func firstNumber(in text: String, after tokens: [String]) -> Int? {
        let words = text.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let spelled: [String: Int] = [
            "a": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
            "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        ]
        for (index, word) in words.enumerated() {
            guard tokens.contains(where: { word.hasPrefix($0) }), index > 0 else { continue }
            let prev = words[index - 1]
            if let n = Int(prev) { return n }
            if let n = spelled[prev] { return n }
        }
        return nil
    }
}

/// Weekly check-in copy → 0...10 so QoL can move with the week.
public enum WeeklyMoodScale: Sendable {
    public static func score(from text: String) -> Double? {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lower.isEmpty else { return nil }
        if lower.contains("gollum") || lower.contains("depress") || lower.contains("hide")
            || lower.contains("nobody") || lower.contains("miserable") {
            return 2
        }
        if lower.contains("happy") || lower.contains("great") || lower.contains("excited")
            || lower.contains("family") || lower.contains("amazing") {
            return 8
        }
        if lower.contains("low") || lower.contains("flat") || lower.contains("meh") {
            return 4
        }
        let digits = lower.filter(\.isNumber)
        if let n = Int(digits), (0...10).contains(n) { return Double(n) }
        return 5
    }
}
