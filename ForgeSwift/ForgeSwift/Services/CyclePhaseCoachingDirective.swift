import Foundation

enum CoachingDomain {
    case workout, nutrition, sleep, stress, general
}

/// Biology-grounded, per-phase, per-domain coaching directives injected into the
/// ARIA system prompt so every coaching surface is phase-aware without relying on
/// the model interpreting raw cycle tags.
enum CyclePhaseCoachingDirective {

    /// Calendar-estimate confidence at or below this (e.g. `population_fallback` ~0.45)
    /// must not push max efforts. Readiness stays the primary guide.
    static let lowConfidenceCeiling = 0.55

    static func directive(
        for phase: MenstrualPhase,
        domain: CoachingDomain,
        confidence: Double = 0.45,
        ovulationMethod: String? = nil
    ) -> String {
        switch domain {
        case .workout:   return workoutDirective(for: phase, confidence: confidence, ovulationMethod: ovulationMethod)
        case .nutrition: return nutritionDirective(for: phase)
        case .sleep:     return sleepDirective(for: phase)
        case .stress:    return stressDirective(for: phase)
        case .general:   return generalDirective(for: phase)
        }
    }

    // MARK: - Workout

    private static func isLowConfidenceCalendarEstimate(
        confidence: Double,
        ovulationMethod: String?
    ) -> Bool {
        confidence < lowConfidenceCeiling || ovulationMethod == "population_fallback"
    }

    private static func workoutRail(lowConfidence: Bool) -> String {
        let disclaimer = "Lifestyle coaching, not medical advice. Never diagnose. Readiness is the primary guide — a phase label is a tendency, not a green light."
        if lowConfidence {
            return "This phase is a low-confidence calendar estimate. Do not push max efforts or treat the label as a strong signal. \(disclaimer)"
        }
        return disclaimer
    }

    private static func workoutDirective(
        for phase: MenstrualPhase,
        confidence: Double,
        ovulationMethod: String?
    ) -> String {
        let lowConfidence = isLowConfidenceCalendarEstimate(
            confidence: confidence,
            ovulationMethod: ovulationMethod
        )
        let rail = workoutRail(lowConfidence: lowConfidence)
        switch phase {
        case .menstruation:
            return "The user appears to be menstruating. Many people notice cramping and that hard efforts feel heavier. Suggest lower-intensity options they already like — walking, yoga, easy swimming — and treat rest as a valid choice if that is what they need. Skip max-effort sessions unless readiness is clearly high. \(rail)"
        case .follicular:
            return "The user appears to be in the follicular phase. Many people notice movement clicking more easily and that they can handle a bit more volume. Some find strength work, intervals, and new patterns feel more available — scale to readiness, not the label. Do not treat the label as permission to chase PRs. \(rail)"
        case .fertileWindow:
            return "The user appears to be in their fertile window approaching ovulation. Some people notice power and coordination feel more available. Favor a thorough warm-up and clean form on heavier lifts — some find joints feel a bit looser around this window. Keep intensity honest to readiness. \(rail)"
        case .ovulation:
            return "The user appears to be ovulating. Some people notice power and motivation feel higher. If readiness is clearly high they can train with intent — still warm up thoroughly and prioritize form. Do not prescribe max singles or race-effort days from this label. \(rail)"
        case .luteal:
            return "The user appears to be in the luteal phase. Many people notice the same effort feels harder and that heat tolerance dips, especially later in the phase. Early luteal: some can maintain strength and moderate cardio. Late luteal: some prefer lower intensity, more sleep, and a lighter calendar. Match the session to readiness rather than forcing a plan. \(rail)"
        case .unknown:
            return ""
        }
    }

    // MARK: - Nutrition

    private static func nutritionDirective(for phase: MenstrualPhase) -> String {
        switch phase {
        case .menstruation:
            return "The user is menstruating. Iron losses from bleeding increase iron requirements — recommend iron-rich foods (red meat, lentils, spinach) with vitamin C to enhance absorption. Anti-inflammatory foods (omega-3s, turmeric) can reduce prostaglandin-driven cramps. Magnesium (dark chocolate, nuts, leafy greens) helps with cramping and mood."
        case .follicular:
            return "The user is in the follicular phase. Insulin sensitivity is high — this is the best time for carb-loading around training. Lighter, antioxidant-rich meals support rising estrogen. The body recovers well from higher training loads, so caloric intake can match increased activity."
        case .fertileWindow, .ovulation:
            return "The user is near or at ovulation. Metabolic rate is slightly elevated. Protein timing around workouts is effective given high anabolic potential. Cruciferous vegetables (broccoli, kale) support estrogen metabolism."
        case .luteal:
            return "The user is in the luteal phase. Progesterone increases appetite and carbohydrate cravings — this is physiologically normal, not a failure. Caloric needs genuinely increase by ~100–300 kcal/day. Magnesium (400 mg/day) significantly reduces PMS symptoms. Reduce sodium to minimise bloating. Complex carbs over simple sugars stabilise blood glucose and mood. Limit caffeine and alcohol in late luteal — they worsen anxiety and sleep disruption."
        case .unknown:
            return ""
        }
    }

    // MARK: - Sleep

    private static func sleepDirective(for phase: MenstrualPhase) -> String {
        switch phase {
        case .menstruation:
            return "The user is menstruating. Cramps and discomfort may fragment sleep. Suggest: heat pack before bed, ibuprofen timing (if appropriate), side-sleeping with pillow between knees to reduce pelvic pressure. Prioritise 8+ hours to support immune function during blood loss."
        case .follicular:
            return "The user is in the follicular phase. Estrogen supports serotonin and deep slow-wave sleep. This is the best phase for sleep quality. Encourage consistent sleep schedule to capitalise on natural sleep advantage."
        case .fertileWindow, .ovulation:
            return "The user is near ovulation. Sleep quality remains good. Minor LH surge can occasionally cause light sleep disruption the night of ovulation — generally not clinically significant."
        case .luteal:
            return "The user is in the luteal phase. Progesterone raises core body temperature, which can cause early waking and fragmented sleep — especially in late luteal. Recommend: keep bedroom cooler (18–19°C), avoid alcohol (worsens temperature regulation), magnesium glycinate at night supports sleep. REM sleep may be slightly reduced. Be understanding if the user reports poor sleep — it is hormonally driven."
        case .unknown:
            return ""
        }
    }

    // MARK: - Stress

    private static func stressDirective(for phase: MenstrualPhase) -> String {
        switch phase {
        case .menstruation:
            return "The user is menstruating. Prostaglandins and dropping hormones can amplify stress sensitivity and emotional reactivity. Validate any emotional intensity — it is physiologically grounded. Recommend: reduce non-essential obligations if possible, gentle movement, heat therapy, extra self-compassion."
        case .follicular:
            return "The user is in the follicular phase. Rising estrogen supports dopamine and serotonin — stress resilience is naturally higher. Good phase for tackling challenging tasks, difficult conversations, or demanding projects."
        case .fertileWindow, .ovulation:
            return "The user is near or at ovulation. Peak confidence and sociability driven by estrogen and testosterone. Stress resilience is at its highest. Ideal for high-stakes presentations, negotiations, or social challenges."
        case .luteal:
            return "The user is in the luteal phase. Progesterone withdrawal in late luteal drives PMDD/PMS symptoms including anxiety, irritability, and low mood in susceptible individuals. This is not weakness — it is a real neuroendocrine shift (progesterone metabolite allopregnanolone modulates GABA receptors). Recommend: reduce stimulants, prioritise rest, gentle exercise, reduce decision load. Acknowledge that difficult emotions in late luteal are often hormonally amplified."
        case .unknown:
            return ""
        }
    }

    // MARK: - General

    private static func generalDirective(for phase: MenstrualPhase) -> String {
        switch phase {
        case .menstruation:
            return "The user is on their period. Be sensitive, practical, and supportive. Validate rest and self-care without being condescending. Suggest phase-appropriate nutrition (iron, magnesium, anti-inflammatory foods) and gentle movement when relevant."
        case .follicular:
            return "The user is in their follicular phase — typically the highest energy, best mood, and strongest performance window of the cycle. Rising estrogen supports cognitive sharpness and social confidence. Encourage ambition, new starts, and taking on challenges."
        case .fertileWindow:
            return "The user is in their fertile window — high energy, peak sociability, strong physical performance driven by estrogen and LH surge. Great time for demanding tasks, social goals, and ambitious training."
        case .ovulation:
            return "The user is ovulating — peak hormonal state: high energy, confidence, and physical capacity from the testosterone and estrogen surge."
        case .luteal:
            return "The user is in their luteal phase. Energy and mood may decline as the phase progresses toward menstruation. Progesterone-driven temperature rise and appetite changes are normal. Normalise slower pacing, honour rest needs, and avoid pushing through symptoms — support, don't push."
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
