import SwiftUI

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
        return "Balanced drivers across sleep, recovery, stress, and energy. Readiness is a composite — not a single sensor."
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
/// Deliberately not `readinessColor(for:)` from Theme+Readiness.swift: that one
/// uses different thresholds, different colours and different words ("Primed /
/// Ready / Moderate / Recovery" against success/steel/warning/danger), and Chat
/// has a third variant again. Unifying them changes what three screens look
/// like, which is a design decision and not a side effect of moving files — so
/// the behaviour here is preserved exactly and merely given a name that cannot
/// collide with the other two now that it has left its single file.
enum HomeReadiness {
    static func color(_ score: Int) -> Color {
        switch score {
        case 85...: return Color.vitality
        case 70..<85: return Color.ember
        case 50..<70: return Color.steel
        default: return Color.alert
        }
    }

    static func label(_ score: Int) -> String {
        switch score {
        case 85...: return "Peak"
        case 70..<85: return "Good"
        case 50..<70: return "Fair"
        default: return "Low"
        }
    }
}

@MainActor
func homeStatusLine(store: AppStore) -> String {
    let score = store.readiness.overall
    switch score {
    case 85...: return "Primed to perform"
    case 70..<85: return "Recovered enough to train"
    case 55..<70: return "Train smart, not maximal"
    default: return "Protect recovery today"
    }
}
