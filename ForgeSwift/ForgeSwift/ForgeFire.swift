import SwiftUI

/// Brand beat on the launch splash. The splash curtains an already-rendered
/// first frame — Home is right behind it — so every second of hold is a
/// second of waiting. One strike, then the curtain lifts. Lockstep comment
/// with `src/lib/forge-splash.ts`.
enum ForgeSplashTiming: Sendable {
    /// Cold launch: anticipation, strike, sparks, wordmark. Hold + fade ≤ 1.6s.
    static let hold: TimeInterval = 1.20
    static let reduceMotionHold: TimeInterval = 0.35
    /// Signed-in users already know the brand. Static hearth, no swing.
    static let signedInHold: TimeInterval = 0.28
    static let fadeOut: TimeInterval = 0.35

    /// Hard ceiling so a future bump cannot become a frozen launch.
    /// Cold path is 1.55s; signed-in stays far under this.
    static let freezeCeiling: TimeInterval = 1.60
    /// Floor so the beat is long enough to land the wordmark.
    static let brandFloor: TimeInterval = 0.30

    static func hold(reduceMotion: Bool, signedIn: Bool) -> TimeInterval {
        if reduceMotion { return reduceMotionHold }
        if signedIn { return signedInHold }
        return hold
    }

    static func pauseNanoseconds(reduceMotion: Bool, signedIn: Bool = false) -> UInt64 {
        UInt64(hold(reduceMotion: reduceMotion, signedIn: signedIn) * 1_000_000_000)
    }
}

/// How fierce the fire is. Splash hearth uses layered teardrops; these
/// counts stay for the shared tongue helper and tests.
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
    /// Flame flicker and heat shimmer sample at this rate — never faster.
    static let tickHz: Double = 12
    static let kind = "rage-fire"

    /// Quantize time so flicker cannot exceed `tickHz`.
    static func flickerTime(_ time: Double) -> Double {
        floor(time * tickHz + 1e-9) / tickHz
    }

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
        let t = reduceMotion ? 0.18 : flickerTime(time)
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

// MARK: - Splash strike

/// One pose on the launch splash: hammer, anvil, flame, sparks.
struct ForgeStrikePose: Equatable, Sendable {
    /// Radians from straight down. Larger means the head is swung back.
    var hammerAngle: Double
    /// 0...1 impact flash.
    var impact: Double
    /// Height of the fire on the anvil.
    var flameScale: Double
    /// 0...1 spark travel after impact.
    var sparkTravel: Double
    /// Heat in the anvil face.
    var heat: Double
}

enum ForgeStrikeGeometry: Sendable {
    /// The strike lives on the launch splash, not the welcome carousel.
    static let host = "splash"
    static let duration: TimeInterval = 1.10
    static let splashDuration: TimeInterval = 1.10
    /// Anticipation finishes here; the downswing starts.
    static let anticipationEnd: Double = 0.16
    /// Impact as a fraction of duration. 1.10 × 0.44 = 0.484s.
    static let strikeImpactFraction: Double = 0.44
    static var splashImpactTime: TimeInterval { splashDuration * strikeImpactFraction }

    static func pose(
        time: Double,
        duration: TimeInterval = ForgeStrikeGeometry.splashDuration,
        reduceMotion: Bool,
        style: ForgeStrikeMotion.Style = ForgeStrikeMotion.style
    ) -> ForgeStrikePose {
        let span = max(duration, 0.01)
        let u = reduceMotion ? 1 : min(1, max(0, time / span))
        return strike(u, style: style)
    }

    /// Pull back, then a quartic drop, then a small recoil. Never linear.
    private static func strike(_ u: Double, style: ForgeStrikeMotion.Style) -> ForgeStrikePose {
        let windup = 1.08
        let gather = 1.24
        let rest = 0.06
        let antic = smoothstep(window(u, 0, anticipationEnd))
        let raised = windup + (gather - windup) * antic
        let down = easeInQuart(window(u, anticipationEnd, strikeImpactFraction))
        let hammerDown = raised * (1 - down) + rest * down
        let hit = spike(u, center: strikeImpactFraction, width: 0.08)

        switch style {
        case .accelerateRebound:
            let rebound = springOvershoot(window(u, strikeImpactFraction, 1), amplitude: 0.13, decay: 10, omega: 18)
            let settle = smoothstep(window(u, strikeImpactFraction, 0.82))
            return ForgeStrikePose(
                hammerAngle: hammerDown + rebound,
                impact: hit,
                flameScale: 0.52 + 0.62 * hit + 0.30 * settle,
                sparkTravel: smoothstep(window(u, strikeImpactFraction, 0.82)),
                heat: 0.36 + 0.58 * hit + 0.22 * settle
            )
        case .forgeAndRest:
            let gatherFlame = smoothstep(window(u, strikeImpactFraction, 0.62))
            return ForgeStrikePose(
                hammerAngle: hammerDown,
                impact: hit * 0.72,
                flameScale: 0.88 + 0.13 * gatherFlame,
                sparkTravel: smoothstep(window(u, strikeImpactFraction, 0.72)),
                heat: 0.40 + 0.28 * gatherFlame
            )
        }
    }

    private static func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }

    private static func smoothstep(_ x: Double) -> Double {
        let t = clamp01(x)
        return t * t * (3 - 2 * t)
    }

    private static func easeInQuart(_ x: Double) -> Double {
        let t = clamp01(x)
        return t * t * t * t
    }

    private static func springOvershoot(
        _ t: Double,
        amplitude: Double,
        decay: Double,
        omega: Double
    ) -> Double {
        let x = clamp01(t)
        if x <= 0 { return 0 }
        return amplitude * exp(-decay * x) * sin(omega * x)
    }

    private static func window(_ u: Double, _ start: Double, _ end: Double) -> Double {
        guard end > start else { return u >= end ? 1 : 0 }
        return clamp01((u - start) / (end - start))
    }

    private static func spike(_ u: Double, center: Double, width: Double) -> Double {
        guard width > 0 else { return 0 }
        let d = abs(u - center) / width
        if d >= 1 { return 0 }
        return 0.5 + 0.5 * cos(d * .pi)
    }
}

/// Full swing + sparks, or a settled hearth with no hammer motion.
enum ForgeStrikePlayback: String, Sendable {
    case full
    /// Signed-in splash: static hearth, no swing, no burst.
    case trimmed
}

/// How the splash beat is driven. Flip `style` to preview the rest-on-the-hearth beat.
enum ForgeStrikeMotion: Sendable {
    enum Style: String, Sendable, CaseIterable {
        /// Accelerate into the strike, slight overshoot / recoil.
        case accelerateRebound
        /// Firm strike, then rest. No rebound or shake.
        case forgeAndRest
    }

    static let style: Style = .accelerateRebound
    static let sparkBackend = "canvas"
    static var swingEasing: String {
        switch style {
        case .accelerateRebound: return "anticipate+easeInQuart+spring"
        case .forgeAndRest: return "anticipate+easeInQuart+rest"
        }
    }
    static let swingIsLinear = false
    static var allowsRebound: Bool { style == .accelerateRebound }
    static var allowsImpactShake: Bool { style == .accelerateRebound }
}

/// Hammer, anvil, and flame. Plays once, then holds the last pose.
struct ForgeStrikeMark: View {
    var duration: TimeInterval = ForgeStrikeGeometry.splashDuration
    var playback: ForgeStrikePlayback = .full

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var startedAt = Date()
    @State private var playing = false
    @State private var frozenTime: TimeInterval = 0
    @State private var generation = 0
    @State private var playTask: Task<Void, Never>?

    private var motionFrozen: Bool { reduceMotion || playback == .trimmed }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !playing)) { (timeline: TimelineViewDefaultContext) in
            let elapsed = displayedTime(at: timeline.date)
            let pose = ForgeStrikeGeometry.pose(
                time: elapsed,
                duration: duration,
                reduceMotion: motionFrozen
            )
            Canvas { context, size in
                ForgeStrikeCanvas.draw(
                    context: &context,
                    size: size,
                    pose: pose,
                    time: elapsed,
                    duration: duration,
                    reduceMotion: motionFrozen
                )
            }
        }
        .accessibilityHidden(true)
        .onAppear { begin() }
        .onDisappear { playTask?.cancel() }
        .onChange(of: reduceMotion) { _, _ in begin() }
        .onChange(of: playback) { _, _ in begin() }
    }

    private func displayedTime(at date: Date) -> TimeInterval {
        if motionFrozen { return duration }
        if playing { return max(0, date.timeIntervalSince(startedAt)) }
        return frozenTime
    }

    private func begin() {
        playTask?.cancel()
        generation += 1
        startedAt = Date()
        let token = generation
        if motionFrozen {
            playing = false
            frozenTime = duration
            return
        }
        frozenTime = 0
        playing = true
        let nanos = UInt64(max(0, duration) * 1_000_000_000)
        playTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled, token == generation else { return }
            frozenTime = duration
            playing = false
        }
    }
}

/// Tasteful chip sparks drawn in Canvas. No emitters, no raster chips.
enum ForgeSparkBurst: Sendable {
    static let kind = "canvas"
    static let shape = "chip"
    static let gravity: Double = 2.6
    static let oneShot = true
    static let maxLifetime: TimeInterval = 0.42
    static let count = 8

    struct Chip: Equatable, Sendable {
        var angle: Double
        var speed: Double
        var size: Double
        var spin: Double
        var life: Double
    }

    static let chips: [Chip] = [
        Chip(angle: -1.22, speed: 1.18, size: 1.00, spin:  2.1, life: 1.00),
        Chip(angle: -0.78, speed: 0.96, size: 0.74, spin: -1.7, life: 0.88),
        Chip(angle: -1.55, speed: 0.84, size: 0.62, spin:  1.4, life: 0.80),
        Chip(angle: -0.42, speed: 1.06, size: 0.70, spin: -2.2, life: 0.92),
        Chip(angle: -1.88, speed: 0.72, size: 0.48, spin:  1.8, life: 0.70),
        Chip(angle: -0.18, speed: 0.88, size: 0.56, spin: -1.1, life: 0.78),
        Chip(angle: -2.05, speed: 0.64, size: 0.42, spin:  2.4, life: 0.62),
        Chip(angle: -1.02, speed: 0.78, size: 0.50, spin: -1.5, life: 0.74)
    ]
}

private enum ForgeStrikeCanvas {
    static func draw(
        context: inout GraphicsContext,
        size: CGSize,
        pose: ForgeStrikePose,
        time: Double,
        duration: TimeInterval,
        reduceMotion: Bool
    ) {
        let s = min(size.width, size.height)
        let grip = CGPoint(x: size.width * 0.34, y: size.height * 0.11)
        let reach = s * 0.58
        let face = point(grip: grip, reach: reach, angle: 0.05)
        let top = face.y
        let headWidth = s * 0.22
        let headDepth = s * 0.112

        if ForgeStrikeMotion.allowsImpactShake {
            context.translateBy(x: 0, y: CGFloat(pose.impact) * s * 0.008)
        }

        drawHearthGlow(context: &context, face: face, top: top, s: s, pose: pose)
        drawAnvil(context: &context, face: face, top: top, s: s, pose: pose)
        drawFlame(context: &context, face: face, top: top, s: s, pose: pose, time: time, reduceMotion: reduceMotion)
        drawFaceHeat(context: &context, face: face, top: top, s: s, pose: pose)
        drawSparks(context: &context, face: face, top: top, s: s, pose: pose)

        if !reduceMotion {
            for (lag, alpha) in [(0.055, 0.10), (0.028, 0.20)] {
                let earlier = ForgeStrikeGeometry.pose(
                    time: time - lag,
                    duration: duration,
                    reduceMotion: false
                )
                guard abs(earlier.hammerAngle - pose.hammerAngle) > 0.04 else { continue }
                drawHammer(
                    context: &context,
                    grip: grip,
                    reach: reach,
                    angle: earlier.hammerAngle,
                    headWidth: headWidth,
                    headDepth: headDepth,
                    opacity: alpha,
                    impact: 0,
                    ghost: true
                )
            }
        }

        drawHammer(
            context: &context,
            grip: grip,
            reach: reach,
            angle: pose.hammerAngle,
            headWidth: headWidth,
            headDepth: headDepth,
            opacity: 1,
            impact: pose.impact,
            ghost: false
        )

        if pose.impact > 0.05 {
            let r = s * (0.035 + 0.08 * pose.impact)
            let flash = CGRect(x: face.x - r, y: top - r * 0.85, width: r * 2, height: r * 1.35)
            context.fill(Path(ellipseIn: flash), with: .color(Color(hex: "FFE7B0").opacity(0.22 * pose.impact)))
            let coreR = r * 0.38
            let core = CGRect(x: face.x - coreR, y: top - coreR * 0.7, width: coreR * 2, height: coreR * 1.4)
            context.fill(Path(ellipseIn: core), with: .color(Color(hex: "FFF4C8").opacity(0.55 * pose.impact)))
        }
    }

    private static func drawHearthGlow(
        context: inout GraphicsContext,
        face: CGPoint,
        top: CGFloat,
        s: CGFloat,
        pose: ForgeStrikePose
    ) {
        let bloom = CGRect(
            x: face.x - s * 0.38,
            y: top - s * (0.28 + 0.34 * pose.flameScale),
            width: s * 0.76,
            height: s * (0.38 + 0.40 * pose.flameScale)
        )
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: s * 0.07))
            layer.fill(
                Path(ellipseIn: bloom),
                with: .color(Color.ember.opacity(0.08 + 0.20 * pose.heat * min(pose.flameScale, 1.15)))
            )
        }
        let inner = bloom.insetBy(dx: bloom.width * 0.22, dy: bloom.height * 0.18)
        context.fill(
            Path(ellipseIn: inner),
            with: .color(Color.ember.opacity(0.06 + 0.12 * pose.heat))
        )
    }

    private static func drawAnvil(
        context: inout GraphicsContext,
        face: CGPoint,
        top: CGFloat,
        s: CGFloat,
        pose: ForgeStrikePose
    ) {
        let body = anvilPath(face: face, top: top, s: s)
        context.fill(
            body,
            with: .linearGradient(
                Gradient(colors: [
                    Color(hex: "4A4F58"),
                    Color(hex: "24272E"),
                    Color(hex: "16181D")
                ]),
                startPoint: CGPoint(x: face.x - s * 0.28, y: top - s * 0.04),
                endPoint: CGPoint(x: face.x + s * 0.18, y: top + s * 0.26)
            )
        )

        let heelShine = CGRect(x: face.x + s * 0.04, y: top - s * 0.006, width: s * 0.12, height: s * 0.05)
        context.fill(
            Path(roundedRect: heelShine, cornerRadius: s * 0.01),
            with: .color(Color(hex: "8A909A").opacity(0.22))
        )

        let horn = CGRect(x: face.x - s * 0.34, y: top - s * 0.01, width: s * 0.16, height: s * 0.045)
        context.fill(
            Path(ellipseIn: horn),
            with: .color(Color(hex: "6A707A").opacity(0.18))
        )

        context.stroke(
            body,
            with: .color(Color.paper.opacity(0.14)),
            style: StrokeStyle(lineWidth: 1, lineJoin: .round)
        )

        var faceLip = Path()
        faceLip.move(to: CGPoint(x: face.x - s * 0.155, y: top))
        faceLip.addLine(to: CGPoint(x: face.x + s * 0.148, y: top))
        context.stroke(
            faceLip,
            with: .linearGradient(
                Gradient(colors: [
                    Color(hex: "C8CDD4").opacity(0.18 + 0.35 * pose.heat),
                    Color(hex: "FFE7B0").opacity(0.15 + 0.55 * pose.heat),
                    Color(hex: "C8CDD4").opacity(0.12)
                ]),
                startPoint: CGPoint(x: face.x - s * 0.16, y: top),
                endPoint: CGPoint(x: face.x + s * 0.16, y: top)
            ),
            style: StrokeStyle(lineWidth: max(1.4, s * 0.011), lineCap: .round)
        )

        let hardy = CGRect(x: face.x + s * 0.06, y: top + s * 0.012, width: s * 0.028, height: s * 0.028)
        context.fill(Path(roundedRect: hardy, cornerRadius: 1.2), with: .color(Color(hex: "0C0D10").opacity(0.88)))

        let waistShade = CGRect(x: face.x - s * 0.07, y: top + s * 0.10, width: s * 0.14, height: s * 0.08)
        context.fill(Path(ellipseIn: waistShade), with: .color(Color.black.opacity(0.18)))
    }

    private static func drawFaceHeat(
        context: inout GraphicsContext,
        face: CGPoint,
        top: CGFloat,
        s: CGFloat,
        pose: ForgeStrikePose
    ) {
        let plate = CGRect(x: face.x - s * 0.15, y: top - s * 0.01, width: s * 0.30, height: s * 0.022)
        context.fill(
            Path(roundedRect: plate, cornerRadius: s * 0.006),
            with: .color(Color.ember.opacity(0.08 + 0.28 * pose.heat))
        )
    }

    private static func drawFlame(
        context: inout GraphicsContext,
        face: CGPoint,
        top: CGFloat,
        s: CGFloat,
        pose: ForgeStrikePose,
        time: Double,
        reduceMotion: Bool
    ) {
        let scale = max(0.18, pose.flameScale)
        let flickerT = reduceMotion ? 0.18 : ForgeFireGeometry.flickerTime(time)
        let lean = reduceMotion ? 0 : 0.012 * sin(flickerT * .pi * 2 * 2.4)
        let pulse = reduceMotion ? 1 : 0.94 + 0.06 * sin(flickerT * .pi * 2 * 3.1)
        let width = s * 0.30
        let height = s * 0.46 * scale * pulse
        let base = CGRect(
            x: face.x - width / 2 + CGFloat(lean) * s,
            y: top - height,
            width: width,
            height: height
        )

        context.drawLayer { bloom in
            bloom.addFilter(.blur(radius: s * 0.045))
            bloom.fill(
                Path(ellipseIn: base.insetBy(dx: -s * 0.04, dy: s * 0.02)),
                with: .color(Color.ember.opacity(0.22 + 0.18 * pose.heat))
            )
        }

        fillFlame(
            context: &context,
            rect: base,
            lean: CGFloat(lean) * s,
            colors: [Color.emberDark.opacity(0.55), Color.ember.opacity(0.28)],
            heat: pose.heat
        )
        fillFlame(
            context: &context,
            rect: base.insetBy(dx: width * 0.16, dy: height * 0.10),
            lean: CGFloat(lean) * s * 0.6,
            colors: [Color.ember.opacity(0.82), Color(hex: "FFB45A").opacity(0.55)],
            heat: pose.heat
        )
        fillFlame(
            context: &context,
            rect: base.insetBy(dx: width * 0.28, dy: height * 0.22),
            lean: CGFloat(lean) * s * 0.25,
            colors: [Color(hex: "FFE08A").opacity(0.92), Color(hex: "FFF6D2").opacity(0.70)],
            heat: pose.heat
        )

        let lickW = width * 0.22
        let lickH = height * 0.42
        let lickLean = reduceMotion ? 0 : 0.018 * sin(flickerT * 5.1 + 1.2)
        let lick = CGRect(
            x: face.x + width * 0.12 + CGFloat(lickLean) * s,
            y: top - lickH * 0.92,
            width: lickW,
            height: lickH
        )
        fillFlame(
            context: &context,
            rect: lick,
            lean: CGFloat(lickLean) * s,
            colors: [Color.ember.opacity(0.50), Color(hex: "FFC36A").opacity(0.22)],
            heat: pose.heat
        )

        let coreW = width * 0.28
        let coreH = height * 0.18
        let core = CGRect(x: face.x - coreW / 2, y: top - coreH * 0.72, width: coreW, height: coreH)
        context.fill(Path(ellipseIn: core), with: .color(Color(hex: "FFF4C4").opacity(0.40 + 0.45 * min(pose.heat, 1))))
        context.fill(
            Path(ellipseIn: core.insetBy(dx: coreW * 0.28, dy: coreH * 0.28)),
            with: .color(Color(hex: "FFE28A").opacity(0.55 + 0.35 * min(pose.heat, 1)))
        )
    }

    private static func fillFlame(
        context: inout GraphicsContext,
        rect: CGRect,
        lean: CGFloat,
        colors: [Color],
        heat: Double
    ) {
        guard rect.width > 1, rect.height > 1 else { return }
        let path = flamePath(rect: rect, lean: lean)
        context.fill(
            path,
            with: .linearGradient(
                Gradient(colors: colors.map { $0.opacity(min(1, 0.72 + 0.28 * heat)) }),
                startPoint: CGPoint(x: rect.midX, y: rect.maxY),
                endPoint: CGPoint(x: rect.midX + lean, y: rect.minY)
            )
        )
    }

    private static func flamePath(rect: CGRect, lean: CGFloat) -> Path {
        let baseL = CGPoint(x: rect.midX - rect.width * 0.22, y: rect.maxY)
        let baseR = CGPoint(x: rect.midX + rect.width * 0.22, y: rect.maxY)
        let tip = CGPoint(x: rect.midX + lean, y: rect.minY)
        var path = Path()
        path.move(to: baseL)
        path.addQuadCurve(
            to: tip,
            control: CGPoint(x: rect.minX + lean * 0.45, y: rect.maxY - rect.height * 0.38)
        )
        path.addQuadCurve(
            to: baseR,
            control: CGPoint(x: rect.maxX + lean * 0.45, y: rect.maxY - rect.height * 0.38)
        )
        path.closeSubpath()
        return path
    }

    private static func drawSparks(
        context: inout GraphicsContext,
        face: CGPoint,
        top: CGFloat,
        s: CGFloat,
        pose: ForgeStrikePose
    ) {
        let travel = pose.sparkTravel
        guard travel > 0.02, travel < 0.98 else { return }
        for chip in ForgeSparkBurst.chips {
            let life = max(0.35, chip.life)
            let t = min(1, travel / life)
            let fade = (1 - t) * (1 - t)
            guard fade > 0.04 else { continue }
            let dist = CGFloat(chip.speed) * s * 0.34 * CGFloat(t)
            let x = face.x + cos(chip.angle) * dist
            let y = top - sin(-chip.angle) * dist * 0.85 + CGFloat(ForgeSparkBurst.gravity) * s * 0.04 * CGFloat(t * t)
            let w = s * 0.014 * CGFloat(chip.size) * (1 - 0.35 * t)
            let h = w * 2.1
            var chipPath = Path()
            chipPath.move(to: CGPoint(x: 0, y: -h / 2))
            chipPath.addQuadCurve(to: CGPoint(x: w / 2, y: 0), control: CGPoint(x: w * 0.42, y: -h * 0.18))
            chipPath.addQuadCurve(to: CGPoint(x: 0, y: h / 2), control: CGPoint(x: w * 0.32, y: h * 0.22))
            chipPath.addQuadCurve(to: CGPoint(x: -w / 2, y: 0), control: CGPoint(x: -w * 0.32, y: h * 0.22))
            chipPath.addQuadCurve(to: CGPoint(x: 0, y: -h / 2), control: CGPoint(x: -w * 0.42, y: -h * 0.18))
            chipPath.closeSubpath()

            var transform = CGAffineTransform.identity
            transform = transform.translatedBy(x: x, y: y)
            transform = transform.rotated(by: chip.spin * t)
            context.fill(
                chipPath.applying(transform),
                with: .color(Color(hex: "FFE7B0").opacity(0.85 * fade))
            )
        }
    }

    private static func drawHammer(
        context: inout GraphicsContext,
        grip: CGPoint,
        reach: CGFloat,
        angle: Double,
        headWidth: CGFloat,
        headDepth: CGFloat,
        opacity: Double,
        impact: Double,
        ghost: Bool
    ) {
        let face = point(grip: grip, reach: reach, angle: angle)
        let dir = CGPoint(x: CGFloat(sin(angle)), y: CGFloat(cos(angle)))
        let neck = CGPoint(x: face.x - dir.x * headDepth * 0.52, y: face.y - dir.y * headDepth * 0.52)
        let handleStart = max(4.4, headDepth * 0.38)
        let handleEnd = max(3.4, headDepth * 0.28)

        if ghost {
            var handle = Path()
            handle.move(to: grip)
            handle.addLine(to: neck)
            context.stroke(
                handle,
                with: .color(Color.paper.opacity(opacity)),
                style: StrokeStyle(lineWidth: handleStart, lineCap: .round)
            )
        } else {
            drawWoodHandle(
                context: &context,
                grip: grip,
                neck: neck,
                startWidth: handleStart,
                endWidth: handleEnd,
                opacity: opacity
            )
        }

        context.drawLayer { layer in
            layer.translateBy(x: face.x, y: face.y)
            layer.rotate(by: .radians(-angle))
            layer.opacity = opacity
            paintHead(
                context: &layer,
                width: headWidth,
                depth: headDepth,
                handleWidth: handleEnd,
                impact: impact,
                ghost: ghost
            )
        }
    }

    private static func paintHead(
        context: inout GraphicsContext,
        width: CGFloat,
        depth: CGFloat,
        handleWidth: CGFloat,
        impact: Double,
        ghost: Bool
    ) {
        let half = width * 0.62
        let faceT = depth * 0.20
        let bodyTop = -depth * 0.92
        let peenTip = CGPoint(x: -half * 1.22, y: -depth * 0.46)

        var head = Path()
        // Strike face, then cheek, top, cross-peen, back to the face.
        head.move(to: CGPoint(x: -half * 0.55, y: 0))
        head.addQuadCurve(to: CGPoint(x: half * 0.78, y: 0), control: CGPoint(x: half * 0.10, y: depth * 0.045))
        head.addLine(to: CGPoint(x: half * 0.82, y: -faceT))
        head.addLine(to: CGPoint(x: half * 0.70, y: bodyTop + depth * 0.16))
        head.addQuadCurve(
            to: CGPoint(x: half * 0.22, y: bodyTop),
            control: CGPoint(x: half * 0.68, y: bodyTop + depth * 0.02)
        )
        head.addLine(to: CGPoint(x: -half * 0.12, y: bodyTop + depth * 0.04))
        head.addQuadCurve(
            to: peenTip,
            control: CGPoint(x: -half * 0.72, y: bodyTop + depth * 0.10)
        )
        head.addQuadCurve(
            to: CGPoint(x: -half * 0.48, y: -faceT),
            control: CGPoint(x: -half * 1.05, y: -depth * 0.28)
        )
        head.addLine(to: CGPoint(x: -half * 0.55, y: 0))
        head.closeSubpath()

        if ghost {
            context.fill(head, with: .color(Color.paper))
            return
        }

        context.fill(
            head,
            with: .linearGradient(
                Gradient(colors: [
                    Color(hex: "6E7580"),
                    Color(hex: "E4E7ED"),
                    Color(hex: "9AA1AB"),
                    Color(hex: "F4F6F8")
                ]),
                startPoint: CGPoint(x: peenTip.x, y: bodyTop),
                endPoint: CGPoint(x: half, y: 0)
            )
        )
        context.stroke(
            head,
            with: .color(Color(hex: "C9CED6").opacity(0.45)),
            style: StrokeStyle(lineWidth: 0.7, lineJoin: .round)
        )

        var peenFace = Path()
        peenFace.move(to: CGPoint(x: -half * 0.10, y: bodyTop + depth * 0.10))
        peenFace.addLine(to: peenTip)
        peenFace.addLine(to: CGPoint(x: -half * 0.42, y: -depth * 0.28))
        peenFace.closeSubpath()
        context.fill(peenFace, with: .color(Color(hex: "C2C7CF").opacity(0.50)))

        var strikeFace = Path()
        strikeFace.move(to: CGPoint(x: -half * 0.55, y: 0))
        strikeFace.addQuadCurve(to: CGPoint(x: half * 0.78, y: 0), control: CGPoint(x: half * 0.10, y: depth * 0.045))
        strikeFace.addLine(to: CGPoint(x: half * 0.82, y: -faceT))
        strikeFace.addLine(to: CGPoint(x: -half * 0.48, y: -faceT))
        strikeFace.closeSubpath()
        context.fill(
            strikeFace,
            with: .linearGradient(
                Gradient(colors: [
                    Color(hex: "C5CAD1"),
                    Color(hex: "F7F8FA"),
                    Color.ember.opacity(0.12 + 0.50 * impact)
                ]),
                startPoint: CGPoint(x: -half, y: -faceT),
                endPoint: CGPoint(x: half, y: 0)
            )
        )

        let spec = CGRect(x: -half * 0.04, y: bodyTop + depth * 0.10, width: half * 0.36, height: depth * 0.10)
        context.fill(Path(ellipseIn: spec), with: .color(Color.white.opacity(0.38)))

        let ferrule = CGRect(
            x: -handleWidth * 0.68,
            y: -depth * 0.58,
            width: handleWidth * 1.36,
            height: handleWidth * 0.50
        )
        context.fill(Path(roundedRect: ferrule, cornerRadius: 1.2), with: .color(Color(hex: "5A606A")))
        context.stroke(
            Path(roundedRect: ferrule, cornerRadius: 1.2),
            with: .color(Color(hex: "8B919A").opacity(0.55)),
            style: StrokeStyle(lineWidth: 0.6)
        )
    }

    private static func drawWoodHandle(
        context: inout GraphicsContext,
        grip: CGPoint,
        neck: CGPoint,
        startWidth: CGFloat,
        endWidth: CGFloat,
        opacity: Double
    ) {
        let handle = taperedHandle(from: grip, to: neck, startWidth: startWidth, endWidth: endWidth)
        context.fill(
            handle,
            with: .linearGradient(
                Gradient(colors: [
                    Color(hex: "6B3F24").opacity(opacity),
                    Color(hex: "C08A52").opacity(opacity),
                    Color(hex: "8A5A32").opacity(opacity),
                    Color(hex: "5A351C").opacity(opacity)
                ]),
                startPoint: grip,
                endPoint: neck
            )
        )
        context.stroke(
            handle,
            with: .color(Color(hex: "3D2414").opacity(0.35 * opacity)),
            style: StrokeStyle(lineWidth: 0.7, lineJoin: .round)
        )

        let dx = neck.x - grip.x
        let dy = neck.y - grip.y
        let len = max(hypot(dx, dy), 0.001)
        let nx = -dy / len * startWidth * 0.16
        let ny = dx / len * startWidth * 0.16
        for grain in 0..<3 {
            let t = CGFloat(0.22 + Double(grain) * 0.22)
            let a = CGPoint(x: grip.x + dx * t + nx, y: grip.y + dy * t + ny)
            let b = CGPoint(x: grip.x + dx * min(1, t + 0.18) + nx, y: grip.y + dy * min(1, t + 0.18) + ny)
            var line = Path()
            line.move(to: a)
            line.addLine(to: b)
            context.stroke(
                line,
                with: .color(Color(hex: "3D2414").opacity(0.22 * opacity)),
                style: StrokeStyle(lineWidth: 0.6, lineCap: .round)
            )
        }
    }

    private static func taperedHandle(
        from: CGPoint,
        to: CGPoint,
        startWidth: CGFloat,
        endWidth: CGFloat
    ) -> Path {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let len = max(hypot(dx, dy), 0.001)
        let nx = -dy / len
        let ny = dx / len
        var path = Path()
        path.move(to: CGPoint(x: from.x + nx * startWidth / 2, y: from.y + ny * startWidth / 2))
        path.addLine(to: CGPoint(x: to.x + nx * endWidth / 2, y: to.y + ny * endWidth / 2))
        path.addLine(to: CGPoint(x: to.x - nx * endWidth / 2, y: to.y - ny * endWidth / 2))
        path.addLine(to: CGPoint(x: from.x - nx * startWidth / 2, y: from.y - ny * startWidth / 2))
        path.closeSubpath()
        return path
    }

    private static func anvilPath(face: CGPoint, top: CGFloat, s: CGFloat) -> Path {
        let faceL = face.x - s * 0.155
        let faceR = face.x + s * 0.148
        let horn = CGPoint(x: face.x - s * 0.355, y: top + s * 0.018)
        let heel = CGPoint(x: face.x + s * 0.225, y: top + s * 0.028)
        var path = Path()
        path.move(to: horn)
        path.addQuadCurve(
            to: CGPoint(x: faceL, y: top - s * 0.012),
            control: CGPoint(x: face.x - s * 0.255, y: top - s * 0.048)
        )
        path.addLine(to: CGPoint(x: faceR, y: top - s * 0.012))
        path.addQuadCurve(
            to: heel,
            control: CGPoint(x: faceR + s * 0.04, y: top - s * 0.004)
        )
        path.addLine(to: CGPoint(x: faceR + s * 0.035, y: top + s * 0.058))
        path.addLine(to: CGPoint(x: faceR - s * 0.018, y: top + s * 0.058))
        path.addQuadCurve(
            to: CGPoint(x: face.x + s * 0.068, y: top + s * 0.195),
            control: CGPoint(x: face.x + s * 0.10, y: top + s * 0.11)
        )
        path.addLine(to: CGPoint(x: face.x + s * 0.138, y: top + s * 0.218))
        path.addLine(to: CGPoint(x: face.x + s * 0.128, y: top + s * 0.248))
        path.addLine(to: CGPoint(x: face.x - s * 0.128, y: top + s * 0.248))
        path.addLine(to: CGPoint(x: face.x - s * 0.138, y: top + s * 0.218))
        path.addLine(to: CGPoint(x: face.x - s * 0.068, y: top + s * 0.195))
        path.addQuadCurve(
            to: CGPoint(x: faceL + s * 0.008, y: top + s * 0.052),
            control: CGPoint(x: face.x - s * 0.10, y: top + s * 0.11)
        )
        path.addLine(to: CGPoint(x: faceL - s * 0.012, y: top + s * 0.052))
        path.addQuadCurve(
            to: horn,
            control: CGPoint(x: face.x - s * 0.275, y: top + s * 0.062)
        )
        path.closeSubpath()
        return path
    }

    private static func point(grip: CGPoint, reach: CGFloat, angle: Double) -> CGPoint {
        CGPoint(
            x: grip.x + CGFloat(sin(angle)) * reach,
            y: grip.y + CGFloat(cos(angle)) * reach
        )
    }
}
