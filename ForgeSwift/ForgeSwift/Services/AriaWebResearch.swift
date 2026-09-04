import Foundation

/// Curated, keyless web reference lookup — local-testing/Simulator only.
///
/// Resolved from a real tradeoff, not guessed at: the user wanted ARIA, in
/// local testing, to reach the real web via the Mac's own internet access
/// so a question like "how do I lose fat and gain muscle while keeping my
/// frame" pulls in genuine outside information instead of only reflecting
/// the fake health data pack back — while never touching Forge's own
/// cloud/AWS resources, and never shipping a client-side API key (the exact
/// anti-pattern PR #154's P0 fix removed). A real open web-search API needs
/// a provider key; this is the keyless-safe alternative chosen instead: a
/// small, hand-picked set of stable, reputable reference pages, fetched
/// directly and read from — no search index, no secret, nothing that can
/// leak.
///
/// Deliberately isolated from `LocalTestingOrchestrator`, whose own doc
/// comment promises it "holds no URLSession... checkable by grep." That
/// promise is about Forge's own backend, and it stays true — the one
/// intentional exception to "no network calls anywhere in local testing"
/// lives entirely in this file, under its own name, so the invariant stays
/// real rather than just asserted in a comment the code no longer matches.
/// `scripts/check-aria-web-research.py` enforces that in CI.
///
/// `@MainActor` because its only caller, `LocalTestingOrchestrator`, already
/// is one — this costs no extra actor hop, and it's what `lookUp` needs
/// anyway to read `AriaOperatingMode.current`, itself `@MainActor` by design.
@MainActor
enum AriaWebResearch {

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        // Must never hang a reply. A slow or wedged fetch degrading to a
        // missed lookup is fine; the same fetch stalling the whole turn
        // would be exactly the kind of "ARIA feels broken" regression this
        // entire PR exists to remove.
        config.timeoutIntervalForRequest = 6
        config.timeoutIntervalForResource = 6
        return URLSession(configuration: config)
    }()

    // MARK: - Trigger

    /// Research-flavored phrasing — triggers when the human is asking for
    /// outside knowledge, not just reflecting their pack. Wired feel comes from
    /// actually reaching out here, not just templating.
    private static let researchPhrases = [
        "how do i", "how to", "best way to", "is it true", "what does the science say",
        "what does research say", "research shows", "studies show", "recomp",
        "lose fat and gain muscle", "gain muscle and lose fat", "how much protein should",
        "is it possible to", "how long does it take to", "evidence for", "evidence on",
        "should i", "do i need", "what should i eat", "what should i do",
        "is it safe to", "can i", "will it help", "does it work",
        "benefits of", "side effects", "how much sleep", "how often should",
    ]

    /// `leadingDomain` is `LocalTestingOrchestrator`'s own domain
    /// classification for the turn — reused rather than re-classified, and
    /// deliberately narrow: only the domains where an outside reference
    /// actually helps, not every message that happens to mention food.
    static func isResearchWorthy(text: String, leadingDomain: AriaLocalDomain) -> Bool {
        // Wired to every life-relevant domain — training, nutrition, progress,
        // plus sleep/recovery/lifestyle where the web actually helps a companion
        // sound connected, not just the gym domains.
        guard [.training, .nutrition, .progress, .sleep, .readiness, .lifestyle, .activity].contains(leadingDomain) else {
            return false
        }
        let lower = text.lowercased()
        return researchPhrases.contains { lower.contains($0) }
    }

    // MARK: - Sources

    /// Each URL here was chosen for stability — a long-standing government
    /// health reference, not a page likely to move or go JS-only — but
    /// could not be live-verified from this development environment, whose
    /// own network sandbox blocks general web egress by design (confirmed
    /// while building this: MedlinePlus, NIH, CDC, and even Wikipedia all
    /// came back EGRESS_BLOCKED from here). Fetch failures degrade to
    /// silence (see `lookUp`), so a stale entry costs one missed lookup,
    /// never a crash — but this table should be spot-checked from a real
    /// Mac the first time this feature is exercised, and kept small and
    /// boring on purpose so that check stays cheap.
    /// Wired but boring on purpose — stable .gov references, not JS-heavy blogs.
    /// Each domain has a primary + fallback so a single moved page doesn't
    /// make ARIA feel offline. The "wired up" feel comes from trying, not
    /// from needing to succeed — miss degrades to local generation.
    private static let sources: [AriaLocalDomain: [(title: String, url: URL)]] = [
        .training: [
            ("MedlinePlus: Exercise and Physical Fitness", URL(string: "https://medlineplus.gov/exerciseandphysicalfitness.html")!),
            ("CDC: Adult Physical Activity Guidelines", URL(string: "https://www.cdc.gov/physical-activity-basics/guidelines/adults.html")!),
        ],
        .nutrition: [
            ("NIH: Protein Fact Sheet", URL(string: "https://ods.od.nih.gov/factsheets/Protein-Consumer/")!),
            ("MedlinePlus: Healthy Diet", URL(string: "https://medlineplus.gov/healthyeating.html")!),
        ],
        .progress: [
            ("CDC: Physical Activity Guidelines", URL(string: "https://www.cdc.gov/physical-activity-basics/guidelines/adults.html")!),
            ("NIH: Benefits of Exercise", URL(string: "https://www.nih.gov/health-information/benefits-exercise")!),
        ],
        .sleep: [
            ("CDC: Sleep and Health", URL(string: "https://www.cdc.gov/sleep/about/index.html")!),
            ("MedlinePlus: Healthy Sleep", URL(string: "https://medlineplus.gov/healthysleep.html")!),
        ],
        .readiness: [
            ("MedlinePlus: Exercise and Physical Fitness", URL(string: "https://medlineplus.gov/exerciseandphysicalfitness.html")!),
            ("CDC: Sleep and Health", URL(string: "https://www.cdc.gov/sleep/about/index.html")!),
        ],
        .lifestyle: [
            ("CDC: Healthy Eating & Activity", URL(string: "https://www.cdc.gov/nutrition/index.html")!),
            ("MedlinePlus: Healthy Living", URL(string: "https://medlineplus.gov/healthy-living.html")!),
        ],
        .activity: [
            ("CDC: Adult Activity Guidelines", URL(string: "https://www.cdc.gov/physical-activity-basics/guidelines/adults.html")!),
        ],
    ]

    // MARK: - Lookup

    /// Returns a short, cited snippet, or nil on anything short of success —
    /// timeout, bad status, empty extracted text. Callers fall back to their
    /// existing local generation, exactly like `AppStore.ariaInsight`'s
    /// established contract: "Returns nil only if... callers should fall
    /// back to their existing local content."
    /// Human, wired feel: tries primary then fallback, returns a snippet that
    /// reads like a companion who checked, not a citation dump. Still keyless,
    /// still Mac-only, still local-testing-gated.
    static func lookUp(domain: AriaLocalDomain) async -> String? {
        guard AriaOperatingMode.current.isLocalTesting else { return nil }
        guard let candidates = sources[domain] else { return nil }

        for source in candidates {
            do {
                let (data, response) = try await session.data(from: source.url)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { continue }
                guard var text = extractText(from: data), !text.isEmpty else { continue }
                // Keep it companion-sized: first useful ~700 chars, not 2000
                if text.count > 750 {
                    let idx = text.index(text.startIndex, offsetBy: 750)
                    let cut = text[..<idx]
                    if let lastPeriod = cut.lastIndex(of: ".") {
                        text = String(cut[..<lastPeriod]) + "."
                    } else {
                        text = String(cut) + "…"
                    }
                }
                // Human-wired voice, blended later by the orchestrator — still cites source
                return "I checked — \(source.title) notes: \(text) — here's how that lands for you:"
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

        // Catch a few more entities that .gov pages actually use
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
        // Return first ~900 chars of readable prose — orchestrator caps to 750
        return String(collapsed.prefix(1800))
    }
}
