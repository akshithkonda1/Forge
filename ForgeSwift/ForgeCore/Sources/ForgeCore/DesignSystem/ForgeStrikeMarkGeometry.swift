import Foundation

/// Procedural Forge brand mark — a hammer striking a flame.
///
/// Welcome / splash only. Not the ARIA nest. No PNG. Numbers lockstep with
/// `src/lib/forge-strike-mark.ts`. Motion is a one-shot strike, then a still
/// idle. Reduce Motion is the idle pose.
///
/// Geometry sits on a 200-unit grid (step 0.005) inside a 1×1 optical box.
public enum ForgeStrikeMarkGeometry: Sendable {
    public static let kind = "hammer-strike"
    public static let assetName = "ForgeStrikeMark"
    public static let paintHz: Double = 12
    public static let tickInterval: Double = 1.0 / 12.0
    public static let strikeDuration: Double = 0.56
    public static let compactThreshold: Double = 36
    public static let heroMinimumSize: Double = 90
    public static let sparkCount = 6
    public static let flameLayerCount = 4
    public static let gridStep: Double = 0.005

    public static let paperHex = "F7F4F0"
    public static let paperShadeHex = "E8E4DE"
    public static let emberHex = "FF4D00"
    public static let emberLightHex = "FF7A3D"
    public static let emberDarkHex = "C43A00"
    public static let amberHex = "FFB84D"
    public static let kernelHex = "FFE6A8"

    /// Eye of the hammer — rotation origin in unit space.
    public static let pivotX: Double = 0.68
    public static let pivotY: Double = 0.50
    public static let strikeX: Double = 0.50
    public static let strikeY: Double = 0.62
    public static let flameOriginX: Double = 0.36
    public static let flameOriginY: Double = 0.860

    public static let raisedAngleDeg: Double = 16
    public static let impactAngleDeg: Double = -44
    public static let idleAngleDeg: Double = -30
    public static let idleFlare: Double = 0.40
    public static let holdEnd: Double = 0.14
    public static let impactEnd: Double = 0.32

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

    public struct FlareScale: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var originX: Double
        public var originY: Double
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
        if p <= holdEnd { return raisedAngleDeg }
        if p <= impactEnd {
            let t = (p - holdEnd) / (impactEnd - holdEnd)
            return lerp(raisedAngleDeg, impactAngleDeg, pow(t, 4))
        }
        return lerp(impactAngleDeg, idleAngleDeg, spring01((p - impactEnd) / (1 - impactEnd)))
    }

    public static func flare(progress: Double) -> Double {
        let p = min(1, max(0, progress))
        let pre = idleFlare * 0.5
        let wind = impactEnd - 0.02
        if p < wind { return pre }
        if p < impactEnd + 0.04 {
            let t = (p - wind) / 0.06
            return lerp(pre, 1.0, min(1, max(0, t)))
        }
        if p < 0.86 {
            return lerp(1.0, idleFlare, spring01((p - 0.36) / 0.5))
        }
        return idleFlare
    }

    public static func flareScale(flare amount: Double) -> FlareScale {
        let f = min(1, max(0, amount))
        return FlareScale(
            x: 0.94 + 0.06 * f,
            y: 0.74 + 0.26 * f,
            originX: flameOriginX,
            originY: flameOriginY
        )
    }

    public static func spring01(_ t: Double) -> Double {
        let p = min(1, max(0, t))
        let zeta = 0.62
        let omega = 9.2
        let wd = omega * sqrt(1 - zeta * zeta)
        let env = exp(-zeta * omega * p)
        return 1 - env * (cos(wd * p) + ((zeta * omega) / wd) * sin(wd * p))
    }

    /// Hammer silhouette in local space (origin at the eye, +x along the handle).
    public static func hammerCommands() -> [Command] {
        [
            .move(-0.243, -0.102),
            .cubic(-0.252, -0.102, -0.258, -0.095, -0.258, -0.086),
            .line(-0.258, 0.086),
            .cubic(-0.258, 0.095, -0.252, 0.102, -0.243, 0.102),
            .line(-0.040, 0.090),
            .cubic(-0.028, 0.090, -0.022, 0.084, -0.022, 0.074),
            .line(-0.022, 0.038),
            .cubic(-0.022, 0.033, -0.018, 0.030, -0.012, 0.030),
            .line(0.340, 0.027),
            .cubic(0.368, 0.027, 0.368, -0.027, 0.340, -0.027),
            .line(-0.012, -0.030),
            .cubic(-0.018, -0.030, -0.022, -0.033, -0.022, -0.038),
            .line(-0.022, -0.074),
            .cubic(-0.022, -0.084, -0.028, -0.090, -0.040, -0.090),
            .close,
            .move(-0.005, -0.015),
            .cubic(0.006, -0.015, 0.016, -0.008, 0.016, 0.000),
            .cubic(0.016, 0.008, 0.006, 0.015, -0.005, 0.015),
            .cubic(-0.016, 0.015, -0.026, 0.008, -0.026, 0.000),
            .cubic(-0.026, -0.008, -0.016, -0.015, -0.005, -0.015),
            .close
        ]
    }

    /// Inset cheek highlight — machined face, hero sizes only.
    public static func hammerHighlightCommands() -> [Command] {
        [
            .move(-0.238, -0.084),
            .cubic(-0.246, -0.084, -0.248, -0.079, -0.248, -0.072),
            .line(-0.248, -0.012),
            .line(-0.040, -0.010),
            .line(-0.040, -0.072),
            .cubic(-0.040, -0.078, -0.044, -0.082, -0.052, -0.084),
            .close
        ]
    }

    /// Canonical flame envelopes. `0` envelope, `1` body, `2` core, `3` kernel.
    public static func flameCommands(index: Int, flare _: Double = 1) -> [Command] {
        switch index {
        case 0:
            return [
                .move(0.248, 0.852),
                .cubic(0.130, 0.720, 0.120, 0.490, 0.180, 0.300),
                .cubic(0.228, 0.150, 0.300, 0.070, 0.350, 0.048),
                .cubic(0.365, 0.070, 0.400, 0.130, 0.418, 0.165),
                .cubic(0.445, 0.120, 0.475, 0.090, 0.500, 0.108),
                .cubic(0.518, 0.130, 0.515, 0.185, 0.490, 0.240),
                .cubic(0.535, 0.360, 0.555, 0.520, 0.528, 0.680),
                .cubic(0.505, 0.800, 0.440, 0.870, 0.360, 0.888),
                .cubic(0.295, 0.905, 0.255, 0.888, 0.248, 0.852),
                .close
            ]
        case 1:
            return [
                .move(0.282, 0.820),
                .cubic(0.188, 0.705, 0.185, 0.500, 0.232, 0.335),
                .cubic(0.268, 0.200, 0.322, 0.132, 0.358, 0.118),
                .cubic(0.372, 0.138, 0.400, 0.185, 0.412, 0.212),
                .cubic(0.432, 0.175, 0.455, 0.152, 0.472, 0.168),
                .cubic(0.486, 0.188, 0.482, 0.230, 0.462, 0.275),
                .cubic(0.500, 0.385, 0.512, 0.520, 0.492, 0.640),
                .cubic(0.476, 0.740, 0.425, 0.808, 0.360, 0.828),
                .cubic(0.315, 0.840, 0.292, 0.834, 0.282, 0.820),
                .close
            ]
        case 2:
            return [
                .move(0.325, 0.520),
                .cubic(0.300, 0.430, 0.302, 0.330, 0.332, 0.250),
                .cubic(0.352, 0.195, 0.372, 0.165, 0.388, 0.158),
                .cubic(0.400, 0.172, 0.412, 0.215, 0.416, 0.265),
                .cubic(0.424, 0.340, 0.420, 0.430, 0.392, 0.490),
                .cubic(0.375, 0.528, 0.345, 0.540, 0.325, 0.520),
                .close
            ]
        default:
            return [
                .move(0.348, 0.420),
                .cubic(0.338, 0.380, 0.340, 0.340, 0.355, 0.312),
                .cubic(0.365, 0.292, 0.378, 0.288, 0.385, 0.300),
                .cubic(0.394, 0.322, 0.395, 0.365, 0.382, 0.405),
                .cubic(0.374, 0.428, 0.358, 0.432, 0.348, 0.420),
                .close
            ]
        }
    }

    public static func spark(index: Int, progress: Double, reduceMotion: Bool) -> Spark {
        let i = max(0, min(sparkCount - 1, index))
        if reduceMotion {
            return Spark(x: strikeX, y: strikeY, radius: 0, opacity: 0)
        }
        let p = min(1, max(0, progress))
        let age = (p - impactEnd) / 0.34
        guard age > 0 else {
            return Spark(x: strikeX, y: strikeY, radius: 0.004, opacity: 0)
        }
        let travel = min(1, max(0, age))
        let fade = travel < 1 ? (1 - travel) : 0
        let seed = Double(i) * 17.13
        let angle = (-118.0 + Double(i) * 26.0 + 7 * sin(seed)) * .pi / 180
        let dist = (0.09 + 0.04 * Double(i % 3)) * travel
        return Spark(
            x: strikeX + cos(angle) * dist,
            y: strikeY + sin(angle) * dist,
            radius: 0.006 + 0.0025 * hash01(seed),
            opacity: 0.72 * fade
        )
    }

    public static func impactGlowOpacity(flare amount: Double) -> Double {
        max(0, min(1, (amount - idleFlare) / (1 - idleFlare))) * 0.42
    }

    public static func impactGlowRadius(flare amount: Double) -> Double {
        0.055 + 0.07 * max(0, min(1, amount))
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
