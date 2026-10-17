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

    public static func rank(
        catalog: [Exercise],
        memory: Memory,
        trainingModel: String,
        goals: [String],
        readiness: Int
    ) -> [Candidate] {
        let gear = (memory.gymType + " " + memory.equipmentNotes).lowercased()
        var out: [Candidate] = []
        for item in catalog {
            if item.triedBefore || memory.tried.contains(item.id) { continue }
            if let decay = memory.suppressed[item.id], decay > 0.4 { continue }
            var score = 0.4
            var reasons: [String] = ["Fits unused catalog"]
            let eq = item.equipment.lowercased()
            if gear.contains(eq) || eq.contains("bodyweight") || gear.isEmpty {
                score += 0.25
                reasons.append("Matches gym/gear")
            }
            if !trainingModel.isEmpty {
                score += 0.15
                reasons.append("Adaptive training model")
            }
            if readiness >= 70 {
                score += 0.1
                reasons.append("Readiness supports a new try")
            } else {
                score -= 0.05
                reasons.append("Readiness says keep it light")
            }
            if goals.contains(where: { item.name.lowercased().contains($0.lowercased()) }) {
                score += 0.1
                reasons.append("Goal overlap")
            }
            if memory.saved.contains(item.id) {
                score += 0.2
                reasons.append("Saved for later")
            }
            out.append(Candidate(id: item.id, name: item.name, score: min(1, score), reasons: reasons))
        }
        return out.sorted { $0.score > $1.score }
    }

    public static func applyFeedback(_ memory: Memory, id: String, feedback: Feedback) -> Memory {
        var next = memory
        switch feedback {
        case .tried:
            if !next.tried.contains(id) { next.tried.append(id) }
            next.suppressed[id] = nil
        case .notInterested:
            next.suppressed[id] = 1
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
