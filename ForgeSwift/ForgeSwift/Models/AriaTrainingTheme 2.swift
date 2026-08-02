import Foundation
import SwiftUI

// MARK: - Training Theme

/// How ARIA frames programming: classic coach vs fandom / narrative styles.
/// Themes change language, session structure, and exercise selection — not medical claims.
enum AriaTrainingTheme: String, Codable, CaseIterable, Identifiable, Hashable {
    case classic
    case soloLeveling
    case demonSlayer
    case onePiece
    case martialArts
    case military
    case superhero
    case athlete

    var id: String { rawValue }

    var label: String {
        switch self {
        case .classic:      return "Classic Coach"
        case .soloLeveling: return "Solo Leveling"
        case .demonSlayer:  return "Demon Slayer"
        case .onePiece:     return "One Piece"
        case .martialArts:  return "Martial Artist"
        case .military:     return "Military Ops"
        case .superhero:    return "Superhero"
        case .athlete:      return "Elite Athlete"
        }
    }

    var tagline: String {
        switch self {
        case .classic:      return "Clear programming. No gimmicks."
        case .soloLeveling: return "Daily quests. Rank-up intensity. Level the player."
        case .demonSlayer:  return "Breath control, core steel, relentless form."
        case .onePiece:     return "Adventure strength — power, grit, and stamina."
        case .martialArts:  return "Striking base, mobility, fight-ready athleticism."
        case .military:     return "Discipline blocks, calisthenics, ruck-ready legs."
        case .superhero:    return "Hero work — strength, agility, and presence."
        case .athlete:      return "Sport performance: power, speed, recovery."
        }
    }

    var icon: String {
        switch self {
        case .classic:      return "figure.strengthtraining.traditional"
        case .soloLeveling: return "bolt.shield.fill"
        case .demonSlayer:  return "flame.fill"
        case .onePiece:     return "sailboat.fill"
        case .martialArts:  return "figure.martial.arts"
        case .military:     return "shield.lefthalf.filled"
        case .superhero:    return "sparkles"
        case .athlete:      return "medal.fill"
        }
    }

    var accentHex: String {
        switch self {
        case .classic:      return "F97316"
        case .soloLeveling: return "6366F1"
        case .demonSlayer:  return "EF4444"
        case .onePiece:     return "0EA5E9"
        case .martialArts:  return "A855F7"
        case .military:     return "22C55E"
        case .superhero:    return "EAB308"
        case .athlete:      return "14B8A6"
        }
    }

    /// Stored on `AriaContext.lifestyleTags` so backend + local path share preference.
    var lifestyleTag: String { "training_theme:\(rawValue)" }

    /// Keywords / phrases that map free-text to this theme (chat + onboarding notes).
    var detectionKeywords: [String] {
        switch self {
        case .classic:
            return []
        case .soloLeveling:
            return [
                "solo leveling", "sololeveling", "sung jinwoo", "jin-woo", "jinwoo",
                "shadow monarche", "shadow monarch", "hunter rank", "daily quest",
                "system quest", "e-rank", "s-rank", "gate clear", "level up hunter",
                "train like solo", "solo-leveling",
            ]
        case .demonSlayer:
            return [
                "demon slayer", "kimetsu", "tanjiro", "zenitsu", "inosuke",
                "breathing form", "total concentration", "hashira", "nichirin",
            ]
        case .onePiece:
            return [
                "one piece", "luffy", "zoro", "sanji", "gear second", "haki",
                "straw hat", "pirate training", "train like zoro",
            ]
        case .martialArts:
            return [
                "martial art", "mma", "muay thai", "boxing", "bjj", "karate",
                "taekwondo", "kickbox", "striking", "grappling",
            ]
        case .military:
            return [
                "military", "bootcamp", "special forces", "operator", "ruck",
                "pt test", "navy seal", "marine", "tactical",
            ]
        case .superhero:
            return [
                "superhero", "batman", "captain america", "spider-man", "spiderman",
                "hero training", "avenger", "train like batman",
            ]
        case .athlete:
            return [
                "elite athlete", "sport performance", "pro athlete", "combine",
                "speed and power", "athletic performance",
            ]
        }
    }

    /// Readiness-band labels used in themed copy.
    func rankLabel(for readiness: Int) -> String {
        switch self {
        case .soloLeveling:
            if readiness >= 90 { return "S-Rank window" }
            if readiness >= 80 { return "A-Rank window" }
            if readiness >= 70 { return "B-Rank window" }
            if readiness >= 55 { return "C-Rank window" }
            return "Recovery dungeon — no forced clears"
        case .demonSlayer:
            if readiness >= 80 { return "Hashira-level focus" }
            if readiness >= 60 { return "Corps training day" }
            return "Breath recovery day"
        case .onePiece:
            if readiness >= 80 { return "Grand Line push" }
            if readiness >= 60 { return "Crew training" }
            return "Log Pose rest day"
        case .military:
            if readiness >= 80 { return "Green-light ops" }
            if readiness >= 60 { return "Standard PT" }
            return "Admin / recovery"
        case .superhero:
            if readiness >= 80 { return "Hero mode" }
            if readiness >= 60 { return "Patrol fitness" }
            return "Cave recovery"
        case .martialArts:
            if readiness >= 80 { return "Fight camp intensity" }
            if readiness >= 60 { return "Technical spar day" }
            return "Mobility & film day"
        case .athlete:
            if readiness >= 80 { return "Performance day" }
            if readiness >= 60 { return "Quality volume" }
            return "Regeneration block"
        case .classic:
            if readiness >= 80 { return "High readiness" }
            if readiness >= 60 { return "Moderate readiness" }
            return "Low readiness"
        }
    }
}

// MARK: - Theme resolution

enum AriaThemeResolver {
    /// Prefer explicit chat intent → profile preference → lifestyle tags → classic.
    static func resolve(
        input: String? = nil,
        preferred: AriaTrainingTheme? = nil,
        lifestyleTags: [String] = [],
        freeTimeTags: [String] = []
    ) -> AriaTrainingTheme {
        if let input, let fromChat = detect(in: input) {
            return fromChat
        }
        if let preferred, preferred != .classic {
            return preferred
        }
        if let fromTags = detectFromTags(lifestyleTags + freeTimeTags) {
            return fromTags
        }
        return preferred ?? .classic
    }

    static func detect(in text: String) -> AriaTrainingTheme? {
        let lower = text.lowercased()
        // Longer / more specific themes first so "solo leveling" wins over generic "level".
        let ordered: [AriaTrainingTheme] = [
            .soloLeveling, .demonSlayer, .onePiece, .martialArts,
            .military, .superhero, .athlete,
        ]
        for theme in ordered {
            if theme.detectionKeywords.contains(where: { lower.contains($0) }) {
                return theme
            }
        }
        // Soft intent: "train like …" without a known franchise → leave nil (caller uses preferred).
        return nil
    }

    static func detectFromTags(_ tags: [String]) -> AriaTrainingTheme? {
        for tag in tags {
            if tag.hasPrefix("training_theme:"),
               let raw = tag.split(separator: ":").last,
               let theme = AriaTrainingTheme(rawValue: String(raw)),
               theme != .classic {
                return theme
            }
        }
        return nil
    }

    /// True when the user is asking for a themed or general training plan.
    static func isPlanRequest(_ text: String) -> Bool {
        let lower = text.lowercased()
        if detect(in: lower) != nil { return true }
        let phrases = [
            "what should i", "train today", "workout today", "what should we",
            "training plan", "workout plan", "build me a", "create a plan",
            "make me a", "program for", "session for", "train like",
            "daily quest", "level up", "give me a workout", "plan my",
            "how should i train", "program today", "today's workout",
            "todays workout", "design a", "coach me",
        ]
        return phrases.contains { lower.contains($0) }
    }

    /// User is explicitly locking a theme preference for future sessions.
    static func isThemePreferenceLock(_ text: String) -> Bool {
        let lower = text.lowercased()
        let locks = [
            "from now on", "always train", "my theme", "set my theme",
            "i like training like", "i want to train like", "prefer",
            "make that my", "stick with",
        ]
        return detect(in: lower) != nil && locks.contains { lower.contains($0) }
    }
}
