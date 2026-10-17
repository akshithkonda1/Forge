import Foundation

/// On-device personalization derived from onboarding, UserContext-shaped
/// fields, and Health-backed mosaic/readiness — never a cloud profile.
///
/// Copy rules: coach, not doctor. Never diagnose. Never say "recovery".
public enum ForgePersonalization: Sendable {

    public enum Focus: String, Codable, CaseIterable, Sendable {
        case strength
        case endurance
        case sleep
        case lifestyle

        public var label: String {
            switch self {
            case .strength: return "Strength"
            case .endurance: return "Endurance"
            case .sleep: return "Sleep"
            case .lifestyle: return "Lifestyle"
            }
        }
    }

    public enum Daypart: String, Sendable {
        case morning, afternoon, evening

        public var greeting: String {
            switch self {
            case .morning: return "Good morning"
            case .afternoon: return "Good afternoon"
            case .evening: return "Good evening"
            }
        }

        public static func at(_ date: Date, calendar: Calendar = .current) -> Daypart {
            let hour = calendar.component(.hour, from: date)
            if hour < 12 { return .morning }
            if hour < 17 { return .afternoon }
            return .evening
        }
    }

    public enum Units: String, Codable, CaseIterable, Sendable {
        case metric
        case imperial

        public var label: String {
            switch self {
            case .metric: return "Metric"
            case .imperial: return "Imperial"
            }
        }
    }

    public enum Accent: String, Codable, CaseIterable, Sendable {
        case ember
        case steel
        case vitality

        public var label: String {
            switch self {
            case .ember: return "Ember"
            case .steel: return "Steel"
            case .vitality: return "Vitality"
            }
        }

        public var hex: String {
            switch self {
            case .ember: return "FF4D00"
            case .steel: return "5B8DEF"
            case .vitality: return "22C55E"
            }
        }
    }

    public struct Preferences: Codable, Equatable, Sendable {
        public var units: Units
        public var accent: Accent
        public var focusOverride: Focus?
        public var homeSectionOrder: [String]

        public static let storageKey = "forge.personalization.prefs.v1"

        public init(
            units: Units = .metric,
            accent: Accent = .ember,
            focusOverride: Focus? = nil,
            homeSectionOrder: [String] = []
        ) {
            self.units = units
            self.accent = accent
            self.focusOverride = focusOverride
            self.homeSectionOrder = homeSectionOrder
        }
    }

    public enum HomeSection: String, CaseIterable, Sendable {
        case todayHero
        case forecast
        case briefing
        case mosaic
        case lifestyle
        case widgets
        case story
        case rest
    }

    public static func firstName(from fullName: String) -> String {
        fullName.split(separator: " ").first.map(String.init) ?? ""
    }

    public static func focus(
        goals: [String],
        workouts: [String],
        override: Focus? = nil
    ) -> Focus {
        if let override { return override }
        let blob = (goals + workouts).joined(separator: " ").lowercased()
        if blob.contains("sleep") || blob.contains("night") || blob.contains("stress") {
            return .sleep
        }
        if blob.contains("endurance") || blob.contains("run") || blob.contains("cardio") {
            return .endurance
        }
        if blob.contains("muscle") || blob.contains("strength") || blob.contains("weight")
            || blob.contains("athletic") || blob.contains("hypertrophy") {
            return .strength
        }
        return .lifestyle
    }

    public static func greeting(
        name: String,
        goals: [String],
        workouts: [String],
        now: Date = Date(),
        override: Focus? = nil
    ) -> String {
        let who = firstName(from: name)
        let part = Daypart.at(now)
        let hi = who.isEmpty ? part.greeting : "\(part.greeting), \(who)"
        let focus = focus(goals: goals, workouts: workouts, override: override)
        switch (part, focus) {
        case (.morning, .sleep):
            return "\(hi). Last night sets the day — keep it honest."
        case (.morning, .strength):
            return "\(hi). Strength day starts with how you showed up."
        case (.morning, .endurance):
            return "\(hi). Easy miles beat a heroic crash."
        case (.evening, .sleep):
            return "\(hi). Protect the night you still have."
        case (.evening, .strength), (.evening, .endurance):
            return "\(hi). The work is done or it isn’t — no extra hero set."
        case (_, .lifestyle):
            return "\(hi). One picture of the life you already have."
        default:
            return "\(hi). \(focus.label) stays the thread."
        }
    }

    public static func ariaOpener(
        name: String,
        goals: [String],
        workouts: [String],
        override: Focus? = nil
    ) -> String {
        let who = firstName(from: name)
        let focus = focus(goals: goals, workouts: workouts, override: override)
        let goal = goals.first.map { $0.replacingOccurrences(of: "-", with: " ") }
        let named = who.isEmpty ? "I'm ARIA." : "\(who) — I'm ARIA."
        let toward = goal.map { " You mentioned \($0.lowercased())." } ?? ""
        switch focus {
        case .sleep:
            return "\(named)\(toward) Sleep struggles, stress, a dip in drive — say it. I steer; I don't diagnose. If it needs a doctor, I'll say so."
        case .strength:
            return "\(named)\(toward) Setbacks and heavy days are fair game. I coach the session in front of you — not a clinical read."
        case .endurance:
            return "\(named)\(toward) Motivation dips happen. We'll size the day you have, not the one on paper."
        case .lifestyle:
            return "\(named)\(toward) Stress, body image, life events — I can sit with those. Lifestyle coach, not a doctor."
        }
    }

    public static func homeSections(
        focus: Focus,
        daypart: Daypart,
        custom: [String] = []
    ) -> [HomeSection] {
        if !custom.isEmpty {
            let parsed = custom.compactMap(HomeSection.init(rawValue:))
            if !parsed.isEmpty { return parsed + HomeSection.allCases.filter { !parsed.contains($0) } }
        }
        var order: [HomeSection]
        switch (daypart, focus) {
        case (.morning, .sleep):
            order = [.todayHero, .briefing, .mosaic, .forecast, .lifestyle, .widgets, .story, .rest]
        case (.evening, .sleep):
            order = [.todayHero, .briefing, .story, .mosaic, .lifestyle, .forecast, .widgets, .rest]
        case (_, .strength), (_, .endurance):
            order = [.todayHero, .forecast, .mosaic, .briefing, .widgets, .lifestyle, .story, .rest]
        case (_, .lifestyle):
            order = [.todayHero, .lifestyle, .briefing, .mosaic, .widgets, .forecast, .story, .rest]
        }
        return order
    }

    public static func formatKg(_ kg: Double, units: Units) -> String {
        switch units {
        case .metric:
            return String(format: "%.1f kg", kg)
        case .imperial:
            return String(format: "%.0f lb", kg * 2.20462262)
        }
    }

    public static func formatCm(_ cm: Double, units: Units) -> String {
        switch units {
        case .metric:
            return String(format: "%.0f cm", cm)
        case .imperial:
            let totalInches = cm / 2.54
            let feet = Int(totalInches / 12)
            let inches = Int(totalInches.rounded()) % 12
            return "\(feet)'\(inches)\""
        }
    }

    public static func formatMl(_ ml: Double, units: Units) -> String {
        switch units {
        case .metric:
            if ml >= 1000 { return String(format: "%.1f L", ml / 1000) }
            return String(format: "%.0f ml", ml)
        case .imperial:
            let oz = ml / 29.5735
            return String(format: "%.0f oz", oz)
        }
    }

    public static func containsBannedCopy(_ line: String) -> Bool {
        let lower = line.lowercased()
        let banned = ["diagnos", "treat", "prescribe", "cure", "medical advice", "recovery"]
        return banned.contains { lower.contains($0) }
    }
}
