import Foundation

// MARK: - Sleep copy bar
//
// Shared lifestyle-coach phrases. Clinical / recovery / "owe" wording stays
// out of the UI. Does not touch readiness scoring (PR #449).

public enum SleepCoachCopy {
    public static let medicalLine = "Worth running anything medical past your doctor first."
    public static let disclaimer = "Lifestyle coaching from your nights. \(medicalLine)"
    public static let stillLearning = "ARIA is still learning your rhythm — a few more nights and tonight's bedtime gets personal."
    public static let dimRoomCue = "Lights and screens down. A bright kitchen keeps the day going."
    public static let environmentHint = "A photo of the room helps ARIA notice light and clutter."

    public static let bannedPhrases = [
        "recovery week", "Adaptive Recovery", "insomnia", "disorder", "diagnosis",
        "not a doctor", "abnormal", "outside your range", "should have",
        "failed", "paying for", "never leaves your phone",
    ]

    /// Standalone "recovery" is banned in public sleep copy; code identifiers may keep it.
    public static func containsBannedPhrase(_ line: String) -> String? {
        let lower = line.lowercased()
        if let hit = bannedPhrases.first(where: { lower.contains($0.lowercased()) }) {
            return hit
        }
        if lower.contains("recovery") {
            return "recovery"
        }
        return nil
    }
}
