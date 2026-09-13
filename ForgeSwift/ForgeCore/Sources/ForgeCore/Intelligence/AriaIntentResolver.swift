import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// What a turn is about, ranked rather than matched.
///
/// Keyword dispatch answers "which branch fires first". That is fine when
/// someone says "build me a session" and wrong for almost everything else: it
/// cannot tell that a person asking about motivation at 40 readiness after two
/// short nights is really asking about recovery, because motivation matched
/// first and the data was never consulted.
///
/// This ranks instead. Language is the strongest signal, but never the only
/// one: the body's current state pushes domains up unprompted, and what this
/// person keeps circling back to nudges ties. Every reading carries its
/// `drivers`, so a surprising route can be read back rather than guessed at —
/// a router nobody can explain is one nobody will trust enough to leave on.
public enum AriaIntentDomain: String, Sendable, CaseIterable {
    case sleep, readiness, training, nutrition, body, cycle, lifestyle, progress
}

public struct AriaIntentReading: Sendable, Equatable {
    public var domain: AriaIntentDomain
    public var score: Double
    /// Why this scored — language hits, data pressure, learned affinity.
    public var drivers: [String]

    public init(domain: AriaIntentDomain, score: Double, drivers: [String]) {
        self.domain = domain
        self.score = score
        self.drivers = drivers
    }
}

/// Everything the resolver may look at. Deliberately plain values: no app
/// types, no HealthKit, nothing main-actor, so this is testable on Linux and
/// in CI where the app itself cannot even be compiled.
public struct AriaIntentInput: Sendable {
    public var text: String
    public var readiness: Int?
    public var sleepMinutesLastNight: Int?
    public var consecutiveShortNights: Int
    public var hasSessionLoggedToday: Bool
    public var cycleTrackingAvailable: Bool
    /// Domain -> turns this session. What they keep asking about.
    public var topicAffinity: [String: Int]
    /// Durable facts already learned ("knee", "half marathon").
    public var rememberedFacts: [String]
    /// Classified calendar tags only (`calendar:kind:…`, busy windows). Never titles.
    public var calendarTags: [String]
    /// 1–10, same range as the live backend's relationship_level.
    public var relationshipLevel: Int

    public init(
        text: String,
        readiness: Int? = nil,
        sleepMinutesLastNight: Int? = nil,
        consecutiveShortNights: Int = 0,
        hasSessionLoggedToday: Bool = false,
        cycleTrackingAvailable: Bool = false,
        topicAffinity: [String: Int] = [:],
        rememberedFacts: [String] = [],
        calendarTags: [String] = [],
        relationshipLevel: Int = 1
    ) {
        self.text = text
        self.readiness = readiness
        self.sleepMinutesLastNight = sleepMinutesLastNight
        self.consecutiveShortNights = consecutiveShortNights
        self.hasSessionLoggedToday = hasSessionLoggedToday
        self.cycleTrackingAvailable = cycleTrackingAvailable
        self.topicAffinity = topicAffinity
        self.rememberedFacts = rememberedFacts
        self.calendarTags = calendarTags
        self.relationshipLevel = relationshipLevel
    }
}

public enum AriaIntentResolver {

    /// Weights are ordered, not tuned. Language outranks data outranks habit,
    /// and the gaps are wide enough that no amount of accumulated affinity can
    /// overturn a clear sentence. "Build me a session" must route to training
    /// on someone who has asked about sleep forty times.
    private enum Weight {
        static let phrase = 6.0
        static let keyword = 3.0
        static let dataPressure = 2.0
        static let fact = 1.25
        static let affinity = 0.35
        static let affinityCap = 1.4
    }

    public static func rank(_ input: AriaIntentInput) -> [AriaIntentReading] {
        let lower = input.text.lowercased()
        var scores: [AriaIntentDomain: Double] = [:]
        var drivers: [AriaIntentDomain: [String]] = [:]

        func add(_ domain: AriaIntentDomain, _ amount: Double, _ why: String) {
            guard amount > 0 else { return }
            scores[domain, default: 0] += amount
            drivers[domain, default: []].append(why)
        }

        // --- Language ---
        //
        // Routed through ContextualParsingEngine rather than plain
        // `lower.contains(...)`: word-boundary safe (a short keyword like
        // "rest" no longer fires inside an unrelated longer word) and
        // typo-tolerant, so a single misspelling does not drop a message out
        // of every phrase/keyword list with zero signal.
        for (domain, phrases) in Self.phrases {
            for phrase in phrases where ContextualParsingEngine.matches(lower, phrase) {
                add(domain, Weight.phrase, "said “\(phrase)”")
                break
            }
        }
        for (domain, words) in Self.keywords {
            let hits = words.filter { ContextualParsingEngine.matches(lower, $0) }
            if !hits.isEmpty {
                let count: Double = Double(hits.count)
                let weight: Double = Weight.keyword * min(2.0, count)
                let named: String = hits.prefix(2).joined(separator: ", ")
                add(domain, weight, "mentions \(named)")
            }
        }
        // Wake-target asks ("up at 6am starting Monday") have no sleep keyword.
        // Without this, `rank` falls through to lifestyle. Do not put "up at"
        // on the sleep phrase list — that steals "what's up at the gym".
        if ScheduleGoalParser.isScheduleAsk(input.text) {
            add(.sleep, Weight.phrase, "named a wake target")
        }

        // --- The body's own argument ---
        //
        // This is the part keyword dispatch cannot do. Someone who never says
        // "recovery" but has slept badly for three nights is asking about
        // recovery whether or not they know it.
        if let readiness = input.readiness {
            if readiness < 50 {
                add(.readiness, Weight.dataPressure * 1.5, "readiness is low")
                add(.sleep, Weight.dataPressure * 0.5, "low readiness often traces to sleep")
            } else if readiness >= 85 {
                add(.training, Weight.dataPressure, "readiness is high enough to spend")
            }
        }
        if let minutes = input.sleepMinutesLastNight, minutes < 6 * 60 {
            add(.sleep, Weight.dataPressure, "short night")
        }
        if input.consecutiveShortNights >= 2 {
            let capped: Double = Double(min(3, input.consecutiveShortNights))
            let weight: Double = Weight.dataPressure * capped / 2.0
            add(.sleep, weight, "\(input.consecutiveShortNights) short nights running")
            add(.readiness, Weight.dataPressure * 0.75, "accumulating sleep debt")
        }
        if input.hasSessionLoggedToday {
            add(.progress, Weight.dataPressure * 0.5, "trained today")
        }

        // --- What they have told us ---
        for fact in input.rememberedFacts {
            let f = fact.lowercased()
            if Self.jointWords.contains(where: { f.contains($0) }) {
                add(.body, Weight.fact, "known limitation: \(fact)")
            }
            if f.contains("marathon") || f.contains("race") || f.contains("comp") {
                add(.training, Weight.fact, "training toward \(fact)")
                add(.progress, Weight.fact * 0.5, "has a goal to measure against")
            }
        }

        // --- What they keep coming back to ---
        for (raw, count) in input.topicAffinity {
            guard let domain = AriaIntentDomain(rawValue: raw), count >= 2 else { continue }
            let scaled: Double = Weight.affinity * Double(count)
            let bump: Double = min(Weight.affinityCap, scaled)
            add(domain, bump, "asks about this a lot")
        }

        if !input.cycleTrackingAvailable {
            scores[.cycle] = nil
            drivers[.cycle] = nil
        }

        // Built with an explicit loop rather than `.map { … }.sorted { … }`.
        // The chained form blew the type-checker's budget outright — mapping a
        // Dictionary into a struct initialiser and feeding that straight into a
        // two-way comparison with a ternary gives it too many overloads to
        // resolve at once. Spelled out, every type is pinned and it checks
        // instantly. Same result, and it reads no worse.
        var readings: [AriaIntentReading] = []
        readings.reserveCapacity(scores.count)
        for (domain, score) in scores {
            let why: [String] = drivers[domain] ?? []
            readings.append(AriaIntentReading(domain: domain, score: score, drivers: why))
        }
        readings.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.domain.rawValue < rhs.domain.rawValue
        }
        let ranked: [AriaIntentReading] = readings

        if ranked.isEmpty {
            return [AriaIntentReading(domain: .lifestyle, score: 0, drivers: ["nothing specific — general coaching"])]
        }
        return ranked
    }

    /// Domains worth actually spawning a specialist for.
    ///
    /// A relative floor, not an absolute one: anything within reach of the
    /// leader joins, everything trailing badly does not. An absolute threshold
    /// would either spawn five workers for a chatty sentence or one for a
    /// genuinely multi-part question, depending on where it was set.
    public static func actionable(_ ranked: [AriaIntentReading], limit: Int = 3) -> [AriaIntentDomain] {
        guard let top = ranked.first, top.score > 0 else { return [.lifestyle] }
        let floor: Double = max(2.0, top.score * 0.45)
        var kept: [AriaIntentDomain] = []
        for reading in ranked where reading.score >= floor {
            kept.append(reading.domain)
            if kept.count == limit { break }
        }
        return kept
    }

    // MARK: - On-device policy (mirrors services.contextual_learner)

    /// Cold-start / session inference. The durable Q-table and Dynamo persona
    /// live on the live backend; this is the same softmax so dummy and local
    /// testing do not invent a second brain. Removing the dummy orchestra
    /// must not take this policy with it — the Python learner stays in charge.
    public static func adapt(_ input: AriaIntentInput) -> AriaAdaptation {
        let cal = Self.parseCalendar(input.calendarTags)
        let eveningBusy: Double = cal.eveningBusy ? 1.0 : 0.0
        let headline: Double = cal.headlines.isEmpty ? 0.0 : 1.0
        var lowRecovery: Double = 0.0
        var highRecovery: Double = 0.0
        if let readiness = input.readiness {
            if readiness < 50 { lowRecovery = 1.0 }
            if readiness >= 75 { highRecovery = 1.0 }
        }
        var shortSleep: Double = 0.0
        var missing: Double = 0.05
        if let minutes = input.sleepMinutesLastNight {
            if minutes < 390 { shortSleep = 1.0 }
        } else {
            missing = 0.7
        }
        let lower = input.text.lowercased()
        var langTrain: Double = 0.0
        var langFood: Double = 0.0
        var langAdvice: Double = 0.0
        if lower.contains("train") || lower.contains("workout") || lower.contains("session") {
            langTrain = 1.0
        }
        if lower.contains("eat") || lower.contains("protein") || lower.contains("food") {
            langFood = 1.0
        }
        if lower.contains("should i") || lower.contains("what should") || lower.contains("train today") {
            langAdvice = 1.0
        }

        let logits: [String: Double] = [
            "protect": 0.2 + 1.6 * eveningBusy + 1.8 * headline + 1.7 * lowRecovery + 1.4 * shortSleep,
            "proceed": 0.5 + 1.5 * highRecovery + 1.4 * langTrain + 0.6 * langAdvice
                - 1.1 * eveningBusy - 1.2 * headline - 1.3 * lowRecovery - 0.9 * shortSleep,
            "fuel": 0.15 + 1.8 * langFood + 0.4 * langTrain,
            "clarify": 0.1 + 2.2 * missing - 0.4 * langAdvice,
        ]
        var ordered: [Double] = []
        let stances: [String] = ["protect", "proceed", "fuel", "clarify"]
        for stance in stances {
            ordered.append(logits[stance] ?? 0.0)
        }
        let probs = Self.softmax(ordered)
        var lead = stances[0]
        var best: Double = -1.0
        for (index, stance) in stances.enumerated() {
            if probs[index] > best {
                best = probs[index]
                lead = stance
            }
        }

        var specialists: [String] = []
        func addSpec(_ name: String) {
            if !specialists.contains(name) {
                specialists.append(name)
            }
        }
        if headline >= 0.5 || eveningBusy >= 0.5 { addSpec("lifestyle") }
        if lead == "protect" {
            addSpec("recovery")
            if shortSleep >= 0.5 { addSpec("sleep") }
        }
        if langTrain >= 0.5 { addSpec("workout") }
        if langFood >= 0.5 { addSpec("lifestyle") }
        if specialists.isEmpty { addSpec("lifestyle") }
        if specialists.count > 3 {
            specialists = Array(specialists.prefix(3))
        }

        var grounding = "generalized"
        if headline >= 0.5 || eveningBusy >= 0.5 || lowRecovery >= 0.5 || shortSleep >= 0.5 {
            grounding = "contextual"
        }

        var bucket = "clear|mixed"
        if headline >= 0.5 {
            bucket = "headline"
        } else if eveningBusy >= 0.5 {
            bucket = "evening_busy"
        } else {
            bucket = "clear"
        }
        var body = "mixed"
        if lowRecovery >= 0.5 || shortSleep >= 0.5 {
            body = "depleted"
        } else if highRecovery >= 0.5 {
            body = "recovered"
        }
        bucket = "\(bucket)|\(body)"

        var how: String = "Still learning how you work — using today's calendar and a cautious prior."
        if !cal.headlines.isEmpty {
            how = "This week has \(cal.headlines[0]) on it — that changes the session, not the relationship."
        } else if cal.eveningBusy {
            how = "Evening is spoken for today."
        }

        var teach: String = "I'll learn what actually works for you from what you do next, not just what you say."
        if !cal.headlines.isEmpty {
            teach = "I'll build around the \(cal.headlines[0]) this week, then learn from whether that actually helped."
        } else if lead == "protect" {
            teach = "Protecting load on thin days is the move until I see how you actually train."
        }

        var move: String = "Give a best-effort read, then ask for the one missing signal."
        if lead == "protect" {
            move = "Protect load and fit a shorter session around the day they already have."
        } else if lead == "proceed" {
            move = "Spend the readiness on one quality session, in the slot they actually use."
        } else if lead == "fuel" {
            move = "Protein and water with the next meal, then train inside the day they have."
        }

        var keepLight = lead == "protect"
        if headline >= 0.5 || eveningBusy >= 0.5 {
            keepLight = true
        }

        let rankedPriority = Self.prioritizeDomains(input, eveningBusy: eveningBusy, morningBusy: cal.morningBusy, headlines: cal.headlines)
        var orderedSpecs: [String] = []
        for domain in rankedPriority.order {
            let spec: String
            switch domain {
            case "sleep": spec = "sleep"
            case "readiness": spec = "recovery"
            case "training": spec = "workout"
            case "lifestyle": spec = "lifestyle"
            case "progress": spec = "progress"
            case "cycle": spec = "cycle"
            default: spec = ""
            }
            if spec.isEmpty { continue }
            if specialists.contains(spec), !orderedSpecs.contains(spec) {
                orderedSpecs.append(spec)
            }
        }
        for spec in specialists where !orderedSpecs.contains(spec) {
            orderedSpecs.append(spec)
        }
        if orderedSpecs.count > 3 {
            specialists = Array(orderedSpecs.prefix(3))
        } else {
            specialists = orderedSpecs
        }

        return AriaAdaptation(
            stance: lead,
            specialists: specialists,
            teachUser: teach,
            keepLight: keepLight,
            howYouWork: how,
            oneNextMove: move,
            bucket: bucket,
            grounding: grounding,
            prioritize: rankedPriority.order,
            priorityReason: rankedPriority.reason,
            eventBucket: rankedPriority.event
        )
    }

    private static func prioritizeDomains(
        _ input: AriaIntentInput,
        eveningBusy: Double,
        morningBusy: Bool,
        headlines: [String]
    ) -> (order: [String], reason: String, event: String) {
        let domains: [String] = [
            "sleep", "readiness", "training", "nutrition",
            "lifestyle", "progress", "body", "cycle",
        ]
        var scores: [String: Double] = [:]
        for domain in domains {
            scores[domain] = 1.0
        }
        let relRaw = Double(max(1, input.relationshipLevel) - 1) / 9.0
        var rel = relRaw
        if rel < 0 { rel = 0 }
        if rel > 1 { rel = 1 }
        let ingestGain = 0.35 + 0.65 * rel

        var event = "clear"
        if !headlines.isEmpty {
            event = headlines[0]
            scores["lifestyle", default: 0] += 2.6
            scores["training", default: 0] -= 0.9
        } else if eveningBusy >= 0.5 {
            event = "evening_busy"
            scores["lifestyle", default: 0] += 1.5
            scores["training", default: 0] -= 0.55
        } else if morningBusy {
            event = "morning_busy"
            scores["lifestyle", default: 0] += 0.8
        }

        let lower = input.text.lowercased()
        let cueTable: [(String, [String])] = [
            ("sleep", ["sleep", "slept", "insomnia", "bedtime", "nap"]),
            ("readiness", ["readiness", "recover", "hrv", "tired", "exhausted", "drained"]),
            ("training", ["train", "workout", "session", "lift", "gym"]),
            ("nutrition", ["eat", "food", "protein", "meal", "calorie", "hydrat"]),
            ("lifestyle", ["work", "travel", "busy", "schedule", "calendar", "tonight", "quality of life", "qol", "wellbeing"]),
            ("progress", ["progress", "gains", "stronger", "streak", "plateau"]),
            ("body", ["pain", "hurt", "knee", "shoulder", "injury", "ache"]),
            ("cycle", ["period", "cycle", "luteal", "follicular", "pms", "cramp"]),
        ]
        for pair in cueTable {
            let domain = pair.0
            let words = pair.1
            var hit = false
            for word in words where lower.contains(word) {
                hit = true
                break
            }
            if hit {
                scores[domain, default: 0] += 1.4
            }
        }
        if ScheduleGoalParser.isScheduleAsk(input.text) {
            scores["sleep", default: 0] += 1.8
        }

        for fact in input.rememberedFacts {
            let f = fact.lowercased()
            if f.contains("sleep") { scores["sleep", default: 0] += 0.8 * ingestGain }
            if f.contains("recover") || f.contains("hrv") || f.contains("readiness") {
                scores["readiness", default: 0] += 0.8 * ingestGain
            }
            if f.contains("train") || f.contains("workout") {
                scores["training", default: 0] += 0.8 * ingestGain
            }
            if f.contains("calendar") || f.contains("busy") {
                scores["lifestyle", default: 0] += 0.8 * ingestGain
            }
            if f.contains("protein") || f.contains("meal") {
                scores["nutrition", default: 0] += 0.8 * ingestGain
            }
            if f.contains("knee") || f.contains("shoulder") {
                scores["body", default: 0] += 0.8 * ingestGain
            }
            if f.contains("cycle") { scores["cycle", default: 0] += 0.8 * ingestGain }
        }

        if let minutes = input.sleepMinutesLastNight, minutes < 390 {
            scores["sleep", default: 0] += 1.6
            scores["training", default: 0] -= 0.5
        }
        if let readiness = input.readiness, readiness < 50 {
            scores["readiness", default: 0] += 1.4
            scores["training", default: 0] -= 0.7
        }

        var ranked: [(String, Double)] = []
        for domain in domains {
            ranked.append((domain, scores[domain] ?? 0))
        }
        ranked.sort { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            return lhs.0 < rhs.0
        }
        var order: [String] = []
        for item in ranked {
            order.append(item.0)
        }

        var reason = "no headline event; conversation + ingest (bond=\(rel))"
        if event == "wedding" || event == "game" || event == "flight" || event == "travel" {
            reason = "event=\(event) leads; conversation, ingest, and relationship rank the rest"
        } else if event == "evening_busy" || event == "morning_busy" {
            reason = "busy window=\(event); ingest and conversation set order after lifestyle"
        }
        return (order, reason, event)
    }

    private static func softmax(_ logits: [Double]) -> [Double] {
        var peak: Double = logits[0]
        for x in logits where x > peak { peak = x }
        var exps: [Double] = []
        var total: Double = 0.0
        for x in logits {
            let e: Double = exp(x - peak)
            exps.append(e)
            total += e
        }
        if total == 0 { return exps }
        var out: [Double] = []
        for e in exps {
            out.append(e / total)
        }
        return out
    }

    private static func parseCalendar(_ tags: [String]) -> (eveningBusy: Bool, morningBusy: Bool, headlines: [String]) {
        var eveningBusy = false
        var morningBusy = false
        var headlines: [String] = []
        let allowed: Set<String> = [
            "wedding", "game", "flight", "travel", "work", "dinner",
            "family", "appointment", "social",
        ]
        let headlineKinds: Set<String> = ["wedding", "game", "flight", "travel"]
        for raw in tags {
            let tag: String = raw
            if tag == "calendar:evening:busy" {
                eveningBusy = true
                continue
            }
            if tag == "calendar:morning:busy" {
                morningBusy = true
                continue
            }
            if tag.hasPrefix("calendar:kind:") {
                let kind = String(tag.dropFirst("calendar:kind:".count))
                if allowed.contains(kind), headlineKinds.contains(kind), !headlines.contains(kind) {
                    headlines.append(kind)
                }
            }
        }
        return (eveningBusy, morningBusy, headlines)
    }

    // MARK: - Vocabulary

    private static let jointWords = ["knee", "shoulder", "back", "hip", "ankle", "wrist", "elbow", "neck"]

    /// Multi-word phrases carry more meaning than any single token in them, so
    /// they score higher and only once per domain.
    private static let phrases: [AriaIntentDomain: [String]] = [
        .training: [
            "build me a session", "what should i train", "workout for", "training plan",
            "what's my workout", "give me a session", "hit the gym", "let's train",
        ],
        .sleep: [
            "how did i sleep", "slept badly", "couldn't sleep", "keep waking", "sleep debt",
            "didn't sleep", "tossed and turned",
        ],
        .readiness: [
            "how am i doing today", "should i train today", "am i recovered", "how's my recovery",
            "how's my hrv", "do i have it in me",
        ],
        .nutrition: ["what should i eat", "how much protein", "am i eating enough", "what should i drink"],
        .body: ["something hurts", "is this an injury", "still sore", "pain in my"],
        .progress: ["am i getting stronger", "how am i progressing", "is this working"],
        .cycle: ["my cycle", "on my period", "time of the month", "cycle day"],
        .lifestyle: [
            "quality of life", "how's my life", "how is my life",
            "lifestyle score", "grade my life", "how am i living",
        ],
    ]

    private static let keywords: [AriaIntentDomain: [String]] = [
        .training: ["train", "workout", "session", "lift", "run", "gym", "sets", "reps"],
        .sleep: ["sleep", "slept", "rest", "bed", "insomnia", "nap", "wiped"],
        .readiness: ["readiness", "recovery", "hrv", "tired", "exhausted", "drained", "energy", "wiped"],
        .nutrition: ["eat", "food", "protein", "meal", "calorie", "hydrate", "water", "carbs"],
        .body: ["pain", "hurt", "sore", "injury", "ache", "strain", "tweak"],
        .cycle: ["period", "menstrual", "luteal", "follicular", "ovulat", "pms", "cramp"],
        .progress: ["progress", "gains", "stronger", "streak", "improving", "plateau"],
        .lifestyle: ["work", "travel", "busy", "stress", "schedule", "time", "qol", "wellbeing"],
    ]
}

public struct AriaAdaptation: Sendable, Equatable {
    public var stance: String
    public var specialists: [String]
    public var teachUser: String
    public var keepLight: Bool
    public var howYouWork: String
    public var oneNextMove: String
    public var bucket: String
    public var grounding: String
    public var prioritize: [String]
    public var priorityReason: String
    public var eventBucket: String
    public var lastVerdict: String
    public var calibration: Double

    public init(
        stance: String,
        specialists: [String],
        teachUser: String,
        keepLight: Bool,
        howYouWork: String,
        oneNextMove: String,
        bucket: String,
        grounding: String,
        prioritize: [String] = [],
        priorityReason: String = "",
        eventBucket: String = "clear",
        lastVerdict: String = "",
        calibration: Double = 0.5
    ) {
        self.stance = stance
        self.specialists = specialists
        self.teachUser = teachUser
        self.keepLight = keepLight
        self.howYouWork = howYouWork
        self.oneNextMove = oneNextMove
        self.bucket = bucket
        self.grounding = grounding
        self.prioritize = prioritize
        self.priorityReason = priorityReason
        self.eventBucket = eventBucket
        self.lastVerdict = lastVerdict
        self.calibration = calibration
    }
}
