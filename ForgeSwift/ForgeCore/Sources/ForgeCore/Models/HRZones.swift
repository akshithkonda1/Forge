import SwiftUI

// MARK: - Heart-rate zones (shared iOS + watchOS)
//
// Ported from `hrZone(for:)` in ForgeSwift/Theme.swift so both platforms
// classify effort identically. Thresholds are the v1 fixed bands; a
// personalized (age/HRmax-based) model can replace `thresholds` later
// without touching call sites.

public struct ForgeHRZone: Equatable, Sendable {
    public let zone: Int
    public let label: String
    public let color: Color

    /// One supportive line per zone, used by in-workout coaching cues.
    /// Effort is framed as information, never as a demand.
    public var coachingLine: String {
        switch zone {
        case 1: return "Easy does it — this pace is pure recovery."
        case 2: return "Perfect Zone 2 — this is what building your base feels like."
        case 3: return "Strong steady work. Breathing hard but in control is the spot."
        case 4: return "High effort — great in doses. Listen for when it's enough."
        default: return "Max effort. Short and sharp, then let it go."
        }
    }
}

public enum ForgeHRZones {
    /// Upper bounds for zones 1-4 (zone 5 is everything above).
    /// Mirrors ForgeSwift/Theme.swift `hrZone(for:)`.
    static let thresholds: [Int] = [110, 130, 150, 165]

    public static func zone(for bpm: Int) -> ForgeHRZone {
        if bpm < thresholds[0] { return ForgeHRZone(zone: 1, label: "Zone 1", color: ForgePalette.textTertiary) }
        if bpm < thresholds[1] { return ForgeHRZone(zone: 2, label: "Zone 2", color: ForgePalette.steel) }
        if bpm < thresholds[2] { return ForgeHRZone(zone: 3, label: "Zone 3", color: ForgePalette.success) }
        if bpm < thresholds[3] { return ForgeHRZone(zone: 4, label: "Zone 4", color: ForgePalette.ember) }
        return ForgeHRZone(zone: 5, label: "Zone 5", color: ForgePalette.danger)
    }

    public static func zone(number: Int) -> ForgeHRZone {
        switch number {
        case ...1: return zone(for: thresholds[0] - 1)
        case 2:    return zone(for: thresholds[0])
        case 3:    return zone(for: thresholds[1])
        case 4:    return zone(for: thresholds[2])
        default:   return zone(for: thresholds[3])
        }
    }
}
