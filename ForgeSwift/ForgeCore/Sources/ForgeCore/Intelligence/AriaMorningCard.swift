import Foundation

/// One morning card: the day's call, 1–3 actions, and a short reason.
///
/// Built from personal patterns, gym/equipment, and declared-condition
/// safety. ARIA speaks only when a tracked number moved, and only at the
/// quiet-to-chatty dial the person set. Reason is 25 words or fewer and
/// must come from numbers, not vibes.
public enum AriaMorningCardBuilder: Sendable {

    public static let maxReasonWords = 25
    public static let maxActions = 3

    public enum Talkativeness: String, Codable, CaseIterable, Sendable {
        case quiet
        case balanced
        case chatty

        public var title: String {
            switch self {
            case .quiet: return "Quiet"
            case .balanced: return "Balanced"
            case .chatty: return "Chatty"
            }
        }

        public var line: String {
            switch self {
            case .quiet:
                return "No spoken nudge. The card is enough."
            case .balanced:
                return "Speak only when a number moved."
            case .chatty:
                return "Speak when a number moved, with a short hello."
            }
        }
    }

    public struct Numbers: Equatable, Sendable {
        public var sleepHours: Double?
        public var readiness: Int?
        public var calendarBusyHours: Double?
        public var habitCompletion: Double?

        public init(
            sleepHours: Double? = nil,
            readiness: Int? = nil,
            calendarBusyHours: Double? = nil,
            habitCompletion: Double? = nil
        ) {
            self.sleepHours = sleepHours
            self.readiness = readiness
            self.calendarBusyHours = calendarBusyHours
            self.habitCompletion = habitCompletion
        }
    }

    public struct Input: Equatable, Sendable {
        public var numbers: Numbers
        public var previous: Numbers?
        public var gymLabel: String
        public var equipmentNotes: String
        public var patternChanges: [String]
        public var safetyChange: String
        public var safetyFlags: [ForgeConditionSafety.Flag]
        public var talkativeness: Talkativeness
        public var quietMode: Bool
        public var hasLifeSignal: Bool

        public init(
            numbers: Numbers,
            previous: Numbers? = nil,
            gymLabel: String = "",
            equipmentNotes: String = "",
            patternChanges: [String] = [],
            safetyChange: String = "",
            safetyFlags: [ForgeConditionSafety.Flag] = [],
            talkativeness: Talkativeness = .balanced,
            quietMode: Bool = false,
            hasLifeSignal: Bool = true
        ) {
            self.numbers = numbers
            self.previous = previous
            self.gymLabel = gymLabel
            self.equipmentNotes = equipmentNotes
            self.patternChanges = patternChanges
            self.safetyChange = safetyChange
            self.safetyFlags = safetyFlags
            self.talkativeness = talkativeness
            self.quietMode = quietMode
            self.hasLifeSignal = hasLifeSignal
        }
    }

    public struct Card: Equatable, Sendable {
        public var call: String
        public var actions: [String]
        public var reason: String
        public var speak: Bool
        public var spokenLine: String
        public var empty: Bool
        public var patternLine: String
        public var ruleLine: String

        public var voiceOverLabel: String {
            if empty { return "Today's card. \(call) \(reason)" }
            let acts = actions.enumerated().map { "Action \($0.offset + 1): \($0.element)" }
                .joined(separator: ". ")
            return "Today's card. \(call). \(acts). \(reason)"
        }
    }

    public static func build(_ input: Input) -> Card {
        if !input.hasLifeSignal,
           input.numbers.sleepHours == nil,
           input.numbers.readiness == nil {
            return Card(
                call: "Nothing measured yet",
                actions: ["Open Sleep after tonight", "Or train from your gym setup"],
                reason: "Need a night of sleep or a session to write today's call.",
                speak: false,
                spokenLine: "",
                empty: true,
                patternLine: "",
                ruleLine: ""
            )
        }

        let call = dayCall(input)
        let actions = Array(dayActions(input).prefix(maxActions))
        let reason = clip(reasonLine(input), max: maxReasonWords)
        let moved = numberMoved(previous: input.previous, current: input.numbers)
        let speak = shouldSpeak(
            moved: moved,
            talkativeness: input.talkativeness,
            quietMode: input.quietMode
        )
        let spoken = spokenLine(
            call: call,
            reason: reason,
            talkativeness: input.talkativeness,
            speak: speak
        )
        let card = Card(
            call: call,
            actions: actions,
            reason: reason,
            speak: speak,
            spokenLine: spoken,
            empty: false,
            patternLine: input.patternChanges.first ?? "",
            ruleLine: input.safetyChange
        )
        return card
    }

    public static func wordCount(_ text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    public static func numberMoved(previous: Numbers?, current: Numbers) -> Bool {
        guard let previous else { return false }
        if delta(previous.sleepHours, current.sleepHours, threshold: 0.5) { return true }
        if let old = previous.readiness, let new = current.readiness,
           abs(old - new) >= 8 {
            return true
        }
        if delta(previous.calendarBusyHours, current.calendarBusyHours, threshold: 1.5) {
            return true
        }
        if delta(previous.habitCompletion, current.habitCompletion, threshold: 0.25) {
            return true
        }
        return false
    }

    public static func shouldSpeak(
        moved: Bool,
        talkativeness: Talkativeness,
        quietMode: Bool
    ) -> Bool {
        if quietMode { return false }
        if talkativeness == .quiet { return false }
        return moved
    }

    // MARK: - Copy

    private static func dayCall(_ input: Input) -> String {
        if input.safetyFlags.contains(.heat) {
            return "Keep it cool and short"
        }
        if input.safetyFlags.contains(.sleepLoss) {
            return "Easy session"
        }
        if let hours = input.numbers.sleepHours, hours < 6.5 {
            return "Easy session"
        }
        if let busy = input.numbers.calendarBusyHours, busy >= 4 {
            return "One small win"
        }
        if let readiness = input.numbers.readiness, readiness < 55 {
            return "Easy session"
        }
        if !input.gymLabel.isEmpty {
            return "Train at \(input.gymLabel)"
        }
        return "Do the next honest session"
    }

    private static func dayActions(_ input: Input) -> [String] {
        var actions: [String] = []
        if let change = input.patternChanges.first, !change.isEmpty {
            actions.append(change)
        }
        if input.safetyFlags.contains(.sleepLoss) {
            actions.append("Keep today's session grounded")
        }
        if input.safetyFlags.contains(.heat) {
            actions.append("Train cooler, stop early if you heat up")
        }
        if actions.isEmpty {
            if let hours = input.numbers.sleepHours, hours < 6.5 {
                actions.append("Shorter session, same structure")
            } else if !input.gymLabel.isEmpty {
                actions.append("Use \(input.gymLabel.lowercased()) as written")
            } else {
                actions.append("Start the session already on Home")
            }
        }
        if let busy = input.numbers.calendarBusyHours, busy >= 4 {
            actions.append("Protect one habit check-in")
        }
        if !input.equipmentNotes.isEmpty, actions.count < maxActions {
            actions.append("Stay on the gear you have")
        }
        if actions.count < 2 {
            actions.append("Drink water with the session")
        }
        return uniqued(actions)
    }

    private static func reasonLine(_ input: Input) -> String {
        var bits: [String] = []
        if let hours = input.numbers.sleepHours {
            bits.append(String(format: "%.1f hours last night", hours))
        }
        if let readiness = input.numbers.readiness {
            bits.append("readiness \(readiness)")
        }
        if let busy = input.numbers.calendarBusyHours, busy >= 1 {
            bits.append(String(format: "%.0f hours on the calendar", busy))
        }
        if let habit = input.numbers.habitCompletion {
            bits.append(String(format: "habits at %.0f%%", habit * 100))
        }
        if bits.isEmpty {
            return "Built from the gym you named and today's plan."
        }
        var line = bits.joined(separator: ", ") + ", so the day stays honest."
        if !input.gymLabel.isEmpty {
            line = bits.joined(separator: ", ")
                + ", so this fits \(input.gymLabel.lowercased())."
        }
        return line
    }

    private static func spokenLine(
        call: String,
        reason: String,
        talkativeness: Talkativeness,
        speak: Bool
    ) -> String {
        guard speak else { return "" }
        if talkativeness == .chatty {
            return "Hey — \(call.lowercased()). \(reason)"
        }
        return "\(call). \(reason)"
    }

    private static func clip(_ text: String, max: Int) -> String {
        let words = text.split { $0.isWhitespace || $0.isNewline }.map(String.init)
        if words.count <= max { return words.joined(separator: " ") }
        return words.prefix(max).joined(separator: " ")
    }

    private static func delta(_ a: Double?, _ b: Double?, threshold: Double) -> Bool {
        guard let a, let b else { return false }
        return abs(a - b) >= threshold
    }

    private static func uniqued(_ items: [String]) -> [String] {
        var seen: Set<String> = []
        var out: [String] = []
        for item in items {
            let key = item.lowercased()
            if seen.insert(key).inserted { out.append(item) }
        }
        return out
    }
}
