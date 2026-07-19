import Foundation

// MARK: - MindfulnessSuggestionEngine
//
// The "instant" tier of ARIA on the wrist: a pure, deterministic rule +
// template engine that turns a `WatchARIAContext` into one
// `MindfulnessRecommendation` in microseconds, fully on-device (privacy)
// and fully testable (SimRunner philosophy). The backend LLM tier is used
// only for deeper debriefs, never for the glanceable suggestion.
//
// Voice rules for every template:
//  - supportive, pattern-focused, zero guilt, max two sentences
//  - epistemic honesty: hedge ("looks like", "may") when signals are weak
//  - reinforce the core philosophy: living well and being healthy are not
//    in tension — the practice serves the user's day, not the other way
//    around.

public enum MindfulnessSuggestionEngine {

    /// Priority order (first matching rule wins):
    /// post-workout reset > desk block + HRV dip > desk block > evening
    /// wind-down > morning grounding > HRV dip anywhere > low readiness >
    /// time-of-day default.
    public static func suggest(for context: WatchARIAContext) -> MindfulnessRecommendation {
        let confident = (context.readinessConfidence ?? 0) >= 0.4

        if context.justFinishedWorkout {
            return MindfulnessRecommendation(
                practice: .bodyScan,
                duration: 300,
                reason: "A few minutes of body scan now helps the work you just did become recovery. Effort and ease belong in the same day.",
                trigger: "post-workout-reset"
            )
        }

        if context.inLongDeskBlock && context.hrvIsDipping {
            return MindfulnessRecommendation(
                practice: .physiologicalSigh,
                duration: 90,
                reason: "Long focus block and your HRV looks like it's dipping. A 90-second physiological sigh helps your nervous system recover without breaking flow.",
                trigger: "desk-block-hrv-dip"
            )
        }

        if context.inLongDeskBlock {
            return MindfulnessRecommendation(
                practice: .focusReset,
                duration: 90,
                reason: "You've been locked in for a while — nice work. Ninety seconds of slow breathing keeps that focus sustainable instead of borrowed.",
                trigger: "desk-block-90m"
            )
        }

        if context.isEvening {
            let sleptPoorly = (context.sleepQualityScore ?? 100) < 60
            return MindfulnessRecommendation(
                practice: .windDown,
                duration: sleptPoorly ? 300 : 240,
                reason: sleptPoorly
                    ? "Last night ran short, so tonight's wind-down matters a little more. A few slow minutes now tilts the odds toward deeper sleep."
                    : "The day is winding down — this breath pattern tells your body it's safe to follow. Rest is part of living well, not time away from it.",
                trigger: "evening-wind-down"
            )
        }

        if context.isMorning {
            let lowReadiness = (context.readinessOverall ?? 100) < 55 && confident
            return MindfulnessRecommendation(
                practice: .morningGrounding,
                duration: 180,
                reason: lowReadiness
                    ? "Your body is asking for a gentler start today, and that's completely fine. Three grounded minutes set the tone better than pushing would."
                    : "A short grounding practice before the day accelerates is the highest-leverage three minutes you'll spend. Start how you mean to continue.",
                trigger: lowReadiness ? "low-readiness-morning" : "morning-grounding"
            )
        }

        if context.hrvIsDipping {
            return MindfulnessRecommendation(
                practice: .stressRelease,
                duration: 180,
                reason: "Your HRV suggests some accumulated tension. Long exhales are the fastest honest way to let it go — no willpower required.",
                trigger: "hrv-dip"
            )
        }

        if let readiness = context.readinessOverall, readiness < 55, confident {
            return MindfulnessRecommendation(
                practice: .bodyScan,
                duration: 300,
                reason: "Recovery-day readiness doesn't mean the day is lost — it means ease pays more than effort today. This scan is the easy win.",
                trigger: "low-readiness"
            )
        }

        return MindfulnessRecommendation(
            practice: .focusReset,
            duration: 180,
            reason: "A three-minute reset between things keeps your best hours actually yours. You can live your best life and still be healthy.",
            trigger: "default-midday"
        )
    }

    // MARK: - Greeting

    /// Home-screen greeting: warm, contextual, one or two sentences.
    public static func greeting(for context: WatchARIAContext, userName: String? = nil) -> String {
        let name = userName.map { " \($0)" } ?? ""
        let opener: String
        switch context.hourOfDay {
        case 5..<12:  opener = "Morning\(name)."
        case 12..<17: opener = "Afternoon\(name)."
        case 17..<21: opener = "Evening\(name)."
        default:      opener = "Hey\(name)."
        }

        guard let readiness = context.readinessOverall, (context.readinessConfidence ?? 0) > 0 else {
            return "\(opener) I'm still gathering today's signals — open Forge on your iPhone or wear your watch a bit longer and I'll catch up."
        }

        let band = ReadinessBand(score: readiness)
        if let mode = context.lifestyleMode {
            return "\(opener) \(band.supportiveDescriptor) \(modeAside(mode))"
        }
        return "\(opener) \(band.supportiveDescriptor)"
    }

    private static func modeAside(_ mode: LifestyleMode) -> String {
        switch mode {
        case .deskCoding, .deepFocus:
            return "I'll watch your focus blocks and only nudge when it genuinely helps."
        case .gym:
            return "When you're ready, I'll meet you at the right effort."
        case .commute:
            return "Use the transit time to arrive settled."
        case .homeRecovery:
            return "Nothing to prove today."
        case .outdoor:
            return "Being outside already counts."
        case .windDown:
            return "Let's keep the evening soft."
        }
    }
}
