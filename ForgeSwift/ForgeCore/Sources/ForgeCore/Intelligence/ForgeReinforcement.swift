import Foundation

/// Misses are problems to solve together, never the person doing it wrong.
public enum ForgeReinforcement: Sendable {

    public static let blamePhrases = [
        "you failed", "you did it wrong", "you messed up", "that's on you",
        "you skipped again", "you broke the streak", "your fault",
    ]

    public static func containsBlame(_ line: String) -> Bool {
        let lower = line.lowercased()
        return blamePhrases.contains { lower.contains($0) }
    }

    public static func reframe(whatHappened: String) -> String {
        let happened = whatHappened.trimmingCharacters(in: .whitespacesAndNewlines)
        let lead = "Here's what we can do to help and solve it."
        if happened.isEmpty { return lead }
        return "\(happened) \(lead)"
    }
}
