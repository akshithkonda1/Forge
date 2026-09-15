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
    static let tickHz: Double = 30
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
    static let tickHz: Double = 30

    static func wobble(index: Int, time: Double, reduceMotion: Bool) -> Double {
        guard !reduceMotion else { return 0 }
        let phase = (AriaSigilGeometry.phaseOffsets[safe: index] ?? 0) * .pi * 2
        return 0.09 * sin(time * 1.55 + phase)
    }

    static func flicker(index: Int, time: Double, reduceMotion: Bool) -> Double {
        guard !reduceMotion else { return 1 }
        let phase = (AriaSigilGeometry.phaseOffsets[safe: index] ?? 0) * .pi * 2
        return 0.78 + 0.22 * (0.5 + 0.5 * sin(time * 3.4 + phase))
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

/// Full-bleed roaring fire. Welcome and splash only — not the ARIA mark.
struct ForgeFireField: View {
    var intensity: ForgeFireIntensity = .rage
    var origin: ForgeFireOrigin = .floor
    var reduceMotionOverride: Bool? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotionEnv
    @Environment(\.forgeMinimalAnimation) private var minimalAnimation

    private var frozen: Bool {
        reduceMotionOverride ?? (reduceMotionEnv || minimalAnimation)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / ForgeFireGeometry.tickHz, paused: frozen)) { timeline in
            let time = frozen ? 0.18 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                drawFire(context: &context, size: size, time: time)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawFire(context: inout GraphicsContext, size: CGSize, time: Double) {
        guard size.width > 2, size.height > 2 else { return }
        var ctx = context
        ctx.blendMode = .plusLighter

        let glowRect = CGRect(origin: .zero, size: size)
        let glowCenter = origin == .floor
            ? CGPoint(x: size.width * 0.5, y: size.height * 0.92)
            : CGPoint(x: size.width * 0.5, y: size.height * 0.58)
        let glowRadius = origin == .floor ? size.height * 0.62 : size.width * 0.48
        let heat = intensity == .rage ? 0.42 : 0.12
        ctx.fill(
            Path(glowRect),
            with: .radialGradient(
                Gradient(colors: [
                    Color(hex: "FF6B2B").opacity(heat),
                    Color(hex: "FF4D00").opacity(heat * 0.45),
                    .clear
                ]),
                center: glowCenter,
                startRadius: 8,
                endRadius: glowRadius
            )
        )

        if origin == .floor, intensity == .rage {
            var bed = Path()
            bed.addEllipse(in: CGRect(
                x: size.width * 0.08,
                y: size.height * 0.78,
                width: size.width * 0.84,
                height: size.height * 0.28
            ))
            ctx.fill(
                bed,
                with: .radialGradient(
                    Gradient(colors: [
                        Color(hex: "FFE28A").opacity(0.35),
                        Color(hex: "FF4D00").opacity(0.28),
                        .clear
                    ]),
                    center: CGPoint(x: size.width * 0.5, y: size.height * 0.96),
                    startRadius: 4,
                    endRadius: size.width * 0.48
                )
            )
        }

        let tongues = intensity.tongueCount
        for i in 0..<tongues {
            let tongue = ForgeFireGeometry.tongue(
                index: i,
                count: tongues,
                time: time,
                intensity: intensity,
                origin: origin,
                reduceMotion: frozen
            )
            fillTongue(&ctx, tongue: tongue, size: size, outer: true)
        }
        for i in 0..<tongues {
            let tongue = ForgeFireGeometry.tongue(
                index: i,
                count: tongues,
                time: time + 0.07,
                intensity: intensity,
                origin: origin,
                reduceMotion: frozen
            )
            fillTongue(&ctx, tongue: tongue, size: size, outer: false)
        }

        for i in 0..<intensity.sparkCount {
            let spark = ForgeFireGeometry.spark(
                index: i,
                time: time,
                intensity: intensity,
                reduceMotion: frozen
            )
            let r = CGFloat(spark.radius) * min(size.width, size.height)
            var path = Path()
            path.addEllipse(in: CGRect(
                x: CGFloat(spark.x) * size.width - r,
                y: CGFloat(spark.y) * size.height - r,
                width: r * 2,
                height: r * 2
            ))
            let hot = intensity == .rage
            ctx.fill(
                path,
                with: .color(
                    Color(
                        red: 1,
                        green: hot ? 0.92 : 0.55,
                        blue: hot ? 0.55 : 0.18
                    ).opacity(spark.opacity)
                )
            )
        }
    }

    private func fillTongue(
        _ ctx: inout GraphicsContext,
        tongue: ForgeFireGeometry.Tongue,
        size: CGSize,
        outer: Bool
    ) {
        let w = size.width
        let h = size.height
        let base = CGPoint(x: tongue.baseX * w, y: tongue.baseY * h)
        let tip = CGPoint(x: tongue.tipX * w, y: tongue.tipY * h)
        let width = CGFloat(tongue.width) * w * (outer ? 1.0 : 0.46)
        let waver = CGFloat(tongue.waver) * w
        let path = flamePath(base: base, tip: tip, width: width, waver: waver)
        let heat = tongue.heat
        if outer {
            ctx.fill(
                path,
                with: .linearGradient(
                    Gradient(colors: [
                        Color(hex: "FF2A00").opacity(0.22 + heat * 0.2),
                        Color(hex: "FF4D00").opacity(0.55 + heat * 0.25),
                        Color(hex: "FFB020").opacity(0.15)
                    ]),
                    startPoint: base,
                    endPoint: tip
                )
            )
        } else {
            ctx.fill(
                path,
                with: .linearGradient(
                    Gradient(colors: [
                        Color(hex: "FF6B2B").opacity(0.55 + heat * 0.3),
                        Color(hex: "FFE28A").opacity(0.45 + heat * 0.5),
                        Color.white.opacity(0.12 + heat * 0.35)
                    ]),
                    startPoint: base,
                    endPoint: tip
                )
            )
        }
    }

    private func flamePath(base: CGPoint, tip: CGPoint, width: CGFloat, waver: CGFloat) -> Path {
        var path = Path()
        let h = base.y - tip.y
        let yBulge = base.y - h * 0.28
        let yWaist = base.y - h * 0.62
        let bulge = width * 1.45
        let waist = width * 0.55
        path.move(to: CGPoint(x: base.x - width * 0.55, y: base.y))
        path.addQuadCurve(
            to: CGPoint(x: base.x - waist + waver, y: yWaist),
            control: CGPoint(x: base.x - bulge + waver * 0.4, y: yBulge)
        )
        path.addQuadCurve(
            to: tip,
            control: CGPoint(x: base.x - waist * 0.4 + waver * 1.2, y: (yWaist + tip.y) / 2)
        )
        path.addQuadCurve(
            to: CGPoint(x: base.x + waist + waver, y: yWaist),
            control: CGPoint(x: base.x + waist * 0.4 + waver * 1.2, y: (yWaist + tip.y) / 2)
        )
        path.addQuadCurve(
            to: CGPoint(x: base.x + width * 0.55, y: base.y),
            control: CGPoint(x: base.x + bulge + waver * 0.4, y: yBulge)
        )
        path.closeSubpath()
        return path
    }
}

/// Compact living flame for the Forge wordmark — a raging tongue, not a 14pt ember glyph.
struct ForgeBrandFlame: View {
    var size: CGFloat = 22
    var reduceMotionOverride: Bool? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotionEnv
    @Environment(\.forgeMinimalAnimation) private var minimalAnimation

    private var frozen: Bool {
        reduceMotionOverride ?? (reduceMotionEnv || minimalAnimation)
    }

    var body: some View {
        ForgeFireField(intensity: .rage, origin: .hearth, reduceMotionOverride: frozen)
            .frame(width: size, height: size * 1.28)
            .mask(
                LinearGradient(
                    colors: [.clear, .white, .white],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .accessibilityHidden(true)
    }
}

#Preview("Rage fire") {
    ZStack {
        Color.black.ignoresSafeArea()
        ForgeFireField(intensity: .rage, origin: .floor)
        VStack(spacing: 12) {
            Text("FORGE")
                .font(.system(size: 32, weight: .black, design: .rounded))
                .tracking(8)
                .foregroundStyle(.white)
            Text("Forged.")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.ember)
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Brand flame") {
    ZStack {
        Color.black.ignoresSafeArea()
        HStack(spacing: 10) {
            ForgeBrandFlame(size: 28)
            Text("Forge")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Ember contrast") {
    ZStack {
        Color.black.ignoresSafeArea()
        ForgeFireField(intensity: .ember, origin: .floor)
        Text("ember — not the welcome fire")
            .font(.caption)
            .foregroundStyle(.white.opacity(0.5))
    }
    .preferredColorScheme(.dark)
}
