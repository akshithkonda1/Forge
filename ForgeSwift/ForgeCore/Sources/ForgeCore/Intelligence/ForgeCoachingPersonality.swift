import Foundation

/// Teaching personality — mindset and methodology only.
///
/// Tone, framing, how setbacks are talked about, pacing, and the intensity of
/// encouragement. Never exercise mechanics, split design, or the session plan.
/// Safety and copy rules always override the preset: adult voice, coach not
/// doctor, no "recovery", no baby talk, care on sensitive topics.
public enum ForgeCoachingPersonality: Sendable {

    /// Stored in UserContext / UserProfile. Either a named preset or the user's
    /// own words (or both: free text colors a picked preset).
    public struct Choice: Codable, Equatable, Sendable {
        public var preset: Preset?
        public var freeText: String

        public static let storageKey = "forge.coaching.personality.v1"

        public init(preset: Preset? = .steadyBuilder, freeText: String = "") {
            self.preset = preset
            self.freeText = ForgeCoachingPersonality.sanitizeFreeText(freeText)
        }

        public var isCustom: Bool { !freeText.isEmpty }

        public var displayLabel: String {
            if let preset { return preset.label }
            if isCustom { return "Your words" }
            return Preset.steadyBuilder.label
        }
    }

    public enum Preset: String, Codable, CaseIterable, Sendable {
        /// Intense physical conditioning with deep mental and psychological discipline.
        case pillarTraining
        case steadyBuilder
        case directCoach
        case curiousExperimenter
        case playfulCompanion

        public var label: String {
            switch self {
            case .pillarTraining: return "Pillar Training"
            case .steadyBuilder: return "Steady builder"
            case .directCoach: return "Direct coach"
            case .curiousExperimenter: return "Curious experimenter"
            case .playfulCompanion: return "Playful companion"
            }
        }

        public var summary: String {
            switch self {
            case .pillarTraining:
                return "Intense physical conditioning with deep mental and psychological discipline. Hard days are named honestly. Never past comfort or safety. Progress is named when it is real. Mindset and methodology only — never exercise form."
            case .steadyBuilder:
                return "Calm, even pacing. Stack small honest days. Setbacks are information, not a verdict."
            case .directCoach:
                return "No-nonsense, adult, and short. Names the thing. Encouragement is respect, not volume."
            case .curiousExperimenter:
                return "Try, notice, adjust. Questions before slogans. Intensity stays curious, not theatrical."
            case .playfulCompanion:
                return "Wry, warm, still an adult. Humor that never talks down. The day stays real."
            }
        }

        /// How a missed night / skipped session is framed.
        public var setbackFrame: String {
            switch self {
            case .pillarTraining:
                return "The path doesn't vanish because one day bent. Name it, then take the next honest step."
            case .steadyBuilder:
                return "One off day is a data point. Tomorrow still stacks if you let it."
            case .directCoach:
                return "You missed it. That's the fact. What's the next session that actually fits."
            case .curiousExperimenter:
                return "What got in the way — sleep, work, stress? That's the experiment, not a failing grade."
            case .playfulCompanion:
                return "Life showed up. Fine. We pick the thread back up without a speech."
            }
        }

        public var encouragementPace: String {
            switch self {
            case .pillarTraining: return "Demand is high. Praise is scarce and earned — and when they take an honest step, name it. Never theatrical. Never past their comfort or safety."
            case .steadyBuilder: return "Low volume. Consistent. One next brick."
            case .directCoach: return "Short. Specific. No pep rally."
            case .curiousExperimenter: return "Interest over hype. Notice what worked."
            case .playfulCompanion: return "Light, dry, never cutesy. Adult company."
            }
        }
    }

    public static let adultVoiceLaw =
        "Always speak like an adult: curious and direct. Never baby talk. Never talk down."

    public static let safetyOverride =
        "Safety and copy rules override this personality: lifestyle coach, not a doctor; never say recovery; never diagnose, treat, prescribe, or cure; on anything medical, suggest a doctor; crisis and self-harm hand off to real resources. Personality never changes the training plan, split, or exercise selection. Pillar Training never pushes the person past their comfort or safety limits, and it names real progress."

    /// System / stub prompt fragment. Plan engines must not read this.
    public static func promptDirective(_ choice: Choice) -> String {
        let preset = choice.preset ?? (choice.isCustom ? nil : .steadyBuilder)
        var lines: [String] = [adultVoiceLaw, safetyOverride]
        if let preset {
            lines.append("Teaching personality: \(preset.label). \(preset.summary)")
            lines.append("Setbacks: \(preset.setbackFrame)")
            lines.append("Encouragement: \(preset.encouragementPace)")
        }
        if choice.isCustom {
            lines.append("The person described the teaching they want, in their words: \"\(choice.freeText)\". Use that for tone and framing only. Do not change exercises, splits, or the session plan to match a metaphor.")
        }
        lines.append("Do not invent chest-day / body-part splits from the personality. Training content stays whatever the plan engine already wrote.")
        return lines.joined(separator: " ")
    }

    /// Colors a setback in this personality. Mechanics stay out.
    public static func colorSetback(_ choice: Choice, whatHappened: String) -> String {
        let frame = (choice.preset ?? .steadyBuilder).setbackFrame
        let happened = whatHappened.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = happened.isEmpty ? frame : "\(happened) \(frame)"
        return sanitizeOutput(body)
    }

    /// Colors encouragement around an unchanged plan line.
    public static func colorPlanTalk(_ choice: Choice, planLine: String) -> String {
        let plan = planLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let lead: String
        switch choice.preset ?? .steadyBuilder {
        case .pillarTraining:
            lead = "The session stands. Meet it with discipline — and stop at the limit that keeps you safe. Name the progress you already made."
        case .steadyBuilder:
            lead = "Same session as written. Keep it honest and unhurried."
        case .directCoach:
            lead = "Here's the work. Do it or resize the day — don't decorate it."
        case .curiousExperimenter:
            lead = "Same session. Notice how it sits, then we'll adjust next time if we should."
        case .playfulCompanion:
            lead = "Same session, no costume. Let's get through it like adults who like each other."
        }
        let custom = choice.isCustom ? " They asked to be coached this way: \(choice.freeText)." : ""
        return sanitizeOutput("\(lead) \(plan)\(custom)")
    }

    /// Plan fingerprint — personality is intentionally unused. Same inputs,
    /// same plan, every preset.
    public static func planFingerprint(
        readiness: Int,
        workoutsThisWeek: Int,
        workoutGoal: Int
    ) -> String {
        let goal = max(1, workoutGoal)
        let done = max(0, workoutsThisWeek)
        let band: String
        if readiness >= 80 { band = "full" }
        else if readiness >= 55 { band = "steady" }
        else { band = "light" }
        return "band:\(band)|sessions:\(done)/\(goal)|lifts:compound-unchanged"
    }

    public static func containsBabyTalk(_ line: String) -> Bool {
        let lower = line.lowercased()
        let banned = [
            "good job champ", "you got this champ", "sweetie", "honey",
            "lil buddy", "little soldier", "yay you", "superstar",
            "whoopsie", "oopsie", "widdle", "pwecious",
        ]
        return banned.contains { lower.contains($0) }
    }

    public static func sanitizeFreeText(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 280 { return trimmed }
        return String(trimmed.prefix(280))
    }

    public static func sanitizeOutput(_ line: String) -> String {
        var text = line
        if ForgePersonalization.containsBannedCopy(text) {
            text = text.replacingOccurrences(of: "recovery", with: "bounce-back", options: .caseInsensitive)
            text = text.replacingOccurrences(of: "Recovery", with: "bounce-back")
        }
        return text
    }

    public static func containsBanned(_ line: String) -> Bool {
        if containsBabyTalk(line) { return true }
        if line.lowercased().contains("chest day") { return true }
        if line.lowercased().contains("soft form") { return true }
        return ForgePersonalization.containsBannedCopy(line)
    }
}
