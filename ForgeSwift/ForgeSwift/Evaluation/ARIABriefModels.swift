import Foundation

enum ARIABriefFocus: String, Codable, Equatable {
    case morning
    case evening
    case postWorkout = "post-workout"
    case midday
    case auto
}

struct ARIABrief: Equatable {
    var focus: ARIABriefFocus
    var title: String
    var headline: String
    var body: String
    var notificationCopy: String
    var trainingDecision: TrainingDecision
    var compoundFlags: [String]
    var generatedAt: Date

    /// Offline fallback when `/aria/brief` is unavailable.
    static func localFallback(
        focus: ARIABriefFocus,
        dailyScores: DailyScores?,
        conclusions: DataConclusions?,
        trainingDecision: TrainingDecision
    ) -> ARIABrief {
        let decision = dailyScores?.trainingDecision ?? trainingDecision
        let strain = dailyScores?.strain.score ?? 0
        let recovery = dailyScores?.recovery.score ?? 0
        let sleep = dailyScores?.sleep.score ?? 0
        let sleepNeed = dailyScores?.sleep.sleepNeedMinutes ?? 0
        let flags = conclusions?.compoundFlags ?? []
        let dashboard = conclusions?.offlineTemplates.dashboard ?? conclusions?.coachingBrief ?? ""

        let title: String
        let headline: String
        let body: String

        switch focus {
        case .evening:
            title = "Evening wind-down"
            headline = sleepNeed > 0
                ? "Sleep need \(sleepNeed)m — start winding down."
                : "Recovery \(recovery)/100 · protect tonight's rest."
            body = "\(dashboard) Sleep score \(sleep)/100."
        case .postWorkout:
            title = "Post-workout debrief"
            headline = "Session complete — strain \(strain)/100."
            body = "Recovery is \(recovery)/100. Cool down, hydrate, and refuel within the hour."
        case .midday:
            title = "ARIA check-in"
            headline = "Recovery \(recovery)/100 · decision: \(decision.label)."
            body = dashboard.isEmpty ? "Midday trilogy check — Strain \(strain), Recovery \(recovery), Sleep \(sleep)." : dashboard
        default:
            title = decision == .train ? "Morning brief — ready to train" : "Morning brief"
            headline = flags.contains("recovery-debt-under-load")
                ? "Recovery debt detected — ease intensity today."
                : "Trilogy: strain \(strain), recovery \(recovery), sleep \(sleep)."
            body = "\(dashboard) Today's action: \(decision.label)."
        }

        let notification = headline.count > 120 ? String(headline.prefix(177)) + "…" : headline
        return ARIABrief(
            focus: focus,
            title: title,
            headline: headline,
            body: body,
            notificationCopy: notification,
            trainingDecision: decision,
            compoundFlags: flags,
            generatedAt: Date()
        )
    }
}