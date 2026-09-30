import Foundation

/// Outside knowledge for one Dummy turn. Untrusted data — never user facts,
/// never written into sleep / training / nutrition fields or durable memory.
public struct AriaWebEvidence: Equatable, Sendable {
    public struct Source: Equatable, Sendable {
        public var title: String
        public var url: String

        public init(title: String, url: String) {
            self.title = title
            self.url = url
        }

        public var host: String {
            let host = URL(string: url)?.host ?? ""
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
    }

    public enum Via: String, Sendable {
        case scout, medlineplus, pubmed, openfda, catalog
    }

    public var text: String
    public var sources: [Source]
    public var via: Via
    public var confidence: Double

    public init(text: String, sources: [Source], via: Via, confidence: Double = 0.5) {
        self.text = text
        self.sources = sources
        self.via = via
        self.confidence = confidence
    }

    /// Short spoken cite: "From cdc.gov: …".
    public var cite: String {
        let label = sources.first.map(\.host).flatMap { $0.isEmpty ? nil : $0 } ?? via.rawValue
        return "From \(label): \(text)"
    }
}

/// Pure parsers for the keyless sources `AriaWebResearch` fetches. Mirrors
/// the Python Dummy's `web_research` parsers so both platforms read the same
/// shapes the same way. Every parser returns empty / nil on a bad shape.
public enum AriaWebParsers {

    public static let maxEvidenceChars = 420

    public struct MedlineRow: Equatable, Sendable {
        public var title: String
        public var url: String
        public var summary: String
    }

    public struct PaperRow: Equatable, Sendable {
        public var title: String
        public var journal: String
        public var year: String
        public var url: String
    }

    public struct DrugLabel: Equatable, Sendable {
        public var name: String
        public var use: String
        public var warnings: String
    }

    // MARK: Text

    public static func plain(_ html: String) -> String {
        var text = html.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        for (entity, char) in [
            ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
            ("&nbsp;", " "), ("&rsquo;", "'"), ("&lsquo;", "'"), ("&ldquo;", "\""), ("&rdquo;", "\""),
            ("&mdash;", " — "), ("&ndash;", "–"), ("&hellip;", "…"), ("&amp;", "&"),
        ] {
            text = text.replacingOccurrences(of: entity, with: char)
        }
        return text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    public static func clip(_ text: String, limit: Int = maxEvidenceChars) -> String {
        let clean = plain(text)
        guard clean.count > limit else { return clean }
        let cut = String(clean.prefix(limit))
        if let stop = cut.lastIndex(of: ".") {
            return String(cut[...stop])
        }
        return cut.trimmingCharacters(in: .whitespaces) + "…"
    }

    // MARK: MedlinePlus health-topic search (XML)

    public static func medlinePlus(_ data: Data) -> [MedlineRow] {
        guard let xml = String(data: data, encoding: .utf8) else { return [] }
        guard let docRe = try? NSRegularExpression(
            pattern: #"<document[^>]*\burl="([^"]+)"[^>]*>(.*?)</document>"#,
            options: [.dotMatchesLineSeparators]
        ) else { return [] }
        let ns = xml as NSString
        var rows: [MedlineRow] = []
        for m in docRe.matches(in: xml, range: NSRange(location: 0, length: ns.length)) {
            let url = ns.substring(with: m.range(at: 1))
            let body = ns.substring(with: m.range(at: 2))
            // Entities are escaped twice in this feed: unescape, then strip tags.
            let title = clip(plain(content(named: "title", in: body)), limit: 160)
            var summary = content(named: "FullSummary", in: body)
            if summary.isEmpty { summary = content(named: "snippet", in: body) }
            let text = clip(plain(summary))
            if url.hasPrefix("https://"), !title.isEmpty, !text.isEmpty {
                rows.append(MedlineRow(title: title, url: url, summary: text))
            }
        }
        return rows
    }

    private static func content(named name: String, in body: String) -> String {
        guard let re = try? NSRegularExpression(
            pattern: #"<content name=""# + NSRegularExpression.escapedPattern(for: name) + #"">(.*?)</content>"#,
            options: [.dotMatchesLineSeparators]
        ) else { return "" }
        let ns = body as NSString
        guard let m = re.firstMatch(in: body, range: NSRange(location: 0, length: ns.length)) else { return "" }
        return plain(ns.substring(with: m.range(at: 1)))
    }

    // MARK: PubMed E-utilities (JSON)

    public static func pubmedIDs(_ data: Data) -> [String] {
        guard let root = json(data),
              let result = root["esearchresult"] as? [String: Any],
              let ids = result["idlist"] as? [Any] else { return [] }
        return ids.map { "\($0)" }.filter { !$0.isEmpty && $0.allSatisfy(\.isNumber) }.prefix(3).map { $0 }
    }

    public static func pubmedSummaries(_ data: Data) -> [PaperRow] {
        guard let root = json(data),
              let result = root["result"] as? [String: Any],
              let uids = result["uids"] as? [String] else { return [] }
        return uids.compactMap { uid -> PaperRow? in
            guard let row = result[uid] as? [String: Any] else { return nil }
            let title = clip(row["title"] as? String ?? "", limit: 240)
            guard !title.isEmpty else { return nil }
            return PaperRow(
                title: title,
                journal: row["source"] as? String ?? "",
                year: String((row["pubdate"] as? String ?? "").prefix(4)),
                url: "https://pubmed.ncbi.nlm.nih.gov/\(uid)/"
            )
        }
    }

    // MARK: openFDA drug label (JSON)

    public static func openFDALabel(_ data: Data) -> DrugLabel? {
        guard let root = json(data),
              let results = root["results"] as? [[String: Any]],
              let row = results.first else { return nil }
        func first(_ key: String) -> String {
            if let list = row[key] as? [String], let head = list.first { return clip(head, limit: 300) }
            return clip(row[key] as? String ?? "", limit: 300)
        }
        let openfda = row["openfda"] as? [String: Any] ?? [:]
        let names = (openfda["generic_name"] as? [String]) ?? (openfda["brand_name"] as? [String]) ?? []
        let use = first("indications_and_usage").isEmpty ? first("purpose") : first("indications_and_usage")
        let warn = first("warnings").isEmpty ? first("boxed_warning") : first("warnings")
        guard !use.isEmpty || !warn.isEmpty else { return nil }
        return DrugLabel(name: names.first ?? "", use: use, warnings: warn)
    }

    // MARK: Open-Meteo forecast + air quality (JSON)

    public static func environment(forecast: Data?, air: Data?, now: Date = Date()) -> AriaEnvironmentRead? {
        let current = forecast.flatMap { json($0) }.flatMap { $0["current"] as? [String: Any] } ?? [:]
        let aq = air.flatMap { json($0) }.flatMap { $0["current"] as? [String: Any] } ?? [:]
        guard !current.isEmpty || !aq.isEmpty else { return nil }
        func num(_ src: [String: Any], _ key: String) -> Double? {
            (src[key] as? NSNumber)?.doubleValue
        }
        let isDay = num(current, "is_day").map { $0 >= 1 }
        return AriaEnvironmentRead(
            apparentTempC: num(current, "apparent_temperature") ?? num(current, "temperature_2m"),
            uvIndex: num(current, "uv_index"),
            usAQI: num(aq, "us_aqi").map { Int($0.rounded()) },
            precipitationMm: num(current, "precipitation"),
            isDay: isDay,
            source: "open-meteo",
            capturedAt: now
        )
    }

    // MARK: ARIA Scout brief (JSON)

    public static func scoutBrief(_ data: Data) -> AriaWebEvidence? {
        guard let root = json(data),
              let answer = root["answer"] as? String,
              !answer.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let rows = (root["sources"] as? [[String: Any]]) ?? []
        let sources = rows.compactMap { row -> AriaWebEvidence.Source? in
            guard let url = row["url"] as? String, url.hasPrefix("https://") else { return nil }
            return AriaWebEvidence.Source(title: row["title"] as? String ?? "", url: url)
        }
        guard !sources.isEmpty else { return nil }
        let confidence = (root["confidence"] as? NSNumber)?.doubleValue ?? 0.5
        return AriaWebEvidence(
            text: clip(answer),
            sources: Array(sources.prefix(4)),
            via: .scout,
            confidence: confidence
        )
    }

    private static func json(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
