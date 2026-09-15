import Foundation
import ForgeCore

/// Production-allowed caller of `AriaWebResearch` for training-age norms.
///
/// Other domains stay local-testing / Test-Ready only. Aging may fetch
/// curated .gov / MedlinePlus cardiorespiratory pages over the device's
/// default internet so fitness-age confidence is calibrated, not guessed.
/// Isolated here so `check-aria-web-research.py` can allow this one extra
/// call site without opening the rest of the app to live fetches.
@MainActor
enum AriaAgingNorms {
    private static var lastAttempt: Date?
    private static var inFlight = false
    private static let ttl: TimeInterval = 6 * 60 * 60
    private static let retryAfterMiss: TimeInterval = 90

    /// Pull public cardio-fitness pages and mark `AgingNorms.webConfirmed`
    /// on success. Fail-open: a timeout leaves the on-device FRIEND table.
    static func refresh(force: Bool = false) async {
        if inFlight { return }
        if !force, let last = lastAttempt {
            if AgingNorms.webConfirmed, Date().timeIntervalSince(last) < ttl { return }
            if !AgingNorms.webConfirmed, Date().timeIntervalSince(last) < retryAfterMiss { return }
        }
        inFlight = true
        defer { inFlight = false }
        lastAttempt = Date()
        let salt = UInt64(Date().timeIntervalSince1970.rounded())
        _ = await AriaWebResearch.lookUp(
            question: "VO2 max cardiorespiratory fitness training age",
            domainRawValue: "aging",
            salt: salt
        )
    }

    /// Cited snippet for an aging question, or nil on timeout / miss.
    static func citedSnippet(question: String, salt: UInt64) async -> String? {
        await AriaWebResearch.lookUp(
            question: question,
            domainRawValue: "aging",
            salt: salt
        )
    }

    static func resetForTests() {
        lastAttempt = nil
        inFlight = false
        AgingNorms.resetForTests()
    }
}
