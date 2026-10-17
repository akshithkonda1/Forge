import Foundation

/// Condition-aware coaching constraints. Positive framing. Never diagnosis.
public enum ForgeConditionAdaptation: Sendable {

    public static func constraints(
        _ conditions: [ForgeLifestyleProfile.HealthConstraint],
        freeform: String = ""
    ) -> [String] {
        var lines: [String] = []
        for condition in conditions {
            switch condition {
            case .seizures, .epilepsy:
                lines.append("Seizure-aware: keep intensity grounded, rest windows, avoid solo high-risk work, watch sleep debt.")
            case .diabetes:
                lines.append("Blood-sugar-aware: timing and fueling reminders around the session as written.")
            case .adhd:
                lines.append("Energy-channeling: short blocks, variety, one clear next step.")
            case .anxiety, .injury, .chronic, .mobility, .other:
                lines.append(condition.saferFraming)
            }
        }
        let extra = freeform.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty {
            lines.append("They also noted: \(String(extra.prefix(160))). Adapt around that. Anything medical, a doctor.")
        }
        return lines
    }

    public static func coachLine(_ conditions: [ForgeLifestyleProfile.HealthConstraint]) -> String {
        if conditions.isEmpty { return "" }
        return "Here's what works with your body. Lifestyle coaching only. Anything medical, check with a doctor."
    }

    public static func containsDiagnosis(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.contains("diagnos") || lower.contains("you have") && lower.contains("disorder")
            || lower.contains("medical advice")
    }
}
