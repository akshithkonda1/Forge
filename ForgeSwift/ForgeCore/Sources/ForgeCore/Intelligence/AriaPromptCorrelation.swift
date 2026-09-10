import Foundation

/// Every ARIA turn must answer the sentence that just arrived.
///
/// Tabs, pins, calendar ingest, and leftover session affinity are context.
/// They may shape *how* a matching specialist answers. They must not swap
/// the topic. A Workout pin plus "what's my quality of life" is a QoL turn.
/// A Lifestyle pin plus "what should I train" is a training turn.
public enum AriaPromptCorrelation: Sendable {

    /// Domains the prompt itself named. Body data, pins, and calendar tags
    /// are ignored so a tuxedo question cannot become a session because
    /// readiness is 40.
    public static func askedDomains(in text: String) -> [AriaIntentDomain] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let lower = trimmed.lowercased()
        var asked: [AriaIntentDomain] = []

        func add(_ domain: AriaIntentDomain) {
            if !asked.contains(domain) { asked.append(domain) }
        }

        if QualityOfLifeLivingStore.isQuestion(trimmed) { add(.lifestyle) }
        if AriaReferenceCatalog.questionSuggestsEventPrep(trimmed) { add(.lifestyle) }
        if calendarAsk(lower) { add(.lifestyle) }
        if boardAsk(lower) { add(.progress) }
        // Language the prompt named, even when a louder phrase (train + slept)
        // would otherwise push eat/food below AriaIntentResolver's relative floor.
        if sleepAsk(lower) { add(.sleep) }
        if trainingAsk(lower) { add(.training) }
        if nutritionAsk(lower) { add(.nutrition) }

        let ranked = AriaIntentResolver.rank(AriaIntentInput(text: trimmed))
        for domain in AriaIntentResolver.actionable(ranked, limit: 4) {
            let score = ranked.first(where: { $0.domain == domain })?.score ?? 0
            if domain == .lifestyle, score < 2, !QualityOfLifeLivingStore.isQuestion(trimmed),
               !AriaReferenceCatalog.questionSuggestsEventPrep(trimmed), !calendarAsk(lower) {
                continue
            }
            add(domain)
        }

        if AriaReferenceCatalog.questionSuggestsEventPrep(trimmed), !trainingAsk(lower) {
            asked.removeAll { $0 == .training }
        }
        return asked
    }

    /// Drop specialists the sentence did not invite. Vague prompts keep a
    /// single leading domain so a pin or tab can still flavor "hey".
    public static func filterDomains(
        _ domains: [AriaIntentDomain],
        toPrompt text: String
    ) -> [AriaIntentDomain] {
        let asked = askedDomains(in: text)
        if asked.isEmpty {
            return [.lifestyle]
        }
        let kept = domains.filter { asked.contains($0) }
        return kept.isEmpty ? asked : kept
    }

    /// Stems from the prompt that a correlated reply should still contain.
    public static func requiredMentions(in text: String) -> [String] {
        let lower = text.lowercased()
        let stems = [
            "sleep", "slept", "train", "workout", "eat", "food", "protein",
            "water", "calendar", "wedding", "tuxedo", "tux", "qol",
            "quality of life", "knee", "shoulder", "progress", "cycle",
            "period", "wear", "suit",
        ]
        return stems.filter { lower.contains($0) }
    }

    public static func correlates(reply: String, toPrompt text: String) -> Bool {
        let mentions = requiredMentions(in: text)
        if mentions.isEmpty { return true }
        let lower = reply.lowercased()
        return mentions.contains { lower.contains($0) }
    }

    /// Pack-story color is for greetings and "how am I", not a specific ask.
    public static func allowsUnpromptedLifeStory(_ text: String) -> Bool {
        if !requiredMentions(in: text).isEmpty { return false }
        let lower = text.lowercased()
        let greetings = ["hey", "hi ", "hello", "what's up", "whats up", "how am i", "how do i feel"]
        if greetings.contains(where: { lower.contains($0) }) { return true }
        return lower.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).count <= 3
    }

    public static func grounded(prompt: String, draft: String) -> String {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if correlates(reply: trimmed, toPrompt: prompt) { return trimmed }
        if QualityOfLifeLivingStore.isQuestion(prompt) {
            return QualityOfLifeLivingStore.coachingLine(
                variety: AriaReplyVariety.occurrence(for: prompt)
            )
        }
        if trimmed.isEmpty {
            return "I heard you — \(prompt.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        return trimmed
    }

    // MARK: - Cues

    public static func trainingAsk(_ lower: String) -> Bool {
        ["train", "workout", "session", "lift", "gym", "exercise"].contains { lower.contains($0) }
    }

    public static func sleepAsk(_ lower: String) -> Bool {
        ["sleep", "slept", "insomnia", "bedtime", "nap"].contains { lower.contains($0) }
    }

    public static func nutritionAsk(_ lower: String) -> Bool {
        ["eat", "food", "protein", "meal", "calorie", "hydrat"].contains { lower.contains($0) }
    }

    public static func calendarAsk(_ lower: String) -> Bool {
        lower.contains("calendar")
            || lower.contains("this week")
            || lower.contains("what's coming up")
            || lower.contains("whats coming up")
            || (lower.contains("week") && (lower.contains("busy") || lower.contains("on my")))
    }

    public static func boardAsk(_ lower: String) -> Bool {
        lower.contains("on my board") || lower.contains("what's on my board") || lower.contains("whats on my board")
    }
}
