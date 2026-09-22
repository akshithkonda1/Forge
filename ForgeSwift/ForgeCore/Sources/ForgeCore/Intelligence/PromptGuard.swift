import Foundation

/// Offline SimRunner check. Twin of `aria_core.prompt_guard`.
///
/// If Dummy has evidence and the facts replay (honesty and determinism ≥ 70),
/// it may make the claim. If it cannot, it must not make that claim or its
/// reverse — it speaks a cautious estimate. It does not error out.
public enum PromptGuard: Sendable {
    public static let connectionFailureMessage = "Couldn't reach Forge. Check your connection."
    public static let connectionFailureCode = "connection_failed"
    public static let floor: Double = 70
    public static let estimateLine =
        "I don't have a clean enough read to lock this in. A cautious estimate: keep today ordinary until more of your day is in."
    public static let estimateReason = "estimate — not enough evidence for a deterministic claim"

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

    public static func withholdsContestedClaim(_ text: String, claims: [String]) -> Bool {
        let body = normalize(text)
        return claims.allSatisfy { claim in
            let needle = normalize(claim)
            return needle.isEmpty || !body.contains(needle)
        }
    }
}
