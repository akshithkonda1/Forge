import Foundation

/// Procedural Forge brand mark — a hammer striking a flame.
///
/// Welcome / splash only. Not the ARIA nest. No PNG. Numbers lockstep with
/// `src/lib/forge-strike-mark.ts`. Motion is a one-shot strike, then a still
/// idle. Reduce Motion is the idle pose.
public enum ForgeStrikeMarkGeometry: Sendable {
    public static let kind = "hammer-strike"
    public static let assetName = "ForgeStrikeMark"
    public static let paintHz: Double = 12
    public static let tickInterval: Double = 1.0 / 12.0
    public static let strikeDuration: Double = 0.55
    public static let compactThreshold: Double = 36
    public static let heroMinimumSize: Double = 90
    public static let sparkCount = 6

    public static let paperHex = "F7F4F0"
    public static let emberHex = "FF4D00"
    public static let emberLightHex = "FF7A3D"
    public static let emberDarkHex = "C43A00"
    public static let amberHex = "FFB84D"

    /// Neck of the hammer — rotation origin in unit space.
    public static let pivotX: Double = 0.56
    public static let pivotY: Double = 0.60

    public static let raisedAngleDeg: Double = -54
    public static let impactAngleDeg: Double = 8
    public static let idleAngleDeg: Double = -24
    public static let idleFlare: Double = 0.34

    public struct Point: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public init(_ x: Double, _ y: Double) {
            self.x = x
            self.y = y
        }
    }

    public enum Command: Equatable, Sendable {
        case move(Double, Double)
        case line(Double, Double)
        case cubic(Double, Double, Double, Double, Double, Double)
        case close
    }

    public struct Spark: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var radius: Double
        public var opacity: Double
    }

    public struct Pose: Equatable, Sendable {
        public var hammerAngleDeg: Double
        public var flare: Double
        public var settled: Bool
    }

    public static func isCompact(size: Double) -> Bool {
        size < compactThreshold
    }

    public static func normalizedProgress(elapsed: Double) -> Double {
        min(1, max(0, elapsed / strikeDuration))
    }

    public static func pose(progress: Double, reduceMotion: Bool) -> Pose {
        if reduceMotion {
            return Pose(hammerAngleDeg: idleAngleDeg, flare: idleFlare, settled: true)
        }
        let p = min(1, max(0, progress))
        return Pose(
            hammerAngleDeg: hammerAngleDeg(progress: p),
            flare: flare(progress: p),
            settled: p >= 1
        )
    }

    public static func hammerAngleDeg(progress: Double) -> Double {
        let p = min(1, max(0, progress))
        if p <= 0.22 { return raisedAngleDeg }
        if p <= 0.40 {
            let t = (p - 0.22) / 0.18
            return lerp(raisedAngleDeg, impactAngleDeg, t * t * t)
        }
        if p <= 0.62 {
            let t = (p - 0.40) / 0.22
            let eased = 1 - pow(1 - t, 3)
            return lerp(impactAngleDeg, idleAngleDeg, eased)
        }
        return idleAngleDeg
    }

    public static func flare(progress: Double) -> Double {
        let p = min(1, max(0, progress))
        let pre = idleFlare * 0.45
        if p < 0.38 { return pre }
        if p < 0.46 {
            let t = (p - 0.38) / 0.08
            return lerp(pre, 1.0, t)
        }
        if p < 0.88 {
            let t = (p - 0.46) / 0.42
            return lerp(1.0, idleFlare, t)
        }
        return idleFlare
    }

    /// Hammer silhouette in local space (origin at the neck, +x along the handle).
    /// Tall cubic head + sharp inner corners so it reads as a hammer, not a spatula.
    public static func hammerCommands() -> [Command] {
        [
            .move(-0.30, -0.165),
            .line(-0.30, 0.165),
            .line(-0.085, 0.165),
            .line(-0.085, 0.058),
            .line(0.40, 0.050),
            .cubic(0.51, 0.050, 0.51, -0.050, 0.40, -0.050),
            .line(-0.085, -0.058),
            .line(-0.085, -0.165),
            .close
        ]
    }

    /// Flame tongue `0` back, `1` mid, `2` core. Unit space, y-down.
    public static func flameCommands(index: Int, flare amount: Double) -> [Command] {
        let f = min(1, max(0, amount))
        let rise = 0.62 + 0.38 * f
        switch index {
        case 0:
            return tongue(
                baseX: 0.34, baseY: 0.86,
                tipX: 0.16 - 0.04 * f, tipY: 0.86 - 0.62 * rise,
                width: 0.155 + 0.045 * f
            )
        case 1:
            return tongue(
                baseX: 0.40, baseY: 0.88,
                tipX: 0.36, tipY: 0.88 - 0.74 * rise,
                width: 0.120 + 0.035 * f
            )
        default:
            return tongue(
                baseX: 0.405, baseY: 0.84,
                tipX: 0.39, tipY: 0.84 - 0.44 * rise,
                width: 0.058 + 0.02 * f
            )
        }
    }

    public static func spark(index: Int, progress: Double, reduceMotion: Bool) -> Spark {
        let i = max(0, min(sparkCount - 1, index))
        if reduceMotion {
            return Spark(x: pivotX, y: pivotY, radius: 0, opacity: 0)
        }
        let p = min(1, max(0, progress))
        let birth = 0.40
        let life = 0.36
        let age = (p - birth) / life
        guard age > 0 else {
            return Spark(x: pivotX, y: pivotY, radius: 0.004, opacity: 0)
        }
        let travel = min(1, max(0, age))
        let fade = travel < 1 ? (1 - travel) : 0
        let seed = Double(i) * 17.13
        let angle = (-125.0 + Double(i) * 28.0 + 8 * sin(seed)) * .pi / 180
        let dist = (0.10 + 0.045 * Double(i % 3)) * travel
        return Spark(
            x: 0.41 + cos(angle) * dist,
            y: 0.64 + sin(angle) * dist,
            radius: 0.007 + 0.003 * hash01(seed),
            opacity: 0.85 * fade
        )
    }

    public static func impactGlowOpacity(flare amount: Double) -> Double {
        max(0, min(1, (amount - idleFlare) / (1 - idleFlare))) * 0.55
    }

    public static func impactGlowRadius(flare amount: Double) -> Double {
        0.04 + 0.05 * max(0, min(1, amount))
    }

    /// Serialize commands to an SVG path in a `viewBox` of `side` units.
    public static func svgPath(_ commands: [Command], side: Double = 100) -> String {
        commands.map { command in
            switch command {
            case .move(let x, let y):
                return "M \(fmt(x * side)) \(fmt(y * side))"
            case .line(let x, let y):
                return "L \(fmt(x * side)) \(fmt(y * side))"
            case .cubic(let cx1, let cy1, let cx2, let cy2, let x, let y):
                return "C \(fmt(cx1 * side)) \(fmt(cy1 * side)) \(fmt(cx2 * side)) \(fmt(cy2 * side)) \(fmt(x * side)) \(fmt(y * side))"
            case .close:
                return "Z"
            }
        }
        .joined(separator: " ")
    }

    public static func contrastRatio(hexA: String, hexB: String) -> Double {
        let a = relativeLuminance(hex: hexA)
        let b = relativeLuminance(hex: hexB)
        let lighter = max(a, b)
        let darker = min(a, b)
        return (lighter + 0.05) / (darker + 0.05)
    }

    // MARK: - Private

    private static func tongue(baseX: Double, baseY: Double, tipX: Double, tipY: Double, width: Double) -> [Command] {
        let left = baseX - width
        let right = baseX + width
        let rise = baseY - tipY
        return [
            .move(left, baseY),
            .cubic(
                left - width * 0.15, baseY - rise * 0.32,
                tipX - width * 0.58, tipY + rise * 0.24,
                tipX, tipY
            ),
            .cubic(
                tipX + width * 0.58, tipY + rise * 0.24,
                right + width * 0.15, baseY - rise * 0.32,
                right, baseY
            ),
            .cubic(
                baseX + width * 0.28, baseY + width * 0.38,
                baseX - width * 0.28, baseY + width * 0.38,
                left, baseY
            ),
            .close
        ]
    }

    private static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * min(1, max(0, t))
    }

    private static func hash01(_ seed: Double) -> Double {
        let n = sin(seed * 12.9898) * 43758.5453
        return n - floor(n)
    }

    private static func fmt(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private static func relativeLuminance(hex: String) -> Double {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF)
        let g = Double((int >> 8) & 0xFF)
        let b = Double(int & 0xFF)
        func channel(_ c: Double) -> Double {
            let s = c / 255
            return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }
}
