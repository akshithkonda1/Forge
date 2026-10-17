import Foundation

/// Calm 503 aria_paused handling. The rest of the app keeps working.
public enum AriaPaused: Sendable {
    public static let code = "aria_paused"
    public static let status = 503
    public static let line = "ARIA is taking a break."
    public static let tutorialLine = ForgeTutorial.pausedLine
    public static let onboardingLine =
        "ARIA is taking a break. You can keep going, or Skip — the rest of Forge still works."
    public static let switcherLine =
        "ARIA is taking a break. Personality will apply on the next reply."

    public static func isPaused(status: Int, code: String?) -> Bool {
        status == 503 && (code == nil || code == Self.code)
    }
}
