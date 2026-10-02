import Foundation

/// The Scout dummy: ARIA's research agent, run inside the Dummy on the phone.
///
/// Swift twin of `backend/scout/{fixtures,keyless,modes}.py`. Same loop as the
/// Scout server — plan → search → rank → read → cross-check → cited brief —
/// with the deterministic rules brain instead of Grok. Four modes:
///
/// * `offline` — searches the built-in corpus of public-health pages; no
///   network, identical output every run (tests, previews, no signal);
/// * `local` — searches keyless public sources (Wikipedia, DuckDuckGo,
///   MedlinePlus, PubMed) and reads their snippets; no server, no cloud model;
/// * `remote` — the deployed Scout server (`AriaScoutClient`);
/// * `off` — no Scout.
///
/// Pure: searching is injected, so this file never touches the network.
public enum AriaScoutMode: String, CaseIterable, Sendable {
    case offline, local, remote, off
}

public struct AriaScoutHit: Equatable, Sendable {
    public var url: String
    public var title: String
    public var snippet: String
    public var engines: [String]

    public init(url: String, title: String, snippet: String, engines: [String]) {
        self.url = url
        self.title = title
        self.snippet = snippet
        self.engines = engines
    }

    public var host: String { (URL(string: url)?.host ?? "").lowercased() }
    public var trust: Double { AriaScoutDummy.trust(host: host) }
}

public struct AriaScoutBrief: Equatable, Sendable {
    public struct Point: Equatable, Sendable {
        public var text: String
        public var sources: [String]
        public var corroborated: Bool
    }

    public struct Page: Equatable, Sendable {
        public var id: String
        public var url: String
        public var host: String
        public var title: String
        public var text: String
        public var trust: Double
    }

    public var query: String
    public var answer: String
    public var points: [Point]
    public var sources: [Page]
    public var confidence: Double
    public var queries: [String]
    public var mode: AriaScoutMode

    /// The brief as Dummy evidence (untrusted outside data), or nil if uncited.
    public var evidence: AriaWebEvidence? {
        guard !answer.isEmpty, !sources.isEmpty else { return nil }
        return AriaWebEvidence(
            text: AriaWebParsers.clip(answer),
            sources: sources.prefix(4).map { .init(title: $0.title, url: $0.url) },
            via: .scout,
            confidence: confidence,
            scoutMode: mode.rawValue
        )
    }
}

public struct AriaScoutFixturePage: Equatable, Sendable {
    public var url: String
    public var title: String
    public var topics: [String]
    public var text: String
}

public enum AriaScoutDummy {

    public static let maxPages = 5
    public static let maxPoints = 4
    public static let maxQueries = 3

    // MARK: Trust (mirrors backend/scout/search.py)

    private static let trustRules: [(String, Double)] = [
        (".gov", 1.0), ("nih.gov", 1.0), ("who.int", 1.0), ("cochranelibrary.com", 0.95),
        ("pubmed.ncbi.nlm.nih.gov", 1.0), (".edu", 0.9), ("mayoclinic.org", 0.9),
        ("clevelandclinic.org", 0.9), ("nhs.uk", 0.95), ("hopkinsmedicine.org", 0.9),
        ("harvard.edu", 0.9), ("acsm.org", 0.9), ("nsca.com", 0.85), ("examine.com", 0.8),
        ("bmj.com", 0.9), ("nature.com", 0.85), ("wikipedia.org", 0.6),
    ]
    private static let lowTrust = [
        "amazon.", "ebay.", "walmart.", "etsy.", "aliexpress.", "pinterest.", "facebook.",
        "instagram.", "tiktok.", "x.com", "twitter.com", "reddit.com", "quora.com",
    ]

    public static func trust(host raw: String) -> Double {
        let host = raw.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !host.isEmpty else { return 0 }
        if lowTrust.contains(where: { host.contains($0) }) { return 0.15 }
        var best = 0.0
        for (rule, weight) in trustRules {
            let matched = rule.hasPrefix(".")
                ? host.hasSuffix(rule)
                : (host == rule || host.hasSuffix("." + rule))
            if matched { best = max(best, weight) }
        }
        return best > 0 ? best : 0.45
    }

    // MARK: Words and sentences

    /// Fixture search ignores filler too (mirrors backend/scout/fixtures.py `_STOP`).
    private static let searchStop: Set<String> = Set(
        ("the and for with that this from are was were have has not you your can will how what does "
            + "much many more need needs should get about too").split(separator: " ").map(String.init)
    )
    /// Synthesis and cross-check (mirrors backend/scout/brain.py `_STOP`).
    private static let brainStop: Set<String> = Set(
        "the and for with that this from are was were have has not you your can will how what"
            .split(separator: " ").map(String.init)
    )
    private static let wordRe = try? NSRegularExpression(pattern: #"[a-z][a-z0-9-]+"#)
    /// A sentence ends at . ! or ? followed by whitespace or the end — so
    /// "0.8 grams" stays whole (mirrors Python's `(?<=[.!?])\s+` split).
    private static let sentenceRe = try? NSRegularExpression(pattern: #"[\s\S]+?(?:[.!?]+(?=\s|$)|$)"#)
    private static let claimBan = try? NSRegularExpression(
        pattern: #"(?i)\bcures?\b|\bstudies\s+prove\b|\bguarantee[sd]?\b|\bmiracle\b"#
    )
    private static let injection = try? NSRegularExpression(
        pattern: #"(?i)ignore\s+(all\s+)?(previous|prior|above)|\byou\s+are\s+(now\s+)?(a|an|the)\b|system\s+prompt|disregard\s+(the\s+)?instructions"#
    )

    static func words(_ text: String) -> Set<String> {
        words(text, stop: brainStop)
    }

    static func words(_ text: String, stop: Set<String>) -> Set<String> {
        let lower = text.lowercased()
        guard let wordRe else { return [] }
        let ns = lower as NSString
        var out: Set<String> = []
        for m in wordRe.matches(in: lower, range: NSRange(location: 0, length: ns.length)) {
            let w = ns.substring(with: m.range)
            if w.count > 2, !stop.contains(w) { out.insert(w) }
        }
        return out
    }

    static func sentences(_ text: String) -> [String] {
        guard let sentenceRe else { return [text] }
        let ns = text as NSString
        return sentenceRe.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func matches(_ re: NSRegularExpression?, _ text: String) -> Bool {
        guard let re else { return false }
        return re.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }

    /// Untrusted page text: drop sentences that address an assistant.
    static func stripInjection(_ text: String) -> String {
        sentences(text).filter { !matches(injection, $0) }.joined(separator: " ")
    }

    // MARK: Offline corpus (mirrors backend/scout/fixtures.py)

    public static let fixtures: [AriaScoutFixturePage] = [
        .init(url: "https://www.cdc.gov/physical-activity-basics/guidelines/adults.html",
              title: "CDC: Physical Activity Guidelines for Adults",
              topics: ["training", "progress", "readiness"],
              text: "Adults need at least 150 minutes of moderate-intensity physical activity each week. Adults also need muscle-strengthening activity that works all major muscle groups on at least two days a week. Some physical activity is better than none, and moving more and sitting less benefits nearly everyone."),
        .init(url: "https://medlineplus.gov/exerciseandphysicalfitness.html",
              title: "MedlinePlus: Exercise and Physical Fitness",
              topics: ["training", "readiness", "lifestyle"],
              text: "Regular physical activity is one of the most important things you can do for your health. If you have been inactive, start slowly and build up your activity over time. Strength training, endurance exercise, balance and flexibility each play a different role in fitness."),
        .init(url: "https://www.cdc.gov/sleep/about/index.html",
              title: "CDC: About Sleep",
              topics: ["sleep", "readiness"],
              text: "Most adults need seven or more hours of sleep each night for good health. Not getting enough sleep is linked with many chronic health problems and can affect how you think, react and feel. Keeping a consistent sleep schedule, even on weekends, supports better sleep."),
        .init(url: "https://www.nhlbi.nih.gov/health/sleep-deprivation",
              title: "NHLBI: Sleep Deprivation and Deficiency",
              topics: ["sleep", "readiness"],
              text: "Sleep deficiency means not getting enough sleep, sleeping at the wrong time of day, or not sleeping well. Sleep deficiency can make it harder to focus, learn and react, and it is linked to a higher risk of injury. Adults generally need seven or more hours of sleep each night to stay healthy."),
        .init(url: "https://ods.od.nih.gov/factsheets/Protein-Consumer/",
              title: "NIH Office of Dietary Supplements: Protein",
              topics: ["nutrition"],
              text: "Protein is found in foods such as meat, poultry, seafood, eggs, dairy, beans, nuts, seeds and soy products. The recommended dietary allowance of protein for most adults is about 0.8 grams per kilogram of body weight per day. Most people in the United States get enough protein from the foods they eat."),
        .init(url: "https://medlineplus.gov/fluidandelectrolytebalance.html",
              title: "MedlinePlus: Fluid and Electrolyte Balance",
              topics: ["nutrition", "heat"],
              text: "Electrolytes are minerals in your body that have an electric charge and help keep fluid levels balanced. You can lose fluids and electrolytes through heavy sweating, vomiting or diarrhea. Drinking enough fluids helps keep your body's fluid and electrolyte balance in check."),
        .init(url: "https://medlineplus.gov/fever.html",
              title: "MedlinePlus: Fever",
              topics: ["fever"],
              text: "A fever is a body temperature that is higher than normal and is often a sign that your body is fighting an infection. Rest and drinking plenty of fluids help when you have a fever. Contact a health care provider for a very high fever, a fever that lasts more than a few days, or a fever with severe symptoms."),
        .init(url: "https://www.cdc.gov/flu/treatment/caring-for-someone.html",
              title: "CDC: Caring for Someone Sick at Home",
              topics: ["fever"],
              text: "A person with a fever should rest and drink plenty of fluids to prevent dehydration. Stay home when you are sick to avoid spreading illness to others. Watch for emergency warning signs such as difficulty breathing or chest pain and seek care right away if they appear."),
        .init(url: "https://medlineplus.gov/heatillness.html",
              title: "MedlinePlus: Heat Illness",
              topics: ["heat"],
              text: "During hot weather, especially with high humidity, sweating is not always enough to cool the body. Heat exhaustion can cause heavy sweating, weakness, dizziness and nausea, and heat stroke is a medical emergency. Drink plenty of fluids and limit strenuous activity during the hottest part of the day."),
        .init(url: "https://www.airnow.gov/aqi/aqi-basics/",
              title: "AirNow: Air Quality Index Basics",
              topics: ["heat", "lifestyle"],
              text: "The Air Quality Index tells you how clean or polluted the outdoor air is. When the air quality is unhealthy, reduce prolonged or heavy exertion outdoors. Sensitive groups, including people with heart or lung disease, should take extra care on poor air days."),
        .init(url: "https://www.womenshealth.gov/menstrual-cycle",
              title: "OASH: Your Menstrual Cycle",
              topics: ["cycle"],
              text: "The average menstrual cycle is about 28 days long, and cycles between 21 and 35 days are common in adults. Periods usually last between two and seven days. Talk to a doctor if your periods suddenly change, become very heavy, or stop for several months."),
        .init(url: "https://medlineplus.gov/stress.html",
              title: "MedlinePlus: Stress",
              topics: ["lifestyle", "readiness"],
              text: "Stress is a feeling of emotional or physical tension, and long-term stress can affect your health. Regular physical activity, enough sleep and relaxation techniques can help you manage stress. Reach out to a health care provider if stress feels overwhelming or does not ease."),
        .init(url: "https://www.fda.gov/consumers/consumer-updates/spilling-beans-how-much-caffeine-too-much",
              title: "FDA: How Much Caffeine Is Too Much?",
              topics: ["nutrition", "sleep"],
              text: "For healthy adults, the FDA has cited 400 milligrams of caffeine a day as an amount not generally associated with negative effects. People vary widely in how sensitive they are to caffeine and how fast they process it. Too much caffeine can cause trouble sleeping, jitters, anxiety and a fast heart rate."),
    ]

    /// Deterministic search over the corpus: keyword overlap, topic as tiebreak.
    public static func fixtureSearch(_ query: String, topic: String = "") -> [AriaScoutHit] {
        let want = words(query, stop: searchStop)
        guard !want.isEmpty else { return [] }
        var scored: [(overlap: Int, onTopic: Int, order: Int, page: AriaScoutFixturePage)] = []
        for (order, page) in fixtures.enumerated() {
            let overlap = want.intersection(words("\(page.title) \(page.text) \(page.topics.joined(separator: " "))", stop: searchStop)).count
            let onTopic = (!topic.isEmpty && page.topics.contains(topic)) ? 1 : 0
            if overlap == 0 && onTopic == 0 { continue }
            scored.append((overlap, onTopic, order, page))
        }
        scored.sort {
            if $0.overlap != $1.overlap { return $0.overlap > $1.overlap }
            if $0.onTopic != $1.onTopic { return $0.onTopic > $1.onTopic }
            return $0.order < $1.order
        }
        return scored.prefix(6).map {
            AriaScoutHit(url: $0.page.url, title: $0.page.title, snippet: $0.page.text, engines: ["offline"])
        }
    }

    // MARK: Plan / rank / synthesize (mirrors backend/scout/brain.py RulesBrain)

    private static let evidenceCues = ["research", "study", "studies", "evidence", "science", "proven", "effective", "safe"]

    public static func plan(_ query: String, topic: String = "", privateTerms: [String] = []) -> [String] {
        let base = AriaQueryPrivacy.scrub(query, privateTerms: privateTerms)
        guard !base.isEmpty else { return [] }
        var queries = [base]
        queries.append(evidenceCues.contains(where: { base.contains($0) }) ? "\(base) systematic review" : "\(base) guidelines")
        if !topic.isEmpty, !base.contains(topic) {
            queries.append("\(base) \(topic)")
        }
        return Array(queries.prefix(maxQueries))
    }

    /// Dedupe by URL, one page per host, trust first, then engine agreement.
    public static func rank(_ hits: [AriaScoutHit], limit: Int = maxPages) -> [AriaScoutHit] {
        var seenURLs: Set<String> = []
        var scored: [(score: Double, order: Int, hit: AriaScoutHit)] = []
        for (order, hit) in hits.enumerated() {
            var key = hit.url.components(separatedBy: "#").first ?? hit.url
            while key.hasSuffix("/") { key.removeLast() }
            guard seenURLs.insert(key).inserted else { continue }
            let agreement = Double(min(Set(hit.engines).count, 4)) * 0.05
            scored.append((hit.trust + agreement, order, hit))
        }
        scored.sort { $0.score != $1.score ? $0.score > $1.score : $0.order < $1.order }
        var seenHosts: Set<String> = []
        var ranked: [AriaScoutHit] = []
        for row in scored {
            guard !seenHosts.contains(row.hit.host) else { continue }
            seenHosts.insert(row.hit.host)
            ranked.append(row.hit)
            if ranked.count >= limit { break }
        }
        return ranked
    }

    /// Pages from ranked hits. Offline and local both read snippets.
    public static func pages(from hits: [AriaScoutHit]) -> [AriaScoutBrief.Page] {
        hits.enumerated().compactMap { (index, hit) -> AriaScoutBrief.Page? in
            let text = stripInjection(hit.snippet)
            guard !text.isEmpty else { return nil }
            return AriaScoutBrief.Page(
                id: "S\(index + 1)",
                url: hit.url,
                host: hit.host,
                title: hit.title.isEmpty ? hit.host : String(hit.title.prefix(200)),
                text: String(text.prefix(4000)),
                trust: hit.trust
            )
        }
    }

    public static func synthesize(
        query: String,
        pages: [AriaScoutBrief.Page]
    ) -> (answer: String, points: [AriaScoutBrief.Point], confidence: Double) {
        let want = words(query)
        var candidates: [(score: Double, order: Int, sentence: String, page: AriaScoutBrief.Page)] = []
        var order = 0
        for page in pages {
            for sentence in sentences(page.text) {
                order += 1
                guard (40...320).contains(sentence.count), !matches(claimBan, sentence) else { continue }
                let overlap = want.intersection(words(sentence)).count
                guard overlap > 0 else { continue }
                candidates.append((Double(overlap) * (0.5 + page.trust), order, sentence, page))
            }
        }
        candidates.sort { $0.score != $1.score ? $0.score > $1.score : $0.order < $1.order }
        // Supporting points must be about the question, not one stray shared word.
        if let best = candidates.first?.score {
            candidates = candidates.filter { $0.score >= best * 0.5 }
        }
        var points: [AriaScoutBrief.Point] = []
        var usedPages: Set<String> = []
        for row in candidates {
            if usedPages.contains(row.page.id), usedPages.count < pages.count { continue }
            let rowWords = words(row.sentence)
            if points.contains(where: { words($0.text) == rowWords }) { continue }
            usedPages.insert(row.page.id)
            points.append(AriaScoutBrief.Point(text: row.sentence, sources: [row.page.id], corroborated: false))
            if points.count >= maxPoints { break }
        }
        crossCheck(&points, pages: pages)
        guard let first = points.first else { return ("", [], 0) }
        let cited = Set(points.flatMap(\.sources))
        let trust = pages.filter { cited.contains($0.id) }.map(\.trust).max() ?? 0
        let corroborated = Double(points.filter(\.corroborated).count)
        let confidence = (min(0.85, 0.35 + 0.3 * trust + 0.1 * corroborated) * 100).rounded() / 100
        return (first.text, points, confidence)
    }

    /// A point is corroborated when another source says overlapping things.
    static func crossCheck(_ points: inout [AriaScoutBrief.Point], pages: [AriaScoutBrief.Page]) {
        for index in points.indices {
            let want = words(points[index].text)
            guard want.count >= 3 else { continue }
            for page in pages where !points[index].sources.contains(page.id) {
                let best = sentences(page.text)
                    .map { Double(want.intersection(words($0)).count) / Double(want.count) }
                    .max() ?? 0
                if best >= 0.4 {
                    points[index].corroborated = true
                    points[index].sources.append(page.id)
                    break
                }
            }
        }
    }

    /// Assemble a brief from per-query search results (interleaved by rank).
    public static func brief(
        query: String,
        queries: [String],
        results: [[AriaScoutHit]],
        mode: AriaScoutMode
    ) -> AriaScoutBrief? {
        var merged: [AriaScoutHit] = []
        let depth = results.map(\.count).max() ?? 0
        for level in 0..<depth {
            for row in results where level < row.count {
                merged.append(row[level])
            }
        }
        let read = pages(from: rank(merged))
        let safe = queries.first ?? query
        let synthesis = synthesize(query: safe, pages: read)
        guard !synthesis.answer.isEmpty else { return nil }
        let cited = Set(synthesis.points.flatMap(\.sources))
        return AriaScoutBrief(
            query: safe,
            answer: synthesis.answer,
            points: synthesis.points,
            sources: read.filter { cited.contains($0.id) },
            confidence: synthesis.confidence,
            queries: queries,
            mode: mode
        )
    }

    /// Offline Scout: the whole loop over the built-in corpus. No network.
    public static func offline(query: String, topic: String = "", privateTerms: [String] = []) -> AriaScoutBrief? {
        let queries = plan(query, topic: topic, privateTerms: privateTerms)
        guard !queries.isEmpty else { return nil }
        return brief(query: query, queries: queries, results: queries.map { fixtureSearch($0, topic: topic) }, mode: .offline)
    }

    /// Local Scout: the same loop over an injected live search (keyless sources).
    public static func local(
        query: String,
        topic: String = "",
        privateTerms: [String] = [],
        search: (String) async -> [AriaScoutHit]
    ) async -> AriaScoutBrief? {
        let queries = plan(query, topic: topic, privateTerms: privateTerms)
        guard !queries.isEmpty else { return nil }
        var results: [[AriaScoutHit]] = []
        for q in queries {
            results.append(await search(q))
        }
        return brief(query: query, queries: queries, results: results, mode: .local)
    }

    // MARK: Keyless parsers (mirrors backend/scout/keyless.py)

    public static func wikipediaHits(_ data: Data) -> [AriaScoutHit] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let query = root["query"] as? [String: Any],
              let pages = query["pages"] as? [String: Any] else { return [] }
        let rows = pages.values.compactMap { $0 as? [String: Any] }
            .sorted { (($0["index"] as? Int) ?? 99) < (($1["index"] as? Int) ?? 99) }
        return rows.compactMap { (page: [String: Any]) -> AriaScoutHit? in
            guard let url = page["fullurl"] as? String, url.hasPrefix("https://") else { return nil }
            let extract = AriaWebParsers.clip(page["extract"] as? String ?? "", limit: 900)
            guard !extract.isEmpty else { return nil }
            return AriaScoutHit(url: url, title: page["title"] as? String ?? "", snippet: extract, engines: ["wikipedia"])
        }
    }

    public static func duckDuckGoHits(_ data: Data) -> [AriaScoutHit] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let url = root["AbstractURL"] as? String, url.hasPrefix("https://") else { return [] }
        let text = AriaWebParsers.clip(root["AbstractText"] as? String ?? "", limit: 900)
        guard !text.isEmpty else { return [] }
        let title = (root["Heading"] as? String) ?? (root["AbstractSource"] as? String) ?? ""
        return [AriaScoutHit(url: url, title: title, snippet: text, engines: ["duckduckgo"])]
    }

    public static func medlinePlusHits(_ data: Data) -> [AriaScoutHit] {
        AriaWebParsers.medlinePlus(data).map {
            AriaScoutHit(url: $0.url, title: $0.title, snippet: $0.summary, engines: ["medlineplus"])
        }
    }

    public static func pubmedHits(_ summary: Data) -> [AriaScoutHit] {
        AriaWebParsers.pubmedSummaries(summary).map { (paper: AriaWebParsers.PaperRow) -> AriaScoutHit in
            let snippet = paper.journal.isEmpty ? paper.title : "\(paper.title) Published in \(paper.journal) (\(paper.year))."
            return AriaScoutHit(url: paper.url, title: paper.title, snippet: snippet, engines: ["pubmed"])
        }
    }
}
