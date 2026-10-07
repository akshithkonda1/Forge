import SwiftUI
import ForgeCore

@MainActor
func readinessWhyCopy(store: AppStore) -> String {
    var bits: [String] = []
    let r = store.readiness
    if r.sleepQuality < 55 {
        bits.append("Sleep quality is dragging the score")
    } else if r.sleepQuality >= 80 {
        bits.append("Sleep looks supportive")
    }
    if r.recoveryScore < 55 {
        bits.append("recovery markers are soft")
    } else if r.recoveryScore >= 80 {
        bits.append("recovery is solid")
    }
    if r.stressLevel >= 65 {
        bits.append("stress is elevated")
    }
    if r.energyBank < 50 {
        bits.append("energy bank is low")
    }
    let cycle = MenstrualHealthStore.shared
    if cycle.settings.enabled, cycle.settings.shareWithAria, cycle.snapshot.recommendRecoveryBias {
        bits.append("cycle phase suggests a recovery bias")
    }
    if bits.isEmpty {
        return "Sleep, recovery, stress, and energy are in balance. This isn’t one sensor — it’s how today looks together."
    }
    let joined = bits.joined(separator: "; ")
    return joined.prefix(1).uppercased() + joined.dropFirst() + "."
}

/// Cycle already lives on a chip. Don't repeat " · Follicular" in the title.
func displaySessionName(_ name: String) -> String {
    let suffixes = ["Menstruation", "Follicular", "Fertile", "Ovulation", "Luteal"]
    for suffix in suffixes {
        let mark = " · \(suffix)"
        if name.hasSuffix(mark) {
            return String(name.dropLast(mark.count))
        }
    }
    return name
}

/// Home's own readiness palette and vocabulary.
///
/// Cuts, hex, and Peak / Good / Fair / Low labels come from
/// `shared/readiness.json` via `HomeReadinessTokens`. Deliberately not
/// `readinessColor(for:)` from Theme+Readiness.swift ("Primed / Ready /
/// Moderate / Recovery") and not ForgeCore `ReadinessBand`. Unifying those
/// is a later design pass — Home keeps its words.
enum HomeReadiness {
    static func color(_ score: Int) -> Color {
        Color(hex: HomeReadinessTokens.hex(for: score))
    }

    static func label(_ score: Int) -> String {
        HomeReadinessTokens.label(for: score)
    }

    /// Spoken band — same cuts as `label`, written for VoiceOver.
    static func voiceOverLabel(_ score: Int) -> String {
        "Readiness \(score) out of 100, \(label(score))"
    }
}

/// Friend-coach strings for the Home primary action. Never "recovery week"
/// or "recovery-first" — those are banned product copy.
enum HomeCoachCopy {
    static let easySessionTitle = "Easy session"
    static let easyDayGuidance = "Easy day — keep the structure, skip the intensity."
    static let easyDayLow = "You're running a bit low. Keep today light."

    static func pulledBack(score: Int) -> String {
        "You're at \(score)%. This session is already pulled back."
    }

    static let bannedPhrases = ["recovery-first", "recovery week"]
}

/// Lifestyle deep-links Home and ARIA already send. Kept here so tests can
/// lock "At Home" / tomorrow without spinning the whole Lifestyle view.
enum LifestyleDeepLink {
    static func segment(from raw: String) -> LifestyleSegment? {
        switch raw.lowercased() {
        case "nutrition": return .nutrition
        case "restaurants", "meals", "food", "places", "map": return .restaurants
        case "wellbeing", "wellness": return .wellbeing
        case "ai", "aioptimization", "optimize": return .aiOptimization
        case "lifetime", "aging", "heart", "cardio", "metabolic", "glucose", "stelo":
            return .lifetime
        case "cook", "cooking", "homecooking": return .homeCooking
        case "home", "athome", "at-home", "tomorrow":
            return .wellbeing
        default: return LifestyleSegment(rawValue: Int(raw) ?? -1)
        }
    }
}

@MainActor
func homeStatusLine(store: AppStore) -> String {
    let score = store.readiness.overall
    switch score {
    case 85...: return "You’re at \(score). You look ready."
    case 70..<85: return "You’re at \(score). A solid session fits."
    case 55..<70: return "You’re at \(score). Train smart, not maximal."
    default: return "You’re at \(score). Easy session today."
    }
}
