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

    /// Research-flavored phrasing — "how do I", "is it true", "the science
    /// on" — not every message that happens to touch training or food.
    /// Same shape as `AriaIntentResolver`'s own phrase tables: literal
    /// substrings, not a classifier.
    private static let researchPhrases = [
        "how do i", "how to", "best way to", "is it true", "what does the science say",
        "what does research say", "research shows", "studies show", "recomp",
        "lose fat and gain muscle", "gain muscle and lose fat", "how much protein should",
        "is it possible to", "how long does it take to", "evidence for", "evidence on",
    ]

    /// `leadingDomain` is `LocalTestingOrchestrator`'s own domain
    /// classification for the turn — reused rather than re-classified, and
    /// deliberately narrow: only the domains where an outside reference
    /// actually helps, not every message that happens to mention food.
    static func isResearchWorthy(text: String, leadingDomain: AriaLocalDomain) -> Bool {
        guard leadingDomain == .training || leadingDomain == .nutrition || leadingDomain == .progress else {
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
    private static let sources: [AriaLocalDomain: [(title: String, url: URL)]] = [
        .training: [
            (
                "MedlinePlus: Exercise and Physical Fitness",
                URL(string: "https://medlineplus.gov/exerciseandphysicalfitness.html")!
            ),
        ],
        .nutrition: [
            (
                "NIH Office of Dietary Supplements: Protein",
                URL(string: "https://ods.od.nih.gov/factsheets/Protein-Consumer/")!
            ),
        ],
        .progress: [
            (
                "CDC: Physical Activity Guidelines for Adults",
                URL(string: "https://www.cdc.gov/physical-activity-basics/guidelines/adults.html")!
            ),
        ],
    ]

    // MARK: - Lookup

    /// Returns a short, cited snippet, or nil on anything short of success —
    /// timeout, bad status, empty extracted text. Callers fall back to their
    /// existing local generation, exactly like `AppStore.ariaInsight`'s
    /// established contract: "Returns nil only if... callers should fall
    /// back to their existing local content."
    static func lookUp(domain: AriaLocalDomain) async -> String? {
        // Structurally redundant today — the only call site already sits
        // inside `LocalTestingOrchestrator`, itself only ever reached when
        // `AriaOperatingMode.current.isLocalTesting` (see AriaService.swift)
        // — but kept as a hard gate here anyway: a future call site added
        // anywhere else must not silently turn this into a live-backend
        // network-egress surface.
        guard AriaOperatingMode.current.isLocalTesting else { return nil }
        guard let candidates = sources[domain], let source = candidates.first else { return nil }

        do {
            let (data, response) = try await session.data(from: source.url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            guard let text = extractText(from: data), !text.isEmpty else { return nil }
            return "From \(source.title): \(text)"
        } catch {
            return nil
        }
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

        let collapsed = stripped
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(2000))
    }
}
