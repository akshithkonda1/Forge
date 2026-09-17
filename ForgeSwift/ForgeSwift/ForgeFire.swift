import SwiftUI

/// Brand hold on the launch splash. Long enough to read FORGE and feel the
/// fire — short of a freeze. Lockstep with `src/lib/forge-splash.ts`.
enum ForgeSplashTiming: Sendable {
    /// Cinematic hold. 2.45s lands the wordmark without looking stuck.
    static let hold: TimeInterval = 2.45
    static let reduceMotionHold: TimeInterval = 0.65
    static let fadeOut: TimeInterval = 0.38

    /// Hard ceiling so a future bump cannot become a frozen launch.
    static let freezeCeiling: TimeInterval = 3.1
    /// Floor so the beat is long enough to feel forged.
    static let brandFloor: TimeInterval = 2.0

    static func pauseNanoseconds(reduceMotion: Bool) -> UInt64 {
        if reduceMotion { return 650_000_000 }
        return 2_450_000_000
    }
}

/// How fierce the fire is. Welcome / splash use `.rage` — a roaring fire,
/// not the retired ember dust.
enum ForgeFireIntensity: String, Sendable, CaseIterable {
    case ember
    case rage

    var tongueCount: Int {
        switch self {
        case .ember: return 8
        case .rage: return 28
        }
    }

    var sparkCount: Int {
        switch self {
        case .ember: return 6
        case .rage: return 24
        }
    }

    var heightScale: Double {
        switch self {
        case .ember: return 0.34
        case .rage: return 1.0
        }
    }

    var coreHeat: Double {
        switch self {
        case .ember: return 0.28
        case .rage: return 0.94
        }
    }
}

enum ForgeFireOrigin: String, Sendable {
    case floor
    case hearth
}

/// Procedural fire — Forge brand moments only. Not the ARIA ring-field.
enum ForgeFireGeometry: Sendable {
    static let tickHz: Double = 12
    static let kind = "rage-fire"

    struct Tongue: Equatable, Sendable {
        var baseX: Double
        var baseY: Double
        var tipX: Double
        var tipY: Double
        var width: Double
        var heat: Double
        var waver: Double
    }

    struct Spark: Equatable, Sendable {
        var x: Double
        var y: Double
        var radius: Double
        var opacity: Double
    }

    static func tongue(
        index: Int,
        count: Int,
        time: Double,
        intensity: ForgeFireIntensity,
        origin: ForgeFireOrigin,
        reduceMotion: Bool
    ) -> Tongue {
        let i = max(0, min(max(count - 1, 0), index))
        let seed = Double(i) * 17.13
        let t = reduceMotion ? 0.18 : time
        let n = max(count, 1)
        let lane = Double(i) / Double(n - 1 == 0 ? 1 : n - 1)
        let heightScale = intensity.heightScale
        let flicker = reduceMotion ? 0.78 : (0.62 + 0.38 * (0.5 + 0.5 * sin(t * (2.4 + Double(i % 5) * 0.35) + seed)))
        let rise = (0.22 + 0.70 * hash01(seed + 2.1)) * heightScale * flicker

        switch origin {
        case .floor:
            let baseX = 0.06 + lane * 0.88 + (reduceMotion ? 0 : 0.03 * sin(t * 1.7 + seed))
            let baseY = 0.94 + 0.04 * hash01(seed + 11)
            let waver = reduceMotion ? 0 : 0.055 * sin(t * 3.2 + seed)
            return Tongue(
                baseX: baseX,
                baseY: baseY,
                tipX: baseX + waver * 1.55,
                tipY: baseY - rise,
                width: (0.034 + 0.055 * hash01(seed + 4)) * (0.75 + 0.55 * heightScale),
                heat: intensity.coreHeat * (0.72 + 0.28 * flicker),
                waver: waver
            )
        case .hearth:
            let angle = lane * .pi * 1.15 + .pi * 0.42
            let reach = (0.22 + 0.38 * hash01(seed)) * heightScale * flicker
            let cx = 0.5 + (reduceMotion ? 0 : 0.02 * sin(t * 1.4 + seed))
            let cy = 0.62
            let waver = reduceMotion ? 0 : 0.04 * sin(t * 3.6 + seed)
            return Tongue(
                baseX: cx + cos(angle) * 0.08,
                baseY: cy,
                tipX: cx + cos(angle) * reach + waver,
                tipY: cy - sin(angle * 0.35 + 0.9) * reach * 1.15,
                width: (0.04 + 0.03 * hash01(seed + 8)) * heightScale,
                heat: intensity.coreHeat * (0.7 + 0.3 * flicker),
                waver: waver
            )
        }
    }

    static func spark(
        index: Int,
        time: Double,
        intensity: ForgeFireIntensity,
        reduceMotion: Bool
    ) -> Spark {
        let seed = Double(index) * 23.71
        if reduceMotion {
            return Spark(
                x: hash01(seed),
                y: 0.55 + hash01(seed + 1) * 0.35,
                radius: 0.004,
                opacity: 0.12
            )
        }
        let speed = 0.18 + Double(index % 7) * 0.04
        let travel = (time * speed + hash01(seed)).truncatingRemainder(dividingBy: 1)
        let lift = intensity == .rage ? 1.0 : 0.45
        return Spark(
            x: hash01(seed + 3) * 0.92 + 0.04 + 0.04 * sin(time * 2.8 + seed),
            y: 1.05 - travel * (0.85 * lift),
            radius: 0.003 + hash01(seed + 5) * (intensity == .rage ? 0.007 : 0.003),
            opacity: (intensity == .rage ? 0.55 : 0.18) * (1 - travel) * (0.55 + 0.45 * hash01(seed + 9))
        )
    }

    private static func hash01(_ seed: Double) -> Double {
        let n = sin(seed * 12.9898) * 43758.5453
        return n - floor(n)
    }
}

/// Extra life on the ARIA ring-field. Draw-time only — does not change
/// `AriaSigilGeometry.ellipse` / PR270 contract numbers.
enum AriaSigilLife: Sendable {
    static let tickHz: Double = 12

    static func wobble(index: Int, time: Double, reduceMotion: Bool) -> Double {
        guard !reduceMotion else { return 0 }
        let phase = (AriaSigilGeometry.phaseOffsets[safe: index] ?? 0) * .pi * 2
        return 0.09 * sin(time * 1.55 + phase)
    }

    /// Contrast rings (contract opacities ≥ 0.70) keep a flicker wave, but the
    /// multiplier is floored so painted opacity never drops below the Cove floor.
    static func flicker(index: Int, time: Double, reduceMotion: Bool) -> Double {
        guard !reduceMotion else { return 1 }
        let phase = (AriaSigilGeometry.phaseOffsets[safe: index] ?? 0) * .pi * 2
        let wave = 0.78 + 0.22 * (0.5 + 0.5 * sin(time * 3.4 + phase))
        let base = AriaSigilGeometry.ringOpacities[safe: index] ?? 0
        if base >= AriaSigilGeometry.contrastFloor {
            return max(wave, AriaSigilGeometry.contrastFloor / base)
        }
        return wave
    }

    static func paintedOpacity(index: Int, time: Double, reduceMotion: Bool) -> Double {
        let base = AriaSigilGeometry.ringOpacities[safe: index] ?? 0
        return base * flicker(index: index, time: time, reduceMotion: reduceMotion)
    }

    static func glowPulse(time: Double, energy: Double, reduceMotion: Bool) -> Double {
        guard !reduceMotion else { return 1 }
        let wave = 0.5 + 0.5 * sin(time * 2.1)
        return 0.7 + 0.3 * wave * (0.5 + max(0, min(1, energy)))
    }

    static func breathScale(time: Double, hero: Bool, reduceMotion: Bool) -> CGFloat {
        guard !reduceMotion, hero else { return 1 }
        return 1 + 0.028 * CGFloat(sin(time * 2.35))
    }
}

private extension Array where Element == Double {
    subscript(safe index: Int) -> Double? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}
