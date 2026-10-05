import Foundation

// ============================================================
// MARK: - Tomorrow's two budgets
// ============================================================

/// Tomorrow is not one score.
///
/// Readiness says what the body can spend. People-energy says what the
/// calendar can spend. They disagree often: a green training day with a
/// thin social budget, or a rest day when seeing someone would still be
/// fine. Fitness apps only publish the body number. This names which
/// budget is actually scarce so ARIA does not spend the one that isn't.
/// Lifestyle coach only — never a diagnosis.
public enum TomorrowBudgets {

    public enum Constraint: String, Sendable {
        case both
        case people
        case body
        case neither
    }

    public struct Snapshot: Sendable, Equatable {
        public var constraint: Constraint
        public var headline: String
        public var coachingLine: String

        public var ariaTags: [String] { ["tomorrow_budget:\(constraint.rawValue)"] }

        public var isSplit: Bool { constraint == .people || constraint == .body }
    }

    public static func snapshot(
        posture: ReadinessForecastEngine.Posture,
        stance: UserWorkingModel.Stance,
        peopleEnergy: HobbyPathEngine.PeopleEnergy
    ) -> Snapshot {
        let bodyThin = posture.keepLight || stance == .capHeroics
        let peopleThin = peopleEnergy == .thin
        let constraint: Constraint
        switch (bodyThin, peopleThin) {
        case (true, true): constraint = .both
        case (false, true): constraint = .people
        case (true, false): constraint = .body
        case (false, false): constraint = .neither
        }
        return Snapshot(
            constraint: constraint,
            headline: headline(constraint),
            coachingLine: coachingLine(constraint)
        )
    }

    public static func parseTag(_ token: String) -> Constraint? {
        let parts = token.split(separator: ":").map(String.init)
        guard parts.count >= 2, parts[0] == "tomorrow_budget" else { return nil }
        return Constraint(rawValue: parts[1])
    }

    private static func headline(_ constraint: Constraint) -> String {
        switch constraint {
        case .both: return "Both budgets are thin"
        case .people: return "Split day — people-budget is the limit"
        case .body: return "Split day — body-budget is the limit"
        case .neither: return "Neither budget is the limit"
        }
    }

    static func coachingLine(_ constraint: Constraint) -> String {
        switch constraint {
        case .both:
            return "Tomorrow both budgets are thin. A short walk or nothing — no hero session, no extra plans."
        case .people:
            return "Split day. Your body can take the session. Your people-budget cannot take the calendar."
        case .body:
            return "Split day. People are fine if you want them. Don't stack a hard session on a thin body."
        case .neither:
            return "Neither budget is the limit. Spend one if you want — not both, just to prove you can."
        }
    }
}
