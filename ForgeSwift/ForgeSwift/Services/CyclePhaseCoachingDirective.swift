import Foundation

enum CoachingDomain {
    case workout, nutrition, sleep, stress, general
}

/// Biology-grounded, per-phase, per-domain coaching directives injected into the
/// ARIA system prompt so every coaching surface is phase-aware without relying on
/// the model interpreting raw cycle tags.
enum CyclePhaseCoachingDirective {

    static func directive(for phase: MenstrualPhase, domain: CoachingDomain) -> String {
        switch domain {
        case .workout:   return workoutDirective(for: phase)
        case .nutrition: return nutritionDirective(for: phase)
        case .sleep:     return sleepDirective(for: phase)
        case .stress:    return stressDirective(for: phase)
        case .general:   return generalDirective(for: phase)
        }
    }

    // MARK: - Workout

    private static func workoutDirective(for phase: MenstrualPhase) -> String {
        switch phase {
        case .menstruation:
            return "The user is menstruating. Prostaglandins cause uterine cramping and may reduce performance. Recommend lower intensity: walking, yoga, gentle swimming. Avoid heavy PRs or max-effort sessions. Validate rest if needed — this is physiologically appropriate, not weakness."
        case .follicular:
            return "The user is in the follicular phase. Rising estrogen improves neuromuscular efficiency, pain tolerance, and recovery speed. This is the best phase for strength PRs, high-intensity interval work, learning new movement patterns, and pushing volume. Encourage ambitious training."
        case .fertileWindow:
            return "The user is in their fertile window approaching ovulation. Estrogen and LH surge peak — power output and coordination are at their highest. Excellent for team sports, explosive work, and technical skill sessions. Watch for ligament laxity (estrogen loosens connective tissue) — prioritise good form on heavy lifts."
        case .ovulation:
            return "The user is ovulating. Testosterone briefly spikes alongside the LH surge — peak power, aggression, and motivation. Best day for one-rep maxes or race efforts. Again flag ligament laxity risk: form over load."
        case .luteal:
            return "The user is in the luteal phase. Progesterone rises, increasing core body temperature by ~0.3°C and raising RPE for the same effort. Early luteal (days 1–7 post-ovulation): maintain strength and moderate cardio. Late luteal (days 8–14): reduce intensity, prioritise sleep, watch for fatigue accumulation and PMS-driven motivation dips. Avoid scheduling major competitions in late luteal."
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
