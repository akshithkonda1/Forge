import Foundation
import ForgeCore

/// Curated, keyless web reference lookup.
///
/// Uses the process's default network route — the iPhone's Wi-Fi (or
/// cellular if that's all that's up), and in Simulator the Mac's own
/// internet. Nothing here talks to Forge's AWS. No client API key.
/// Pages are a hand-picked .gov / MedlinePlus set in
/// `AriaReferenceCatalog`; which page and which excerpt depend on the
/// actual question plus a session salt, so ARIA does not recite the same
/// CDC paragraph every turn.
///
/// Isolated from `LocalTestingOrchestrator`, which must stay
/// URLSession-free (`scripts/check-aria-web-research.py`). Gated to
/// local testing because that is still the running ARIA mode.
@MainActor
enum AriaWebResearch {

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6
        config.timeoutIntervalForResource = 6
        config.waitsForConnectivity = false
        config.allowsCellularAccess = true
        return URLSession(configuration: config)
    }()

    // MARK: - Trigger

    private static let researchPhrases = [
        "how do i", "how to", "best way to", "is it true", "what does the science say",
        "what does research say", "research shows", "studies show", "recomp",
        "lose fat and gain muscle", "gain muscle and lose fat", "how much protein should",
        "is it possible to", "how long does it take to", "evidence for", "evidence on",
        "should i", "do i need", "what should i eat", "what should i do",
        "is it safe to", "can i", "will it help", "does it work",
        "benefits of", "side effects", "how much sleep", "how often should",
        "fever", "temperature", "too hot", "running hot", "thermometer",
        "chills", "is this normal", "what does it mean if",
    ]

    static func isResearchWorthy(text: String, leadingDomain: AriaLocalDomain) -> Bool {
        guard [
            .training, .nutrition, .progress, .sleep, .readiness,
            .lifestyle, .activity, .body, .cycle,
        ].contains(leadingDomain) else {
            return false
        }
        let lower = text.lowercased()
        if AriaReferenceCatalog.questionSuggestsFever(text) { return true }
        return researchPhrases.contains { lower.contains($0) }
    }

    // MARK: - Lookup

    /// Returns a cited snippet, or nil on timeout / bad status / empty text.
    /// Tries the catalog's rotated list so a moved page does not strand the turn.
    static func lookUp(
        domain: AriaLocalDomain,
        question: String,
        salt: UInt64
    ) async -> String? {
        guard AriaOperatingMode.current.isLocalTesting else { return nil }
        let topic = AriaReferenceCatalog.resolvedTopic(
            domainRawValue: domain.rawValue,
            question: question
        )
        let picks = AriaReferenceCatalog.picks(topic: topic, question: question, salt: salt)
        guard !picks.isEmpty else { return nil }

        for pick in picks {
            guard let url = pick.source.pageURL else { continue }
            do {
                let (data, response) = try await session.data(from: url)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { continue }
                guard var text = extractText(from: data), !text.isEmpty else { continue }
                if pick.excerptStart > 0, text.count > pick.excerptStart + 80 {
                    let start = text.index(text.startIndex, offsetBy: pick.excerptStart)
                    text = String(text[start...])
                }
                if text.count > 750 {
                    let idx = text.index(text.startIndex, offsetBy: 750)
                    let cut = text[..<idx]
                    if let lastPeriod = cut.lastIndex(of: ".") {
                        text = String(cut[..<lastPeriod]) + "."
                    } else {
                        text = String(cut) + "…"
                    }
                }
                return "\(pick.voiceLead): \(text) — here's how that lands for you:"
            } catch {
                continue
            }
        }
        return nil
    }

    /// Plain regex tag-stripping, not `NSAttributedString`'s HTML importer:
    /// that importer is WebKit-backed on iOS and has a documented history
    /// of main-thread-only behavior, which would have been exactly the
    /// wrong tradeoff for a background fetch this careful about never
    /// hitching the chat UI. A curated handful of static reference pages
    /// doesn't need full-fidelity HTML rendering, just readable body text.
    private static func extractText(from data: Data) -> String? {
        guard let html = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1) else { return nil }

        var stripped = html.replacingOccurrences(
            of: #"(?is)<(script|style)[^>]*>.*?</\1>"#,
            with: " ",
            options: .regularExpression
        )
        stripped = stripped.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        stripped = stripped
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")

        stripped = stripped
            .replacingOccurrences(of: "&rsquo;", with: "'")
            .replacingOccurrences(of: "&ldquo;", with: "\"")
            .replacingOccurrences(of: "&rdquo;", with: "\"")
            .replacingOccurrences(of: "&mdash;", with: " — ")
            .replacingOccurrences(of: "&#8212;", with: " — ")
            .replacingOccurrences(of: "&hellip;", with: "…")

        let collapsed = stripped
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(1800))
    }
}
