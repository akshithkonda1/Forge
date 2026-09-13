import Foundation
import ForgeCore

/// Follow-up that binds to the last ARIA act instead of starting a new hunt.
enum AriaDummyFollowUp: Equatable {
    case none
    case accept
    case decline
    case easier
    case shorter
    case lessLegs
    case askSleep
}

/// Forge-local side effects. Dummy never writes Apple Calendar titles.
enum AriaDummyAction: Equatable {
    enum ReminderKind: String, Equatable {
        case hydration, meal, sleep, workout
    }

    case persistWorkout
    case persistTheme
    case rememberFact(String)
    case scaleEasier
    case scaleShorter
    case cancelWorkout
    case skipLegs
    case scheduleReminder(kind: ReminderKind, hour: Int?)
    case logWater(milliliters: Double)
    case writeNote(String)
    case recordSport(name: String, minutes: Int, completed: Bool)
}

struct AriaDummyBeat {
    var domain: AriaIntentDomain
    var prose: String
    var card: RichCardPayload? = nil
    var suggestedActions: [String] = []
    var actions: [AriaDummyAction] = []
}

/// Parsed turn: clauses, ranked domains, discourse, and the constraint string
/// fed to the plan engine. Pure so tests can lock routing without AppStore.
struct AriaDummyInterpretation: Equatable {
    var clauses: [String]
    var domains: [AriaIntentDomain]
    var primaryAgent: AriaCoachAgent
    var followUp: AriaDummyFollowUp
    var reminder: AriaDummyAction?
    var joints: [String]
    var skipLegs: Bool
    var keepLight: Bool
    var constrainedPlanInput: String
    var preferCalisthenics: Bool
    var logWaterMl: Double?
    var noteToWrite: String?
    var readBoard: Bool
    var recordedSport: AriaDummySport?
    var readCalendar: Bool
}

struct AriaDummySport: Equatable {
    var name: String
    var minutes: Int
    var completed: Bool
}

struct AriaDummyActs: Equatable {
    var preferCalisthenics = false
    var logWaterMl: Double? = nil
    var noteToWrite: String? = nil
    var readBoard = false
    var sport: AriaDummySport? = nil
    var readCalendar = false
}

/// Local conductor for the dummy orchestra. No URLSession, no Bedrock, no
/// off-device LLM. Slight creativity is seeded phrase variation plus, when
/// the phone has Apple Intelligence, an optional on-device polish that must
/// keep the skeleton facts.
enum AriaDummyTurn {

    static let usesOffDeviceLLM = false
    static let writesCalendarEvents = false

    private static let intentNeedles = [
        "sleep", "slept", "insomnia", "bedtime", "last night",
        "train", "workout", "session", "lift", "gym", "squat",
        "eat", "food", "protein", "meal", "lunch", "dinner", "breakfast",
        "water", "hydrat", "remind", "nudge", "ping me",
        "knee", "shoulder", "hip", "ankle", "elbow", "wrist", "neck",
        "sore", "pain", "hurt", "legs", "recover", "hrv",
        "progress", "streak", "cycle", "period",
        "calisthenic", "bodyweight", "write that", "on my board",
        "log water", "drank water", "note that", "remember that",
        "basketball", "soccer", "tennis", "played", "sport", "hiking",
        "pickleball", "volleyball", "golf", "boxing",
        "calendar", "busy window", "what's on my week",
    ]

    private static let jointWords = [
        "knee", "shoulder", "back", "hip", "ankle", "wrist", "elbow", "neck",
    ]

    static func clauses(in text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        // ContextualParsingEngine also splits on commas, which the old
        // dash/semicolon/connective-only split did not: "slept badly, want
        // to hit the gym" used to reach here as one unsplit blob.
        let rawParts = ContextualParsingEngine.splitClauses(trimmed)
        guard rawParts.count > 1 else { return [trimmed] }

        var merged: [String] = []
        for part in rawParts {
            if hasIntentNeedle(part) {
                merged.append(part)
            } else if let last = merged.popLast() {
                merged.append("\(last) \(part)")
            } else {
                merged.append(part)
            }
        }
        let withNeedles = merged.filter(hasIntentNeedle)
        if withNeedles.count >= 2 { return withNeedles }
        return [trimmed]
    }

    static func followUp(in text: String) -> AriaDummyFollowUp {
        let t = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.count < 72 else { return .none }
        if t.contains("what about sleep") || t == "how did i sleep" || t == "and sleep?" {
            return .askSleep
        }
        if matches(t, ["less legs", "skip legs", "no squats", "no leg day"]) { return .lessLegs }
        if matches(t, ["easier", "lighter", "too hard", "scale it", "scale down", "less intense"]) {
            return .easier
        }
        if matches(t, ["shorter", "less time", "cut it down", "make it shorter"]) { return .shorter }
        if matches(t, ["skip it", "cancel", "never mind", "no thanks", "don't", "do not"]) {
            return .decline
        }
        if matches(t, ["yes", "do it", "that one", "go ahead", "lock it in", "sounds good", "let's do it"]) {
            return .accept
        }
        return .none
    }

    static func reminder(in text: String) -> AriaDummyAction? {
        let lower = text.lowercased()
        let asked = lower.contains("remind") || lower.contains("nudge") || lower.contains("ping me")
            || lower.contains("notify me")
        guard asked else { return nil }
        let parsed = hour(in: lower)
        if lower.contains("water") || lower.contains("hydrat") {
            return .scheduleReminder(kind: .hydration, hour: parsed)
        }
        if lower.contains("eat") || lower.contains("food") || lower.contains("meal")
            || lower.contains("protein") || lower.contains("lunch") || lower.contains("dinner") {
            let mealHour = (parsed.map { $0 > 0 && $0 < 8 ? $0 + 12 : $0 }) ?? 13
            return .scheduleReminder(kind: .meal, hour: mealHour)
        }
        if lower.contains("sleep") || lower.contains("bed") || lower.contains("wind down") {
            return .scheduleReminder(kind: .sleep, hour: parsed ?? 21)
        }
        if lower.contains("train") || lower.contains("workout") {
            return .scheduleReminder(kind: .workout, hour: parsed)
        }
        return .scheduleReminder(kind: .meal, hour: parsed)
    }

    static func joints(in text: String, remembered: [String]) -> [String] {
        var found: [String] = []
        let blob = (text + " " + remembered.joined(separator: " ")).lowercased()
        for joint in jointWords where blob.contains(joint) && !found.contains(joint) {
            found.append(joint)
        }
        return found
    }

    static func acts(in text: String) -> AriaDummyActs {
        let lower = text.lowercased()
        var acts = AriaDummyActs()
        acts.preferCalisthenics = lower.contains("calisthenic")
            || lower.contains("bodyweight session")
            || lower.contains("bodyweight workout")
            || lower.contains("no-equipment")
            || lower.contains("no equipment")
            || lower.contains("no-gear")
            || lower.contains("no gear")
        acts.logWaterMl = waterLogMilliliters(in: lower)
        acts.noteToWrite = noteToWrite(in: text)
        acts.readBoard = lower.contains("on my board")
            || lower.contains("what do you know")
            || lower.contains("read my notes")
            || lower.contains("what have you written")
            || lower.contains("what's on my board")
            || lower.contains("whats on my board")
        if let sport = sportAct(in: text) {
            acts.sport = sport
        }
        acts.readCalendar = lower.contains("on my calendar")
            || lower.contains("what's on my calendar")
            || lower.contains("whats on my calendar")
            || lower.contains("my calendar")
            || (lower.contains("calendar") && (lower.contains("week") || lower.contains("today") || lower.contains("busy")))
            || lower.contains("what's on this week")
            || lower.contains("whats on this week")
            || lower.contains("what's coming up")
            || lower.contains("whats coming up")
            || lower.contains("how does my week")
            || lower.contains("how's my week")
            || lower.contains("hows my week")
            || lower.contains("think about my week")
            || lower.contains("what's this week")
            || lower.contains("whats this week")
        return acts
    }

    static func waterLogMilliliters(in text: String) -> Double? {
        let lower = text.lowercased()
        if lower.contains("remind") { return nil }
        let asked = (lower.contains("log") && (lower.contains("water") || lower.contains("drank")))
            || lower.contains("i drank water")
            || lower.contains("i had a glass")
            || lower.contains("log that i drank")
            || (lower.contains("drank") && lower.contains("water"))
        guard asked else { return nil }
        if let oz = firstCapture(in: lower, pattern: #"(\d+(?:\.\d+)?)\s*(?:oz|ounces?)"#) {
            return HydrationEngine.milliliters(fromFluidOunces: oz)
        }
        if let ml = firstCapture(in: lower, pattern: #"(\d+(?:\.\d+)?)\s*(?:ml|milliliters?)"#) {
            return ml
        }
        return 250
    }

    static func noteToWrite(in text: String) -> String? {
        let lower = text.lowercased()
        let triggers = [
            "write that down:", "write that down",
            "note that:", "note that",
            "remember that:", "remember that",
            "remember i ",
            "put this on my board:", "put this on my board",
            "put that on my board:", "put that on my board",
            "add that to my board",
        ]
        guard let trigger = triggers.first(where: { lower.contains($0) }) else { return nil }
        guard let range = lower.range(of: trigger) else { return nil }
        let after = text[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = after.trimmingCharacters(in: CharacterSet(charactersIn: ".,:;"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count >= 3 { return String(cleaned.prefix(180)) }
        return "I'll keep the last thing you told me."
    }

    static func sportAct(in text: String) -> AriaDummySport? {
        guard let def = ExerciseLibrary.matchSport(in: text) else { return nil }
        let lower = text.lowercased()
        let planning = lower.contains("give me")
            || lower.contains("build me")
            || lower.contains("want to")
            || lower.contains("let's play")
            || lower.contains("lets play")
            || (lower.contains("session") && !lower.contains("played") && !lower.contains("log"))
        let completed = !planning && (
            lower.contains("played")
            || lower.contains("i did")
            || lower.contains("just finished")
            || lower.contains("finished a")
            || lower.contains("record")
            || lower.contains("log ")
            || lower.contains("logged")
            || lower.contains("went to")
            || lower.contains("had a game")
            || lower.contains("had a match")
            || lower.contains("practice")
        )
        return AriaDummySport(
            name: def.name,
            minutes: durationMinutes(in: lower),
            completed: completed
        )
    }

    static func durationMinutes(in text: String) -> Int {
        let lower = text.lowercased()
        if lower.contains("hour and a half") || lower.contains("1.5 hour") || lower.contains("ninety") {
            return 90
        }
        if lower.contains("an hour") || lower.contains("one hour") || lower.contains("1 hour") {
            return 60
        }
        if let mins = firstCapture(in: lower, pattern: #"(\d+)\s*(?:min|mins|minute)"#) {
            return min(180, max(10, Int(mins)))
        }
        return 45
    }

    private static func firstCapture(in text: String, pattern: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges >= 2,
              let cap = Range(match.range(at: 1), in: text) else { return nil }
        return Double(text[cap])
    }

    static func interpret(
        text: String,
        agent: AriaCoachAgent,
        agents: [AriaCoachAgent],
        signals: AriaIntentInput,
        sleepWeak: Bool,
        readinessLow: Bool
    ) -> AriaDummyInterpretation {
        let parts = clauses(in: text)
        var domains: [AriaIntentDomain] = []

        func add(_ domain: AriaIntentDomain) {
            if !domains.contains(domain) { domains.append(domain) }
        }

        let roster = agents.isEmpty ? [agent] : agents
        let acts = acts(in: text)
        for item in roster {
            add(domain(for: item))
        }
        for domain in AriaIntentResolver.actionable(AriaIntentResolver.rank(signals), limit: 4) {
            add(domain)
        }
        for clause in parts {
            var sub = signals
            sub.text = clause
            for domain in AriaIntentResolver.actionable(AriaIntentResolver.rank(sub), limit: 2) {
                add(domain)
            }
        }
        if reminder(in: text) != nil { add(.nutrition) }
        if acts.preferCalisthenics { add(.training) }
        if acts.sport != nil { add(.training) }
        if acts.logWaterMl != nil { add(.nutrition) }
        if acts.noteToWrite != nil { add(.lifestyle) }
        if acts.readBoard { add(.progress) }
        if acts.readCalendar { add(.lifestyle) }
        if domains.contains(.nutrition), agent != .lifestyle, acts.noteToWrite == nil {
            domains.removeAll { $0 == .lifestyle }
        }

        let jointsFound = joints(in: text, remembered: signals.rememberedFacts)
        let skipLegs = text.lowercased().contains("skip legs")
            || text.lowercased().contains("less legs")
            || text.lowercased().contains("no squats")
            || jointsFound.contains(where: { ["knee", "hip", "ankle"].contains($0) })
        let keepLight = sleepWeak || readinessLow
            || text.lowercased().contains("keep it light")
            || text.lowercased().contains("easy session")

        var extra: [String] = [text]
        if skipLegs { extra.append("lats upper body skip legs") }
        if jointsFound.contains("shoulder") || jointsFound.contains("elbow") {
            extra.append("keep pressing light")
        }
        if keepLight { extra.append("keep it light recovery session") }
        if acts.preferCalisthenics { extra.append("bodyweight calisthenics session") }
        let constrained = extra.joined(separator: ". ")

        let primary: AriaCoachAgent
        if agent != .aria, domains.contains(domain(for: agent)) {
            primary = agent
        } else {
            primary = primaryAgent(from: domains, roster: roster, fallback: agent)
        }
        return AriaDummyInterpretation(
            clauses: parts,
            domains: domains,
            primaryAgent: primary,
            followUp: followUp(in: text),
            reminder: reminder(in: text),
            joints: jointsFound,
            skipLegs: skipLegs,
            keepLight: keepLight,
            constrainedPlanInput: constrained,
            preferCalisthenics: acts.preferCalisthenics,
            logWaterMl: acts.logWaterMl,
            noteToWrite: acts.noteToWrite,
            readBoard: acts.readBoard,
            recordedSport: acts.sport,
            readCalendar: acts.readCalendar
        )
    }

    /// Cause → constraint → created system → side effect. Seeded variation so
    /// the fill-in does not reprint the same sentence every Device Hub tap.
    static func compose(
        beats: [AriaDummyBeat],
        interpretation: AriaDummyInterpretation,
        name: String,
        seed: UInt64,
        prompt: String = ""
    ) -> String {
        var rng = AriaSeededRNG(seed: seed == 0 ? 0xA11A : seed)
        let sleep = beats.first { $0.domain == .sleep || $0.domain == .readiness }
        let train = beats.first { $0.domain == .training }
        let food = beats.first { $0.domain == .nutrition || $0.domain == .lifestyle }
        let body = beats.first { $0.domain == .body }
        let extra = beats.filter {
            $0.domain == .cycle || $0.domain == .progress
        }
        let askedFood = AriaPromptCorrelation.requiredMentions(in: prompt)
            .contains { ["eat", "food", "protein", "water"].contains($0) }
            || interpretation.logWaterMl != nil
            || interpretation.noteToWrite != nil
            || interpretation.readCalendar
            || QualityOfLifeLivingStore.isQuestion(prompt)
            || AriaReferenceCatalog.questionSuggestsEventPrep(prompt)

        var sentences: [String] = []
        let hey = name.isEmpty ? "" : rng.pick(["Hey \(name) — ", "\(name), ", ""])

        if let sleep {
            let limit = sleep.prose.lowercased().contains("up at") ? 220 : 140
            sentences.append(hey + clip(sleep.prose, limit: limit))
        } else if let body {
            sentences.append(hey + clip(body.prose, limit: 140))
        } else if !hey.isEmpty {
            sentences.append(hey.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        if interpretation.skipLegs || interpretation.keepLight, train != nil {
            let constraint: String
            if interpretation.skipLegs && interpretation.keepLight {
                constraint = rng.pick([
                    "so I'm not writing heavy legs on a thin night.",
                    "so we skip the heavy lower work and keep the load honest.",
                    "so legs stay off the menu and intensity stays kind.",
                ])
            } else if interpretation.skipLegs {
                constraint = rng.pick([
                    "so I'm not writing heavy legs.",
                    "so we route around that joint and leave squats off.",
                    "so lower-body load stays out of the way.",
                ])
            } else {
                constraint = rng.pick([
                    "so this is not a hero day.",
                    "so we keep the session honest, not heroic.",
                    "so intensity stays on a leash.",
                ])
            }
            sentences.append(constraint)
        }

        if let train {
            sentences.append(clip(train.prose, limit: 280))
        }
        if let food, askedFood || train == nil {
            let lowerFood = food.prose.lowercased()
            let calendarThought = interpretation.readCalendar
                || lowerFood.contains("calendar")
                || lowerFood.contains("wedding")
                || lowerFood.contains("trip")
                || lowerFood.contains("travel")
                || lowerFood.contains("busy window")
                || lowerFood.contains("lifestyle qol")
                || lowerFood.contains("quality of life")
                || lowerFood.contains("tux")
                || lowerFood.contains("suit")
            let limit = calendarThought ? 280 : 140
            sentences.append(clip(food.prose, limit: limit))
        }
        if let body, sleep != nil {
            sentences.append(clip(body.prose, limit: 120))
        }
        for beat in extra {
            sentences.append(clip(beat.prose, limit: 140))
        }

        var joined = sentences
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .replacingOccurrences(of: "  ", with: " ")
        let lower = joined.lowercased()
        if interpretation.domains.contains(.sleep),
           !lower.contains("sleep"), !lower.contains("night"), !lower.contains("slept") {
            joined = "Last night was thin. " + joined
        }
        let promptLower = prompt.lowercased()
        if interpretation.domains.contains(.nutrition),
           interpretation.logWaterMl == nil,
           promptLower.contains("eat") || promptLower.contains("food") || promptLower.contains("protein"),
           !lower.contains("eat"), !lower.contains("food"), !lower.contains("protein"),
           !lower.contains("water") {
            joined += " " + AriaReplyVariety.pick([
                "Keep food simple — protein and something you will actually eat.",
                "Eat something you'll actually finish — protein first, nothing fancy.",
                "Food stays simple: protein plus a plate you will eat.",
                "Don't overthink the plate — protein and a meal you'll finish.",
            ], prompt: prompt)
        }
        return joined
    }

    static func domain(for agent: AriaCoachAgent) -> AriaIntentDomain {
        switch agent {
        case .workout: return .training
        case .sleep: return .sleep
        case .recovery: return .readiness
        case .lifestyle: return .nutrition
        case .progress: return .progress
        case .cycle: return .cycle
        case .aria: return .lifestyle
        }
    }

    static func reminderType(for kind: AriaDummyAction.ReminderKind) -> ReminderType {
        switch kind {
        case .hydration: return .hydration
        case .meal: return .meal
        case .sleep: return .sleep
        case .workout: return .workout
        }
    }

    static func stepDown(_ intensity: WorkoutIntensity) -> WorkoutIntensity {
        switch intensity {
        case .max: return .high
        case .high: return .moderate
        case .moderate: return .low
        case .low: return .low
        }
    }

    static func isLegMove(_ name: String) -> Bool {
        let lower = name.lowercased()
        let needles = [
            "squat", "lunge", "leg press", "rdl", "deadlift", "hip thrust",
            "calf", "quad", "hamstring", "leg curl", "leg extension", "step-up",
        ]
        return needles.contains { lower.contains($0) }
    }

    static func hour(in text: String) -> Int? {
        let pattern = #"at\s+(\d{1,2})(?::\d{2})?\s*(am|pm|a\.m\.|p\.m\.)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges >= 2,
              let hourRange = Range(match.range(at: 1), in: text),
              var value = Int(text[hourRange]) else { return nil }
        if match.numberOfRanges >= 3, match.range(at: 2).location != NSNotFound,
           let ampmRange = Range(match.range(at: 2), in: text) {
            let ampm = text[ampmRange].lowercased()
            if ampm.contains("p"), value < 12 { value += 12 }
            if ampm.contains("a"), value == 12 { value = 0 }
        }
        return min(23, max(0, value))
    }

    // MARK: - Private

    private static func hasIntentNeedle(_ text: String) -> Bool {
        ContextualParsingEngine.matchesAny(text, intentNeedles)
    }

    private static func matches(_ text: String, _ needles: [String]) -> Bool {
        ContextualParsingEngine.matchesAny(text, needles)
    }

    private static func primaryAgent(
        from domains: [AriaIntentDomain],
        roster: [AriaCoachAgent],
        fallback: AriaCoachAgent
    ) -> AriaCoachAgent {
        if let pinned = roster.first(where: { $0 != .aria }),
           domains.contains(domain(for: pinned)),
           roster.count == 1 {
            return pinned
        }
        let order: [AriaCoachAgent] = [.workout, .recovery, .sleep, .cycle, .progress, .lifestyle]
        for agent in order where domains.contains(domain(for: agent)) {
            return agent
        }
        return roster.first { $0 != .aria } ?? fallback
    }

    private static func clip(_ prose: String, limit: Int) -> String {
        let trimmed = prose
            .replacingOccurrences(of: "\n\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= limit { return trimmed }
        let idx = trimmed.index(trimmed.startIndex, offsetBy: limit)
        if let stop = trimmed[..<idx].lastIndex(of: ".") {
            return String(trimmed[...stop])
        }
        return String(trimmed[..<idx]).trimmingCharacters(in: .whitespaces) + "."
    }
}
