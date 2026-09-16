import Foundation

// MARK: - Living character (how you live, not who your uncle is)
//
// Closed chips only. No family tree, no addresses, no SF-86. ARIA keeps this
// on-device so split-second replies (Dummy, training flavor, Lifestyle) can
// read who you are as a human without a model round-trip.

public enum LivingMovementPreference: String, Codable, CaseIterable, Sendable {
    case cardio
    case strength
    case mix

    public var title: String {
        switch self {
        case .cardio: return "Cardio"
        case .strength: return "Strength"
        case .mix: return "A mix"
        }
    }

    public var livingTag: String { "living:move:\(rawValue)" }
}

public enum LivingEatingRhythm: String, Codable, CaseIterable, Sendable {
    case light
    case moderate
    case heavy

    public var title: String {
        switch self {
        case .light: return "Light eater"
        case .moderate: return "Moderate"
        case .heavy: return "I eat a lot"
        }
    }

    public var livingTag: String { "living:volume:\(rawValue)" }
}

public enum LivingHobby: String, Codable, CaseIterable, Sendable {
    case outdoors
    case gym
    case cooking
    case making
    case music
    case reading
    case games
    case rest

    public var title: String {
        switch self {
        case .outdoors: return "Being outside"
        case .gym: return "The gym"
        case .cooking: return "Cooking"
        case .making: return "Making things"
        case .music: return "Music"
        case .reading: return "Reading"
        case .games: return "Games"
        case .rest: return "Resting at home"
        }
    }

    public var livingTag: String { "living:hobby:\(rawValue)" }
}

public extension QualityOfLifePersona {
    /// Compact tag vocabulary Dummy / PlanEngine / Habit paths can read locally.
    func livingTags() -> [String] {
        var tags: [String] = []
        if archetype != .unset {
            tags.append("living:archetype:\(archetype.rawValue)")
        }
        if let food = nutritionRelationship?.trimmingCharacters(in: .whitespacesAndNewlines),
           !food.isEmpty {
            tags.append("living:eat:\(food.lowercased())")
        }
        if let rhythm = eatingRhythm {
            tags.append(rhythm.livingTag)
        }
        if let move = movementPreference {
            tags.append(move.livingTag)
        }
        for hobby in (hobbies ?? []).prefix(4) {
            tags.append(hobby.livingTag)
        }
        if let hours = sleepNeedPreferenceHours {
            tags.append(String(format: "living:sleep_need:%.1f", hours))
        }
        return tags
    }

    /// One paragraph ARIA can speak without calling the model.
    func characterLine() -> String {
        var parts: [String] = []
        if archetype != .unset {
            parts.append("You live like a \(archetype.title.lowercased()).")
        }
        if let move = movementPreference, move != .mix {
            parts.append("You typically like \(move.title.lowercased()).")
        } else if movementPreference == .mix {
            parts.append("You like a mix of cardio and strength.")
        }
        let hobbyTitles = (hobbies ?? []).prefix(3).map { $0.title.lowercased() }
        if !hobbyTitles.isEmpty {
            parts.append("Free days: \(hobbyTitles.joined(separator: ", ")).")
        }
        if let food = nutritionRelationship?.trimmingCharacters(in: .whitespacesAndNewlines),
           !food.isEmpty {
            var foodBit = "Food is \(food)"
            if let rhythm = eatingRhythm {
                foodBit += ", \(rhythm.title.lowercased())"
            }
            parts.append(foodBit + ".")
        } else if let rhythm = eatingRhythm {
            parts.append("\(rhythm.title).")
        }
        if let hours = sleepNeedPreferenceHours {
            parts.append(String(format: "Sleep want about %.1f hours.", hours))
        }
        parts.append("I keep this on-device so I don't have to ask the model who you are.")
        return parts.joined(separator: " ")
    }

    /// Short flavor for a local training decision — never a second personality quiz.
    static func livingDecisionNote(from tags: [String]) -> String? {
        let move = tags.first { $0.hasPrefix("living:move:") }
            .map { String($0.dropFirst("living:move:".count)) }
        let hobbies = tags.compactMap { tag -> String? in
            guard tag.hasPrefix("living:hobby:") else { return nil }
            return LivingHobby(rawValue: String(tag.dropFirst("living:hobby:".count)))?.title.lowercased()
        }
        var bits: [String] = []
        if let move, move != "mix", let pref = LivingMovementPreference(rawValue: move) {
            bits.append("You like \(pref.title.lowercased())")
        }
        if let first = hobbies.first {
            if hobbies.count > 1 {
                bits.append("free days lean \(first) and \(hobbies[1])")
            } else {
                bits.append("free days lean \(first)")
            }
        }
        guard !bits.isEmpty else { return nil }
        return bits.joined(separator: "; ") + " — pulled from your local profile."
    }
}

public extension QualityOfLifeLivingStore {
    static func livingTags(defaults: UserDefaults = .standard) -> [String] {
        loadPersona(defaults: defaults).livingTags()
    }

    /// Chat that is asking who they are as a human — answer from the local
    /// persona, never mint a model biography.
    static func isCharacterQuestion(_ text: String) -> Bool {
        if isQuestion(text) { return false }
        let lower = text.lowercased()
        let phrases = [
            "who am i",
            "who i am",
            "who you think i am",
            "how do i live",
            "how i live",
            "what do you know about me",
            "what you know about me",
            "my lifestyle profile",
            "my character",
            "what are my hobbies",
            "how do i usually train",
            "do i like cardio",
            "do i like strength",
        ]
        return phrases.contains { lower.contains($0) }
    }

    static func characterLine(
        defaults: UserDefaults = .standard,
        variety: Int = 0
    ) -> String {
        let persona = loadPersona(defaults: defaults)
        let hasLiving = persona.archetype != .unset && persona.archetype != .balanced
            || persona.movementPreference != nil
            || !(persona.hobbies ?? []).isEmpty
            || persona.nutritionRelationship != nil
            || persona.eatingRhythm != nil
        if !hasLiving && persona.archetype == .balanced
            && persona.movementPreference == nil
            && (persona.hobbies ?? []).isEmpty
            && persona.nutritionRelationship == nil {
            let missing = [
                "I don't have a living profile yet. Open Lifestyle and tell me how you live — how you eat, how you like to move, what fills a free day. I keep that on-device.",
                "No living character on file. Lifestyle interview is how I learn the shape of your week, not your family tree.",
                "Tell me how you live in Lifestyle and I'll keep it local — hobbies, eating rhythm, cardio vs strength. No model trip for that.",
            ]
            let index = variety < 0 ? 0 : variety
            return missing[index % missing.count]
        }
        let line = persona.characterLine()
        let openers = ["", "Same profile Life uses. ", "On-device, not a model guess: "]
        let index = variety < 0 ? 0 : variety
        return openers[index % openers.count] + line
    }
}
