import Foundation

/// How freely ARIA may answer a given turn.
///
/// The old behaviour was binary: `guidanceOnly` was on, so every training,
/// low-energy or pain turn got the same disclaimer appended, forever. That is
/// the worst of both worlds. It reads as legal boilerplate on "my quads are
/// sore from squats", so people learn to skip the last line of every reply —
/// and then it is still just a line when someone describes chest pain, where
/// skipping it matters.
///
/// Three bands instead. Ordinary coaching loses the disclaimer entirely,
/// because a coach who hedges everything is not trusted on anything. What is
/// bought with that is a real stop at the top: when the sentence is actually
/// clinical, ARIA does not coach around it and does not bury the answer under
/// a session plan.
public enum AriaGuidanceBand: String, Sendable, Equatable {

    /// Ordinary lifestyle coaching. Soreness, sleep, food, motivation, load.
    /// No disclaimer — this is the band the app lives in.
    case coach

    /// Still coachable, but the limit gets named once, in plain language, and
    /// professional input is offered rather than used as a way to stop talking.
    case coachWithCare

    /// Not ours. Do not coach around it, do not soften it into a training
    /// note, do not attach a workout. Say it plainly and point at real help.
    case referOut
}

public struct AriaGuidanceDecision: Sendable, Equatable {
    public var band: AriaGuidanceBand
    /// The phrase that triggered a non-`coach` band, for logs and tests. Never
    /// shown to the user — naming their own words back at them as a "trigger"
    /// reads like being flagged by a system rather than heard by a coach.
    public var matched: String?
    /// Ready-to-use line for the two non-ordinary bands.
    public var line: String?

    public init(band: AriaGuidanceBand, matched: String? = nil, line: String? = nil) {
        self.band = band
        self.matched = matched
        self.line = line
    }
}

public enum AriaGuidancePolicy {

    /// Checked before anything else and never overridable by tone, mode, or
    /// how well ARIA knows someone. Familiarity earns informality, not a
    /// shortcut past this.
    private static let referOut: [(needle: String, line: String)] = [
        ("chest pain", "Stop what you're doing and get medical help now — chest pain isn't something I can coach around."),
        ("chest tightness", "Please treat chest tightness as urgent and speak to a doctor or emergency service now."),
        ("pressure in my chest", "That needs emergency care now, not a training decision."),
        ("can't breathe", "If you're struggling to breathe, call emergency services now."),
        ("cant breathe", "If you're struggling to breathe, call emergency services now."),
        ("passed out", "Fainting needs a doctor before any training question — please get it looked at."),
        ("fainted", "Fainting needs a doctor before any training question — please get it looked at."),
        ("blacked out", "Blacking out needs medical review before we talk about load."),
        ("slurred speech", "Sudden speech changes are an emergency — call emergency services now."),
        ("face is drooping", "That's an emergency. Call emergency services now."),
        ("numb on one side", "Sudden one-sided numbness is an emergency — call emergency services now."),
        ("kill myself", "I'm not the right help for this, and I don't want to hand you a workout instead. Please talk to someone now — a crisis line, a doctor, or someone you trust."),
        ("want to die", "I'm not the right help for this. Please reach out to a crisis line or someone you trust today."),
        ("hurt myself", "I'm not the right help for this. Please talk to a crisis line, a doctor, or someone you trust."),
        ("should i stop taking", "Never change a prescription on my say-so — that's between you and whoever prescribed it."),
        ("increase my dose", "Dosing is your prescriber's call, not mine."),
        ("do i have", "I can't diagnose, and guessing at one would be worse than useless. That's a question for a clinician."),
        ("is this cancer", "I can't answer that, and I won't guess. Please see a doctor."),
        ("make myself throw up", "I won't help with that. Please talk to a doctor or an eating-disorder helpline — that's the help that's actually useful here."),
        ("how little can i eat", "I'm not going to help you undereat. If food feels like this right now, a doctor or a dietitian is the right person."),
        ("stop eating for", "I won't build that. If you want to talk about fuelling properly, I'm here for that."),
    ]

    /// Real, common, and worth naming once — then coaching anyway. These are
    /// the cases where deflecting entirely would fail someone who has a
    /// perfectly reasonable training question attached.
    private static let care: [(needle: String, line: String)] = [
        ("for weeks", "Pain that's stuck around for weeks is worth getting looked at properly — I can work around it, but I can't tell you what it is."),
        ("for months", "Months is long enough to get it assessed. I'll keep the work clear of it in the meantime."),
        ("getting worse", "If it's trending worse rather than settling, get it seen. I'll keep today away from it."),
        ("sharp pain", "Sharp is the kind I take seriously — worth a professional look. Nothing today should reproduce it."),
        ("dizzy", "Dizziness I'd want a doctor's read on. Let's keep today low and off your feet where we can."),
        ("lightheaded", "Worth mentioning to a doctor if it repeats. Today we go easy."),
        ("can't put weight", "If you can't load it at all, that's an assessment, not a training tweak."),
        ("swollen", "Swelling that hasn't settled deserves a look. I'll route around it."),
        ("numb", "Numbness is worth a professional opinion. I'll keep load off it."),
        ("pregnant", "Training through pregnancy is real and doable, but the parameters are your doctor's to set — bring me what they say and I'll build inside it."),
    ]

    public static func decide(text: String, guidanceOnlyMode: Bool = false) -> AriaGuidanceDecision {
        let lower = text.lowercased()

        for entry in referOut where lower.contains(entry.needle) {
            return AriaGuidanceDecision(band: .referOut, matched: entry.needle, line: entry.line)
        }
        for entry in care where lower.contains(entry.needle) {
            return AriaGuidanceDecision(band: .coachWithCare, matched: entry.needle, line: entry.line)
        }

        // Someone who declared a condition during onboarding gets the careful
        // band on body-related turns only — not on "what should I eat", which
        // is how the old flag behaved and why it read as boilerplate.
        if guidanceOnlyMode, bodyRelated(lower) {
            return AriaGuidanceDecision(
                band: .coachWithCare,
                matched: "guidance_only",
                line: "Structure and pacing from me; anything diagnostic stays with your clinician."
            )
        }

        return AriaGuidanceDecision(band: .coach)
    }

    private static func bodyRelated(_ lower: String) -> Bool {
        // Annotated and split for the same reason the resolver's expressions
        // were: an unannotated literal feeding straight into `contains(where:)`
        // is the shape that just cost a CI round trip next door.
        let markers: [String] = ["pain", "hurt", "sore", "injury", "ache", "strain", "symptom", "flare"]
        return markers.contains { lower.contains($0) }
    }

    /// Whether an ordinary turn should carry a light reminder anyway.
    ///
    /// Occasionally, not always. A reminder every single time is wallpaper;
    /// one that shows up now and then is still read. Deterministic in the turn
    /// index so it does not flicker between two renders of the same message.
    public static func shouldRemindOnOrdinaryTurn(turnIndex: Int) -> Bool {
        turnIndex > 0 && turnIndex % 12 == 0
    }
}
