import Foundation

/// Adaptive training model — mindset and methodology only.
///
/// The person describes their training style in their own words. Forge and
/// ARIA coach against that description. Never exercise mechanics, split
/// design, or the session plan. Safety and copy rules always override:
/// adult voice, coach not doctor, no "recovery", never past comfort or
/// safety, name real progress.
public enum ForgeCoachingPersonality: Sendable {

    /// Stored in UserContext / UserProfile. `freeText` is the adaptive
    /// training model. Optional named tones are secondary, never branded
    /// characters.
    public struct Choice: Codable, Equatable, Sendable {
        public var preset: Preset?
        public var freeText: String

        public static let storageKey = "forge.coaching.personality.v1"

        public init(preset: Preset? = nil, freeText: String = "") {
            self.preset = preset
            self.freeText = ForgeCoachingPersonality.sanitizeFreeText(freeText)
        }

        /// The user's training style in their own words.
        public var adaptiveTrainingModel: String { freeText }

        public var isCustom: Bool { !freeText.isEmpty }

        public var displayLabel: String {
            let model = freeText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !model.isEmpty {
                if model.count <= 36 { return model }
                return String(model.prefix(33)).trimmingCharacters(in: .whitespaces) + "…"
            }
            if let preset { return preset.label }
            return "Describe your style"
        }

        enum CodingKeys: String, CodingKey {
            case preset, freeText
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let raw = try c.decodeIfPresent(String.self, forKey: .preset)
            preset = Preset.fromStored(raw)
            freeText = ForgeCoachingPersonality.sanitizeFreeText(
                try c.decodeIfPresent(String.self, forKey: .freeText) ?? ""
            )
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeIfPresent(preset?.rawValue, forKey: .preset)
            try c.encode(freeText, forKey: .freeText)
        }
    }

    public enum Preset: String, Codable, CaseIterable, Sendable {
        case steadyBuilder
        case directCoach
        case curiousExperimenter
        case playfulCompanion

        public var label: String {
            switch self {
            case .steadyBuilder: return "Steady builder"
            case .directCoach: return "Direct coach"
            case .curiousExperimenter: return "Curious experimenter"
            case .playfulCompanion: return "Playful companion"
            }
        }

        public var summary: String {
            switch self {
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
            case .steadyBuilder: return "Low volume. Consistent. One next brick."
            case .directCoach: return "Short. Specific. No pep rally."
            case .curiousExperimenter: return "Interest over hype. Notice what worked."
            case .playfulCompanion: return "Light, dry, never cutesy. Adult company."
            }
        }

        /// Retired branded names — never a live preset.
        public static let retiredRawValues: Set<String> = [
            "pillarTraining", "hashira", "hashiraTraining",
            "demonSlayer", "tanjiro",
        ]

        public static func fromStored(_ raw: String?) -> Preset? {
            guard let raw, !raw.isEmpty else { return nil }
            if retiredRawValues.contains(raw) { return nil }
            return Preset(rawValue: raw)
        }
    }

    /// Placeholder only. Hashira is a reference for intensity, never a preset.
    public static let modelPlaceholder =
        "e.g. intense physical, intense mental, intense psychological training. Hashira is a reference for that intensity — not a preset name."

    public static let adultVoiceLaw =
        "Always speak like an adult: curious and direct. Never use child-register pep. Never talk down."

    public static let safetyOverride =
        "Safety and copy rules override this model: lifestyle coach, not a doctor; never say recovery; never diagnose, treat, prescribe, or cure; on anything medical, suggest a doctor; crisis and self-harm hand off to real resources. The adaptive training model is mindset and method only — never exercise form, never the session plan, split, or exercise selection. Never push the person past their comfort or safety limits. Name real progress when it is real."

    /// System / stub prompt fragment. Plan engines must not read this.
    /// Condition constraints layer on automatically when the person has shared them.
    public static func promptDirective(
        _ choice: Choice,
        conditions: [ForgeLifestyleProfile.HealthConstraint] = [],
        freeform: String = ""
    ) -> String {
        var lines: [String] = [adultVoiceLaw, safetyOverride]
        if choice.isCustom {
            lines.append("Adaptive training model, in their words: \"\(choice.freeText)\". Coach against that description for tone and framing only. Do not change exercises, splits, or the session plan to match a metaphor.")
        } else if let preset = choice.preset {
            lines.append("Teaching tone: \(preset.label). \(preset.summary)")
            lines.append("Setbacks: \(preset.setbackFrame)")
            lines.append("Encouragement: \(preset.encouragementPace)")
        }
        let adapted = ForgeConditionAdaptation.constraints(conditions, freeform: freeform)
        if !adapted.isEmpty {
            lines.append(contentsOf: adapted)
            let coach = ForgeConditionAdaptation.coachLine(conditions)
            if !coach.isEmpty { lines.append(coach) }
        }
        lines.append("Do not invent chest-day / body-part splits from the training model. Training content stays whatever the plan engine already wrote.")
        return lines.joined(separator: " ")
    }

    /// Colors a setback in this personality. Mechanics stay out.
    public static func colorSetback(_ choice: Choice, whatHappened: String) -> String {
        let frame: String
        if choice.isCustom {
            frame = "Name it, keep the method they asked for, and take the next honest step — never past comfort or safety."
        } else {
            frame = (choice.preset ?? .steadyBuilder).setbackFrame
        }
        let happened = whatHappened.trimmingCharacters(in: .whitespacesAndNewlines)
        if ForgeReinforcement.containsBlame(happened) {
            return sanitizeOutput(ForgeReinforcement.reframe(whatHappened: ""))
        }
        let body = happened.isEmpty ? frame : "\(happened) \(frame)"
        return sanitizeOutput(body)
    }

    /// Colors encouragement around an unchanged plan line.
    public static func colorPlanTalk(_ choice: Choice, planLine: String) -> String {
        let plan = planLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let lead: String
        if choice.isCustom {
            lead = "Same session as written. Coach it in their words — mindset and method, never form. Stop at comfort and safety. Name the progress that's real."
        } else {
            switch choice.preset ?? .steadyBuilder {
            case .steadyBuilder:
                lead = "Same session as written. Keep it honest and unhurried."
            case .directCoach:
                lead = "Here's the work. Do it or resize the day — don't decorate it."
            case .curiousExperimenter:
                lead = "Same session. Notice how it sits, then we'll adjust next time if we should."
            case .playfulCompanion:
                lead = "Same session, no costume. Let's get through it like adults who like each other."
            }
        }
        let custom = choice.isCustom ? " They asked to be coached this way: \(choice.freeText)." : ""
        return sanitizeOutput("\(lead) \(plan)\(custom)")
    }

    /// Plan fingerprint — personality is intentionally unused. Same inputs,
    /// same plan, every model.
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
