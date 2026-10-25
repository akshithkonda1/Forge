import SwiftUI

/// Brand beat on the launch splash. The splash curtains an already-rendered
/// first frame — Home is right behind it — so every second of hold is a
/// second of pure waiting. The beat is short on purpose, and the web
/// client's own rule is the rule here too: "Returning users already know
/// the brand — keep a beat, not a wait." Lockstep with `src/lib/forge-splash.ts`.
enum ForgeSplashTiming: Sendable {
    /// 0.65s: the hammer lands at ~0.46s, sparks fly, then the curtain lifts.
    /// A beat, not a wait. (Was 2.45s, which read as a frozen launch.)
    static let hold: TimeInterval = 0.65
    static let reduceMotionHold: TimeInterval = 0.3
    static let fadeOut: TimeInterval = 0.3

    /// Hard ceiling so a future bump cannot become a frozen launch again.
    /// The whole forced wait (hold + fade) must stay under a second.
    static let freezeCeiling: TimeInterval = 1.0
    /// Floor so the beat is long enough to land the wordmark.
    static let brandFloor: TimeInterval = 0.3

    static func pauseNanoseconds(reduceMotion: Bool) -> UInt64 {
        if reduceMotion { return 300_000_000 }
        return 650_000_000
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

// MARK: - Hammer against the flame

/// One hammer beat for the welcome screen and the launch splash.
/// A bounded strike, then a still pose. Not the rage-fire field.
enum ForgeStrikeVariation: String, Sendable, CaseIterable, Identifiable {
    case strike
    case quench
    case spark
    case temper

    var id: String { rawValue }

    var title: String {
        switch self {
        case .strike: return "Strike"
        case .quench: return "Quench"
        case .spark: return "Spark"
        case .temper: return "Temper"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .strike: return "Hammer strikes the flame"
        case .quench: return "Hammer lifts out of the flame"
        case .spark: return "Hammer strikes and a spark ring travels out"
        case .temper: return "Hammer taps and the flame steadies"
        }
    }
}

struct ForgeStrikePose: Equatable, Sendable {
    /// Radians from straight down. Larger means the head is swung back, up and to the right.
    var hammerAngle: Double
    /// 0...1 impact flash.
    var impact: Double
    /// Height of the fire on the anvil.
    var flameScale: Double
    /// 0...1 spark ring / burst travel.
    var sparkTravel: Double
    /// Heat in the anvil face.
    var heat: Double
}

enum ForgeStrikeGeometry: Sendable {
    /// Welcome beat. Long enough to read the swing, then it holds.
    static let duration: TimeInterval = 1.05
    /// Launch strike. Impact lands inside `ForgeSplashTiming.hold`; the
    /// settle plays out under the fade, so the curtain stays a beat.
    static let splashDuration: TimeInterval = 1.2
    /// Where `.strike` peaks, as a fraction of its duration.
    static let strikeImpactFraction: Double = 0.38
    /// Seconds from splash appear to hammer impact (~0.46s).
    static var splashImpactTime: TimeInterval { splashDuration * strikeImpactFraction }

    static func pose(
        variation: ForgeStrikeVariation,
        time: Double,
        duration: TimeInterval = ForgeStrikeGeometry.duration,
        reduceMotion: Bool
    ) -> ForgeStrikePose {
        let span = max(duration, 0.01)
        let u = reduceMotion ? 1 : min(1, max(0, time / span))
        switch variation {
        case .strike: return strike(u)
        case .quench: return quench(u)
        case .spark: return spark(u)
        case .temper: return temper(u)
        }
    }

    /// Raised hammer falls into the fire. The flame flares, then settles into a hearth.
    private static func strike(_ u: Double) -> ForgeStrikePose {
        let down = easeIn(window(u, 0, strikeImpactFraction))
        let hit = spike(u, center: strikeImpactFraction, width: 0.10)
        let bounce = spike(u, center: 0.50, width: 0.10)
        let settle = smoothstep(window(u, 0.38, 0.78))
        return ForgeStrikePose(
            hammerAngle: 1.12 * (1 - down) + 0.04 * down + 0.18 * bounce,
            impact: hit,
            flameScale: 0.42 + 0.78 * hit + 0.28 * settle,
            sparkTravel: smoothstep(window(u, 0.38, 0.88)),
            heat: 0.32 + 0.68 * hit + 0.28 * settle
        )
    }

    /// Hammer starts in the fire and lifts clear. The flame collapses to a coal.
    private static func quench(_ u: Double) -> ForgeStrikePose {
        let lift = smoothstep(window(u, 0.06, 0.62))
        let die = smoothstep(window(u, 0.10, 0.74))
        return ForgeStrikePose(
            hammerAngle: 0.06 + 1.06 * lift,
            impact: spike(u, center: 0.12, width: 0.12) * 0.55,
            flameScale: 1.02 - 0.80 * die,
            sparkTravel: smoothstep(u) * 0.30,
            heat: 0.88 - 0.64 * die
        )
    }

    /// A shorter strike. The hearth stays. A spark ring travels out and remains as a faint halo.
    private static func spark(_ u: Double) -> ForgeStrikePose {
        let down = easeIn(window(u, 0.04, 0.34))
        let hit = spike(u, center: 0.34, width: 0.08)
        return ForgeStrikePose(
            hammerAngle: 0.96 * (1 - down) + 0.05 * down + 0.12 * spike(u, center: 0.46, width: 0.10),
            impact: hit * 0.72,
            flameScale: 0.64 + 0.20 * hit,
            sparkTravel: smoothstep(window(u, 0.34, 0.94)),
            heat: 0.48 + 0.40 * hit + 0.12 * smoothstep(window(u, 0.34, 0.94))
        )
    }

    /// A short tap, then the hammer rests back and the flame levels off.
    private static func temper(_ u: Double) -> ForgeStrikePose {
        let down = easeIn(window(u, 0.14, 0.42))
        let recover = smoothstep(window(u, 0.55, 0.88))
        return ForgeStrikePose(
            hammerAngle: 0.55 * (1 - down) + 0.05 * down
                + 0.10 * spike(u, center: 0.52, width: 0.09)
                + 0.24 * recover,
            impact: spike(u, center: 0.42, width: 0.07) * 0.42,
            flameScale: 0.48 + 0.18 * smoothstep(window(u, 0.28, 0.80)),
            sparkTravel: smoothstep(window(u, 0.42, 0.70)) * 0.22,
            heat: 0.40 + 0.30 * smoothstep(window(u, 0.36, 0.86))
        )
    }

    private static func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }

    private static func smoothstep(_ x: Double) -> Double {
        let t = clamp01(x)
        return t * t * (3 - 2 * t)
    }

    private static func easeIn(_ x: Double) -> Double {
        let t = clamp01(x)
        return t * t
    }

    private static func window(_ u: Double, _ start: Double, _ end: Double) -> Double {
        guard end > start else { return u >= end ? 1 : 0 }
        return clamp01((u - start) / (end - start))
    }

    /// 1 at `center`, 0 outside `width`.
    private static func spike(_ u: Double, center: Double, width: Double) -> Double {
        guard width > 0 else { return 0 }
        let d = abs(u - center) / width
        if d >= 1 { return 0 }
        return 0.5 + 0.5 * cos(d * .pi)
    }
}

private struct ForgeWelcomeCoveredKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True while the launch splash still covers the welcome screen.
    /// The strike waits until the screen is actually visible.
    var forgeWelcomeCovered: Bool {
        get { self[ForgeWelcomeCoveredKey.self] }
        set { self[ForgeWelcomeCoveredKey.self] = newValue }
    }
}

/// Hammer, anvil, and flame. Plays once per appearance, then holds the last pose.
struct ForgeStrikeMark: View {
    var variation: ForgeStrikeVariation
    var isActive: Bool = true
    var duration: TimeInterval = ForgeStrikeGeometry.duration
    /// Bump to play the beat again from the wind-up.
    var replayToken: Int = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.forgeWelcomeCovered) private var covered

    @State private var startedAt = Date()
    @State private var playing = false
    @State private var frozenTime: TimeInterval = 0
    @State private var generation = 0
    @State private var playTask: Task<Void, Never>?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !playing)) { (timeline: TimelineViewDefaultContext) in
            Canvas { context, size in
                let elapsed = displayedTime(at: timeline.date)
                let pose = ForgeStrikeGeometry.pose(
                    variation: variation,
                    time: elapsed,
                    duration: duration,
                    reduceMotion: reduceMotion
                )
                ForgeStrikeCanvas.draw(
                    context: &context,
                    size: size,
                    variation: variation,
                    pose: pose,
                    time: elapsed,
                    duration: duration,
                    reduceMotion: reduceMotion
                )
            }
        }
        .accessibilityHidden(true)
        .onAppear { arm() }
        .onDisappear { playTask?.cancel() }
        .onChange(of: isActive) { _, _ in arm() }
        .onChange(of: covered) { wasCovered, isCovered in
            if wasCovered && !isCovered {
                playAfterCurtain()
            } else {
                arm()
            }
        }
        .onChange(of: replayToken) { _, _ in
            guard isActive, !covered else { return }
            begin()
        }
        .onChange(of: reduceMotion) { _, _ in arm() }
        .onChange(of: variation) { _, _ in arm() }
    }

    private func displayedTime(at date: Date) -> TimeInterval {
        if reduceMotion { return duration }
        if playing { return max(0, date.timeIntervalSince(startedAt)) }
        return frozenTime
    }

    private func arm() {
        guard isActive, !covered else {
            playTask?.cancel()
            if playing {
                frozenTime = max(0, Date().timeIntervalSince(startedAt))
                playing = false
            }
            return
        }
        begin()
    }

    /// The splash fades off. Start once the welcome mark is the thing on screen.
    private func playAfterCurtain() {
        playTask?.cancel()
        let token = generation
        let nanos = UInt64(ForgeSplashTiming.fadeOut * 1_000_000_000)
        playTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled, token == generation else { return }
            begin()
        }
    }

    private func begin() {
        playTask?.cancel()
        generation += 1
        startedAt = Date()
        let token = generation
        if reduceMotion {
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

private enum ForgeStrikeCanvas {
    static func draw(
        context: inout GraphicsContext,
        size: CGSize,
        variation: ForgeStrikeVariation,
        pose: ForgeStrikePose,
        time: Double,
        duration: TimeInterval,
        reduceMotion: Bool
    ) {
        let s = min(size.width, size.height)
        let grip = CGPoint(x: size.width * 0.38, y: size.height * 0.16)
        let reach = s * 0.56
        let face = point(grip: grip, reach: reach, angle: 0.05)
        let top = face.y + 1
        let headWidth = s * 0.22
        let headDepth = s * 0.11

        context.translateBy(x: 0, y: CGFloat(pose.impact) * s * 0.012)

        let glowRect = CGRect(
            x: face.x - s * 0.34,
            y: top - s * (0.22 + 0.28 * pose.flameScale),
            width: s * 0.68,
            height: s * (0.28 + 0.36 * pose.flameScale)
        )
        context.fill(
            Path(ellipseIn: glowRect),
            with: .color(Color.ember.opacity(0.05 + 0.16 * pose.heat * min(pose.flameScale, 1.2)))
        )

        let anvil = anvilPath(face: face, top: top, s: s)
        context.fill(anvil, with: .color(Color(hex: "2C3038")))
        context.stroke(
            anvil,
            with: .color(Color.paper.opacity(0.16)),
            style: StrokeStyle(lineWidth: 1, lineJoin: .round)
        )

        let slot = CGRect(x: face.x - s * 0.13, y: top - s * 0.015, width: s * 0.26, height: s * 0.045)
        context.fill(Path(roundedRect: slot, cornerRadius: s * 0.02), with: .color(Color(hex: "0C0C0E")))

        drawFlame(
            context: &context,
            face: face,
            top: top,
            s: s,
            pose: pose,
            time: time,
            reduceMotion: reduceMotion
        )

        var lip = Path()
        lip.move(to: CGPoint(x: face.x - s * 0.16, y: top))
        lip.addLine(to: CGPoint(x: face.x + s * 0.16, y: top))
        context.stroke(
            lip,
            with: .color(Color.ember.opacity(0.20 + 0.75 * pose.heat)),
            style: StrokeStyle(lineWidth: max(1.5, s * 0.012), lineCap: .round)
        )

        drawBurst(context: &context, variation: variation, pose: pose, face: face, s: s)

        if !reduceMotion {
            for (lag, alpha) in [(0.07, 0.10), (0.035, 0.22)] {
                let earlier = ForgeStrikeGeometry.pose(
                    variation: variation,
                    time: time - lag,
                    duration: duration,
                    reduceMotion: false
                )
                guard abs(earlier.hammerAngle - pose.hammerAngle) > 0.03 else { continue }
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

        if pose.impact > 0.04 {
            let r = s * (0.05 + 0.14 * pose.impact)
            let flash = CGRect(x: face.x - r, y: top - r * 0.85, width: r * 2, height: r * 1.5)
            context.fill(Path(ellipseIn: flash), with: .color(Color.ember.opacity(0.28 * pose.impact)))
            let coreR = r * 0.42
            let core = CGRect(x: face.x - coreR, y: top - coreR, width: coreR * 2, height: coreR * 2)
            context.fill(
                Path(ellipseIn: core),
                with: .color(Color(hex: "FFE28A").opacity(0.85 * pose.impact))
            )
        }
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
        let scale = max(0.12, pose.flameScale)
        let flameWidth = s * 0.34
        let flameHeight = s * 0.52 * scale
        let flameRect = CGRect(
            x: face.x - flameWidth / 2,
            y: top - flameHeight,
            width: flameWidth,
            height: flameHeight
        )
        let count = scale > 0.9 ? 10 : (scale > 0.45 ? 7 : 4)
        for index in 0..<count {
            let tongue = ForgeFireGeometry.tongue(
                index: index,
                count: count,
                time: time,
                intensity: .ember,
                origin: .floor,
                reduceMotion: reduceMotion
            )
            let base = CGPoint(
                x: flameRect.minX + CGFloat(tongue.baseX) * flameRect.width,
                y: top - CGFloat(1 - tongue.baseY) * flameRect.height
            )
            let tip = CGPoint(
                x: flameRect.minX + CGFloat(tongue.tipX) * flameRect.width,
                y: top - CGFloat(1 - tongue.tipY) * flameRect.height
            )
            let width = CGFloat(tongue.width) * flameRect.width * 2.6
            let hot = min(1, tongue.heat / 0.28)
            let color: Color = hot > 0.85 ? Color(hex: "FFE28A") : (hot > 0.55 ? Color.emberLight : Color.ember)
            let alpha = min(1, (0.35 + 0.65 * hot) * (0.45 + 0.55 * pose.heat))
            context.fill(tonguePath(base: base, tip: tip, width: width), with: .color(color.opacity(alpha)))
        }

        let coreW = flameWidth * 0.42
        let coreH = flameHeight * 0.28
        let core = CGRect(x: face.x - coreW / 2, y: top - coreH, width: coreW, height: coreH)
        context.fill(
            Path(ellipseIn: core),
            with: .color(Color(hex: "FFE28A").opacity(0.25 + 0.45 * min(pose.heat, 1)))
        )

        if scale < 0.4 {
            for index in 0..<3 {
                let shift = CGFloat(index - 1) * s * 0.045
                let coal = CGRect(x: face.x + shift - s * 0.018, y: top - s * 0.03, width: s * 0.036, height: s * 0.028)
                context.fill(Path(ellipseIn: coal), with: .color(Color.emberDark.opacity(0.9)))
            }
        }
    }

    private static func drawBurst(
        context: inout GraphicsContext,
        variation: ForgeStrikeVariation,
        pose: ForgeStrikePose,
        face: CGPoint,
        s: CGFloat
    ) {
        if variation == .spark, pose.sparkTravel > 0.02 {
            let radius = CGFloat(pose.sparkTravel) * s * 0.40
            let alpha = max(0.20, (1 - pose.sparkTravel) * 0.90)
            let ring = CGRect(x: face.x - radius, y: face.y - radius * 0.92, width: radius * 2, height: radius * 2)
            context.stroke(
                Path(ellipseIn: ring),
                with: .color(Color.emberLight.opacity(alpha)),
                style: StrokeStyle(lineWidth: max(1, s * 0.008), lineCap: .round)
            )
            let inner = radius * 0.72
            if inner > 4 {
                let innerRect = CGRect(x: face.x - inner, y: face.y - inner * 0.92, width: inner * 2, height: inner * 2)
                context.stroke(
                    Path(ellipseIn: innerRect),
                    with: .color(Color(hex: "FFE28A").opacity(alpha * 0.7)),
                    style: StrokeStyle(lineWidth: max(0.5, s * 0.004))
                )
            }
        }

        let showSparks = pose.impact > 0.08 || (variation == .spark && pose.sparkTravel > 0.04) || (variation == .quench && pose.impact > 0.05)
        guard showSparks else { return }
        let count = variation == .spark ? 11 : 7
        let travel = variation == .spark ? pose.sparkTravel : max(pose.impact, 0.15)
        for index in 0..<count {
            let t = Double(index) / Double(max(count - 1, 1))
            let angle = -.pi * 0.98 + t * .pi * 0.96
            let jitter = 0.65 + 0.35 * hash01(Double(index) * 3.1 + 1.7)
            let dist = s * CGFloat(0.05 + 0.32 * travel * jitter)
            let point = CGPoint(
                x: face.x + CGFloat(cos(angle)) * dist,
                y: face.y + CGFloat(sin(angle)) * dist
            )
            let radius = s * (variation == .spark ? 0.012 : 0.010) * CGFloat(0.7 + 0.6 * hash01(Double(index) + 4))
            let alpha = variation == .spark
                ? max(0.25, (1 - pose.sparkTravel) * 0.85)
                : pose.impact * 0.9
            let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
            let color = index % 3 == 0 ? Color(hex: "FFE28A") : Color.emberLight
            context.fill(Path(ellipseIn: rect), with: .color(color.opacity(alpha)))
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
        let neck = CGPoint(x: face.x - dir.x * headDepth, y: face.y - dir.y * headDepth)

        var handle = Path()
        handle.move(to: grip)
        handle.addLine(to: neck)
        context.stroke(
            handle,
            with: .color((ghost ? Color.paper : Color(hex: "A56B3C")).opacity(opacity)),
            style: StrokeStyle(lineWidth: max(3, headDepth * 0.28), lineCap: .round)
        )

        let half = headWidth / 2
        context.drawLayer { layer in
            layer.translateBy(x: face.x, y: face.y)
            // Positive rotation is clockwise. Negate so the head's back
            // follows the handle up to the grip.
            layer.rotate(by: .radians(-angle))
            layer.opacity = opacity

            var head = Path()
            head.move(to: CGPoint(x: -half, y: 0))
            head.addLine(to: CGPoint(x: half, y: 0))
            head.addLine(to: CGPoint(x: half * 0.72, y: -headDepth))
            head.addLine(to: CGPoint(x: -half * 0.72, y: -headDepth))
            head.closeSubpath()
            layer.fill(head, with: .color(ghost ? Color.paper : Color(hex: "E4E7EC")))
            if !ghost {
                var cheek = Path()
                cheek.move(to: CGPoint(x: -half * 0.72, y: -headDepth))
                cheek.addLine(to: CGPoint(x: half * 0.72, y: -headDepth))
                cheek.addLine(to: CGPoint(x: half * 0.78, y: -headDepth * 0.72))
                cheek.addLine(to: CGPoint(x: -half * 0.78, y: -headDepth * 0.72))
                cheek.closeSubpath()
                layer.fill(cheek, with: .color(Color(hex: "9AA1AB")))
                var strikeFace = Path()
                strikeFace.move(to: CGPoint(x: -half, y: 0))
                strikeFace.addLine(to: CGPoint(x: half, y: 0))
                strikeFace.addLine(to: CGPoint(x: half * 0.92, y: -headDepth * 0.18))
                strikeFace.addLine(to: CGPoint(x: -half * 0.92, y: -headDepth * 0.18))
                strikeFace.closeSubpath()
                layer.fill(strikeFace, with: .color(Color.ember.opacity(0.25 + 0.75 * impact)))
            }
        }
    }

    private static func anvilPath(face: CGPoint, top: CGFloat, s: CGFloat) -> Path {
        let left = face.x - s * 0.20
        let right = face.x + s * 0.18
        var path = Path()
        path.move(to: CGPoint(x: left - s * 0.14, y: top - s * 0.045))
        path.addQuadCurve(
            to: CGPoint(x: left, y: top),
            control: CGPoint(x: left - s * 0.10, y: top - s * 0.09)
        )
        path.addLine(to: CGPoint(x: right, y: top))
        path.addLine(to: CGPoint(x: right, y: top + s * 0.055))
        path.addLine(to: CGPoint(x: right - s * 0.07, y: top + s * 0.055))
        path.addLine(to: CGPoint(x: right - s * 0.11, y: top + s * 0.16))
        path.addLine(to: CGPoint(x: left + s * 0.05, y: top + s * 0.16))
        path.addLine(to: CGPoint(x: left + s * 0.015, y: top + s * 0.055))
        path.addLine(to: CGPoint(x: left - s * 0.02, y: top + s * 0.055))
        path.addLine(to: CGPoint(x: left - s * 0.02, y: top))
        path.closeSubpath()
        return path
    }

    private static func tonguePath(base: CGPoint, tip: CGPoint, width: CGFloat) -> Path {
        let dx = tip.x - base.x
        let dy = tip.y - base.y
        let len = max(hypot(dx, dy), 0.001)
        let nx = -dy / len * width
        let ny = dx / len * width
        let mid = CGPoint(x: (base.x + tip.x) / 2, y: (base.y + tip.y) / 2)
        var path = Path()
        path.move(to: base)
        path.addQuadCurve(to: tip, control: CGPoint(x: mid.x + nx, y: mid.y + ny))
        path.addQuadCurve(to: base, control: CGPoint(x: mid.x - nx, y: mid.y - ny))
        path.closeSubpath()
        return path
    }

    private static func point(grip: CGPoint, reach: CGFloat, angle: Double) -> CGPoint {
        CGPoint(
            x: grip.x + CGFloat(sin(angle)) * reach,
            y: grip.y + CGFloat(cos(angle)) * reach
        )
    }

    private static func hash01(_ seed: Double) -> Double {
        let n = sin(seed * 12.9898) * 43758.5453
        return n - floor(n)
    }
}
