import Foundation

/// Condition-aware coaching as a first-class input.
///
/// Optional. Positive framing ("here's what works with your body").
/// Lifestyle coaching only — never diagnosis or medical advice.
/// Copy uses rest and readiness, never recovery.
public enum ForgeConditionAdaptation: Sendable {

    public enum Domain: String, CaseIterable, Sendable {
        case training, sleep, stress, mood, dayToDay
    }

    /// Training-session constraints. Applied automatically by the adaptive
    /// training model. Never framed as a limitation or a warning.
    public static func constraints(
        _ conditions: [ForgeLifestyleProfile.HealthConstraint],
        freeform: String = ""
    ) -> [String] {
        var lines: [String] = []
        var seen: Set<ForgeLifestyleProfile.HealthConstraint> = []
        for condition in conditions where seen.insert(condition).inserted {
            lines.append(trainingConstraint(condition))
        }
        let extra = freeform.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty {
            lines.append(
                "They also noted: \(String(extra.prefix(160))). Adapt around that. Anything medical, a doctor."
            )
        }
        return lines
    }

    public static func trainingConstraint(
        _ condition: ForgeLifestyleProfile.HealthConstraint
    ) -> String {
        switch condition {
        case .seizures, .epilepsy:
            return "Here's what works with your body: seizure-aware intensity ceiling, predictable rest windows, skip solo high-risk work, and sleep-deprivation awareness. Lifestyle coaching only."
        case .diabetes:
            return "Here's what works with your body: blood-sugar-aware timing and fueling reminders around the session as written. Lifestyle coaching only."
        case .adhd:
            return "Here's what works with your body: energy-channeling structure — short blocks, variety, one clear next step. Lifestyle coaching only."
        case .anxiety, .injury, .chronic, .mobility, .other:
            return condition.saferFraming
        }
    }

    /// Sleep, stress, mood, and day-to-day coaching using the same context.
    public static func line(
        domain: Domain,
        conditions: [ForgeLifestyleProfile.HealthConstraint],
        freeform: String = ""
    ) -> String {
        let extra = freeform.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !conditions.isEmpty || !extra.isEmpty else { return "" }
        var bits: [String] = []
        var seen: Set<ForgeLifestyleProfile.HealthConstraint> = []
        for condition in conditions where seen.insert(condition).inserted {
            bits.append(domainLine(domain, condition))
        }
        if !extra.isEmpty {
            bits.append("Adapt around what they wrote: \(String(extra.prefix(80))).")
        }
        bits.append("Lifestyle coaching only. Anything medical, check with a doctor.")
        return bits.joined(separator: " ")
    }

    /// Sleep / stress / mood / day-to-day — training is `constraints(_:)`.
    public static func coachingAcrossLife(
        _ conditions: [ForgeLifestyleProfile.HealthConstraint],
        freeform: String = ""
    ) -> [String] {
        [Domain.sleep, .stress, .mood, .dayToDay].compactMap { domain in
            let text = line(domain: domain, conditions: conditions, freeform: freeform)
            return text.isEmpty ? nil : text
        }
    }

    public static func coachLine(_ conditions: [ForgeLifestyleProfile.HealthConstraint]) -> String {
        if conditions.isEmpty { return "" }
        return "Here's what works with your body. Lifestyle coaching only. Anything medical, check with a doctor."
    }

    /// Layer condition constraints onto the adaptive training model copy.
    public static func applyToTrainingModel(
        _ model: String,
        conditions: [ForgeLifestyleProfile.HealthConstraint],
        freeform: String = ""
    ) -> String {
        let extra = constraints(conditions, freeform: freeform)
        let body = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if extra.isEmpty { return body }
        let prefix = body.isEmpty ? "" : body + " "
        let doctor = coachLine(conditions)
        let joined = extra.joined(separator: " ")
        if doctor.isEmpty { return prefix + joined }
        return prefix + joined + " " + doctor
    }

    public static func containsDiagnosis(_ line: String) -> Bool {
        let lower = line.lowercased()
        if lower.contains("medical advice") { return true }
        if lower.contains("diagnos") { return true }
        if lower.contains("you have") && lower.contains("disorder") { return true }
        if lower.contains("prescrib") { return true }
        if lower.contains("you should take") { return true }
        return false
    }

    public static func containsRecovery(_ line: String) -> Bool {
        line.lowercased().contains("recovery")
    }

    /// Solo or extreme names the epilepsy constraint should not surface first.
    public static func isSoloHighRisk(_ name: String) -> Bool {
        let lower = name.lowercased()
        let tokens = [
            "hang clean", "snatch", "clean and jerk", "muscle-up",
            "handstand", "box jump", "battle rope", "slam", "rope climb",
        ]
        return tokens.contains { lower.contains($0) }
    }

    private static func domainLine(
        _ domain: Domain,
        _ condition: ForgeLifestyleProfile.HealthConstraint
    ) -> String {
        switch (domain, condition) {
        case (.training, _):
            return trainingConstraint(condition)
        case (.sleep, .seizures), (.sleep, .epilepsy):
            return "Sleep-deprivation awareness: protect rest windows so the next day has a grounded intensity ceiling."
        case (.sleep, .diabetes):
            return "Sleep timing that leaves room for fueling reminders around the morning session."
        case (.sleep, .adhd):
            return "A short, clear wind-down next step. Variety over a long ritual."
        case (.sleep, _):
            return "Honest sleep and rest windows. Here's what works with your body."
        case (.stress, .seizures), (.stress, .epilepsy):
            return "Keep the day grounded. Rest windows over stacking load."
        case (.stress, .diabetes):
            return "Steady timing and fueling. No rush, no lecture."
        case (.stress, .adhd):
            return "Channel the energy: one short block, then the next step."
        case (.stress, _):
            return "Here's what works with your body on a tense day: smaller, clearer moves."
        case (.mood, .seizures), (.mood, .epilepsy):
            return "Mood follows rest and sleep more than grind. Grounded intensity still applies."
        case (.mood, .diabetes):
            return "Mood coaching stays with timing and fueling, never a clinical read."
        case (.mood, .adhd):
            return "Mood gets a clear next step and a short block — not a lecture."
        case (.mood, _):
            return "Here's what works with your body today. Coach, not clinician."
        case (.dayToDay, .seizures), (.dayToDay, .epilepsy):
            return "Day-to-day: skip solo high-risk, keep rest windows, watch sleep debt."
        case (.dayToDay, .diabetes):
            return "Day-to-day: blood-sugar-aware timing and fueling reminders as written."
        case (.dayToDay, .adhd):
            return "Day-to-day: short blocks, variety, one clear next step."
        case (.dayToDay, _):
            return "Day-to-day coaching adapts around what they told us."
        }
    }
}
