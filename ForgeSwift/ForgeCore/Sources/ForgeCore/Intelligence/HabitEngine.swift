import Foundation

/// ARIA's deep habit layer — the piece that turns Lifestyle from a dashboard into a companion.
///
/// A habit is not a checkbox. It is a loop: cue → routine → payoff/cost, verified against
/// the user's actual numbers (sleep debt, HRV, markers, social). The engine reads the signals
/// Lifestyle already collects and emits the 2-3 loops that actually move the needle, each with
/// the smallest interrupt that can break it.
///
/// Pure Swift, no HealthKit, testable — like ReadinessCalculator.
public struct DeepHabit: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var cue: String
    public var routine: String
    public var payoff: String
    public var cost: String
    public var category: Category
    public var confidence: Double // 0...1 how much evidence
    public var evidence: String // 1 line citing real numbers
    public var breaker: String // one smallest next move
    public var breakerAction: String // button label

    public enum Category: String, Codable, CaseIterable, Sendable {
        case sleep, nutrition, movement, social, recovery
        public var icon: String {
            switch self {
            case .sleep: return "moon.stars.fill"
            case .nutrition: return "fork.knife"
            case .movement: return "figure.run"
            case .social: return "person.2.fill"
            case .recovery: return "heart.fill"
            }
        }
        public var colorKey: String { rawValue }
    }

    public init(id: String, title: String, cue: String, routine: String, payoff: String, cost: String, category: Category, confidence: Double, evidence: String, breaker: String, breakerAction: String) {
        self.id = id; self.title = title; self.cue = cue; self.routine = routine
        self.payoff = payoff; self.cost = cost; self.category = category
        self.confidence = confidence; self.evidence = evidence; self.breaker = breaker; self.breakerAction = breakerAction
    }
}

/// Input Lifestyle already has: metrics, stats, sleep onset variance, markers, social.
public struct HabitSignals: Sendable {
    public var sleepAverage: Double // hours
    public var sleepVarianceMinutes: Int? // std or range
    public var hrv: Double?
    public var hrvBaseline: Double?
    public var steps: Int
    public var protein: Double
    public var waterGlasses: Double
    public var totalCalories: Int
    public var markers: [FakeLifestyleMarker]
    public var social: [FakeSocialEvent]
    public var nightsAvailable: Int
    public var qualityOfLifeScore: Int

    public init(sleepAverage: Double, sleepVarianceMinutes: Int? = nil, hrv: Double? = nil, hrvBaseline: Double? = nil, steps: Int, protein: Double, waterGlasses: Double, totalCalories: Int, markers: [FakeLifestyleMarker] = [], social: [FakeSocialEvent] = [], nightsAvailable: Int = 0, qualityOfLifeScore: Int = 80) {
        self.sleepAverage = sleepAverage; self.sleepVarianceMinutes = sleepVarianceMinutes
        self.hrv = hrv; self.hrvBaseline = hrvBaseline; self.steps = steps
        self.protein = protein; self.waterGlasses = waterGlasses; self.totalCalories = totalCalories
        self.markers = markers; self.social = social; self.nightsAvailable = nightsAvailable
        self.qualityOfLifeScore = qualityOfLifeScore
    }
}

public enum HabitEngine {

    public static func analyze(_ s: HabitSignals) -> [DeepHabit] {
        var out: [DeepHabit] = []

        // 1) Irregular wind-down — the biggest lever
        if let variance = s.sleepVarianceMinutes, variance > 60 || s.sleepAverage < 7.0 {
            let evidence: String
            if variance > 90 {
                evidence = "Bedtime moved \(variance)m across the last week · avg \(String(format: "%.1f", s.sleepAverage))h (target 8h)"
            } else if s.sleepAverage < 7 {
                evidence = "Avg \(String(format: "%.1f", s.sleepAverage))h — \(String(format: "%.1f", 8 - s.sleepAverage))h under target, variance \(variance)m"
            } else {
                evidence = "Sleep variance \(variance)m — enough to cut deep sleep ~18%"
            }
            out.append(DeepHabit(
                id: "sleep_variance",
                title: "Wobbly wind-down",
                cue: "Evening at home after 22:00",
                routine: "Phone stays with you on the couch → late scroll → 00:30 sleep",
                payoff: "Felt productive for 20m",
                cost: "Deep sleep cut, tomorrow's readiness down",
                category: .sleep,
                confidence: variance > 90 ? 0.85 : 0.65,
                evidence: evidence,
                breaker: "Tonight, leave phone charging in the kitchen at 22:00. Just that.",
                breakerAction: "Try kitchen-phone"
            ))
        }

        // 2) Social → late night → HRV dip
        let drinksNights = s.social.filter { $0.drinks >= 2 }
        let lateNights = s.social.filter { $0.ranLate }
        if !drinksNights.isEmpty || lateNights.count >= 2 {
            let count = drinksNights.count
            let drinks = drinksNights.reduce(0) { $0 + $1.drinks }
            out.append(DeepHabit(
                id: "social_late",
                title: "Late social → late sleep",
                cue: "Dinner or drinks out after 19:00",
                routine: "\(count) evenings with \(drinks) drinks, \(lateNights.count) ran past midnight",
                payoff: "Connection, fun — real",
                cost: "Onset pushed ~70m, next-morning HRV down",
                category: .social,
                confidence: lateNights.count >= 2 ? 0.82 : 0.62,
                evidence: "\(count) social nights, \(drinks) drinks total · \(lateNights.count) late",
                breaker: "Next dinner out, pick one earlier night this week. No perfection needed.",
                breakerAction: "Keep one early"
            ))
        }

        // 3) Hydration loop
        if s.waterGlasses < 6 {
            out.append(DeepHabit(
                id: "hydration",
                title: "Dehydration drag",
                cue: "Morning at desk, no water in sight",
                routine: "Coffee only until lunch → \(Int(s.waterGlasses)) glasses by 14:00",
                payoff: "None — just habit inertia",
                cost: "Energy dips, recovery slows",
                category: .nutrition,
                confidence: 0.78,
                evidence: "\(Int(s.waterGlasses)) glasses today · need ~8",
                breaker: "Put a full glass where you code. Finish it before coffee #2.",
                breakerAction: "Glass first"
            ))
        }

        // 4) Protein gap loop
        let proteinGap = max(0, Int(180 - s.protein))
        if proteinGap > 30 {
            out.append(DeepHabit(
                id: "protein_gap",
                title: "Protein under-shoot",
                cue: "Next meal, no protein anchor",
                routine: "Carbs/fat first → \(Int(s.protein))g by now, gap \(proteinGap)g",
                payoff: "Quick, tasty",
                cost: "Muscle recovery throttled, hunger returns fast",
                category: .nutrition,
                confidence: proteinGap > 50 ? 0.8 : 0.6,
                evidence: "\(Int(s.protein))g / 180g · \(proteinGap)g short",
                breaker: "Next plate: protein first, palm-sized. That's the whole rule.",
                breakerAction: "Protein first"
            ))
        }

        // 5) Sedentary day loop
        if s.steps < 6000 {
            out.append(DeepHabit(
                id: "sedentary",
                title: "Long still stretch",
                cue: "Desk 10:00–16:00 with one context",
                routine: "\(s.steps) steps by now → body stays in one mode",
                payoff: "Focus preserved short-term",
                cost: "Circulation, mood, and QOL dip",
                category: .movement,
                confidence: s.steps < 3500 ? 0.78 : 0.6,
                evidence: "\(s.steps) steps · target 10k",
                breaker: "One 12-min walk between calls. No gear, no app.",
                breakerAction: "12-min walk"
            ))
        }

        // 6) HRV dip without sleep cause — recovery loop
        if let hrv = s.hrv, let base = s.hrvBaseline, base > 0, hrv < base - 8 {
            let drop = Int(base - hrv)
            out.append(DeepHabit(
                id: "hrv_dip",
                title: "Recovery dip",
                cue: "Yesterday's load or short night",
                routine: "HRV \(Int(hrv))ms vs baseline \(Int(base))ms (−\(drop)ms)",
                payoff: "You pushed — good",
                cost: "Today's window is smaller than it looks",
                category: .recovery,
                confidence: drop > 15 ? 0.82 : 0.62,
                evidence: "HRV \(Int(hrv)) vs \(Int(base)) baseline · sleep \(String(format: "%.1f", s.sleepAverage))h",
                breaker: "Hold load steady today; don't add volume. Reassess tomorrow.",
                breakerAction: "Hold steady"
            ))
        }

        // Keep the most confident 3 — Lifestyle wants depth, not a list
        return out
            .sorted { $0.confidence > $1.confidence }
            .prefix(3)
            .map { $0 }
    }

    /// One-line ARIA insight derived from the top habit — used for the header card.
    public static func companionLine(for habits: [DeepHabit]) -> String? {
        guard let top = habits.first else { return nil }
        switch top.id {
        case "sleep_variance":
            return "I see a wobbly wind-down \(top.evidence.lowercased()). Want to try the kitchen-phone break tonight?"
        case "social_late":
            return "Late social nights are pushing your sleep \(top.evidence.lowercased()). One earlier night this week would move the needle."
        case "hydration":
            return "Water's low \(top.evidence.lowercased()) — one glass before coffee #2 is the smallest win."
        case "protein_gap":
            return "Protein's \(top.evidence.lowercased()) — next meal, protein first?"
        case "sedentary":
            return "Steps are \(top.evidence.lowercased()) — a 12-min walk between calls is enough."
        case "hrv_dip":
            return "Recovery dipped \(top.evidence.lowercased()). Holding steady today protects tomorrow."
        default:
            return "\(top.title): \(top.evidence) — \(top.breaker)"
        }
    }

    /// LifestyleTags ARIA will see — one tag per habit, stable id.
    public static func lifestyleTags(for habits: [DeepHabit]) -> [String] {
        habits.map { "habit:\($0.id):\($0.category.rawValue):\(Int($0.confidence * 100))" }
    }

    /// ARIA constraints derived from habits — e.g., cross_zone sleep hygiene
    public static func constraints(for habits: [DeepHabit]) -> [String] {
        var c: [String] = []
        if habits.contains(where: { $0.category == .sleep }) {
            c.append("habit:sleep_hygiene: protect 22:30 wind-down")
        }
        if habits.contains(where: { $0.category == .social }) {
            c.append("habit:social: one early night this week")
        }
        return c
    }
}
