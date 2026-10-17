import Foundation

/// Ingest filter: store health and lifestyle context only.
public enum AriaHealthFilter: Sendable {

    public static let healthTerms = [
        "sleep", "dream", "hobby", "people", "goal", "mood", "stress",
        "workout", "train", "eat", "food", "nutrition", "water", "rest",
        "readiness", "routine", "epilep", "seizure", "adhd", "diabetes",
        "blood sugar", "night", "walk", "stretch",
    ]

    public static let offDomain = [
        "looking for a job", "job hunting", "career change", "resume",
        "promotion at work", "quit my job",
    ]

    public enum Decision: Equatable, Sendable {
        case store(AriaContextMemory.Domain)
        case storeHealthAngle(AriaContextMemory.Domain, excerpt: String)
        case skip
    }

    public static func decide(_ text: String) -> Decision {
        let lower = text.lowercased()
        let off = offDomain.contains { lower.contains($0) }
        let healthHit = healthTerms.contains { lower.contains($0) }
        if off && !healthHit {
            return .skip
        }
        if off && healthHit {
            let angle: String
            if lower.contains("sleep") {
                angle = "Sleep is taking a hit from work stress."
            } else if lower.contains("stress") {
                angle = "Work stress is showing up in the body."
            } else {
                angle = "Stress load is the health angle — not the career plan."
            }
            return .storeHealthAngle(.moodMentality, excerpt: angle)
        }
        return .store(AriaContextMemory.classify(text))
    }
}
