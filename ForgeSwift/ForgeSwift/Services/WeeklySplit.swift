import Foundation

/// How the training week is owned. `rotate` lets ARIA walk complementary
/// libraries after yesterday; `fixed` honors the weekday map they set.
enum SchedulePlanningMode: String, Codable, CaseIterable, Identifiable {
    case rotate
    case fixed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rotate: return "Rotate for me"
        case .fixed: return "I’ll pick the days"
        }
    }

    var detail: String {
        switch self {
        case .rotate:
            return "ARIA walks the week — Tuesday legs, Wednesday chest and abs — and skips tissue that’s still fresh."
        case .fixed:
            return "You assign the body part and how many exercises each day. Change it anytime."
        }
    }
}

/// One weekday on the walking week. Sunday = 0 … Saturday = 6.
struct WeeklySplitSlot: Codable, Equatable, Hashable, Identifiable {
    var weekday: Int
    var primary: String
    var extra: String?
    var exerciseCount: Int

    var id: Int { weekday }

    var isRest: Bool { primary == "rest" }

    var title: String {
        if isRest { return "Rest" }
        if primary == "push" && extra == "core" { return "Chest and abs" }
        if primary == "pull" && extra == "core" { return "Back and core" }
        if primary == "full_body" { return "Full body" }
        return WeeklySplit.regionTitle(primary)
    }

    var region: TargetMuscle.Region? {
        WeeklySplit.region(from: primary)
    }

    var extraRegion: TargetMuscle.Region? {
        extra.flatMap(WeeklySplit.region(from:))
    }

    static let defaultWeek: [WeeklySplitSlot] = [
        WeeklySplitSlot(weekday: 0, primary: "rest", extra: nil, exerciseCount: 0),
        WeeklySplitSlot(weekday: 1, primary: "push", extra: nil, exerciseCount: 5),
        WeeklySplitSlot(weekday: 2, primary: "legs", extra: nil, exerciseCount: 6),
        WeeklySplitSlot(weekday: 3, primary: "push", extra: "core", exerciseCount: 6),
        WeeklySplitSlot(weekday: 4, primary: "pull", extra: nil, exerciseCount: 5),
        WeeklySplitSlot(weekday: 5, primary: "full_body", extra: nil, exerciseCount: 6),
        WeeklySplitSlot(weekday: 6, primary: "conditioning", extra: nil, exerciseCount: 4),
    ]
}

enum WeeklySplit {
    static let dayLabels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    static let dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    static let focusChoices: [(id: String, extra: String?, label: String)] = [
        ("rest", nil, "Rest"),
        ("push", nil, "Push"),
        ("legs", nil, "Legs"),
        ("push", "core", "Chest + abs"),
        ("pull", nil, "Pull"),
        ("full_body", nil, "Full body"),
        ("core", nil, "Core"),
        ("conditioning", nil, "Conditioning"),
    ]

    static func sun0(from date: Date, calendar: Calendar = .current) -> Int {
        calendar.component(.weekday, from: date) - 1
    }

    static func normalized(_ split: [WeeklySplitSlot]) -> [WeeklySplitSlot] {
        var byDay: [Int: WeeklySplitSlot] = [:]
        for slot in WeeklySplitSlot.defaultWeek { byDay[slot.weekday] = slot }
        for slot in split where (0...6).contains(slot.weekday) {
            byDay[slot.weekday] = slot
        }
        return (0...6).compactMap { byDay[$0] }
    }

    static func slot(for weekday: Int, in split: [WeeklySplitSlot]) -> WeeklySplitSlot {
        let week = normalized(split)
        let day = ((weekday % 7) + 7) % 7
        return week.first(where: { $0.weekday == day }) ?? WeeklySplitSlot.defaultWeek[day]
    }

    static func trainingDays(in split: [WeeklySplitSlot]) -> [Int] {
        normalized(split).filter { !$0.isRest }.map(\.weekday)
    }

    static func region(from raw: String) -> TargetMuscle.Region? {
        switch raw {
        case "push": return .push
        case "pull": return .pull
        case "legs": return .legs
        case "core": return .core
        case "conditioning", "full_body": return .conditioning
        default: return nil
        }
    }

    static func regionTitle(_ raw: String) -> String {
        switch raw {
        case "push": return "Push"
        case "pull": return "Pull"
        case "legs": return "Legs"
        case "core": return "Core"
        case "conditioning": return "Conditioning"
        case "full_body": return "Full body"
        case "rest": return "Rest"
        default: return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func parseWeekday(in text: String) -> Int? {
        let lower = text.lowercased()
        let aliases: [(String, Int)] = [
            ("sunday", 0), ("sun", 0),
            ("monday", 1), ("mon", 1),
            ("tuesday", 2), ("tues", 2), ("tue", 2),
            ("wednesday", 3), ("wed", 3),
            ("thursday", 4), ("thurs", 4), ("thur", 4), ("thu", 4),
            ("friday", 5), ("fri", 5),
            ("saturday", 6), ("sat", 6),
        ]
        return aliases
            .filter { lower.contains($0.0) }
            .max(by: { $0.0.count < $1.0.count })?
            .1
    }

    static func wantsReplayPrior(_ text: String) -> Bool {
        let lower = text.lowercased()
        let needles = [
            "yesterday", "day prior", "prior day", "go back",
            "last day's", "last days", "do yesterday",
            "yesterday's session", "yesterdays session",
        ]
        return needles.contains { lower.contains($0) }
    }

    static func summary(mode: SchedulePlanningMode, split: [WeeklySplitSlot]) -> String {
        let week = normalized(split)
        let bits = week.filter { !$0.isRest }.map { "\(dayLabels[$0.weekday]) \($0.title.lowercased())" }
        let days = bits.isEmpty ? "rest week" : bits.joined(separator: " · ")
        switch mode {
        case .rotate: return "Rotate for me"
        case .fixed: return days
        }
    }
}
