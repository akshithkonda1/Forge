import Foundation

/// Phone Home readiness + Today Progress chrome tokens.
///
/// Lockstep with `shared/readiness.json`. Same palette, type, and ring
/// language — evolved toward solid geometry and motivation psychology.
/// Not a HUD costume. Home vocabulary is Peak / Good / Fair / Low — do
/// not invent clinical band names, and do not replace Nest
/// (`AriaNestGeometry`) with this chrome. Watch palettes stay elsewhere;
/// web may read the same file.
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

    /// Event-glow sample only. Ceiling is nest `paintHz` (12) — this chrome
    /// may spend 6 Hz for a close/log pulse, then pauses. Never an idle loop.
    public static let tickHz: Double = 6
    public static let tickHzCeiling: Double = 12
    public static let tickInterval: Double = 1.0 / 6.0
    public static let glowHz: Double = 0.35
    /// Cove chrome floor — armed major ticks never ride the glow breath.
    public static let tickChromeFloor: Double = 0.70
    public static let armedMajorTickOpacity: Double = 0.78
    public static let inArcMinimumScale: Double = 0.7

    /// Goal-gradient: 4/5 tracks (80%) is "almost there" — closing momentum.
    public static let almostTherePercent = 80
    public static let closingRemaining = 1
    public static let almostThereFloor: Double = 0.70
    /// Glow is a reward pulse, not a 6 Hz costume breath.
    public static let eventGlowOnly = true
    public static let liveGlowDefault = false
    public static let brackets = false
    public static let scanlines = false
    /// Miss / open states stay steel — never the Low alert red.
    public static let missHex = "7BA6F7"
    public static let glowRadius: Double = 5
    public static let tickMajorWidth: Double = 1.25
    public static let tickMinorWidth: Double = 0.55

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
            case .good: return "F5A524"
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

    /// Closing-the-ring: one track left, or the day is already at 80%+.
    public static func isAlmostThere(percent: Int, remaining: Int) -> Bool {
        let clamped = min(max(percent, 0), 100)
        return remaining == closingRemaining || (clamped >= almostTherePercent && clamped < 100)
    }

    public static func isClosed(_ percent: Int) -> Bool {
        percent >= 100
    }

    /// Per-track goal gradient (mosaic tiles, habits, water).
    public static func tileAlmostThere(_ progress: Double) -> Bool {
        progress >= almostThereFloor && progress < 1
    }

    /// Live clock only for an event pulse. Idle chrome stays still.
    public static func shouldRunClock(
        reduceMotion: Bool,
        sceneActive: Bool,
        onscreen: Bool,
        eventGlow: Bool
    ) -> Bool {
        let animate = eventGlowOnly ? eventGlow : (liveGlowDefault || eventGlow)
        return !isClockPaused(
            reduceMotion: reduceMotion,
            sceneActive: sceneActive,
            onscreen: onscreen,
            animate: animate
        )
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
    /// Decorative — head / arc shadow only. Tick chrome ignores this.
    public static func headGlow(time: Double, paused: Bool) -> Double {
        if paused { return 1 }
        return 0.62 + 0.38 * (0.5 + 0.5 * sin(time * .pi * 2 * glowHz))
    }

    public static func tickArmed(index: Int, sweep: Double) -> Bool {
        guard tickCount > 0 else { return false }
        return Double(index) / Double(tickCount) <= sweep + 0.0001
    }

    /// Tick paint is frozen. `glow` is accepted so tests prove breath cannot
    /// dip armed major chrome below `tickChromeFloor`.
    public static func paintedTickOpacity(major: Bool, armed: Bool, glow: Double) -> Double {
        _ = glow
        if major && armed { return max(tickChromeFloor, armedMajorTickOpacity) }
        if armed { return 0.42 }
        if major { return 0.28 }
        return 0.16
    }

    /// Accessibility content sizes keep only the score in-arc.
    public static func showsInArcMeta(isAccessibilitySize: Bool) -> Bool {
        !isAccessibilitySize
    }

    public static func containsBannedPhrase(_ line: String) -> String? {
        let lower = line.lowercased()
        return bannedSurfacePhrases.first { lower.contains($0) }
    }
}
