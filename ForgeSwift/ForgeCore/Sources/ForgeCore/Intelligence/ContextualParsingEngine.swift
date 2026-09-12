import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

// ============================================================
// MARK: - Turning raw text into whole words worth matching on
// ============================================================

/// Shared word-matching used everywhere ARIA decides what a message is about:
/// `AriaCoachAgentRouter` and `AriaDummyTurn` on the phone, `AriaIntentResolver`
/// here in ForgeCore. All three used to ask the same fragile question — "does
/// this substring appear anywhere in the raw text" — which fails in two
/// opposite directions at once:
///
/// - A short needle like `"rest"` or `"nap"` fires inside `"restaurant"` or
///   `"napkin"`, words that have nothing to do with sleep. `"sex"` firing
///   inside `"exercise"` was already worth a hand-rolled whole-word check in
///   `AriaCoachAgent.swift`; every other needle list had the same exposure
///   with no guard at all.
/// - A single typo drops a message out of every needle list with zero
///   signal — `"sleeep"` matches nothing, so a real sleep question silently
///   becomes generalist small talk instead of routing correctly. Plain
///   `.contains` has no notion of "close enough".
///
/// This engine answers "is this word actually said" instead: tokenize, then
/// accept an exact hit, a shared dictionary lemma (so "sleeping"/"slept"
/// converge on "sleep" the same way a person reads them), a small
/// same-length-class typo, or — for a few needle lists that lean on
/// deliberately truncated stems like `"ovulat"` or `"hydrat"` to catch every
/// inflection of a word without listing each one — a prefix match bounded to
/// a plausible inflectional ending, not an arbitrary continuation.
///
/// NaturalLanguage is Apple-only, so lemma lookup sits behind
/// `#if canImport(NaturalLanguage)`, same as `SecureStore.swift` gates the
/// Keychain behind `#if canImport(Security)`. `AriaIntentInput`'s own doc
/// comment says this package is meant to stay testable on Linux; the
/// fallback tokenizer keeps that true; the lemma branch is simply a no-op
/// there; the exact/fuzzy/prefix checks — which is where the false-positive
/// fixes above actually live — do not depend on it at all.
public enum ContextualParsingEngine {

    /// A lowercased word from the input, with its dictionary base form where
    /// one is available. `lemma == text` wherever a real lemma could not be
    /// found (rare tokens, or the non-Apple fallback path) — comparisons
    /// against it then degrade to a same-word check rather than misfiring.
    public struct Token: Equatable {
        public let text: String
        public let lemma: String
    }

    // ------------------------------------------------------------
    // MARK: Tokenizing
    // ------------------------------------------------------------

    /// Letter-run tokens, lowercased, punctuation and whitespace dropped.
    public static func tokenize(_ text: String) -> [Token] {
        #if canImport(NaturalLanguage)
        return naturalLanguageTokenize(text)
        #else
        return plainTokenize(text)
        #endif
    }

    #if canImport(NaturalLanguage)
    private static func naturalLanguageTokenize(_ text: String) -> [Token] {
        guard !text.isEmpty else { return [] }
        var tokens: [Token] = []
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = text
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .lemma,
            options: [.omitPunctuation, .omitWhitespace, .omitOther]
        ) { tag, range in
            let word = text[range].lowercased()
            guard word.contains(where: { $0.isLetter }) else { return true }
            let lemma = tag?.rawValue.lowercased()
            tokens.append(Token(text: word, lemma: (lemma?.isEmpty == false) ? lemma! : word))
            return true
        }
        return tokens
    }
    #endif

    /// Portable fallback: a maximal run of Unicode letters is one token, its
    /// own lemma. Same rule `AriaMessageTokens.containsAnyWord` used to apply
    /// only to the cycle/sex needles — generalized here for every needle.
    private static func plainTokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var current = ""
        func flush() {
            guard !current.isEmpty else { return }
            let word = current.lowercased()
            tokens.append(Token(text: word, lemma: word))
            current.removeAll(keepingCapacity: true)
        }
        for ch in text {
            if ch.isLetter { current.append(ch) } else { flush() }
        }
        flush()
        return tokens
    }

    // ------------------------------------------------------------
    // MARK: Matching
    // ------------------------------------------------------------

    /// A few common inflectional endings a truncated stem needle (`"ovulat"`,
    /// `"hydrat"`, `"recover"`) is allowed to complete into. Deliberately
    /// short: this is what separates "hydrat" + "ing" (a real inflection)
    /// from "nap" + "kin" (an unrelated word that happens to start the same
    /// way), which a bare prefix check cannot tell apart on its own.
    private static let inflectionalSuffixes: Set<String> = [
        "ing", "ion", "ions", "ers", "ors", "able", "ment",
    ]

    /// How many single-character edits ("sleeep" → "sleep" is one insertion)
    /// a needle of this length tolerates before it stops being "the same
    /// word, mistyped" and starts being "a different, shorter word". Needles
    /// of 4 letters or fewer get none at all — at that length almost any
    /// single edit lands on a real, different word ("rest"/"test"), so fuzzy
    /// matching there would trade one false-positive class for another.
    private static func maxTypoDistance(forNeedleLength length: Int) -> Int {
        switch length {
        case ...4: return 0
        case 5...7: return 1
        default: return 2
        }
    }

    /// Bounded Levenshtein distance — the classic single-row DP, nothing
    /// fancier. Needle lists here run a few dozen words at most per message,
    /// so there is no case for a faster algorithm.
    private static func editDistance(_ a: String, _ b: String) -> Int {
        if a == b { return 0 }
        let aChars = Array(a)
        let bChars = Array(b)
        var previous = Array(0...bChars.count)
        for (i, ca) in aChars.enumerated() {
            var current = [i + 1] + Array(repeating: 0, count: bChars.count)
            for (j, cb) in bChars.enumerated() {
                let cost = (ca == cb) ? 0 : 1
                current[j + 1] = min(
                    previous[j + 1] + 1,   // deletion
                    current[j] + 1,        // insertion
                    previous[j] + cost     // substitution
                )
            }
            previous = current
        }
        return previous[bChars.count]
    }

    /// Whether `token` is close enough to `needle` to count as the same word:
    /// exact, a shared lemma, a bounded-length prefix ending in a plausible
    /// inflection, or a small typo.
    private static func tokenMatches(_ token: Token, needle: String, needleLemma: String) -> Bool {
        if token.text == needle { return true }
        if token.lemma == needle || token.lemma == needleLemma { return true }
        if token.text.hasPrefix(needle) {
            let leftover = token.text.dropFirst(needle.count)
            if leftover.count <= 2 { return true }
            if leftover.count <= 4, inflectionalSuffixes.contains(String(leftover)) { return true }
        }
        let tolerance = maxTypoDistance(forNeedleLength: needle.count)
        if tolerance > 0, abs(token.text.count - needle.count) <= tolerance,
           editDistance(token.text, needle) <= tolerance {
            return true
        }
        return false
    }

    /// A single-word needle, matched whole-word against `text` (exact, lemma,
    /// bounded prefix, or small typo — see `tokenMatches`). Multi-word needles
    /// always return `false` here; use `containsPhrase` or let `matches`
    /// dispatch for you.
    public static func containsWord(_ text: String, _ needle: String) -> Bool {
        let needle = needle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty, !needle.contains(" ") else { return false }
        let needleLemma = tokenize(needle).first?.lemma ?? needle
        return tokenize(text).contains { tokenMatches($0, needle: needle, needleLemma: needleLemma) }
    }

    /// A multi-word needle, matched as a whole-word-boundary substring —
    /// still anchored so `" pr "`-style manual padding is unnecessary, but
    /// not fuzzy: a wrong phrase reads as a different intent far more easily
    /// than a wrong single word does, so this stays exact past the boundary
    /// fix. Falls back to a single-word `containsWord` when `phrase` turns
    /// out not to have a space in it, so callers never need to check first.
    public static func containsPhrase(_ text: String, _ phrase: String) -> Bool {
        let phrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !phrase.isEmpty else { return false }
        guard phrase.contains(" ") else { return containsWord(text, phrase) }
        let escaped = NSRegularExpression.escapedPattern(for: phrase)
        guard let regex = try? NSRegularExpression(pattern: "\\b\(escaped)\\b", options: .caseInsensitive) else {
            return text.lowercased().contains(phrase)
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    /// Drop-in replacement for `needles.contains { text.contains($0) }` —
    /// dispatches each needle to `containsWord` or `containsPhrase` by
    /// whether it has a space in it.
    public static func matches(_ text: String, _ needle: String) -> Bool {
        needle.contains(" ") ? containsPhrase(text, needle) : containsWord(text, needle)
    }

    public static func matchesAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { matches(text, $0) }
    }

    // ------------------------------------------------------------
    // MARK: Clause splitting
    // ------------------------------------------------------------

    /// Split a run-on into clause-sized pieces on `|`, em/en-dash, `;`,
    /// commas, and the literal connectives "and"/"then"/"also". Commas were
    /// the gap: "I slept badly, want to hit the gym" had no dash, semicolon,
    /// or connective word to split on before this, so it always reached
    /// clause-aware callers as a single unsplit blob. Pure splitting only —
    /// deciding whether a piece is worth keeping (does it actually name an
    /// intent) is the caller's vocabulary, not this engine's, so that stays
    /// with each call site (`AriaDummyTurn.clauses`, for one).
    public static func splitClauses(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let normalized = trimmed
            .replacingOccurrences(of: "—", with: " | ")
            .replacingOccurrences(of: "–", with: " | ")
            .replacingOccurrences(of: ";", with: " | ")
            .replacingOccurrences(of: ",", with: " | ")
        guard let regex = try? NSRegularExpression(
            pattern: #"\s*(?:\||\band\b|\bthen\b|\balso\b)\s*"#,
            options: .caseInsensitive
        ) else {
            return [trimmed]
        }
        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        var parts: [String] = []
        var last = normalized.startIndex
        for match in regex.matches(in: normalized, options: [], range: range) {
            guard let matchRange = Range(match.range, in: normalized) else { continue }
            let piece = String(normalized[last..<matchRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { parts.append(piece) }
            last = matchRange.upperBound
        }
        let tail = String(normalized[last...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { parts.append(tail) }
        return parts.isEmpty ? [trimmed] : parts
    }
}
