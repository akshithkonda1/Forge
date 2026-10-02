import Foundation

// ============================================================
// MARK: - Life Context text helpers
// ============================================================
//
// Privacy contract
// ----------------
// What ARIA / the backend sees: nothing from this file. These helpers turn
// text into lowercase word runs so the Reminders classifier and the Messages
// engine can match Forge's own fixed vocabulary against it.
// What stays on-device: the text itself, and only for the duration of one
// call. Nothing here stores, logs, or returns the input; the only outputs are
// booleans and words that were already in the caller's hands.

/// Word-level matching shared by `RemindersClassifier` and
/// `MessageContextEngine`. Internal on purpose: no code outside ForgeCore needs
/// a raw-text helper, and every one of them is a place text could leak from.
enum LifeContextText {

    private static let posix = Locale(identifier: "en_US_POSIX")

    /// Lowercased, diacritic-folded words. Curly apostrophes are straightened
    /// and kept inside words ("i'll", "can't", "doctor's"); every other
    /// character that is not an ASCII letter or digit separates words. Hyphens
    /// separate too, so lexicon phrases are written "check up", "co worker".
    static func words(_ text: String) -> [String] {
        let folded = text
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: posix)
            .lowercased()
        var out: [String] = []
        var current = ""
        for character in folded {
            if character.isASCII, character.isLetter || character.isNumber || character == "'" {
                current.append(character)
            } else if !current.isEmpty {
                appendTrimmed(current, to: &out)
                current = ""
            }
        }
        if !current.isEmpty { appendTrimmed(current, to: &out) }
        return out
    }

    /// `words` joined by single spaces and padded with one space each side, so
    /// `contains(padded, phrase)` is a whole-word, whole-phrase test.
    static func padded(_ text: String) -> String {
        " " + words(text).joined(separator: " ") + " "
    }

    /// Whole-phrase test against a `padded` string. `phrase` must already be in
    /// `words` form: lowercase, single spaces, no punctuation but apostrophes.
    static func contains(_ padded: String, _ phrase: String) -> Bool {
        padded.contains(" " + phrase + " ")
    }

    /// The first phrase (in list order) present in `padded`.
    static func firstMatch(_ padded: String, in phrases: [String]) -> String? {
        phrases.first { contains(padded, $0) }
    }

    /// How many distinct phrases from `phrases` appear in `padded`.
    static func matchCount(_ padded: String, in phrases: [String]) -> Int {
        phrases.reduce(0) { $0 + (contains(padded, $1) ? 1 : 0) }
    }

    /// True when `output` repeats more than `maxWords` consecutive words from
    /// any of `sources`. The engine runs this on every summary it writes, so
    /// "no verbatim message text" is enforced in code, not only in tests.
    static func repeatsVerbatim(_ output: String, from sources: [String], maxWords: Int = 4) -> Bool {
        let window = maxWords + 1
        let outputWords = words(output)
        guard outputWords.count >= window else { return false }
        let haystack = " " + outputWords.joined(separator: " ") + " "
        for source in sources {
            let sourceWords = words(source)
            guard sourceWords.count >= window else { continue }
            for start in 0...(sourceWords.count - window) {
                let run = " " + sourceWords[start..<(start + window)].joined(separator: " ") + " "
                if haystack.contains(run) { return true }
            }
        }
        return false
    }

    private static func appendTrimmed(_ word: String, to out: inout [String]) {
        let trimmed = word.trimmingCharacters(in: CharacterSet(charactersIn: "'"))
        if !trimmed.isEmpty { out.append(trimmed) }
    }
}
