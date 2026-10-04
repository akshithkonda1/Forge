import Foundation

// ============================================================
// MARK: - Reminders workload
// ============================================================
//
// Privacy contract
// ----------------
// What ARIA sees: counts. Overdue, due today, due tomorrow, high priority, and
// one count per classified kind (health, travel, work, social, errand, home,
// finance, other) — as `reminders:` tags built from those integers and Forge's
// own kind names. On-device ARIA only: `AriaOnDeviceHealthPolicy` removes every
// `reminders:` tag before a remote (/ai/chat) request.
// What stays on-device: everything else, and only in memory. A reminder's
// title, notes, and list name are read once, inside `ReminderItem`'s
// initializer, to pick a kind, and are dropped before it returns.
// `ReminderItem` is deliberately not `Codable`, so it cannot be written down
// by accident. The workload is recomputed on every refresh and never persisted.

/// What a reminder is about, decided on this iPhone from its title (then its
/// list's name) with fixed keyword rules. The kind — never the title — is what
/// ARIA reads.
public enum ReminderKind: String, Codable, Sendable, CaseIterable {
    case health, travel, work, social, errand, home, finance, other
}

/// One open reminder reduced to what the workload needs. Holds no text.
public struct ReminderItem: Sendable, Equatable {
    public let dueDate: Date?
    /// False for an all-day reminder (due on a day, not at a time).
    public let hasDueTime: Bool
    /// EventKit priority: 0 none, 1–4 high, 5 medium, 6–9 low.
    public let priority: Int
    public let isCompleted: Bool
    public let kind: ReminderKind

    /// Classifies `title` (then `listTitle`) and keeps only the result.
    public init(
        title: String,
        listTitle: String?,
        dueDate: Date?,
        hasDueTime: Bool,
        priority: Int,
        isCompleted: Bool
    ) {
        self.init(
            kind: RemindersClassifier.classify(title: title, listTitle: listTitle),
            dueDate: dueDate,
            hasDueTime: hasDueTime,
            priority: priority,
            isCompleted: isCompleted
        )
    }

    public init(
        kind: ReminderKind,
        dueDate: Date?,
        hasDueTime: Bool,
        priority: Int,
        isCompleted: Bool
    ) {
        self.kind = kind
        self.dueDate = dueDate
        self.hasDueTime = hasDueTime
        self.priority = priority
        self.isCompleted = isCompleted
    }

    public var isHighPriority: Bool { (1...4).contains(priority) }
}

/// The structured signal ARIA reads instead of the Reminders list.
public struct RemindersWorkload: Sendable, Codable, Equatable {
    /// Incomplete reminders whose due day has passed, or whose due time has.
    public var overdueCount: Int
    /// Due later today (not yet overdue).
    public var dueTodayCount: Int
    public var dueTomorrowCount: Int
    /// High priority (EventKit 1–4) among everything counted above or due in
    /// the horizon.
    public var highPriorityCount: Int
    /// `ReminderKind.rawValue` → count, for everything overdue or due within
    /// the horizon. List names never become keys: a list only ever contributes
    /// through the kind it classifies to.
    public var kindCounts: [String: Int]

    public init(
        overdueCount: Int = 0,
        dueTodayCount: Int = 0,
        dueTomorrowCount: Int = 0,
        highPriorityCount: Int = 0,
        kindCounts: [String: Int] = [:]
    ) {
        self.overdueCount = overdueCount
        self.dueTodayCount = dueTodayCount
        self.dueTomorrowCount = dueTomorrowCount
        self.highPriorityCount = highPriorityCount
        self.kindCounts = kindCounts
    }

    public static let empty = RemindersWorkload()

    /// Today plus the next fourteen days.
    public static let horizonDays = 14

    public var totalCount: Int { kindCounts.values.reduce(0, +) }

    public var isClear: Bool {
        overdueCount == 0 && dueTodayCount == 0 && dueTomorrowCount == 0 && totalCount == 0
    }

    /// Bucket open reminders. Completed and undated reminders are skipped;
    /// anything due after the horizon is not counted anywhere.
    public static func build(
        from items: [ReminderItem],
        now: Date,
        calendar: Calendar = .current,
        horizonDays: Int = RemindersWorkload.horizonDays
    ) -> RemindersWorkload {
        let startToday = calendar.startOfDay(for: now)
        let startTomorrow = calendar.date(byAdding: .day, value: 1, to: startToday) ?? startToday
        let startDayAfter = calendar.date(byAdding: .day, value: 2, to: startToday) ?? startTomorrow
        let horizonEnd = calendar.date(byAdding: .day, value: horizonDays + 1, to: startToday) ?? startDayAfter

        var workload = RemindersWorkload()
        for item in items where !item.isCompleted {
            guard let due = item.dueDate else { continue }
            let overdue = due < startToday || (item.hasDueTime && due < now)
            if overdue {
                workload.overdueCount += 1
            } else if due < startTomorrow {
                workload.dueTodayCount += 1
            } else if due < startDayAfter {
                workload.dueTomorrowCount += 1
            } else if due >= horizonEnd {
                continue
            }
            if item.isHighPriority { workload.highPriorityCount += 1 }
            workload.kindCounts[item.kind.rawValue, default: 0] += 1
        }
        return workload
    }

    /// Tags for on-device ARIA. Integers and Forge's own kind names only, in a
    /// fixed order. A workload with nothing due is a single `reminders:clear`.
    public var ariaTags: [String] {
        guard !isClear else { return ["reminders:clear"] }
        var tags = [
            "reminders:overdue:\(overdueCount)",
            "reminders:due_today:\(dueTodayCount)",
            "reminders:due_tomorrow:\(dueTomorrowCount)",
            "reminders:high_priority:\(highPriorityCount)",
        ]
        for kind in ReminderKind.allCases {
            if let count = kindCounts[kind.rawValue], count > 0 {
                tags.append("reminders:kind:\(kind.rawValue):\(count)")
            }
        }
        return tags
    }

    /// "2 overdue · 3 today · 1 tomorrow · 1 high priority" for the settings row.
    public var summaryLine: String {
        guard !isClear else { return "Nothing due in the next two weeks" }
        var parts: [String] = []
        if overdueCount > 0 { parts.append("\(overdueCount) overdue") }
        if dueTodayCount > 0 { parts.append("\(dueTodayCount) today") }
        if dueTomorrowCount > 0 { parts.append("\(dueTomorrowCount) tomorrow") }
        if highPriorityCount > 0 { parts.append("\(highPriorityCount) high priority") }
        if parts.isEmpty {
            parts.append("\(totalCount) due in the next two weeks")
        }
        return parts.joined(separator: " · ")
    }

    /// What on-device ARIA says when it reads the board.
    public var spokenLine: String {
        guard !isClear else { return "Reminders are clear for the next two weeks." }
        var parts: [String] = []
        if overdueCount > 0 { parts.append("\(overdueCount) overdue") }
        if dueTodayCount > 0 { parts.append("\(dueTodayCount) due today") }
        if dueTomorrowCount > 0 { parts.append("\(dueTomorrowCount) due tomorrow") }
        if parts.isEmpty { parts.append("\(totalCount) due in the next two weeks") }
        return "Reminders: " + parts.joined(separator: ", ") + " — I count them, I don't read the titles."
    }
}

/// Fixed keyword rules: title first, then the list's name. The first kind
/// whose words appear wins, in the order below — so "pick up prescription" is
/// health before errand, and "buy birthday gift" is social before errand.
public enum RemindersClassifier {

    static let rules: [(ReminderKind, [String])] = [
        (.travel, [
            "flight", "airport", "boarding pass", "passport", "visa", "hotel", "airbnb", "trip",
            "pack for", "packing", "luggage", "suitcase", "itinerary", "rental car", "vacation", "travel",
        ]),
        (.health, [
            "doctor", "doctor's", "dentist", "dental", "physio", "physical therapy", "therapy", "therapist",
            "pharmacy", "prescription", "refill", "meds", "medication", "vitamins", "pills", "checkup",
            "check up", "blood test", "blood work", "labs", "vaccine", "flu shot", "gym", "workout", "work out",
            "yoga", "stretch", "go for a run", "long run", "optometrist", "eye exam", "dermatologist",
            "chiropractor", "health", "fitness", "medical",
        ]),
        (.work, [
            "report", "deck", "slides", "presentation", "meeting", "client", "deadline", "submit", "standup",
            "stand up", "1 1", "project", "proposal", "boss", "manager", "interview", "timesheet",
            "expense report", "office", "work", "recruiter", "phone screen",
        ]),
        (.finance, [
            "pay", "bill", "bills", "rent", "mortgage", "tax", "taxes", "bank", "invoice", "transfer",
            "venmo", "budget", "insurance", "credit card", "finance", "money",
        ]),
        (.social, [
            "birthday", "party", "gift", "present", "rsvp", "wedding", "dinner with", "drinks", "brunch",
            "invite", "anniversary", "catch up", "call mom", "call dad", "call grandma", "call grandpa",
            "card for", "friends", "family", "social",
        ]),
        (.home, [
            "clean", "laundry", "dishes", "vacuum", "trash", "garbage", "recycling", "fix", "repair",
            "plumber", "water plants", "mow", "yard", "meal prep", "cook", "home", "household",
        ]),
        (.errand, [
            "buy", "pick up", "pickup", "drop off", "groceries", "grocery", "store", "shop", "shopping",
            "return", "post office", "mail", "package", "dry cleaning", "car wash", "oil change", "errands",
        ]),
    ]

    public static func classify(title: String, listTitle: String? = nil) -> ReminderKind {
        if let kind = match(title) { return kind }
        if let listTitle, let kind = match(listTitle) { return kind }
        return .other
    }

    static func match(_ text: String) -> ReminderKind? {
        let padded = LifeContextText.padded(text)
        guard padded.count > 2 else { return nil }
        for (kind, phrases) in rules where LifeContextText.firstMatch(padded, in: phrases) != nil {
            return kind
        }
        return nil
    }
}
