import Foundation

/// Fail-closed gate for text that must never leave this phone toward TTS.
///
/// Kokoro is on-device, so spoken lines do not go to a vendor. This
/// sanitizer still refuses names, emails, phones, and health-metric
/// numbers if anything tries to send a cloud payload. Qualitative
/// coaching is marked clean; `canSendToCloud` is informational only —
/// the runtime never posts TTS.
public enum AriaTTSPrivacy: Sendable {
    public static let canaryName = "AkshithKondaCanary"
    public static let canaryEmail = "akshith.canary@forge.test"
    public static let canaryHRV = "HRV 32"
    public static let canaryReadiness = "readiness 88"

    public struct Sanitized: Equatable, Sendable {
        public var text: String
        public var safe: Bool
        public var reason: String?

        public var canSendToCloud: Bool { safe && !text.isEmpty }
    }

    public static func sanitize(_ text: String, names: [String] = []) -> Sanitized {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return Sanitized(text: "", safe: false, reason: "privacy") }
        if looksLikePII(line, names: names) {
            return Sanitized(text: "", safe: false, reason: "privacy")
        }
        return Sanitized(text: line, safe: true, reason: nil)
    }

    public static func looksLikePII(_ text: String, names: [String] = []) -> Bool {
        let lower = text.lowercased()
        if text.contains("@") { return true }
        if lower.contains("hrv") && text.contains(where: \.isNumber) { return true }
        if lower.contains("readiness") && text.contains(where: \.isNumber) { return true }
        if lower.contains("bpm") { return true }
        if names.contains(where: { !$0.isEmpty && lower.contains($0.lowercased()) }) {
            return true
        }
        if lower.contains(canaryName.lowercased()) { return true }
        if lower.contains(canaryEmail.lowercased()) { return true }
        return false
    }
}
