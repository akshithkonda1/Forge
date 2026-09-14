import Foundation

// MARK: - AriaDayBrief
//
// One-line on-device "day brief" for Watch Home + complications. Pure and
// deterministic (SimRunner-friendly): no network, no LLM. Complements the
// mindfulness suggestion with a glanceable summary of readiness + sleep +
// the next best action.

public enum AriaDayBrief {

    /// Compose a single sentence the wrist can show under ARIA's greeting.
    public static func line(
        for context: WatchARIAContext,
        recommendation: MindfulnessRecommendation?
    ) -> String {
        let readinessBit: String
        if let score = context.readinessOverall, (context.readinessConfidence ?? 0) > 0 {
            let band = ReadinessBand(score: score)
            readinessBit = "Readiness \(score) (\(band.label))"
        } else {
            readinessBit = "Still gathering readiness"
        }

        let sleepBit: String
        if let quality = context.sleepQualityScore {
            if quality < 60 {
                sleepBit = "sleep ran short"
            } else if quality >= 80 {
                sleepBit = "sleep looked solid"
            } else {
                sleepBit = "sleep was okay"
            }
        } else if let minutes = context.sleepMinutes, minutes > 0 {
            let hours = minutes / 60.0
            sleepBit = String(format: "slept %.1fh", hours)
        } else {
            sleepBit = "sleep still syncing"
        }

        let actionBit: String
        if let rec = recommendation {
            actionBit = "Next: \(rec.durationLabel) \(rec.practice.displayName)"
        } else {
            actionBit = "Next: a short reset when you want it"
        }

        return "\(readinessBit) · \(sleepBit). \(actionBit)."
    }
}
