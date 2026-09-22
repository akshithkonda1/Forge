import Foundation

/// Offline SimRunner gate. Twin of `aria_core.prompt_guard`.
///
/// Dummy may speak only when it can be honest *and* deterministic. Either
/// score below 70 kills the turn — the app shows a connection failure and
/// ARIA does not say the line. Wording may move; facts (type +
/// recommendation) must hold. Quality axes like context utilization do not
/// kill a live prompt.
public enum PromptGuard: Sendable {
    public static let connectionFailureMessage = "Couldn't reach Forge. Check your connection."
    public static let connectionFailureCode = "connection_failed"
    public static let floor: Double = 70

    public static func normalize(_ text: String?) -> String {
        (text ?? "")
            .lowercased()
            .split { $0.isWhitespace || $0.isNewline }
            .joined(separator: " ")
    }

    public static func fingerprint(
        recommendation: String? = nil,
        responseType: String? = nil
    ) -> String {
        [normalize(responseType), normalize(recommendation)]
            .joined(separator: "\u{1e}")
    }

    public static func consistent(
        firstRecommendation: String? = nil,
        secondRecommendation: String? = nil,
        firstResponseType: String? = nil,
        secondResponseType: String? = nil
    ) -> Bool {
        fingerprint(recommendation: firstRecommendation, responseType: firstResponseType)
            == fingerprint(recommendation: secondRecommendation, responseType: secondResponseType)
    }

    public static func honestyScore(confidence: Double?, honesty: Double? = nil) -> Double {
        if let honesty {
            return min(100, max(0, honesty))
        }
        // Confidence is not a SimRunner honesty score. A Dummy turn without
        // an evaluator number is allowed to speak; the live kill is honesty
        // < 70 or a fact replay that cannot hold.
        return 80
    }

    public static func honest(confidence: Double?, honesty: Double? = nil) -> Bool {
        honestyScore(confidence: confidence, honesty: honesty) >= floor
    }

    public static func determinismScore(
        firstRecommendation: String? = nil,
        secondRecommendation: String? = nil,
        firstResponseType: String? = nil,
        secondResponseType: String? = nil
    ) -> Double {
        consistent(
            firstRecommendation: firstRecommendation,
            secondRecommendation: secondRecommendation,
            firstResponseType: firstResponseType,
            secondResponseType: secondResponseType
        ) ? 100 : 0
    }

    public static func passes(
        firstRecommendation: String? = nil,
        secondRecommendation: String? = nil,
        firstResponseType: String? = nil,
        secondResponseType: String? = nil,
        firstConfidence: Double? = nil,
        secondConfidence: Double? = nil,
        firstHonesty: Double? = nil,
        secondHonesty: Double? = nil
    ) -> Bool {
        guard honest(confidence: firstConfidence, honesty: firstHonesty) else { return false }
        guard honest(confidence: secondConfidence, honesty: secondHonesty) else { return false }
        return determinismScore(
            firstRecommendation: firstRecommendation,
            secondRecommendation: secondRecommendation,
            firstResponseType: firstResponseType,
            secondResponseType: secondResponseType
        ) >= floor
    }
}
