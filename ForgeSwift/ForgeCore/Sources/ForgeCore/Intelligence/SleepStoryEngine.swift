import Foundation

// MARK: - SleepStoryEngine
//
// "Last night's story" + "tonight's plan" as pure templates — the same
// instant/on-device tier as the other engines. Voice contract: patterns,
// not verdicts; a short night is context for pacing the day, never a
// failure; and every story ends pointing forward.

public enum SleepStoryEngine {

    // MARK: Last night

    public static func story(night: SleepNight?, readiness: ReadinessScore?, factors: [SleepFactor] = []) -> String {
        guard let night, night.totalMinutes > 0 else {
            return "No sleep data from last night yet — once your watch syncs, I'll tell you the story. Until then, pace by feel; you know yourself well."
        }

        let hours = night.totalMinutes / 60
        let deepShare = night.totalMinutes > 0 ? night.deepMinutes / night.totalMinutes : 0
        let factorNote = factors.first.map { " \($0.ariaNote)" } ?? ""

        if hours < 6 {
            let readinessLink = readiness.map { " Today's readiness (\($0.overall)) reflects it — a lighter-touch day still counts fully." }
                ?? " A lighter-touch day still counts fully."
            return "A short night at \(night.durationLabel) — your body kept what mattered most.\(readinessLink)\(factorNote)"
        }

        if deepShare >= 0.18 {
            return "\(night.durationLabel) with strong deep sleep (\(Int(night.deepMinutes)) min) — that's the physical recharge doing its job. Spend it on whatever matters most today.\(factorNote)"
        }

        if night.awakeMinutes > 45 {
            return "\(night.durationLabel) total, but with some wakeful stretches — the kind of night that feels longer than it restores. Be a little generous with yourself today.\(factorNote)"
        }

        return "A solid \(night.durationLabel) — steady architecture, nothing to fix. Consistency like this is quietly the whole game.\(factorNote)"
    }

    // MARK: Tonight

    public static func tonightPlan(
        plan: WindDownPlan?,
        night: SleepNight?,
        highCognitiveLoadDay: Bool = false,
        calendar: Calendar = .current
    ) -> String {
        guard let plan else {
            return "I'm still learning your sleep rhythm — a few more nights and I'll suggest a personal wind-down time. Tonight, aim for the bedtime that usually feels right."
        }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        let windDownTime = formatter.string(from: plan.windDownStart)

        let sleptShort = (night?.totalMinutes ?? 480) < 6 * 60
        if highCognitiveLoadDay {
            return "Heavy thinking day — a 4-minute wind-down around \(windDownTime) gives your mind a runway and tilts tonight toward deep sleep."
        }
        if sleptShort {
            return "After last night, tonight is the easy win: start winding down around \(windDownTime) and let the window do the work."
        }
        return "Your rhythm points to winding down around \(windDownTime). A few slow breaths then keeps a good streak of nights going."
    }
}
