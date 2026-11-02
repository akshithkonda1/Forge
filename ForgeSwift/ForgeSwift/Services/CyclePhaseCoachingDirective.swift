import Foundation

enum CoachingDomain {
    case workout, nutrition, sleep, stress, general
}

/// Biology-grounded, per-phase, per-domain coaching directives injected into the
/// ARIA system prompt so every coaching surface is phase-aware without relying on
/// the model interpreting raw cycle tags.
enum CyclePhaseCoachingDirective {

    static let lifestyleDisclaimer =
        "Lifestyle coaching, not medical advice. Readiness is the primary guide — never treat a phase label as a diagnosis or a guarantee."

    static func directive(
        for phase: MenstrualPhase,
        domain: CoachingDomain,
        confidence: Double = 0.7,
        lutealDays: Int = CycleBiology.defaultLutealDays,
        ovulationMethod: String? = nil
    ) -> String {
        switch domain {
        case .workout:   return workoutDirective(for: phase, confidence: confidence, lutealDays: lutealDays, ovulationMethod: ovulationMethod)
        case .nutrition: return nutritionDirective(for: phase)
        case .sleep:     return sleepDirective(for: phase)
        case .stress:    return stressDirective(for: phase)
        case .general:   return generalDirective(for: phase)
        }
    }

    /// Calendar-only or population estimates should not push max efforts.
    static func isLowConfidenceEstimate(confidence: Double, ovulationMethod: String?) -> Bool {
        if confidence < 0.55 { return true }
        if ovulationMethod == "population_fallback" { return true }
        return false
    }

    static func lutealSplit(lutealDays: Int) -> (earlyEnd: Int, lateStart: Int, luteal: Int) {
        let luteal = CycleBiology.clampLutealDays(lutealDays)
        let lateStart = max(2, (luteal / 2) + 1)
        return (lateStart - 1, lateStart, luteal)
    }

    // MARK: - Workout

    private static func workoutDirective(
        for phase: MenstrualPhase,
        confidence: Double,
        lutealDays: Int,
        ovulationMethod: String?
    ) -> String {
        let low = isLowConfidenceEstimate(confidence: confidence, ovulationMethod: ovulationMethod)
        let readiness = lifestyleDisclaimer
        if low, phase != .unknown {
            return "Cycle phase is a low-confidence estimate (\(ovulationMethod ?? "calendar"), \(Int((confidence * 100).rounded()))%). Keep readiness as the primary guide. Favor technique, moderate work, and how the user feels today — do not push max efforts, one-rep attempts, or race efforts from a calendar guess. \(readiness)"
        }
        switch phase {
        case .menstruation:
            return "The user appears to be menstruating. Many people notice cramping and that hard sessions feel harder. Favor lower intensity — walking, yoga, easy swimming — and treat rest as valid, not weakness. Skip max-effort sessions unless readiness is clearly high. \(readiness)"
        case .follicular:
            return "The user appears to be in the follicular phase. Many people notice training can feel more available — strength work, intervals, and learning new patterns. Some find progressive overload easier now. Encourage ambition only when readiness agrees; do not treat this as a guaranteed performance window. \(readiness)"
        case .fertileWindow:
            return "The user appears to be in a fertile-window estimate approaching ovulation. Some people notice power and coordination feel more available — useful for skill work or explosive sessions if readiness is high. A few notice joints feel looser; prioritize form over load. This is a tendency, not a fact about their hormones today. \(readiness)"
        case .ovulation:
            return "The user appears to be around an estimated ovulation day. Some people notice motivation or power feel higher. Keep form and warm-up honest; do not call this the best day for one-rep maxes or frame it as aggression. If readiness is soft, stay moderate. \(readiness)"
        case .luteal:
            let split = lutealSplit(lutealDays: lutealDays)
            return "The user appears to be in the luteal phase. Many people notice the same effort can feel harder as the phase progresses, and some notice a slight rise in resting temperature. Early luteal (about the first \(split.earlyEnd) days after estimated ovulation): many can keep strength and moderate cardio. Late luteal (days \(split.lateStart)–\(split.luteal) of the luteal stretch): some find energy and motivation dip — ease intensity, prioritize sleep, and avoid stacking a peak effort on a guess. \(readiness)"
        case .unknown:
            return ""
        }
    }

    // MARK: - Nutrition

    private static func nutritionDirective(for phase: MenstrualPhase) -> String {
        switch phase {
        case .menstruation:
            return "The user appears to be menstruating. Iron-rich foods (red meat, lentils, spinach) with vitamin C are a common lifestyle suggestion during bleeding. Some people find anti-inflammatory foods and magnesium (dark chocolate, nuts, leafy greens) helpful for cramps and mood. Not medical advice."
        case .follicular:
            return "The user appears to be in the follicular phase. Some people find carbs around training sit well in this window. Lighter, antioxidant-rich meals are a reasonable match if training volume is up. Match intake to activity; do not claim a metabolic diagnosis."
        case .fertileWindow, .ovulation:
            return "The user appears to be near an estimated ovulation. Some people notice appetite or energy shift slightly. Protein around workouts is a solid lifestyle habit. Cruciferous vegetables are a reasonable dietary pattern — not a treatment."
        case .luteal:
            return "The user appears to be in the luteal phase. Many people notice a bigger appetite and carb cravings — that can be a normal tendency, not a failure. Some find magnesium, complex carbs, and a little less caffeine or alcohol feel better late in the phase. Lifestyle coaching only."
        case .unknown:
            return ""
        }
    }

    // MARK: - Sleep

    private static func sleepDirective(for phase: MenstrualPhase) -> String {
        switch phase {
        case .menstruation:
            return "The user appears to be menstruating. Cramps and discomfort may fragment sleep for some people. Lifestyle ideas: heat before bed, side-sleeping with a pillow between the knees, and protecting a full night. Not medical advice."
        case .follicular:
            return "The user appears to be in the follicular phase. Many people notice sleep feels easier here. Encourage a consistent schedule so they can use that window — still follow how they actually slept last night."
        case .fertileWindow, .ovulation:
            return "The user appears to be near an estimated ovulation. Sleep quality often stays decent; a few people notice a lighter night around mid-cycle. Treat that as a possible tendency, not a clinical finding."
        case .luteal:
            return "The user appears to be in the luteal phase. Some people notice earlier waking or more fragmented sleep, especially late luteal. Lifestyle ideas: a cooler bedroom, less alcohol, and a consistent wind-down. If they report poor sleep, believe them — do not diagnose a hormone disorder."
        case .unknown:
            return ""
        }
    }

    // MARK: - Stress

    private static func stressDirective(for phase: MenstrualPhase) -> String {
        switch phase {
        case .menstruation:
            return "The user appears to be menstruating. Some people notice stress and emotions feel louder. Validate that without diagnosing it. Lifestyle ideas: fewer non-essential obligations, gentle movement, heat, extra self-compassion."
        case .follicular:
            return "The user appears to be in the follicular phase. Many people notice stress sits a bit easier. A reasonable window to take on harder conversations or projects if they want to — readiness still leads."
        case .fertileWindow, .ovulation:
            return "The user appears to be near an estimated ovulation. Some people notice more social energy or confidence. Useful for high-stakes work if they feel up to it; never frame it as a hormone fact."
        case .luteal:
            return "The user appears to be in the luteal phase. Some people notice anxiety, irritability, or low mood later in the phase. That can be a real lived pattern — it is not weakness and it is not a diagnosis. Lifestyle ideas: fewer stimulants, more rest, gentler training, a lighter decision load."
        case .unknown:
            return ""
        }
    }

    // MARK: - General

    private static func generalDirective(for phase: MenstrualPhase) -> String {
        switch phase {
        case .menstruation:
            return "The user appears to be on their period. Be sensitive, practical, and supportive. Validate rest and self-care without being condescending. Suggest phase-appropriate nutrition and gentle movement when relevant. Lifestyle coaching, not medical advice."
        case .follicular:
            return "The user appears to be in their follicular phase — many people notice higher energy and a stronger training window. Encourage ambition and new starts when readiness agrees. Not a diagnosis."
        case .fertileWindow:
            return "The user appears to be in a fertile-window estimate — some people notice more energy or sociability. A good time for demanding tasks if they feel up to it. Phase labels are not contraception."
        case .ovulation:
            return "The user appears to be around an estimated ovulation day. Some people notice higher energy or confidence. Keep claims tentative and readiness-first."
        case .luteal:
            return "The user appears to be in their luteal phase. Energy and mood may ease as the phase progresses toward menstruation. Some people notice temperature or appetite shifts. Normalize a slower pace, honor rest, and do not push through symptoms. Lifestyle coaching, not medical advice."
        case .unknown:
            return ""
        }
    }
}

extension CyclePhaseCoachingDirective {
    /// Classifies a coaching domain from the user's own message so the injected
    /// directive matches what they're actually asking about, instead of always
    /// falling back to the general directive.
    static func classifyDomain(from text: String) -> CoachingDomain {
        let lower = text.lowercased()
        if lower.contains("workout") || lower.contains("train") || lower.contains("exercise")
            || lower.contains("lift") || lower.contains("gym")
            || lower.contains("run") || lower.contains("mile") || lower.contains("jog") {
            return .workout
        }
        if lower.contains("eat") || lower.contains("food") || lower.contains("protein")
            || lower.contains("meal") || lower.contains("calorie") || lower.contains("hydrat") { return .nutrition }
        if lower.contains("sleep") || lower.contains("tired") || lower.contains("exhausted")
            || lower.contains("rest") { return .sleep }
        if lower.contains("stress") || lower.contains("anxious") || lower.contains("overwhelmed")
            || lower.contains("mood") { return .stress }
        return .general
    }
}
