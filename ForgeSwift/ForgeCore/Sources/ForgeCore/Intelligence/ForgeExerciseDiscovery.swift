import Foundation

/// Rank unused exercises that fit gym and gear. Inspectable linear score.
public enum ForgeExerciseDiscovery: Sendable {

    public enum Feedback: String, Codable, Sendable {
        case tried
        case notInterested
        case saved
    }

    public struct Candidate: Equatable, Sendable {
        public var id: String
        public var name: String
        public var score: Double
        public var reasons: [String]

        /// Inspectable, not a black box.
        public var scoreLabel: String {
            String(format: "Score %.0f", score * 100)
        }
    }

    public struct Memory: Codable, Equatable, Sendable {
        public var gymType: String
        public var equipmentNotes: String
        public var tried: [String]
        public var suppressed: [String: Double]
        public var saved: [String]

        public init(
            gymType: String = "commercial gym",
            equipmentNotes: String = "",
            tried: [String] = [],
            suppressed: [String: Double] = [:],
            saved: [String] = []
        ) {
            self.gymType = gymType
            self.equipmentNotes = equipmentNotes
            self.tried = tried
            self.suppressed = suppressed
            self.saved = saved
        }
    }

    public struct Exercise: Equatable, Sendable {
        public var id: String
        public var name: String
        public var equipment: String
        public var triedBefore: Bool

        public init(id: String, name: String, equipment: String, triedBefore: Bool = false) {
            self.id = id
            self.name = name
            self.equipment = equipment
            self.triedBefore = triedBefore
        }
    }

    public static func fits(_ item: Exercise, memory: Memory) -> Bool {
        let eq = item.equipment.lowercased()
        if eq.contains("bodyweight") || eq.isEmpty { return true }
        let gear = (memory.gymType + " " + memory.equipmentNotes).lowercased()
        if gear.contains("commercial") || gear.contains("industrial") || gear.contains("crossfit") {
            return true
        }
        if gear.contains(eq) { return true }
        return gearTokens.contains { gear.contains($0) && eq.contains($0) }
    }

    public static func rank(
        catalog: [Exercise],
        memory: Memory,
        trainingModel: String,
        goals: [String],
        readiness: Int,
        load: Int = 40,
        engagement: Double = 0,
        conditions: [ForgeLifestyleProfile.HealthConstraint] = [],
        freeform: String = ""
    ) -> [Candidate] {
        let seizureAware = conditions.contains(.seizures) || conditions.contains(.epilepsy)
        let diabetesAware = conditions.contains(.diabetes)
        let adhdAware = conditions.contains(.adhd)
        let adaptedModel = ForgeConditionAdaptation.applyToTrainingModel(
            trainingModel,
            conditions: conditions,
            freeform: freeform
        )
        var out: [Candidate] = []
        for item in catalog {
            if item.triedBefore || memory.tried.contains(item.id) { continue }
            if memory.saved.contains(item.id) { continue }
            if let decay = memory.suppressed[item.id], decay > 0.4 { continue }
            guard fits(item, memory: memory) else { continue }
            if seizureAware, ForgeConditionAdaptation.isSoloHighRisk(item.name) { continue }
            var score = 0.4
            var reasons: [String] = ["Fits unused catalog"]
            score += 0.25
            reasons.append("Matches gym/gear")
            if !adaptedModel.isEmpty {
                score += 0.15
                reasons.append("Adaptive training model")
            }
            if seizureAware {
                score += 0.04
                reasons.append("Here's what works with your body — grounded intensity, rest windows")
            }
            if diabetesAware {
                score += 0.03
                reasons.append("Blood-sugar-aware timing and fueling reminders")
            }
            if adhdAware {
                score += 0.03
                reasons.append("Short blocks, variety, one clear next step")
            }
            if readiness >= 70 {
                score += 0.1
                reasons.append("Readiness supports a new try")
            } else {
                score -= 0.05
                reasons.append("Readiness says keep it light")
            }
            if load >= 75 {
                score -= 0.08
                reasons.append("Load is high — keep it light")
            } else {
                score += 0.05
                reasons.append("Load leaves room for something new")
            }
            if engagement > 0.3 {
                score += 0.05
                reasons.append("Past engagement")
            }
            if goals.contains(where: { item.name.lowercased().contains($0.lowercased()) }) {
                score += 0.1
                reasons.append("Goal overlap")
            }
            let clamped = min(1, max(0, score))
            reasons.insert(String(format: "Score %.0f", clamped * 100), at: 0)
            out.append(Candidate(id: item.id, name: item.name, score: clamped, reasons: reasons))
        }
        return out.sorted { $0.score > $1.score }
    }

    public static func applyFeedback(
        _ memory: Memory,
        id: String,
        feedback: Feedback,
        catalog: [Exercise] = []
    ) -> Memory {
        var next = memory
        switch feedback {
        case .tried:
            if !next.tried.contains(id) { next.tried.append(id) }
            next.suppressed[id] = nil
            next.saved.removeAll { $0 == id }
        case .notInterested:
            next.suppressed[id] = 1
            if let item = catalog.first(where: { $0.id == id }) {
                for other in catalog where other.id != id && other.equipment.lowercased() == item.equipment.lowercased() {
                    next.suppressed[other.id] = max(next.suppressed[other.id] ?? 0, 0.7)
                }
            }
        case .saved:
            if !next.saved.contains(id) { next.saved.append(id) }
        }
        var decayed: [String: Double] = [:]
        for (key, value) in next.suppressed {
            let nextValue = value * 0.85
            if nextValue > 0.08 { decayed[key] = nextValue }
        }
        next.suppressed = decayed
        return next
    }

    public static let suggestLine =
        "Here's something new you could try with what you've got."

    public static let gearTokens = [
        "dumbbell", "barbell", "kettlebell", "rack", "bench", "cable",
        "band", "treadmill", "bike", "rower", "trap bar", "pull-up bar",
        "rings", "sled",
    ]

    /// Learn exact gear from chat or a logged session. Never overwrites a user edit
    /// of the same token; only appends missing tokens.
    public static func learnEquipment(notes: String, from text: String) -> String {
        var parts = notes
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        let lower = text.lowercased()
        for token in gearTokens where lower.contains(token) {
            if !parts.contains(where: { $0.contains(token) }) {
                parts.append(token)
            }
        }
        return parts.joined(separator: ", ")
    }
}
