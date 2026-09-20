import Foundation

/// The eight-way choice ARIA's suggestion box offers. Coarse on purpose: the
/// box asks "what part of the body today?", not for 22 individual muscles.
enum TrainingFocus: String, CaseIterable, Codable, Sendable {
    case chest, back, legs, shoulders, arms, core, fullBody, conditioning

    var chipLabel: String {
        switch self {
        case .chest: return "Chest"
        case .back: return "Back"
        case .legs: return "Legs"
        case .shoulders: return "Shoulders"
        case .arms: return "Arms"
        case .core: return "Core"
        case .fullBody: return "Full body"
        case .conditioning: return "Cardio"
        }
    }

    /// The catalog muscles this focus covers — used to build the plan and to
    /// find sports that train the same tissue. Covers all 22 TargetMuscle
    /// cases, mirroring `from(mentioned:)` below.
    var muscles: [TargetMuscle] {
        switch self {
        case .chest: return [.chest]
        case .back: return [.upperBack, .lats, .traps]
        case .legs: return [.quads, .hamstrings, .glutes, .adductors, .abductors, .calves, .hipFlexors, .lowerBack]
        case .shoulders: return [.frontDelts, .sideDelts, .rearDelts]
        case .arms: return [.biceps, .triceps, .forearms]
        case .core: return [.abs, .obliques]
        case .fullBody: return [.fullBody]
        case .conditioning: return [.cardio]
        }
    }

    /// A keyword the plan engine's `TargetMuscle.mentioned(in:)` will resolve,
    /// so a forced focus can be passed through the normal input path.
    var planKeyword: String {
        switch self {
        case .chest: return "chest"
        case .back: return "back"
        case .legs: return "legs"
        case .shoulders: return "shoulders"
        case .arms: return "arms"
        case .core: return "core"
        case .fullBody: return "full body"
        case .conditioning: return "cardio"
        }
    }

    /// Map a mentioned catalog muscle (or chip text) back to a focus.
    static func from(mentioned muscle: TargetMuscle) -> TrainingFocus {
        switch muscle {
        case .chest: return .chest
        case .upperBack, .lats, .traps: return .back
        case .quads, .hamstrings, .glutes, .adductors, .abductors, .calves, .hipFlexors, .lowerBack: return .legs
        case .frontDelts, .sideDelts, .rearDelts: return .shoulders
        case .biceps, .triceps, .forearms: return .arms
        case .abs, .obliques: return .core
        case .fullBody: return .fullBody
        case .cardio: return .conditioning
        }
    }

    static func from(text: String) -> TrainingFocus? {
        guard let muscle = TargetMuscle.mentioned(in: text) else { return nil }
        return from(mentioned: muscle)
    }

    /// Weekly-split region ids ("push", "pull", "legs", …) map to a focus so
    /// the onboarding week seeds day-one predictions.
    static func from(splitRegion region: String) -> TrainingFocus? {
        switch region {
        case "push": return .chest
        case "pull": return .back
        case "legs": return .legs
        case "core": return .core
        case "full_body": return .fullBody
        case "conditioning": return .conditioning
        default: return nil
        }
    }
}

extension ExerciseLibrary {
    /// Sports whose primary or secondary muscles include any of these — so a
    /// chest day can offer swimming, a leg day soccer. The sports person never
    /// has to leave the muscle conversation.
    static func sportsFor(muscles: [TargetMuscle]) -> [ExerciseDefinition] {
        sports.filter { def in
            muscles.contains { def.primary.contains($0) || def.secondary.contains($0) }
        }
    }
}

/// What ARIA has learned about how this person trains. Pure value type:
/// record choices, predict the next one. The path of least resistance —
/// when ARIA already knows what Tuesday means, it just puts it on the board.
struct TrainingHabits: Codable, Sendable {

    /// Who owns the plan. `.ariaLeads` = "take charge / rotate for me";
    /// `.userLeads` = ARIA learns the pattern and follows it.
    enum Mode: String, Codable, Sendable {
        case userLeads, ariaLeads
    }

    enum Choice: Codable, Sendable, Equatable {
        case focus(TrainingFocus)
        case sport(String)

        var key: String {
            switch self {
            case .focus(let f): return "focus:\(f.rawValue)"
            case .sport(let name): return "sport:\(name.lowercased())"
            }
        }

        var displayName: String {
            switch self {
            case .focus(let f): return f.chipLabel.lowercased()
            case .sport(let name): return name
            }
        }

        static func from(key: String) -> Choice? {
            if key.hasPrefix("focus:"), let f = TrainingFocus(rawValue: String(key.dropFirst(6))) {
                return .focus(f)
            }
            if key.hasPrefix("sport:") {
                return .sport(String(key.dropFirst(6)).capitalized)
            }
            return nil
        }
    }

    struct Suggestion: Sendable, Equatable {
        let choice: Choice
        /// Grounded attribution, e.g. "Mondays are usually chest for you".
        let reason: String
    }

    var mode: Mode = .userLeads
    /// WeeklySplit convention: 0 = Sunday … 6 = Saturday. Choice key → times chosen.
    var weekdayChoices: [Int: [String: Int]] = [:]
    /// Most recent choice keys, newest last. Caps at 14.
    var recentKeys: [String] = []
    /// 0…1 — how often this person trains through sports.
    var sportAffinity: Double = 0
    /// Sports they love, most-loved first. Seeded from onboarding.
    var favoriteSports: [String] = []

    // MARK: - Calendar

    /// WeeklySplit weekday index (0 = Sunday … 6 = Saturday) for a date.
    static func weekdayIndex(for date: Date, calendar: Calendar = .current) -> Int {
        (calendar.component(.weekday, from: date) + 6) % 7
    }

    static func weekdayName(for index: Int) -> String {
        ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][index % 7]
    }

    // MARK: - Seeding (onboarding)

    /// Seed from the onboarding conversation: the weekly split becomes
    /// day-one predictions, "rotate for me" hands ARIA the week, and named
    /// sports become the sports shelf.
    mutating func seedFromProfile(
        weeklySplit: [WeeklySplitSlot],
        scheduleMode: SchedulePlanningMode,
        sportNames: [String]
    ) {
        mode = scheduleMode == .rotate ? .ariaLeads : .userLeads
        for slot in weeklySplit where !slot.isRest {
            if let focus = TrainingFocus.from(splitRegion: slot.primary) {
                // A planned split counts double — it's a stated intention,
                // not just one observed Tuesday.
                let key = Choice.focus(focus).key
                weekdayChoices[slot.weekday, default: [:]][key, default: 0] += 2
            }
        }
        let sports = Array(NSOrderedSet(array: sportNames).array as? [String] ?? sportNames)
        favoriteSports = Array(sports.prefix(6))
        if !favoriteSports.isEmpty { sportAffinity = max(sportAffinity, 0.5) }
    }

    // MARK: - Recording

    mutating func record(_ choice: Choice, weekday: Int) {
        guard (0...6).contains(weekday) else { return }
        weekdayChoices[weekday, default: [:]][choice.key, default: 0] += 1
        recentKeys.append(choice.key)
        if recentKeys.count > 14 { recentKeys.removeFirst(recentKeys.count - 14) }
        switch choice {
        case .sport(let name):
            sportAffinity = min(1, sportAffinity + 0.15)
            favoriteSports.removeAll { $0.caseInsensitiveCompare(name) == .orderedSame }
            favoriteSports.insert(name, at: 0)
            favoriteSports = Array(favoriteSports.prefix(6))
        case .focus:
            sportAffinity = max(0, sportAffinity - 0.05)
        }
    }

    mutating func setMode(_ mode: Mode) {
        self.mode = mode
    }

    // MARK: - Prediction

    /// What ARIA should propose before asking. Nil means "ask the human" —
    /// the suggestion box. A suggestion is only returned when the pattern is
    /// real: seen at least twice and dominant for that weekday.
    func suggestion(forWeekday weekday: Int) -> Suggestion? {
        guard mode == .userLeads, (0...6).contains(weekday) else { return nil }
        if let counts = weekdayChoices[weekday], !counts.isEmpty {
            let total = counts.values.reduce(0, +)
            if let top = counts.max(by: { $0.value < $1.value }),
               top.value >= 2, Double(top.value) / Double(total) >= 0.6,
               let choice = Choice.from(key: top.key) {
                let day = Self.weekdayName(for: weekday)
                return Suggestion(
                    choice: choice,
                    reason: "\(day)s are usually \(choice.displayName) for you"
                )
            }
        }
        if sportAffinity >= 0.6, let sport = favoriteSports.first {
            return Suggestion(
                choice: .sport(sport),
                reason: "you usually play your way through the week"
            )
        }
        return nil
    }

    func suggestion(for date: Date, calendar: Calendar = .current) -> Suggestion? {
        suggestion(forWeekday: Self.weekdayIndex(for: date, calendar: calendar))
    }

    // MARK: - Ownership phrases (lowercased input)

    /// "Take charge" in all its forms — explicit delegation: ARIA owns the plan.
    static func isTakeChargePhrase(in lower: String) -> Bool {
        ["take charge", "you pick", "you decide", "surprise me",
         "whatever you think", "i trust you", "rotate for me", "you choose",
         "dealer's choice", "dealers choice"].contains { lower.contains($0) }
    }

    /// "I'll pick" — explicit user ownership: ARIA learns and follows.
    static func isUserLedPhrase(in lower: String) -> Bool {
        ["i'll pick", "i will pick", "i'll decide", "i will decide",
         "let me pick", "let me decide", "my call",
         "i'll choose", "i will choose"].contains { lower.contains($0) }
    }

    /// Bare sports request — "sports", "something sporty" — opens the picker.
    static func isSportPickerRequest(in lower: String) -> Bool {
        let t = lower.trimmingCharacters(in: .whitespacesAndNewlines)
        return t == "sports" || t == "sport"
            || t.contains("something sporty") || t.contains("a sport")
            || t.contains("play something")
    }

    // MARK: - Chip routing

    /// The suggestion box's chip labels. Tapping a chip sends its label back
    /// as bare text — the turn parser routes these to training so a tap
    /// never lands nowhere. Exact labels only: "my shoulders are tight"
    /// must NOT route here.
    static var boxChipLabels: Set<String> {
        Set(
            TrainingFocus.allCases.map { $0.chipLabel.lowercased() }
                + ["sports", "sport", "you pick", "something else"]
        )
    }

    static func isBoxChip(_ text: String) -> Bool {
        boxChipLabels.contains(
            text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        )
    }
}
