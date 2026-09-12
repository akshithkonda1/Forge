import Foundation

/// Same words pasted again must not reprint the last ARIA line.
///
/// Copy-paste, suggested-action taps, and Device Hub re-sends often arrive as
/// the identical string. Dummy and rule replies were hashed off that string,
/// so the transcript looked canned. Occurrence + remembered fingerprints
/// rotate phrasing while `AriaPromptCorrelation` keeps the topic.
public enum AriaReplyVariety: Sendable {

    public static let defaultsKey = "forge.aria.replyVariety.v1"
    private static let promptCap = 48
    private static let recentCap = 8

    private struct Turn: Codable, Sendable {
        var count: Int
        var recent: [String]
    }

    private struct Store: Codable, Sendable {
        var order: [String]
        var turns: [String: Turn]
    }

    /// Collapse copy-paste noise (nbsp, zero-width, extra spaces) so two
    /// pasted questions count as the same prompt.
    public static func normalizePrompt(_ text: String) -> String {
        var folded = text.lowercased()
        folded = folded.replacingOccurrences(of: "\u{00a0}", with: " ")
        folded = folded.replacingOccurrences(of: "\u{200b}", with: "")
        folded = folded.replacingOccurrences(of: "\u{200c}", with: "")
        folded = folded.replacingOccurrences(of: "\u{200d}", with: "")
        folded = folded.replacingOccurrences(of: "\u{feff}", with: "")
        folded = folded.replacingOccurrences(of: "\u{2018}", with: "'")
        folded = folded.replacingOccurrences(of: "\u{2019}", with: "'")
        folded = folded.replacingOccurrences(of: "\u{201c}", with: "\"")
        folded = folded.replacingOccurrences(of: "\u{201d}", with: "\"")
        return folded
            .split { $0.isWhitespace || $0.isNewline }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func normalizeReply(_ text: String) -> String {
        normalizePrompt(text)
    }

    /// Call once per user-visible coaching turn. Returns a 1-based occurrence.
    @discardableResult
    public static func beginTurn(
        prompt: String,
        defaults: UserDefaults = .standard
    ) -> Int {
        let key = normalizePrompt(prompt)
        guard !key.isEmpty else { return 0 }
        var store = load(defaults)
        var turn = store.turns[key] ?? Turn(count: 0, recent: [])
        turn.count += 1
        store.turns[key] = turn
        touch(&store, key: key)
        save(store, defaults)
        return turn.count
    }

    public static func occurrence(
        for prompt: String,
        defaults: UserDefaults = .standard
    ) -> Int {
        let key = normalizePrompt(prompt)
        guard !key.isEmpty else { return 0 }
        return load(defaults).turns[key]?.count ?? 0
    }

    public static func salt(
        prompt: String,
        occurrence: Int,
        extra: UInt64 = 0
    ) -> UInt64 {
        let mix = extra &+ (UInt64(max(0, occurrence)) &* 0x9E37_79B9_7F4A_7C15)
        return AriaReferenceCatalog.stableMix(normalizePrompt(prompt), salt: mix)
    }

    public static func pick<T>(
        _ items: [T],
        prompt: String,
        defaults: UserDefaults = .standard
    ) -> T {
        precondition(!items.isEmpty, "AriaReplyVariety.pick needs a non-empty bank")
        let n = max(0, occurrence(for: prompt, defaults: defaults) - 1)
        return items[n % items.count]
    }

    /// Rephrase `draft` until it is not a replay of a recent reply to this prompt.
    public static func distinct(
        prompt: String,
        draft: String,
        defaults: UserDefaults = .standard
    ) -> String {
        let key = normalizePrompt(prompt)
        let grounded = AriaPromptCorrelation.grounded(prompt: prompt, draft: draft)
        guard !key.isEmpty else { return grounded }

        var store = load(defaults)
        var turn = store.turns[key] ?? Turn(count: 1, recent: [])
        let recent = Set(turn.recent)
        let candidates = variants(
            draft: grounded,
            occurrence: max(1, turn.count)
        )

        var chosen = grounded
        for candidate in candidates {
            let next = AriaPromptCorrelation.grounded(prompt: prompt, draft: candidate)
            if !recent.contains(normalizeReply(next)) {
                chosen = next
                break
            }
        }
        if recent.contains(normalizeReply(chosen)) {
            chosen = AriaPromptCorrelation.grounded(
                prompt: prompt,
                draft: "\(grounded) I'm answering that again, not replaying the last line."
            )
        }

        turn.recent.append(normalizeReply(chosen))
        if turn.recent.count > recentCap {
            turn.recent.removeFirst(turn.recent.count - recentCap)
        }
        store.turns[key] = turn
        touch(&store, key: key)
        save(store, defaults)
        return chosen
    }

    public static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }

    // MARK: - Variants

    static func variants(draft: String, occurrence: Int) -> [String] {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let rotated = rotatedSentences(trimmed, shift: max(1, occurrence))
        let extras = [
            rotated,
            "Another cut at that — \(trimmed)",
            "Still on what you asked — \(trimmed)",
            "Fresh pass: \(trimmed)",
            "Same question, new phrasing — \(trimmed)",
        ]
        return uniqueKeepingOrder([trimmed] + extras.filter { !$0.isEmpty })
    }

    static func rotatedSentences(_ text: String, shift: Int) -> String {
        let parts = text
            .split(separator: ".", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard parts.count >= 2, shift != 0 else { return text }
        let n = ((shift % parts.count) + parts.count) % parts.count
        let rotated = Array(parts[n...]) + Array(parts[..<n])
        return rotated.map { part -> String in
            if part.hasSuffix("!") || part.hasSuffix("?") { return part }
            return part + "."
        }.joined(separator: " ")
    }

    // MARK: - Persistence

    private static func uniqueKeepingOrder(_ items: [String]) -> [String] {
        var seen: [String] = []
        for item in items {
            let key = normalizeReply(item)
            if !seen.contains(where: { normalizeReply($0) == key }) {
                seen.append(item)
            }
        }
        return seen
    }

    private static func touch(_ store: inout Store, key: String) {
        store.order.removeAll { $0 == key }
        store.order.append(key)
        while store.order.count > promptCap {
            let drop = store.order.removeFirst()
            store.turns.removeValue(forKey: drop)
        }
    }

    private static func load(_ defaults: UserDefaults) -> Store {
        guard let data = defaults.data(forKey: defaultsKey),
              let store = try? JSONDecoder().decode(Store.self, from: data) else {
            return Store(order: [], turns: [:])
        }
        return store
    }

    private static func save(_ store: Store, _ defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(store) {
            defaults.set(data, forKey: defaultsKey)
        }
    }
}
