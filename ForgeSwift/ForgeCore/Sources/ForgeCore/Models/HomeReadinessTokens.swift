import Foundation

/// Phone Home readiness + Today Progress HUD tokens.
///
/// Lockstep with `shared/readiness.json`. Home vocabulary is Peak / Good /
/// Fair / Low — do not invent clinical band names, and do not replace Nest
/// (`AriaNestGeometry`) with this chrome. Watch / web palettes stay elsewhere.
public enum HomeReadinessTokens: Sendable {
    public static let kind = "home-progress-hud"
    public static let surface = "phone-home"
    public static let mixLock = "chrome-not-nest"

    public static let plateHex = "7EC8FF"
    public static let emberSteelHex = "7BA6F7"

    public static let tickCount = 48
    public static let majorEvery = 6
    public static let ringSize: Double = 168
    public static let compactRingSize: Double = 92
    public static let stroke: Double = 5.5
    public static let compactStroke: Double = 4.5

    /// Lean HUD glow sample. Ceiling is nest `paintHz` (12) — this chrome
    /// spends 6 Hz and pauses when Reduce Motion, backgrounded, or offscreen.
    public static let tickHz: Double = 6
    public static let tickHzCeiling: Double = 12
    public static let tickInterval: Double = 1.0 / 6.0
    public static let glowHz: Double = 0.35

    public static let plotFloor = 30
    public static let plotCap = 100
    public static let trendWindowDays = 7
    public static let trendWindowAnchor = "lastNight"
    public static let trendPoints = "window"
    public static let nightDate = "bedtime"
    public static let nightCutoffHour = 12

    public static let bannedSurfacePhrases = [
        "diagnos", "treat", "prescribe", "cure", "medical advice",
        "recovery-first", "recovery week"
    ]

    /// Theme / Watch band words that Home HUD must not adopt.
    public static let foreignBandLabels = ["Primed", "Ready", "Moderate", "Recovery"]

    public enum Band: String, CaseIterable, Sendable {
        case peak
        case good
        case fair
        case low

        public var label: String {
            switch self {
            case .peak: return "Peak"
            case .good: return "Good"
            case .fair: return "Fair"
            case .low: return "Low"
            }
        }

        public var hex: String {
            switch self {
            case .peak: return "22C55E"
            case .good: return "FF4D00"
            case .fair: return "5B8DEF"
            case .low: return "EF4444"
            }
        }

        public var minScore: Int {
            switch self {
            case .peak: return 85
            case .good: return 70
            case .fair: return 50
            case .low: return 0
            }
        }
    }

    public static func band(for score: Int) -> Band {
        switch min(max(score, 0), 100) {
        case 85...: return .peak
        case 70..<85: return .good
        case 50..<70: return .fair
        default: return .low
        }
    }

    public static func label(for score: Int) -> String {
        band(for: score).label
    }

    public static func hex(for score: Int) -> String {
        band(for: score).hex
    }

    public static func sweep(from percent: Int) -> Double {
        Double(min(max(percent, 0), 100)) / 100.0
    }

    /// Reduce Motion paints the finished ring. Live paint may still be filling.
    public static func ringSweep(
        percent: Int,
        reduceMotion: Bool,
        animatedProgress: Double?
    ) -> Double {
        if reduceMotion { return sweep(from: percent) }
        return animatedProgress ?? sweep(from: percent)
    }

    public static func isClockPaused(
        reduceMotion: Bool,
        sceneActive: Bool,
        onscreen: Bool,
        animate: Bool
    ) -> Bool {
        reduceMotion || !sceneActive || !onscreen || !animate
    }

    /// Still pose is full glow. Live pose is a slow breath sampled at `tickHz`.
    public static func headGlow(time: Double, paused: Bool) -> Double {
        if paused { return 1 }
        return 0.62 + 0.38 * (0.5 + 0.5 * sin(time * .pi * 2 * glowHz))
    }

    public static func tickArmed(index: Int, sweep: Double) -> Bool {
        guard tickCount > 0 else { return false }
        return Double(index) / Double(tickCount) <= sweep + 0.0001
    }

    public static func containsBannedPhrase(_ line: String) -> String? {
        let lower = line.lowercased()
        return bannedSurfacePhrases.first { lower.contains($0) }
    }
}
