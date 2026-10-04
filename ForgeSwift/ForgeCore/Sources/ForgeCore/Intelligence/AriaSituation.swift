import Foundation

/// Dummy perception: gather every signal, then judge the situation case by case.
///
/// Swift twin of `backend/ai/simrunner/aria_simrunner/perception.py`. Pure and
/// network-free — the app builds `AriaSituationInput` from what is already on
/// the phone (HealthKit hydrate, calendar horizon tags, cycle phase, the
/// thread, the clock, and a cached weather read) and this decides:
///
/// * every signal with where it came from — measured, said, world, thread;
/// * the conflicts between them ("you feel great, but the night was short");
/// * one posture (refer / rest / protect / steady / push) and concrete decisions;
/// * what ARIA does not know, and which questions need outside knowledge.
///
/// `brief` is the same read as plain text for Apple's on-device model. No
/// raw vitals in spoken lines — words only.
public enum AriaSituationPosture: String, Sendable, Equatable {
    case refer, rest, protect, steady, push
}

public struct AriaEnvironmentRead: Equatable, Sendable {
    public var apparentTempC: Double?
    public var uvIndex: Double?
    public var usAQI: Int?
    public var precipitationMm: Double?
    public var isDay: Bool?
    public var source: String
    public var capturedAt: Date

    public init(
        apparentTempC: Double? = nil,
        uvIndex: Double? = nil,
        usAQI: Int? = nil,
        precipitationMm: Double? = nil,
        isDay: Bool? = nil,
        source: String = "none",
        capturedAt: Date = Date()
    ) {
        self.apparentTempC = apparentTempC
        self.uvIndex = uvIndex
        self.usAQI = usAQI
        self.precipitationMm = precipitationMm
        self.isDay = isDay
        self.source = source
        self.capturedAt = capturedAt
    }

    public var hot: Bool { (apparentTempC ?? -99) >= 32 }
    public var cold: Bool { (apparentTempC ?? 99) <= -8 }
    public var smoky: Bool { (usAQI ?? 0) >= 101 }
    public var stormy: Bool { (precipitationMm ?? 0) >= 4 }
    public var harshSun: Bool { (uvIndex ?? 0) >= 8 }
}

public struct AriaSituationSignal: Equatable, Sendable {
    public enum Source: String, Sendable { case measured, said, world, thread }
    public var name: String
    public var band: String
    public var source: Source
    public var confidence: Double

    public init(_ name: String, _ band: String, _ source: Source, _ confidence: Double = 0.8) {
        self.name = name
        self.band = band
        self.source = source
        self.confidence = confidence
    }
}

public struct AriaSituationConflict: Equatable, Sendable {
    public enum Severity: String, Sendable { case low, medium, high }
    public var kind: String
    public var line: String
    public var severity: Severity
}

public struct AriaResearchNeed: Equatable, Sendable {
    /// Scrubbed keyword query — the only text that may leave the phone.
    public var query: String
    /// Reference topic (`AriaReferenceTopic` raw value, or "heat").
    public var topic: String
    public var why: String
}

public struct AriaSituationDecisions: Equatable, Sendable {
    public var keepLight = false
    public var shorten = false
    public var moveIndoors = false
    public var askFirst = false
    public var referOut = false
    public var rest = false

    public init() {}

    public var labels: [String] {
        var out: [String] = []
        if keepLight { out.append("keep light") }
        if shorten { out.append("shorten") }
        if moveIndoors { out.append("move indoors") }
        if askFirst { out.append("ask first") }
        if referOut { out.append("refer out") }
        if rest { out.append("rest") }
        return out
    }
}

/// Everything on the phone the Dummy may perceive for one turn.
public struct AriaSituationInput: Equatable, Sendable {
    public var prompt: String
    public var sleepHours: Double?
    public var readiness: Int?
    public var sleepDebtHours: Double?
    public var isOvertrained: Bool
    public var trainingStreak: Int
    public var daysSinceWorkout: Int?
    public var chronotype: String?
    public var localHour: Int?
    /// `calendar:horizon:<kind>:<days>` tags — kinds only, never titles.
    public var calendarHorizonTags: [String]
    public var busyWindowsToday: Int
    public var cyclePhase: String?
    public var priorPrompts: [String]
    public var environment: AriaEnvironmentRead?
    /// Names the phone knows (user, supported people) — never sent anywhere.
    public var privateTerms: [String]

    public init(
        prompt: String,
        sleepHours: Double? = nil,
        readiness: Int? = nil,
        sleepDebtHours: Double? = nil,
        isOvertrained: Bool = false,
        trainingStreak: Int = 0,
        daysSinceWorkout: Int? = nil,
        chronotype: String? = nil,
        localHour: Int? = nil,
        calendarHorizonTags: [String] = [],
        busyWindowsToday: Int = 0,
        cyclePhase: String? = nil,
        priorPrompts: [String] = [],
        environment: AriaEnvironmentRead? = nil,
        privateTerms: [String] = []
    ) {
        self.prompt = prompt
        self.sleepHours = sleepHours
        self.readiness = readiness
        self.sleepDebtHours = sleepDebtHours
        self.isOvertrained = isOvertrained
        self.trainingStreak = trainingStreak
        self.daysSinceWorkout = daysSinceWorkout
        self.chronotype = chronotype
        self.localHour = localHour
        self.calendarHorizonTags = calendarHorizonTags
        self.busyWindowsToday = busyWindowsToday
        self.cyclePhase = cyclePhase
        self.priorPrompts = priorPrompts
        self.environment = environment
        self.privateTerms = privateTerms
    }
}

public struct AriaSituationRead: Equatable, Sendable {
    public var posture: AriaSituationPosture
    public var signals: [AriaSituationSignal]
    public var conflicts: [AriaSituationConflict]
    public var decisions: AriaSituationDecisions
    public var unknowns: [String]
    public var research: [AriaResearchNeed]
    public var environment: AriaEnvironmentRead?

    public func signal(_ name: String) -> AriaSituationSignal? {
        signals.first { $0.name == name }
    }

    /// One human sentence for the sharpest medium/high conflict, or nil.
    public var spokenLine: String? {
        let order: [AriaSituationConflict.Severity: Int] = [.high: 0, .medium: 1, .low: 2]
        return conflicts
            .filter { $0.severity != .low }
            .sorted { (order[$0.severity] ?? 3) < (order[$1.severity] ?? 3) }
            .first?.line
    }

    /// The read as plain text for an on-device model prompt. No digits.
    public var brief: String {
        var lines = ["Posture: \(posture.rawValue)."]
        if !signals.isEmpty {
            lines.append("Signals: " + signals.map { "\($0.name) \($0.band) (\($0.source.rawValue))" }.joined(separator: "; ") + ".")
        }
        for c in conflicts {
            lines.append("Conflict (\(c.severity.rawValue)): \(c.line)")
        }
        if !decisions.labels.isEmpty {
            lines.append("Decisions: " + decisions.labels.joined(separator: ", ") + ".")
        }
        if !unknowns.isEmpty {
            lines.append("Unknown: " + unknowns.joined(separator: ", ") + ".")
        }
        return lines.joined(separator: "\n")
    }

    /// Short tag for `confidenceReason` — proves the turn was judged.
    public var reasonTag: String {
        let kinds = conflicts.map(\.kind)
        return kinds.isEmpty ? "situation · \(posture.rawValue)" : "situation · \(posture.rawValue) · \(kinds.joined(separator: "+"))"
    }
}

public enum AriaSituation {

    static let positive = [
        "feel great", "feeling great", "feel amazing", "feeling amazing", "feel good", "feeling good",
        "feel strong", "feeling strong", "full of energy", "ready to go", "pumped", "fired up",
        "feel fresh", "feeling fresh", "never felt better",
    ]
    static let negative = [
        "exhausted", "tired", "wiped", "drained", "run down", "rundown", "burnt out", "burned out",
        "no energy", "low energy", "sluggish", "beat up", "feel awful", "feel terrible", "stressed",
    ]
    static let wantsHard = [
        "go hard", "going hard", "max out", "maxing", "pr ", "personal record", "heavy", "hiit",
        "intense", "push it", "push hard", "long run", "all out", "race pace", "sprint", "crush ",
    ]
    static let training = [
        "train", "workout", "session", "lift", "gym", "run ", "running", "ride ", "swim", "hiit",
        "squat", "leg day", "cardio",
    ]
    static let outdoor = ["run ", "running", "ride ", "hike", "bike", "outside", "outdoor", "trail", "tennis", "soccer", "golf"]
    static let illness = [
        "fever", "flu ", "feel sick", "feeling sick", "i'm sick", "im sick", "got sick", "been sick",
        "sick with", "a cold", "covid", "sore throat", "chills", "vomit", "nausea",
        "stomach bug", "congested", "sinus infection",
    ]
    static let redFlags = [
        "chest pain", "chest tightness", "fainted", "passed out", "shortness of breath",
        "can't breathe", "cannot breathe", "numb arm", "slurred",
    ]
    static let joints = ["knee", "shoulder", "back", "hip", "ankle", "wrist", "elbow", "neck"]
    static let pain = ["pain", "hurt", "hurts", "injur", "tweak", "sprain", "strain", "pulled"]
    static let events = [
        "wedding", "race ", "marathon", "half marathon", "10k", "5k", "meet ", "competition", "game",
        "tournament", "interview", "flight", "trip ", "photo shoot", "presentation",
    ]
    static let researchCues = [
        "how do i", "how to", "how much", "how many", "how long", "how often", "what is", "what are",
        "what does", "why do", "why does", "why is", "is it safe", "is it ok", "is it bad", "is it true",
        "should i take", "does it work", "do i need", "benefits of", "side effects", "evidence",
        "research", "studies", "science", " vs ", "versus", "supplement", "dose", "dosage",
    ]

    /// Start-of-word match; a trailing space in the needle also pins the end
    /// ("run " matches "run" and "run," but not "brunch" or "runway").
    static func has(_ lower: String, _ needles: [String]) -> Bool {
        needles.contains { matches(lower, $0) }
    }

    static func matches(_ lower: String, _ needle: String) -> Bool {
        let pinEnd = needle.hasSuffix(" ")
        let body = needle.trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { return false }
        var search = lower.startIndex..<lower.endIndex
        while let range = lower.range(of: body, options: [], range: search) {
            let startOK: Bool = {
                guard range.lowerBound > lower.startIndex else { return true }
                return !isLetter(lower[lower.index(before: range.lowerBound)])
            }()
            let endOK: Bool = {
                guard pinEnd, range.upperBound < lower.endIndex else { return true }
                return !isLetter(lower[range.upperBound])
            }()
            if startOK && endOK { return true }
            search = lower.index(after: range.lowerBound)..<lower.endIndex
        }
        return false
    }

    private static func isLetter(_ ch: Character) -> Bool {
        ch.isLetter && ch.isASCII
    }

    /// Days until a spoken event, or nil.
    public static func eventDays(in text: String) -> Int? {
        let lower = " \(text.lowercased()) "
        guard has(lower, events) else { return nil }
        if lower.contains("today") || lower.contains("tonight") { return 0 }
        if lower.contains("tomorrow") { return 1 }
        if lower.contains("this weekend") || lower.contains("saturday") || lower.contains("sunday") { return 3 }
        if lower.contains("next week") { return 7 }
        let words: [String: Int] = [
            "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
            "a couple": 2, "a few": 3,
        ]
        guard let re = try? NSRegularExpression(
            pattern: #"\bin\s+(\d{1,2}|one|two|three|four|five|six|seven|a couple|a few)\s+days?\b"#
        ) else { return nil }
        let ns = lower as NSString
        guard let m = re.firstMatch(in: lower, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let raw = ns.substring(with: m.range(at: 1))
        return Int(raw) ?? words[raw]
    }

    /// Nearest calendar horizon (`calendar:horizon:<kind>:<days>`), if any.
    public static func calendarEvent(from tags: [String]) -> (kind: String, days: Int)? {
        var best: (kind: String, days: Int)?
        for tag in tags where tag.hasPrefix("calendar:horizon:") {
            let parts = tag.split(separator: ":").map(String.init)
            guard parts.count >= 4, let days = Int(parts[3]), days >= 0 else { continue }
            if best == nil || days < best!.days {
                best = (parts[2], days)
            }
        }
        return best
    }

    public static func researchTopic(_ lowerPadded: String) -> String {
        if has(lowerPadded, illness) || lowerPadded.contains("temperature") { return "fever" }
        let table: [(String, [String])] = [
            ("sleep", ["sleep", "insomnia", "nap", "melatonin"]),
            ("nutrition", ["protein", "creatine", "supplement", "eat", "diet", "carb", "fat loss", "calorie", "vitamin"]),
            ("cycle", ["period", "cycle", "menstru", "ovulat"]),
            ("training", ["train", "workout", "lift", "run", "cardio", "muscle", "strength", "zone"]),
            ("readiness", ["recover", "hrv", "soreness", "rest day"]),
        ]
        for (topic, cues) in table where cues.contains(where: { lowerPadded.contains($0) }) {
            return topic
        }
        return "lifestyle"
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    public static func perceive(_ input: AriaSituationInput) -> AriaSituationRead {
        let lower = " \(input.prompt.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)) "
        var signals: [AriaSituationSignal] = []
        var conflicts: [AriaSituationConflict] = []
        var decisions = AriaSituationDecisions()
        var unknowns: [String] = []

        // --- measured -----------------------------------------------------
        var sleepBand = ""
        if let hours = input.sleepHours, hours > 0 {
            sleepBand = hours < 6.4 ? "thin" : (hours >= 7.4 ? "rebuilt" : "decent")
            signals.append(.init("sleep", sleepBand, .measured, 0.9))
        } else {
            unknowns.append("last night's sleep")
        }
        var recovery = ""
        if let readiness = input.readiness, readiness > 0 {
            if readiness < 50 || (input.sleepDebtHours ?? 0) > 5 || input.isOvertrained {
                recovery = "asking"
            } else if readiness >= 75 {
                recovery = "ready"
            } else {
                recovery = "steady"
            }
            signals.append(.init("recovery", recovery, .measured, 0.8))
        }
        var load = ""
        if input.isOvertrained {
            load = "overreached"
        } else if input.trainingStreak >= 3 {
            load = "on a streak"
        } else if (input.daysSinceWorkout ?? 0) >= 3 {
            load = "fresh"
        }
        if !load.isEmpty { signals.append(.init("load", load, .measured, 0.8)) }
        if let chrono = input.chronotype, !chrono.isEmpty {
            signals.append(.init("chronotype", chrono, .measured, 0.6))
        }
        if let phase = input.cyclePhase, !phase.isEmpty, phase != "unknown" {
            signals.append(.init("cycle", phase, .measured, 0.7))
        }
        if input.busyWindowsToday >= 3 {
            signals.append(.init("calendar", "packed day", .measured, 0.7))
        }

        // --- said ---------------------------------------------------------
        let saidGood = has(lower, Self.positive)
        let saidLow = has(lower, Self.negative)
        if saidGood {
            signals.append(.init("feeling", "good", .said, 0.7))
        } else if saidLow {
            signals.append(.init("feeling", "low", .said, 0.8))
        }
        let trainingAsk = has(lower, Self.training)
        let hard = has(lower, Self.wantsHard)
        let outdoorAsk = trainingAsk && has(lower, Self.outdoor)
        // "sick of my job" is a mood, not an illness.
        let ill = has(lower, Self.illness) && !lower.contains("sick of") && !lower.contains("sick and tired")
        let redFlag = has(lower, Self.redFlags)
        let joint = Self.joints.first { matches(lower, $0) && has(lower, Self.pain) }
        var spokenEventDays = Self.eventDays(in: input.prompt)
        var eventSource: AriaSituationSignal.Source = .said
        if spokenEventDays == nil, let cal = calendarEvent(from: input.calendarHorizonTags) {
            spokenEventDays = cal.days
            eventSource = .measured
        }
        if ill { signals.append(.init("illness", "reported", .said, 0.8)) }
        if let joint { signals.append(.init("injury", joint, .said, 0.8)) }
        if let days = spokenEventDays {
            let band = days == 0 ? "today" : (days == 1 ? "tomorrow" : "in \(days) days")
            signals.append(.init("event", band, eventSource, 0.7))
        }
        if let last = input.priorPrompts.last?.lowercased(),
           ["slept", "sleep", "last night"].contains(where: { last.contains($0) }) {
            signals.append(.init("thread", "sleep came up", .thread, 0.6))
        }

        // --- world --------------------------------------------------------
        if let hour = input.localHour {
            let tod = (hour >= 21 || hour < 5) ? "night" : (hour < 12 ? "morning" : "day")
            signals.append(.init("time", tod, .world, 1.0))
        }
        let env = input.environment
        if let env, env.source != "none" {
            for (flag, label) in [(env.hot, "hot"), (env.cold, "freezing"), (env.smoky, "poor air"),
                                  (env.stormy, "stormy"), (env.harshSun, "harsh sun")] where flag {
                signals.append(.init("outside", label, .world, 0.85))
            }
        }

        // --- evaluate, case by case --------------------------------------
        if redFlag {
            decisions.referOut = true
            conflicts.append(.init(kind: "red_flag", line: "That symptom needs a clinician before any training — please get it checked today.", severity: .high))
        }
        if ill {
            decisions.rest = true
            if trainingAsk {
                conflicts.append(.init(kind: "illness_vs_training", line: "You're sick and asking to train — today the training is rest and fluids.", severity: .high))
            }
        }
        if saidGood && (sleepBand == "thin" || recovery == "asking") {
            decisions.keepLight = true
            conflicts.append(.init(kind: "said_vs_measured", line: "You feel good, but last night ran short — I'll trust the feeling and cap the ceiling.", severity: .medium))
        }
        if saidLow && recovery == "ready" && trainingAsk {
            decisions.keepLight = true
            conflicts.append(.init(kind: "said_vs_measured", line: "Everything looks ready on paper, but you don't feel it — how you feel wins today.", severity: .medium))
        }
        if hard && (recovery == "asking" || load == "overreached") {
            decisions.keepLight = true
            conflicts.append(.init(kind: "intent_vs_recovery", line: "You want a hard day on a body that's asking for an easy one — we'll bank the effort instead of spending it.", severity: .medium))
        }
        if let days = spokenEventDays, days <= 2, trainingAsk {
            decisions.keepLight = true
            decisions.shorten = true
            conflicts.append(.init(kind: "event_taper", line: "With the big day this close, we sharpen instead of load.", severity: .medium))
        }
        if let joint, trainingAsk {
            decisions.keepLight = true
            conflicts.append(.init(kind: "injury_vs_training", line: "We train around the \(joint), not through it.", severity: .medium))
        }
        if outdoorAsk, let env, env.hot || env.smoky || env.stormy || env.cold {
            decisions.moveIndoors = true
            let why = env.smoky ? "the air is rough" : env.hot ? "it's dangerously hot" : env.cold ? "it's freezing" : "the weather is ugly"
            conflicts.append(.init(kind: "world_vs_outdoor", line: "Take it inside today — \(why) out there.", severity: .medium))
        }
        if let hour = input.localHour, hour >= 21 || hour < 4, trainingAsk, hard {
            decisions.shorten = true
            conflicts.append(.init(kind: "late_vs_sleep", line: "This late, a hard session steals from tonight's sleep — short and easy.", severity: .low))
        }
        if trainingAsk, sleepBand.isEmpty {
            decisions.askFirst = true
        }

        // --- posture ------------------------------------------------------
        let posture: AriaSituationPosture
        if decisions.referOut {
            posture = .refer
        } else if decisions.rest {
            posture = .rest
        } else if decisions.keepLight || recovery == "asking" || sleepBand == "thin" {
            posture = .protect
        } else if hard && recovery == "ready" && !saidLow {
            posture = .push
        } else {
            posture = .steady
        }

        // --- what needs the outside world --------------------------------
        var research: [AriaResearchNeed] = []
        if has(lower, Self.researchCues) || ill {
            let query = AriaQueryPrivacy.scrub(input.prompt, privateTerms: input.privateTerms)
            if !query.isEmpty {
                research.append(.init(query: query, topic: researchTopic(lower), why: "question needs outside knowledge"))
            }
        }
        if outdoorAsk, env?.hot == true, !research.contains(where: { $0.topic == "heat" }) {
            research.append(.init(query: "exercise in hot weather safety", topic: "heat", why: "training outside in heat"))
        }

        return AriaSituationRead(
            posture: posture,
            signals: signals,
            conflicts: conflicts,
            decisions: decisions,
            unknowns: unknowns,
            research: research,
            environment: env
        )
    }
}
