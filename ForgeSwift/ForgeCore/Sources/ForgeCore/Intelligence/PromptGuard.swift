import Foundation

/// Offline same-prompt replay check. Twin of `aria_core.prompt_guard`.
///
/// Dummy generates a turn twice with the same occurrence/seed. If the two
/// spoken answers disagree, the turn is killed and the app shows a
/// connection failure — never a wobbly coach line.
public enum PromptGuard: Sendable {
    public static let connectionFailureMessage = "Couldn't reach Forge. Check your connection."
    public static let connectionFailureCode = "connection_failed"

    public static func normalize(_ text: String?) -> String {
        (text ?? "")
            .lowercased()
            .split { $0.isWhitespace || $0.isNewline }
            .joined(separator: " ")
    }

    public static func fingerprint(
        message: String,
        recommendation: String? = nil,
        responseType: String = ""
    ) -> String {
        [normalize(responseType), normalize(recommendation), normalize(message)]
            .joined(separator: "\u{1e}")
    }

    public static func consistent(
        firstMessage: String,
        secondMessage: String,
        firstRecommendation: String? = nil,
        secondRecommendation: String? = nil
    ) -> Bool {
        fingerprint(message: firstMessage, recommendation: firstRecommendation)
            == fingerprint(message: secondMessage, recommendation: secondRecommendation)
    }
}
