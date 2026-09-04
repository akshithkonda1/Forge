import Foundation

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

    public init(
        text: String,
        readiness: Int? = nil,
        sleepMinutesLastNight: Int? = nil,
        consecutiveShortNights: Int = 0,
        hasSessionLoggedToday: Bool = false,
        cycleTrackingAvailable: Bool = false,
        topicAffinity: [String: Int] = [:],
        rememberedFacts: [String] = []
    ) {
        self.text = text
        self.readiness = readiness
        self.sleepMinutesLastNight = sleepMinutesLastNight
        self.consecutiveShortNights = consecutiveShortNights
        self.hasSessionLoggedToday = hasSessionLoggedToday
        self.cycleTrackingAvailable = cycleTrackingAvailable
        self.topicAffinity = topicAffinity
        self.rememberedFacts = rememberedFacts
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
        for (domain, phrases) in Self.phrases {
            for phrase in phrases where lower.contains(phrase) {
                add(domain, Weight.phrase, "said “\(phrase)”")
                break
            }
        }
        for (domain, words) in Self.keywords {
            let hits = words.filter { lower.contains($0) }
            if !hits.isEmpty {
                let count: Double = Double(hits.count)
                let weight: Double = Weight.keyword * min(2.0, count)
                let named: String = hits.prefix(2).joined(separator: ", ")
                add(domain, weight, "mentions \(named)")
            }
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

    // MARK: - Vocabulary

    private static let jointWords = ["knee", "shoulder", "back", "hip", "ankle", "wrist", "elbow", "neck"]

    /// Multi-word phrases carry more meaning than any single token in them, so
    /// they score higher and only once per domain.
    private static let phrases: [AriaIntentDomain: [String]] = [
        .training: ["build me a session", "what should i train", "workout for", "training plan", "what's my workout", "give me a session"],
        .sleep: ["how did i sleep", "slept badly", "couldn't sleep", "keep waking", "sleep debt"],
        .readiness: ["how am i doing today", "should i train today", "am i recovered", "how's my recovery"],
        .nutrition: ["what should i eat", "how much protein", "am i eating enough"],
        .body: ["something hurts", "is this an injury", "still sore", "pain in my"],
        .progress: ["am i getting stronger", "how am i progressing", "is this working"],
        .cycle: ["my cycle", "on my period", "time of the month", "cycle day"],
    ]

    private static let keywords: [AriaIntentDomain: [String]] = [
        .training: ["train", "workout", "session", "lift", "run", "gym", "sets", "reps"],
        .sleep: ["sleep", "slept", "rest", "bed", "insomnia", "nap"],
        .readiness: ["readiness", "recovery", "hrv", "tired", "exhausted", "drained", "energy"],
        .nutrition: ["eat", "food", "protein", "meal", "calorie", "hydrate", "water", "carbs"],
        .body: ["pain", "hurt", "sore", "injury", "ache", "strain", "tweak"],
        .cycle: ["period", "menstrual", "luteal", "follicular", "ovulat", "pms", "cramp"],
        .progress: ["progress", "gains", "stronger", "streak", "improving", "plateau"],
        .lifestyle: ["work", "travel", "busy", "stress", "schedule", "time"],
    ]
}
