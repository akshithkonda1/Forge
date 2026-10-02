import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

// ============================================================
// MARK: - Messages context engine
// ============================================================
//
// Privacy contract
// ----------------
// What ARIA sees: `[LifeContextFact]` — kind, a fixed-vocabulary label, a
// one-sentence summary Forge wrote ("Dinner with a friend Friday 7pm"), a
// date, a confidence, and a keyed hash. On-device ARIA only: the brief and
// `life_context:` tags are removed before any remote (/ai/chat) request.
// What stays on-device: the messages, in memory, for one `extract` call. The
// engine stores nothing — it is a value type with no cache, no log, and no
// I/O. Every summary is built from templates over Forge's own words, then
// checked against the input: if five consecutive input words ever appear in
// a summary, the summary is cut to "<Kind> <when>", and dropped if that still
// repeats the input. Names, places and organizations that NLTagger finds only
// move confidence; they are never copied into a fact.
// iOS gives apps no API to read Messages, and Forge does not try: turns come
// only from conversations the user hands over (Share Sheet), one share at a
// time.
//
// Determinism: same turns, same key, same calendar → same facts. Relative
// dates resolve against each message's own timestamp, never the clock; ties
// break on fixed orders; no randomness, no sampling, no model.

public struct MessageContextEngine: Sendable {

    public static let defaultMinimumConfidence = 0.6
    public static let defaultMaxStoredFacts = 200

    public struct Configuration: Sendable {
        public var calendar: Calendar
        /// Facts below this are dropped, in `extract` and in `merge`.
        public var minimumConfidence: Double
        /// Oldest-first eviction beyond this many facts.
        public var maxStoredFacts: Int
        /// Bounds on work per call; a pasted novel cannot stall the share sheet.
        public var maxTurns: Int
        public var maxCharactersPerTurn: Int
        /// How many replies from the other side may confirm or decline a plan.
        public var confirmationWindow: Int

        public init(
            calendar: Calendar = .current,
            minimumConfidence: Double = MessageContextEngine.defaultMinimumConfidence,
            maxStoredFacts: Int = MessageContextEngine.defaultMaxStoredFacts,
            maxTurns: Int = 2_000,
            maxCharactersPerTurn: Int = 2_000,
            confirmationWindow: Int = 3
        ) {
            self.calendar = calendar
            self.minimumConfidence = minimumConfidence
            self.maxStoredFacts = maxStoredFacts
            self.maxTurns = maxTurns
            self.maxCharactersPerTurn = maxCharactersPerTurn
            self.confirmationWindow = confirmationWindow
        }
    }

    public let configuration: Configuration
    private let hashKey: LifeContextHashKey

    public init(hashKey: LifeContextHashKey, configuration: Configuration = Configuration()) {
        self.hashKey = hashKey
        self.configuration = configuration
    }

    // ------------------------------------------------------------
    // MARK: Extraction
    // ------------------------------------------------------------

    /// Raw turns in, structured facts out. Nothing is retained.
    public func extract(from turns: [MessageTurn]) -> [LifeContextFact] {
        guard !turns.isEmpty else { return [] }
        let ordered = turns.prefix(max(0, configuration.maxTurns))
            .enumerated()
            .sorted { a, b in
                a.element.timestamp != b.element.timestamp
                    ? a.element.timestamp < b.element.timestamp
                    : a.offset < b.offset
            }
            .map { $0.element }

        let detector = try? NSDataDetector(types: Self.detectorTypes)
        let features = ordered.enumerated().map { index, turn in
            analyze(turn, index: index, detector: detector)
        }

        var candidates: [Candidate] = []
        for index in features.indices where features[index].isEnglish {
            candidates.append(contentsOf: evaluate(at: index, in: features))
        }

        // Every five-word run of the input, once, so the verbatim guard is a
        // set lookup per summary instead of a scan of the conversation.
        var sourceRuns = Set<String>()
        for feature in features {
            sourceRuns.formUnion(Self.runs(of: feature.words, length: Self.verbatimRunLength))
        }

        var facts: [LifeContextFact] = []
        for candidate in candidates {
            let confidence = Self.rounded(candidate.confidence)
            guard confidence >= configuration.minimumConfidence,
                  let summary = guardedSummary(for: candidate, sourceRuns: sourceRuns) else { continue }
            facts.append(LifeContextFact(
                kind: candidate.kind,
                label: candidate.label,
                summary: summary,
                date: candidate.when?.date,
                confidence: confidence,
                sourceHash: sourceHash(for: candidate, in: features),
                observedAt: candidate.observedAt
            ))
        }
        return Self.capped(Self.sorted(Self.collapse(facts, calendar: configuration.calendar)), to: configuration.maxStoredFacts)
    }

    /// `existing` plus `incoming`, deduplicated by `sourceHash` (the more
    /// confident copy wins), below-threshold facts dropped, capped with
    /// oldest-first eviction.
    public func merge(_ incoming: [LifeContextFact], into existing: [LifeContextFact]) -> [LifeContextFact] {
        Self.merge(
            incoming,
            into: existing,
            minimumConfidence: configuration.minimumConfidence,
            cap: configuration.maxStoredFacts
        )
    }

    public static func merge(
        _ incoming: [LifeContextFact],
        into existing: [LifeContextFact],
        minimumConfidence: Double = defaultMinimumConfidence,
        cap: Int = defaultMaxStoredFacts
    ) -> [LifeContextFact] {
        var byHash: [String: LifeContextFact] = [:]
        var order: [String] = []
        for fact in existing + incoming {
            if let current = byHash[fact.sourceHash] {
                if fact.confidence > current.confidence { byHash[fact.sourceHash] = fact }
            } else {
                byHash[fact.sourceHash] = fact
                order.append(fact.sourceHash)
            }
        }
        let kept = order.compactMap { byHash[$0] }.filter { $0.confidence >= minimumConfidence }
        return capped(sorted(kept), to: cap)
    }

    // ------------------------------------------------------------
    // MARK: Per-turn analysis
    // ------------------------------------------------------------

    struct TurnFeatures {
        let index: Int
        let turn: MessageTurn
        let text: String
        let words: [String]
        let padded: String
        let isQuestion: Bool
        let when: ResolvedWhen?
        let hasTransit: Bool
        let hasAddressOrLink: Bool
        let placeCount: Int
        let organizationCount: Int
        let isEnglish: Bool

        var isFromMe: Bool { turn.isFromMe }

        func has(_ phrases: [String]) -> Bool {
            LifeContextText.firstMatch(padded, in: phrases) != nil
        }
    }

    private static let detectorTypes: NSTextCheckingResult.CheckingType.RawValue =
        NSTextCheckingResult.CheckingType.date.rawValue
        | NSTextCheckingResult.CheckingType.address.rawValue
        | NSTextCheckingResult.CheckingType.link.rawValue
        | NSTextCheckingResult.CheckingType.transitInformation.rawValue

    private func analyze(_ turn: MessageTurn, index: Int, detector: NSDataDetector?) -> TurnFeatures {
        let text = String(turn.text.prefix(max(0, configuration.maxCharactersPerTurn)))
        let words = LifeContextText.words(text)
        let padded = " " + words.joined(separator: " ") + " "
        let evening = LifeContextText.firstMatch(padded, in: LifeContextLexicon.evening) != nil

        var hasTransit = false
        var hasAddressOrLink = false
        var detectedDate: NSTextCheckingResult?
        if let detector {
            let range = NSRange(location: 0, length: (text as NSString).length)
            for match in detector.matches(in: text, options: [], range: range) {
                switch match.resultType {
                case .transitInformation: hasTransit = true
                case .address, .link: hasAddressOrLink = true
                case .date: if detectedDate == nil { detectedDate = match }
                default: break
                }
            }
        }

        let when = LifeContextDateResolver.resolve(
            text,
            anchor: turn.timestamp,
            calendar: configuration.calendar,
            evening: evening
        ) ?? detectedDate.flatMap { reanchor($0, in: text, anchor: turn.timestamp) }

        // NLTagger only where an entity changes a score: travel (a place) and
        // commitments (an organization). It never contributes text.
        let wantsEntities = LifeContextText.firstMatch(padded, in: LifeContextLexicon.travelPhrases) != nil
            || LifeContextText.firstMatch(padded, in: LifeContextLexicon.commitmentPhrases) != nil
        let entities = wantsEntities ? Self.entityCounts(in: text) : (places: 0, organizations: 0)

        return TurnFeatures(
            index: index,
            turn: turn,
            text: text,
            words: words,
            padded: padded,
            isQuestion: text.contains("?"),
            when: when,
            hasTransit: hasTransit,
            hasAddressOrLink: hasAddressOrLink,
            placeCount: entities.places,
            organizationCount: entities.organizations,
            isEnglish: Self.looksEnglish(text)
        )
    }

    /// An absolute date NSDataDetector found ("12 Oct 2026", "2026-10-12"),
    /// re-anchored to the message. Relative phrases the detector resolved
    /// against today's clock are ignored — they would break determinism.
    private func reanchor(_ match: NSTextCheckingResult, in text: String, anchor: Date) -> ResolvedWhen? {
        guard let detected = match.date else { return nil }
        let matched = (text as NSString).substring(with: match.range)
        let normalized = LifeContextDateResolver.normalize(matched)
        let numeric = matched.range(of: #"\d[/\-.]\d"#, options: .regularExpression) != nil
        guard numeric || LifeContextDateResolver.containsMonthName(normalized) else { return nil }

        var source = Calendar(identifier: .gregorian)
        source.timeZone = match.timeZone ?? TimeZone.current
        let parts = source.dateComponents([.year, .month, .day, .hour, .minute], from: detected)
        guard let month = parts.month, let day = parts.day else { return nil }
        let explicitYear = matched.range(of: #"\b(19|20)\d{2}\b"#, options: .regularExpression) != nil ? parts.year : nil
        let hasTime = matched.range(of: #"\d:\d{2}|\d\s?(am|pm|AM|PM)"#, options: .regularExpression) != nil
        return LifeContextDateResolver.resolveAbsolute(
            month: month,
            day: day,
            explicitYear: explicitYear,
            hour: hasTime ? parts.hour : nil,
            minute: hasTime ? parts.minute : nil,
            anchor: anchor,
            calendar: configuration.calendar
        )
    }

    private static func entityCounts(in text: String) -> (places: Int, organizations: Int) {
        #if canImport(NaturalLanguage)
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var places = 0
        var organizations = 0
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .nameType,
            options: [.omitPunctuation, .omitWhitespace, .joinNames]
        ) { tag, _ in
            if tag == NLTag.placeName { places += 1 }
            if tag == NLTag.organizationName { organizations += 1 }
            return true
        }
        return (places, organizations)
        #else
        return (0, 0)
        #endif
    }

    /// The lexicon is English. A long turn the recognizer is sure is another
    /// language is skipped rather than mis-read; short turns ("ok!", "yes")
    /// are too short to judge and always pass.
    private static func looksEnglish(_ text: String) -> Bool {
        #if canImport(NaturalLanguage)
        guard text.count >= 24 else { return true }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
        guard let top = hypotheses.max(by: { a, b in
            a.value != b.value ? a.value < b.value : a.key.rawValue > b.key.rawValue
        }) else { return true }
        return top.key == .english || top.value < 0.9
        #else
        return true
        #endif
    }

    // ------------------------------------------------------------
    // MARK: Rules
    // ------------------------------------------------------------

    struct Candidate {
        let kind: LifeContextFact.Kind
        let label: String
        let display: String
        let role: String?
        let when: ResolvedWhen?
        let confidence: Double
        /// Indices into the features array of every turn this fact rests on.
        let sources: [Int]
        let observedAt: Date
    }

    private enum Response {
        case confirmed(Int)
        case declined(Int)
        case none
    }

    private func evaluate(at index: Int, in features: [TurnFeatures]) -> [Candidate] {
        let found: [Candidate?] = [
            plan(index, features),
            event(index, features),
            travel(index, features),
            commitment(index, features),
            commitmentFromRequest(index, features),
            health(index, features),
            stress(index, features),
            relationship(index, features),
        ]
        return found.compactMap { $0 }
    }

    /// The first reply from the other side, within the window, that confirms
    /// or declines.
    private func response(to index: Int, in features: [TurnFeatures]) -> Response {
        let sender = features[index].turn.sender
        var replies = 0
        var next = index + 1
        while next < features.count, replies < configuration.confirmationWindow {
            let reply = features[next]
            if reply.turn.sender != sender {
                replies += 1
                if Self.confirms(reply) { return .confirmed(next) }
                if Self.declines(reply) { return .declined(next) }
            }
            next += 1
        }
        return .none
    }

    private static func confirms(_ turn: TurnFeatures) -> Bool {
        turn.has(LifeContextLexicon.confirm) || turn.text.contains("\u{1F44D}")
    }

    private static func declines(_ turn: TurnFeatures) -> Bool {
        !confirms(turn) && turn.has(LifeContextLexicon.decline)
    }

    private func role(in indices: [Int], of features: [TurnFeatures]) -> String? {
        for (role, phrases) in LifeContextLexicon.roles {
            for index in indices where features.indices.contains(index) && features[index].has(phrases) {
                return role
            }
        }
        return nil
    }

    // Plans: dinner, drinks, coffee, a workout — with someone, at a time.
    private func plan(_ index: Int, _ features: [TurnFeatures]) -> Candidate? {
        let turn = features[index]
        guard let cue = LifeContextLexicon.firstCue(turn.padded, in: LifeContextLexicon.plans) else { return nil }
        var score = 0.45
        var when = turn.when
        var sources = [index]
        if turn.has(LifeContextLexicon.planVerbs) { score += 0.1 }
        if turn.has(LifeContextLexicon.hedge) { score -= 0.2 }
        if Self.declines(turn) { score -= 0.35 }
        switch response(to: index, in: features) {
        case .confirmed(let reply):
            score += 0.2
            sources.append(reply)
            if when == nil { when = features[reply].when }
        case .declined(let reply):
            score -= 0.35
            sources.append(reply)
        case .none:
            break
        }
        if when != nil { score += 0.2 }
        if turn.hasAddressOrLink { score += 0.05 }
        return Candidate(
            kind: .plan, label: cue.label, display: cue.display,
            role: self.role(in: sources, of: features) ?? "a friend",
            when: when, confidence: score, sources: sources, observedAt: turn.turn.timestamp
        )
    }

    // Occasions: a wedding, a birthday, a race.
    private func event(_ index: Int, _ features: [TurnFeatures]) -> Candidate? {
        let turn = features[index]
        guard let cue = LifeContextLexicon.firstCue(turn.padded, in: LifeContextLexicon.events) else { return nil }
        var score = 0.55
        var when = turn.when
        var sources = [index]
        if turn.has(LifeContextLexicon.hedge) { score -= 0.2 }
        if Self.declines(turn) { score -= 0.35 }
        switch response(to: index, in: features) {
        case .confirmed(let reply):
            score += 0.1
            sources.append(reply)
            if when == nil { when = features[reply].when }
        case .declined(let reply):
            score -= 0.35
            sources.append(reply)
        case .none:
            break
        }
        if when != nil { score += 0.2 }
        return Candidate(
            kind: .event, label: cue.label, display: cue.display, role: nil,
            when: when, confidence: score, sources: sources, observedAt: turn.turn.timestamp
        )
    }

    // Travel: flights, trips, hotel stays.
    private func travel(_ index: Int, _ features: [TurnFeatures]) -> Candidate? {
        let turn = features[index]
        guard let cue = LifeContextLexicon.firstCue(turn.padded, in: LifeContextLexicon.travel)
            ?? (turn.hasTransit ? LifeContextLexicon.flight : nil) else { return nil }
        var score = 0.5
        if turn.hasTransit { score += 0.15 }
        if turn.placeCount > 0 { score += 0.1 }
        if turn.has(LifeContextLexicon.firstPerson) { score += 0.05 }
        if !turn.isFromMe && !turn.has(LifeContextLexicon.shared) { score -= 0.1 }
        if turn.has(LifeContextLexicon.hedge) { score -= 0.2 }
        if Self.declines(turn) { score -= 0.35 }
        if turn.when != nil { score += 0.2 }
        return Candidate(
            kind: .travel, label: cue.label, display: cue.display, role: nil,
            when: turn.when, confidence: score, sources: [index], observedAt: turn.turn.timestamp
        )
    }

    // Commitments the user made ("I'll send the deck by Friday").
    private func commitment(_ index: Int, _ features: [TurnFeatures]) -> Candidate? {
        let turn = features[index]
        guard turn.isFromMe, !turn.has(LifeContextLexicon.attendance) else { return nil }
        let strong = turn.has(LifeContextLexicon.commitmentStrong)
        guard strong || turn.has(LifeContextLexicon.commitmentNormal) else { return nil }
        guard LifeContextLexicon.firstCue(turn.padded, in: LifeContextLexicon.plans) == nil,
              LifeContextLexicon.firstCue(turn.padded, in: LifeContextLexicon.events) == nil,
              LifeContextLexicon.firstCue(turn.padded, in: LifeContextLexicon.travel) == nil else { return nil }
        var score = 0.5
        if strong { score += 0.1 }
        if turn.has(LifeContextLexicon.hedge) { score -= 0.2 }
        if turn.when != nil { score += 0.2 }
        let work = turn.has(LifeContextLexicon.workContext) || turn.organizationCount > 0
        return Candidate(
            kind: .commitment,
            label: work ? "work deadline" : "commitment",
            display: work ? "Work deadline" : "Commitment",
            role: nil, when: turn.when, confidence: score, sources: [index], observedAt: turn.turn.timestamp
        )
    }

    // Commitments the user agreed to ("Can you send it Friday?" — "Yes, will do").
    private func commitmentFromRequest(_ index: Int, _ features: [TurnFeatures]) -> Candidate? {
        let turn = features[index]
        guard !turn.isFromMe, turn.has(LifeContextLexicon.requests),
              LifeContextLexicon.firstCue(turn.padded, in: LifeContextLexicon.plans) == nil,
              LifeContextLexicon.firstCue(turn.padded, in: LifeContextLexicon.events) == nil,
              LifeContextLexicon.firstCue(turn.padded, in: LifeContextLexicon.travel) == nil,
              case .confirmed(let reply) = response(to: index, in: features),
              features[reply].isFromMe else { return nil }
        let when = turn.when ?? features[reply].when
        var score = 0.6
        if when != nil { score += 0.2 }
        let work = turn.has(LifeContextLexicon.workContext) || features[reply].has(LifeContextLexicon.workContext)
        return Candidate(
            kind: .commitment,
            label: work ? "work deadline" : "commitment",
            display: work ? "Work deadline" : "Commitment",
            role: nil, when: when, confidence: score, sources: [index, reply],
            observedAt: features[reply].turn.timestamp
        )
    }

    // Health signals — the user's own, never the other person's.
    private func health(_ index: Int, _ features: [TurnFeatures]) -> Candidate? {
        let turn = features[index]
        guard turn.isFromMe,
              let match = LifeContextLexicon.health.first(where: { turn.has($0.cue.phrases) }) else { return nil }
        var score = match.base
        if turn.has(LifeContextLexicon.intensifiers) { score += 0.1 }
        if turn.has(LifeContextLexicon.healthNegations) { score -= 0.4 }
        let isAppointment = match.cue.label == "medical appointment"
        if isAppointment, turn.when != nil { score += 0.15 }
        return Candidate(
            kind: .healthSignal, label: match.cue.label, display: match.cue.display, role: nil,
            when: isAppointment ? turn.when : nil, confidence: score, sources: [index],
            observedAt: turn.turn.timestamp
        )
    }

    // Stress signals — the user's own.
    private func stress(_ index: Int, _ features: [TurnFeatures]) -> Candidate? {
        let turn = features[index]
        guard turn.isFromMe else { return nil }
        let strong = LifeContextText.matchCount(turn.padded, in: LifeContextLexicon.stressStrong)
        let weak = LifeContextText.matchCount(turn.padded, in: LifeContextLexicon.stressWeak)
        guard strong + weak > 0 else { return nil }
        var score = strong > 0 ? 0.65 : 0.45
        score += min(0.2, 0.1 * Double(strong + weak - 1))
        if turn.has(LifeContextLexicon.intensifiers) { score += 0.1 }
        if turn.has(LifeContextLexicon.stressNegations) { score -= 0.4 }
        let work = turn.has(LifeContextLexicon.workContext)
        if work { score += 0.05 }
        return Candidate(
            kind: .stressSignal,
            label: work ? "work stress" : "stress",
            display: work ? "Stress signal about work" : "Stress signal",
            role: nil, when: nil, confidence: score, sources: [index], observedAt: turn.turn.timestamp
        )
    }

    // Relationship signals: closeness or friction, with a role, never a name.
    private func relationship(_ index: Int, _ features: [TurnFeatures]) -> Candidate? {
        let turn = features[index]
        let neighborhood = [index - 1, index, index + 1]
        let friction = turn.has(LifeContextLexicon.friction)
        let warm = turn.has(LifeContextLexicon.warm)
        guard friction || warm else { return nil }
        var score = friction ? 0.6 : 0.5
        var sources = [index]
        if !friction {
            let window = configuration.confirmationWindow
            let lower = max(0, index - window)
            let upper = min(features.count - 1, index + window)
            if lower <= upper, let echo = (lower...upper).first(where: { other in
                other != index
                    && features[other].turn.sender != turn.turn.sender
                    && features[other].has(LifeContextLexicon.warm)
            }) {
                score += 0.15
                sources.append(echo)
            }
        }
        let who = self.role(in: neighborhood, of: features)
        if who != nil { score += 0.05 }
        return Candidate(
            kind: .relationship,
            label: friction ? "friction" : "connection",
            display: friction ? "Friction" : "Close connection",
            role: who ?? "someone close",
            when: nil, confidence: score, sources: sources.sorted(), observedAt: turn.turn.timestamp
        )
    }

    // ------------------------------------------------------------
    // MARK: Summaries, hashes, ordering
    // ------------------------------------------------------------

    static let verbatimRunLength = 5

    private func guardedSummary(for candidate: Candidate, sourceRuns: Set<String>) -> String? {
        let whenText = candidate.when.map { render($0, anchor: candidate.observedAt) }
        let full = summary(for: candidate, whenText: whenText)
        if !repeats(full, sourceRuns) { return full }
        let short = [candidate.kind.displayName, whenText].compactMap { $0 }.joined(separator: " ")
        return repeats(short, sourceRuns) ? nil : short
    }

    private func repeats(_ summary: String, _ sourceRuns: Set<String>) -> Bool {
        Self.runs(of: LifeContextText.words(summary), length: Self.verbatimRunLength)
            .contains { sourceRuns.contains($0) }
    }

    static func runs(of words: [String], length: Int) -> [String] {
        guard length > 0, words.count >= length else { return [] }
        return (0...(words.count - length)).map { words[$0..<($0 + length)].joined(separator: " ") }
    }

    private func summary(for candidate: Candidate, whenText: String?) -> String {
        func with(_ base: String) -> String {
            [base, whenText].compactMap { $0 }.joined(separator: " ")
        }
        switch candidate.kind {
        case .plan:
            return with("\(candidate.display) with \(candidate.role ?? "a friend")")
        case .event, .travel:
            return with(candidate.display)
        case .commitment:
            if let whenText {
                return candidate.label == "work deadline" ? "Work deadline \(whenText)" : "Commitment due \(whenText)"
            }
            return candidate.label == "work deadline" ? "Open work commitment" : "Open commitment"
        case .healthSignal:
            return with(candidate.display)
        case .stressSignal:
            return candidate.display
        case .relationship:
            return "\(candidate.display) with \(candidate.role ?? "someone close")"
        }
    }

    private static let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    private static let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// "Friday 7pm" within six days of the message, "Oct 12 7:30pm" beyond.
    /// Built from calendar components, not a DateFormatter, so it cannot vary
    /// with the device's locale.
    func render(_ when: ResolvedWhen, anchor: Date) -> String {
        if when.precision == .week { return "next week" }
        let calendar = configuration.calendar
        let delta = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: anchor),
            to: calendar.startOfDay(for: when.date)
        ).day ?? Int.max
        var text: String
        if (0...6).contains(delta) {
            let weekday = calendar.component(.weekday, from: when.date)
            text = Self.weekdayNames[(weekday - 1 + 7) % 7]
        } else {
            let month = calendar.component(.month, from: when.date)
            text = "\(Self.monthNames[(month - 1 + 12) % 12]) \(calendar.component(.day, from: when.date))"
        }
        if when.precision == .time {
            let hour = calendar.component(.hour, from: when.date)
            let minute = calendar.component(.minute, from: when.date)
            let twelve = hour % 12 == 0 ? 12 : hour % 12
            let suffix = hour < 12 ? "am" : "pm"
            text += minute == 0
                ? " \(twelve)\(suffix)"
                : " \(twelve):" + String(format: "%02d", minute) + suffix
        }
        return text
    }

    private func sourceHash(for candidate: Candidate, in features: [TurnFeatures]) -> String {
        let material = candidate.sources.map { index -> String in
            let feature = features[index]
            let who: String
            switch feature.turn.sender {
            case .me: who = "me"
            case .them(let id): who = id.value
            }
            return who + ":" + feature.words.joined(separator: " ")
        }.joined(separator: "\u{1E}")
        return hashKey.digest(
            "\(candidate.kind.rawValue)|\(candidate.label)|\(material)",
            domain: "forge.lifeContext.fact.v1",
            byteLength: 16
        )
    }

    private static func rounded(_ value: Double) -> Double {
        (min(1, max(0, value)) * 100).rounded() / 100
    }

    /// One fact per kind + label + day within a single extraction — "Dinner
    /// Friday?" and "yes, dinner Friday!" are one plan. The most confident
    /// wins; ties keep the earlier.
    static func collapse(_ facts: [LifeContextFact], calendar: Calendar) -> [LifeContextFact] {
        var best: [String: LifeContextFact] = [:]
        var order: [String] = []
        for fact in facts {
            let day = fact.date.map { String(Int(calendar.startOfDay(for: $0).timeIntervalSince1970)) } ?? "-"
            let key = "\(fact.kind.rawValue)|\(fact.label)|\(day)"
            if let current = best[key] {
                if fact.confidence > current.confidence { best[key] = fact }
            } else {
                best[key] = fact
                order.append(key)
            }
        }
        var seenHashes = Set<String>()
        return order.compactMap { best[$0] }.filter { seenHashes.insert($0.sourceHash).inserted }
    }

    private static let kindOrder: [LifeContextFact.Kind: Int] = Dictionary(
        uniqueKeysWithValues: LifeContextFact.Kind.allCases.enumerated().map { ($1, $0) }
    )

    static func sorted(_ facts: [LifeContextFact]) -> [LifeContextFact] {
        facts.sorted { a, b in
            if a.observedAt != b.observedAt { return a.observedAt < b.observedAt }
            let ka = kindOrder[a.kind] ?? 0
            let kb = kindOrder[b.kind] ?? 0
            if ka != kb { return ka < kb }
            return a.sourceHash < b.sourceHash
        }
    }

    /// Keep the newest `cap` of an already-sorted list.
    static func capped(_ facts: [LifeContextFact], to cap: Int) -> [LifeContextFact] {
        guard facts.count > max(0, cap) else { return facts }
        return Array(facts.suffix(max(0, cap)))
    }
}

// ============================================================
// MARK: - Lexicon
// ============================================================

/// Forge's fixed vocabulary. Phrases are in `LifeContextText.words` form:
/// lowercase, single spaces, apostrophes kept, hyphens written as spaces.
/// Arrays, not dictionaries, so matching order — and so output — is fixed.
enum LifeContextLexicon {

    struct Cue {
        let label: String
        let display: String
        let phrases: [String]
    }

    static func firstCue(_ padded: String, in cues: [Cue]) -> Cue? {
        cues.first { LifeContextText.firstMatch(padded, in: $0.phrases) != nil }
    }

    // MARK: Plans

    static let plans: [Cue] = [
        Cue(label: "dinner", display: "Dinner", phrases: ["dinner", "supper"]),
        Cue(label: "lunch", display: "Lunch", phrases: ["lunch"]),
        Cue(label: "brunch", display: "Brunch", phrases: ["brunch"]),
        Cue(label: "breakfast", display: "Breakfast", phrases: ["breakfast"]),
        Cue(label: "coffee", display: "Coffee", phrases: ["coffee"]),
        Cue(label: "drinks", display: "Drinks", phrases: ["drinks", "a drink", "beers", "a beer", "happy hour", "wine night"]),
        Cue(label: "workout", display: "Workout", phrases: [
            "gym", "workout", "work out", "run together", "go for a run", "climbing", "yoga class",
            "spin class", "pickleball", "tennis", "hike",
        ]),
        Cue(label: "movie", display: "Movie", phrases: ["movie", "movies", "cinema", "film"]),
        Cue(label: "hangout", display: "Hangout", phrases: [
            "hang out", "hangout", "meet up", "meetup", "catch up", "get together", "come over", "game night",
        ]),
    ]

    static let planVerbs = [
        "let's", "lets", "wanna", "want to", "are we still", "still on", "meet", "grab", "join us", "join me",
        "down for", "up for", "free for", "you free", "are you free", "how about", "shall we", "we should",
        "see you at",
    ]

    // MARK: Events

    static let events: [Cue] = [
        Cue(label: "wedding", display: "Wedding", phrases: ["wedding"]),
        Cue(label: "birthday", display: "Birthday", phrases: ["birthday", "bday"]),
        Cue(label: "anniversary", display: "Anniversary", phrases: ["anniversary"]),
        Cue(label: "graduation", display: "Graduation", phrases: ["graduation"]),
        Cue(label: "race", display: "Race", phrases: [
            "marathon", "half marathon", "5k", "10k", "race day", "triathlon", "the race",
        ]),
        Cue(label: "concert", display: "Concert", phrases: ["concert", "festival"]),
        Cue(label: "game", display: "Game", phrases: ["the game", "tournament", "playoff", "playoffs"]),
        Cue(label: "party", display: "Party", phrases: ["party"]),
        Cue(label: "shower", display: "Shower", phrases: ["baby shower", "bridal shower"]),
        Cue(label: "funeral", display: "Funeral", phrases: ["funeral", "memorial service"]),
        Cue(label: "conference", display: "Conference", phrases: ["conference", "offsite"]),
    ]

    // MARK: Travel

    static let flight = Cue(label: "flight", display: "Flight", phrases: [
        "flight", "flights", "flying", "fly out", "flying out", "airport", "boarding", "layover", "lands at",
        "landing at", "my plane",
    ])

    static let travel: [Cue] = [
        flight,
        Cue(label: "trip", display: "Trip", phrases: [
            "trip", "road trip", "vacation", "getaway", "travel", "traveling", "travelling", "out of town",
        ]),
        Cue(label: "hotel", display: "Hotel stay", phrases: ["hotel", "airbnb"]),
    ]

    static var travelPhrases: [String] { travel.flatMap(\.phrases) }

    // MARK: Commitments

    static let commitmentStrong = [
        "i promise", "promise i'll", "i promised", "deadline", "due by", "due on", "is due", "submit by",
        "i committed", "i've committed", "no later than", "by end of day", "by eod",
    ]
    static let commitmentNormal = [
        "i'll", "i will", "i need to", "i have to", "i've got to", "ive got to", "i gotta", "i must",
        "remind me to", "i owe",
    ]
    static var commitmentPhrases: [String] { commitmentStrong + commitmentNormal + requests }

    static let requests = [
        "can you", "could you", "would you", "please", "pls", "plz", "need you to", "make sure you",
        "don't forget to", "dont forget to", "remember to",
    ]

    static let workContext = [
        "work", "report", "deck", "slides", "presentation", "client", "project", "proposal", "boss",
        "manager", "meeting", "submit", "invoice", "office", "team", "review", "standup", "deliverable",
    ]

    // MARK: Health

    static let health: [(cue: Cue, base: Double)] = [
        (Cue(label: "medical appointment", display: "Medical appointment", phrases: [
            "doctor's appointment", "doctor appointment", "doctors appointment", "see the doctor", "see a doctor",
            "dentist", "dental", "physio", "physical therapy", "checkup", "check up", "blood work", "bloodwork",
            "blood test", "mri", "x ray", "surgery", "specialist",
        ]), 0.6),
        (Cue(label: "unwell", display: "Feeling unwell", phrases: [
            "sick", "fever", "flu", "covid", "a cold", "the cold", "sore throat", "food poisoning", "throwing up",
            "vomiting", "stomach bug", "migraine", "nauseous", "infection", "feel ill", "feeling ill", "i'm ill",
            "im ill",
        ]), 0.65),
        (Cue(label: "injury", display: "Injury mention", phrases: [
            "injured", "injury", "sprained", "sprain", "pulled a muscle", "pulled my", "tweaked my", "strained",
            "hurt my", "broke my", "concussion", "torn",
        ]), 0.65),
        (Cue(label: "poor sleep", display: "Poor sleep mention", phrases: [
            "can't sleep", "cant sleep", "couldn't sleep", "couldnt sleep", "insomnia", "barely slept",
            "didn't sleep", "didnt sleep", "no sleep", "up all night",
        ]), 0.6),
        (Cue(label: "run down", display: "Feeling run down", phrases: [
            "headache", "sore", "run down", "under the weather",
        ]), 0.45),
    ]

    static let healthNegations = [
        "not sick", "no longer sick", "feeling better", "all better", "recovered", "over it", "not injured",
        "not hurt", "no fever",
    ]

    // MARK: Stress

    static let stressStrong = [
        "stressed", "stressing", "stressful", "overwhelmed", "anxious", "anxiety", "burnt out", "burned out",
        "burnout", "panicking", "panic attack", "freaking out", "breaking down", "can't cope", "cant cope",
        "drowning in", "at my limit", "losing my mind",
    ]
    static let stressWeak = [
        "swamped", "slammed", "so busy", "crazy busy", "crazy week", "rough day", "rough week", "long day",
        "long week", "exhausted", "drained", "frustrated", "behind on", "too much on my plate",
    ]
    static let stressNegations = [
        "not stressed", "less stressed", "no longer stressed", "not overwhelmed", "feeling calmer", "not anxious",
    ]

    // MARK: Relationship

    static let warm = [
        "love you", "miss you", "proud of you", "thinking of you", "grateful for you", "means a lot",
    ]
    static let friction = [
        "we had a fight", "had a fight", "got in a fight", "we argued", "argument", "upset with me",
        "mad at me", "upset with you", "mad at you", "broke up", "breaking up", "not talking to",
        "not speaking", "ignoring me",
    ]

    /// Most specific first.
    static let roles: [(String, [String])] = [
        ("your partner", [
            "wife", "husband", "partner", "girlfriend", "boyfriend", "fiance", "fiancee", "hubby",
        ]),
        ("family", [
            "mom", "mum", "mother", "dad", "father", "parents", "sister", "brother", "grandma", "grandpa",
            "nana", "aunt", "uncle", "cousin", "son", "daughter", "kids", "family", "in laws", "niece", "nephew",
        ]),
        ("a colleague", [
            "boss", "manager", "coworker", "coworkers", "co worker", "co workers", "colleague", "colleagues",
            "client", "clients", "team",
        ]),
        ("a friend", ["friend", "friends", "buddy", "bestie", "roommate"]),
    ]

    // MARK: Modifiers

    static let confirm = [
        "yes", "yeah", "yep", "yup", "sure", "sounds good", "sounds great", "perfect", "deal", "works for me",
        "that works", "i'm in", "im in", "count me in", "see you", "see ya", "can't wait", "cant wait",
        "absolutely", "definitely", "for sure", "ok", "okay", "no problem", "no worries", "will do",
        "i'll be there", "on it", "done",
    ]
    static let decline = [
        "can't", "cant", "cannot", "can not", "no", "nope", "not this time", "rain check", "raincheck",
        "another time", "i'm busy", "im busy", "won't make it", "wont make it", "have to cancel",
        "need to cancel", "cancel",
    ]
    static let hedge = [
        "maybe", "might", "perhaps", "not sure", "sometime", "someday", "at some point", "possibly",
        "i'll try", "try to", "probably not",
    ]
    static let intensifiers = [
        "so", "really", "super", "very", "totally", "completely", "awful", "terrible", "horrible", "badly",
        "extremely", "insanely",
    ]
    /// A turn that is mostly "I'll be there" — attendance, not a commitment.
    static let attendance = [
        "see you", "see ya", "i'll be there", "i'm in", "im in", "count me in", "sounds good", "sounds great",
        "can't wait", "cant wait",
    ]
    static let firstPerson = ["i'm", "im", "i am", "we're", "we are", "my", "our", "i'll", "we'll"]
    static let shared = ["we", "us", "you", "our", "we're", "we'll", "you're"]
    static let evening = [
        "dinner", "supper", "drinks", "tonight", "tonite", "evening", "night", "movie", "party", "concert",
        "happy hour", "bar",
    ]
}
