import SwiftUI
import UIKit

/// Brand beat on the launch splash. The splash curtains an already-rendered
/// first frame — Home is right behind it — so every second of hold is a
/// second of pure waiting. The beat is short on purpose, and the web
/// client's own rule is the rule here too: "Returning users already know
/// the brand — keep a beat, not a wait." Lockstep with `src/lib/forge-splash.ts`.
enum ForgeSplashTiming: Sendable {
    /// 0.65s: the hammer lands at ~0.48s, sparks fly, then the curtain lifts.
    /// A beat, not a wait. (Was 2.45s, which read as a frozen launch.)
    /// Flag: hold + fade = 0.95s, only 50ms under `freezeCeiling` 1.0.
    /// Flag: web `src/lib/forge-splash.ts` is still 2450ms / freezeCeiling 3100ms
    /// — not lockstep with this iOS beat.
    static let hold: TimeInterval = 0.65
    static let reduceMotionHold: TimeInterval = 0.3
    /// Signed-in users already know the brand. Static flame, no swing, ≤0.3s.
    static let signedInHold: TimeInterval = 0.25
    static let fadeOut: TimeInterval = 0.3

    /// Hard ceiling so a future bump cannot become a frozen launch again.
    /// The whole forced wait (hold + fade) must stay under a second.
    /// Full path sits at 0.95s — a 50ms margin, not a comfortable gap.
    static let freezeCeiling: TimeInterval = 1.0
    /// Floor so the beat is long enough to land the wordmark.
    static let brandFloor: TimeInterval = 0.3

    static func hold(reduceMotion: Bool, signedIn: Bool) -> TimeInterval {
        if reduceMotion { return reduceMotionHold }
        if signedIn { return signedInHold }
        return hold
    }

    static func pauseNanoseconds(reduceMotion: Bool, signedIn: Bool = false) -> UInt64 {
        UInt64(hold(reduceMotion: reduceMotion, signedIn: signedIn) * 1_000_000_000)
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
    /// Splash: 1.2 × 0.40 = 0.48s, inside the 0.46–0.50s window.
    static let strikeImpactFraction: Double = 0.40
    /// Seconds from splash appear to hammer impact (~0.48s).
    static var splashImpactTime: TimeInterval { splashDuration * strikeImpactFraction }

    static func pose(
        variation: ForgeStrikeVariation,
        time: Double,
        duration: TimeInterval = ForgeStrikeGeometry.duration,
        reduceMotion: Bool,
        style: ForgeStrikeMotion.Style = ForgeStrikeMotion.style
    ) -> ForgeStrikePose {
        let span = max(duration, 0.01)
        let u = reduceMotion ? 1 : min(1, max(0, time / span))
        switch variation {
        case .strike: return strike(u, style: style)
        case .quench: return quench(u)
        case .spark: return spark(u)
        case .temper: return temper(u)
        }
    }

    /// Raised hammer falls into the fire. Quartic ease-in — never linear.
    /// Style A rebounds; style B lands and rests.
    private static func strike(_ u: Double, style: ForgeStrikeMotion.Style) -> ForgeStrikePose {
        let down = easeInQuart(window(u, 0, strikeImpactFraction))
        let hit = spike(u, center: strikeImpactFraction, width: 0.10)
        switch style {
        case .accelerateRebound:
            let rebound = springOvershoot(window(u, strikeImpactFraction, 1), amplitude: 0.22, decay: 9, omega: 16)
            let settle = smoothstep(window(u, strikeImpactFraction, 0.80))
            return ForgeStrikePose(
                hammerAngle: 1.14 * (1 - down) + 0.04 * down + rebound,
                impact: hit,
                flameScale: 0.42 + 0.78 * hit + 0.28 * settle,
                sparkTravel: smoothstep(window(u, strikeImpactFraction, 0.90)),
                heat: 0.32 + 0.68 * hit + 0.28 * settle
            )
        case .forgeAndRest:
            let gather = smoothstep(window(u, strikeImpactFraction, 0.62))
            return ForgeStrikePose(
                hammerAngle: 1.14 * (1 - down) + 0.14 * down,
                impact: hit * 0.72,
                flameScale: 0.88 + 0.13 * gather,
                sparkTravel: smoothstep(window(u, strikeImpactFraction, 0.72)),
                heat: 0.40 + 0.28 * gather
            )
        }
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

    /// Accelerates hard into the strike. Linear is rejected for the swing.
    private static func easeInQuart(_ x: Double) -> Double {
        let t = clamp01(x)
        return t * t * t * t
    }

    /// Damped rebound after impact. 0 at the hit, a brief overshoot, then rest.
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

/// Full swing + sparks, or a settled flame with no hammer motion.
enum ForgeStrikePlayback: String, Sendable {
    case full
    /// Signed-in splash: static hearth, no swing, no burst.
    case trimmed
}

/// How the splash beat is driven. Flip `style` to preview Nox's beat.
enum ForgeStrikeMotion: Sendable {
    enum Style: String, Sendable, CaseIterable {
        /// Akshith t74u: accelerate into the strike, slight overshoot / rebound.
        case accelerateRebound
        /// Nox forging-yourself: firm strike, then rest. No rebound, recoil, or shake.
        case forgeAndRest
    }

    /// Default A. Set to `.forgeAndRest` to ship Option B.
    static let style: Style = .accelerateRebound

    static let sparkBackend = "CAEmitterLayer"
    static var swingEasing: String {
        switch style {
        case .accelerateRebound: return "easeInQuart+spring"
        case .forgeAndRest: return "easeInQuart+rest"
        }
    }
    static let swingIsLinear = false
    static var allowsRebound: Bool { style == .accelerateRebound }
    static var allowsImpactShake: Bool { style == .accelerateRebound }
}

/// Hammer, anvil, and flame. Plays once per appearance, then holds the last pose.
struct ForgeStrikeMark: View {
    var variation: ForgeStrikeVariation
    var isActive: Bool = true
    var duration: TimeInterval = ForgeStrikeGeometry.duration
    /// Bump to play the beat again from the wind-up.
    var replayToken: Int = 0
    var playback: ForgeStrikePlayback = .full

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.forgeWelcomeCovered) private var covered

    @State private var startedAt = Date()
    @State private var playing = false
    @State private var frozenTime: TimeInterval = 0
    @State private var generation = 0
    @State private var playTask: Task<Void, Never>?
    @State private var sparkBurst = 0

    private var motionFrozen: Bool { reduceMotion || playback == .trimmed }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !playing)) { (timeline: TimelineViewDefaultContext) in
            let elapsed = displayedTime(at: timeline.date)
            let pose = ForgeStrikeGeometry.pose(
                variation: variation,
                time: elapsed,
                duration: duration,
                reduceMotion: motionFrozen
            )
            ZStack {
                Canvas { context, size in
                    ForgeStrikeCanvas.draw(
                        context: &context,
                        size: size,
                        variation: variation,
                        pose: pose,
                        time: elapsed,
                        duration: duration,
                        reduceMotion: motionFrozen
                    )
                }
                if !motionFrozen {
                    ForgeSparkEmitterView(
                        burstToken: sparkBurst,
                        variation: variation
                    )
                }
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
        .onChange(of: playback) { _, _ in arm() }
    }

    private func displayedTime(at date: Date) -> TimeInterval {
        if motionFrozen { return duration }
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
        if motionFrozen {
            playing = false
            frozenTime = duration
            return
        }
        frozenTime = 0
        playing = true
        let nanos = UInt64(max(0, duration) * 1_000_000_000)
        let impactNanos = UInt64(max(0, impactTime) * 1_000_000_000)
        playTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: impactNanos)
            guard !Task.isCancelled, token == generation else { return }
            sparkBurst += 1
            let remain = nanos > impactNanos ? nanos - impactNanos : 0
            try? await Task.sleep(nanoseconds: remain)
            guard !Task.isCancelled, token == generation else { return }
            frozenTime = duration
            playing = false
        }
    }

    private var impactTime: TimeInterval {
        switch variation {
        case .strike: return duration * ForgeStrikeGeometry.strikeImpactFraction
        case .quench: return duration * 0.12
        case .spark: return duration * 0.34
        case .temper: return duration * 0.42
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

        let shake = ForgeStrikeMotion.allowsImpactShake ? 0.012 : 0
        context.translateBy(x: 0, y: CGFloat(pose.impact) * s * shake)

        let bloomRect = CGRect(
            x: face.x - s * 0.42,
            y: top - s * (0.30 + 0.38 * pose.flameScale),
            width: s * 0.84,
            height: s * (0.40 + 0.48 * pose.flameScale)
        )
        context.drawLayer { bloom in
            bloom.addFilter(.blur(radius: s * 0.055))
            bloom.fill(
                Path(ellipseIn: bloomRect),
                with: .color(Color.ember.opacity(0.10 + 0.28 * pose.heat * min(pose.flameScale, 1.2)))
            )
        }
        let glowRect = CGRect(
            x: face.x - s * 0.30,
            y: top - s * (0.20 + 0.28 * pose.flameScale),
            width: s * 0.60,
            height: s * (0.26 + 0.34 * pose.flameScale)
        )
        context.fill(
            Path(ellipseIn: glowRect),
            with: .color(Color.ember.opacity(0.08 + 0.18 * pose.heat * min(pose.flameScale, 1.2)))
        )

        let anvil = anvilPath(face: face, top: top, s: s)
        context.fill(
            anvil,
            with: .linearGradient(
                Gradient(colors: [
                    Color(hex: "3C414A"),
                    Color(hex: "1A1C22"),
                    Color(hex: "2C3038")
                ]),
                startPoint: CGPoint(x: face.x - s * 0.22, y: top - s * 0.05),
                endPoint: CGPoint(x: face.x + s * 0.16, y: top + s * 0.16)
            )
        )
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
        let flameWidth = s * 0.38
        let flameHeight = s * 0.58 * scale
        let flickerT = reduceMotion ? 0.18 : ForgeFireGeometry.flickerTime(time)
        let shimmer = reduceMotion ? 0 : 0.014 * sin(flickerT * .pi * 2 * 3)
        let flameRect = CGRect(
            x: face.x - flameWidth / 2 + CGFloat(shimmer) * s,
            y: top - flameHeight,
            width: flameWidth,
            height: flameHeight
        )

        paintTongues(
            context: &context,
            top: top,
            flameRect: flameRect,
            pose: pose,
            time: time,
            reduceMotion: reduceMotion,
            intensity: .rage,
            count: scale > 0.9 ? 12 : (scale > 0.45 ? 8 : 5),
            band: .outer
        )
        paintTongues(
            context: &context,
            top: top,
            flameRect: flameRect.insetBy(dx: flameWidth * 0.10, dy: flameHeight * 0.08),
            pose: pose,
            time: time,
            reduceMotion: reduceMotion,
            intensity: .rage,
            count: scale > 0.9 ? 8 : 6,
            band: .mid
        )
        paintTongues(
            context: &context,
            top: top,
            flameRect: flameRect.insetBy(dx: flameWidth * 0.20, dy: flameHeight * 0.18),
            pose: pose,
            time: time,
            reduceMotion: reduceMotion,
            intensity: .ember,
            count: 5,
            band: .core
        )

        let coreW = flameWidth * 0.34
        let coreH = flameHeight * 0.22
        let core = CGRect(x: face.x - coreW / 2, y: top - coreH * 0.85, width: coreW, height: coreH)
        context.fill(
            Path(ellipseIn: core),
            with: .color(Color(hex: "FFF4C4").opacity(0.35 + 0.50 * min(pose.heat, 1)))
        )
        let kernel = core.insetBy(dx: coreW * 0.28, dy: coreH * 0.30)
        context.fill(
            Path(ellipseIn: kernel),
            with: .color(Color(hex: "FFE28A").opacity(0.55 + 0.40 * min(pose.heat, 1)))
        )

        for index in 0..<3 {
            let shift = CGFloat(index - 1) * s * 0.042
            let coal = CGRect(x: face.x + shift - s * 0.016, y: top - s * 0.022, width: s * 0.032, height: s * 0.024)
            context.fill(Path(ellipseIn: coal), with: .color(Color.emberDark.opacity(0.85)))
        }
    }

    private enum FlameBand {
        case outer, mid, core
    }

    private static func paintTongues(
        context: inout GraphicsContext,
        top: CGFloat,
        flameRect: CGRect,
        pose: ForgeStrikePose,
        time: Double,
        reduceMotion: Bool,
        intensity: ForgeFireIntensity,
        count: Int,
        band: FlameBand
    ) {
        guard flameRect.width > 1, flameRect.height > 1 else { return }
        for index in 0..<count {
            let tongue = ForgeFireGeometry.tongue(
                index: index,
                count: count,
                time: time,
                intensity: intensity,
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
            let widthScale: CGFloat
            let color: Color
            let alphaScale: Double
            switch band {
            case .outer:
                widthScale = 3.1
                color = Color.emberDark
                alphaScale = 0.42
            case .mid:
                widthScale = 2.4
                color = Color.ember
                alphaScale = 0.62
            case .core:
                widthScale = 1.8
                color = Color(hex: "FFE28A")
                alphaScale = 0.80
            }
            let width = CGFloat(tongue.width) * flameRect.width * widthScale
            let hot = min(1, tongue.heat / max(intensity.coreHeat, 0.01))
            let alpha = min(1, (0.30 + 0.70 * hot) * (0.40 + 0.60 * pose.heat) * alphaScale)
            context.fill(tonguePath(base: base, tip: tip, width: width), with: .color(color.opacity(alpha)))
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
        // Impact sparks live on CAEmitterLayer. Canvas keeps the spark-page
        // ring only — no uniform circles.
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
        let handleWidth = max(3.5, headDepth * 0.30)

        if ghost {
            var handle = Path()
            handle.move(to: grip)
            handle.addLine(to: neck)
            context.stroke(
                handle,
                with: .color(Color.paper.opacity(opacity)),
                style: StrokeStyle(lineWidth: handleWidth, lineCap: .round)
            )
        } else {
            drawWoodHandle(
                context: &context,
                grip: grip,
                neck: neck,
                width: handleWidth,
                opacity: opacity
            )
        }

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
            if ghost {
                layer.fill(head, with: .color(Color.paper))
            } else {
                layer.fill(
                    head,
                    with: .linearGradient(
                        Gradient(colors: [
                            Color(hex: "6A717C"),
                            Color(hex: "E8ECF2"),
                            Color(hex: "9AA1AB"),
                            Color(hex: "F4F6F8")
                        ]),
                        startPoint: CGPoint(x: -half, y: -headDepth),
                        endPoint: CGPoint(x: half, y: 0)
                    )
                )
                var cheek = Path()
                cheek.move(to: CGPoint(x: -half * 0.72, y: -headDepth))
                cheek.addLine(to: CGPoint(x: half * 0.72, y: -headDepth))
                cheek.addLine(to: CGPoint(x: half * 0.78, y: -headDepth * 0.72))
                cheek.addLine(to: CGPoint(x: -half * 0.78, y: -headDepth * 0.72))
                cheek.closeSubpath()
                layer.fill(cheek, with: .color(Color(hex: "8B929C").opacity(0.88)))
                let spec = CGRect(
                    x: -half * 0.18,
                    y: -headDepth * 0.86,
                    width: half * 0.55,
                    height: headDepth * 0.16
                )
                layer.fill(
                    Path(ellipseIn: spec),
                    with: .color(Color(hex: "FFFFFF").opacity(0.55))
                )
                var strikeFace = Path()
                strikeFace.move(to: CGPoint(x: -half, y: 0))
                strikeFace.addLine(to: CGPoint(x: half, y: 0))
                strikeFace.addLine(to: CGPoint(x: half * 0.92, y: -headDepth * 0.18))
                strikeFace.addLine(to: CGPoint(x: -half * 0.92, y: -headDepth * 0.18))
                strikeFace.closeSubpath()
                layer.fill(
                    strikeFace,
                    with: .linearGradient(
                        Gradient(colors: [
                            Color(hex: "C5CAD1"),
                            Color(hex: "F7F8FA"),
                            Color.ember.opacity(0.20 + 0.80 * impact)
                        ]),
                        startPoint: CGPoint(x: -half, y: -headDepth * 0.18),
                        endPoint: CGPoint(x: half, y: 0)
                    )
                )
                let ferrule = CGRect(
                    x: -handleWidth * 0.55,
                    y: -headDepth - handleWidth * 0.15,
                    width: handleWidth * 1.1,
                    height: handleWidth * 0.55
                )
                layer.fill(Path(roundedRect: ferrule, cornerRadius: 1), with: .color(Color(hex: "5C616A")))
            }
        }
    }

    private static func drawWoodHandle(
        context: inout GraphicsContext,
        grip: CGPoint,
        neck: CGPoint,
        width: CGFloat,
        opacity: Double
    ) {
        var handle = Path()
        handle.move(to: grip)
        handle.addLine(to: neck)
        context.stroke(
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
            ),
            style: StrokeStyle(lineWidth: width, lineCap: .round)
        )
        let dx = neck.x - grip.x
        let dy = neck.y - grip.y
        let len = max(hypot(dx, dy), 0.001)
        let nx = -dy / len * width * 0.18
        let ny = dx / len * width * 0.18
        for grain in 0..<4 {
            let t = CGFloat(0.18 + Double(grain) * 0.18)
            let a = CGPoint(x: grip.x + dx * t, y: grip.y + dy * t)
            let b = CGPoint(x: grip.x + dx * min(1, t + 0.16), y: grip.y + dy * min(1, t + 0.16))
            var line = Path()
            line.move(to: CGPoint(x: a.x + nx, y: a.y + ny))
            line.addLine(to: CGPoint(x: b.x + nx, y: b.y + ny))
            context.stroke(
                line,
                with: .color(Color(hex: "3D2414").opacity(0.28 * opacity)),
                style: StrokeStyle(lineWidth: 0.7, lineCap: .round)
            )
        }
        context.stroke(
            handle,
            with: .color(Color(hex: "4A2C16").opacity(0.35 * opacity)),
            style: StrokeStyle(lineWidth: max(2, width * 0.22), lineCap: .round)
        )
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

// MARK: - One-shot sparks (CAEmitterLayer)

/// Ballistic ember chips. Not uniform circles. One burst, then silence.
enum ForgeSparkBurst: Sendable {
    static let kind = "ca-emitter"
    static let shape = "chip"
    static let gravity: Double = 240
    static let oneShot = true
    static let maxLifetime: TimeInterval = 0.55

    static func birthCount(for variation: ForgeStrikeVariation) -> Int {
        switch variation {
        case .strike: return 28
        case .spark: return 36
        case .quench: return 14
        case .temper: return 8
        }
    }
}

struct ForgeSparkEmitterView: UIViewRepresentable {
    var burstToken: Int
    var variation: ForgeStrikeVariation

    func makeUIView(context: Context) -> ForgeSparkHostView {
        let view = ForgeSparkHostView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: ForgeSparkHostView, context: Context) {
        view.variation = variation
        if burstToken != view.lastToken {
            view.lastToken = burstToken
            if burstToken > 0 {
                view.burst()
            }
        }
    }
}

final class ForgeSparkHostView: UIView {
    var variation: ForgeStrikeVariation = .strike
    var lastToken = 0
    private static let chip: CGImage? = ForgeSparkHostView.makeChip()

    func burst(retries: Int = 8) {
        guard bounds.width > 1, bounds.height > 1 else {
            guard retries > 0 else { return }
            DispatchQueue.main.async { [weak self] in self?.burst(retries: retries - 1) }
            return
        }
        let emitter = CAEmitterLayer()
        emitter.emitterShape = .point
        emitter.emitterMode = .volume
        emitter.renderMode = .additive
        emitter.emitterSize = .zero
        emitter.emitterPosition = CGPoint(x: bounds.midX, y: bounds.height * 0.58)
        emitter.beginTime = CACurrentMediaTime()
        emitter.birthRate = 1
        emitter.emitterCells = cells()
        layer.addSublayer(emitter)
        if ForgeStrikeMotion.allowsImpactShake {
            punch()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak emitter] in
            emitter?.birthRate = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + ForgeSparkBurst.maxLifetime + 0.08) { [weak emitter] in
            emitter?.removeFromSuperlayer()
        }
    }

    /// Core Animation punch at impact — springy, not linear.
    private func punch() {
        let shake = CAKeyframeAnimation(keyPath: "transform.translation.y")
        shake.values = [0, 4, -1.6, 0]
        shake.keyTimes = [0, 0.22, 0.58, 1]
        shake.duration = 0.14
        shake.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(shake, forKey: "impact-punch")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let emitters = layer.sublayers?.compactMap({ $0 as? CAEmitterLayer }) {
            for emitter in emitters {
                emitter.emitterPosition = CGPoint(x: bounds.midX, y: bounds.height * 0.58)
            }
        }
    }

    private func cells() -> [CAEmitterCell] {
        let count = ForgeSparkBurst.birthCount(for: variation)
        switch ForgeStrikeMotion.style {
        case .accelerateRebound:
            return [
                makeCell(
                    birth: Float(count) * 12,
                    velocity: 168,
                    scale: 0.42,
                    color: UIColor(red: 1, green: 0.89, blue: 0.54, alpha: 1),
                    cool: (red: -0.15, green: -0.55, blue: -0.85),
                    range: .pi * 0.72
                ),
                makeCell(
                    birth: Float(count) * 9,
                    velocity: 124,
                    scale: 0.28,
                    color: UIColor(red: 1, green: 0.48, blue: 0.12, alpha: 0.95),
                    cool: (red: -0.25, green: -0.70, blue: -0.40),
                    range: .pi * 0.72
                ),
                makeCell(
                    birth: Float(count) * 6,
                    velocity: 88,
                    scale: 0.16,
                    color: UIColor(red: 0.77, green: 0.23, blue: 0.02, alpha: 0.85),
                    cool: (red: -0.40, green: -0.35, blue: -0.10),
                    range: .pi * 0.72
                )
            ]
        case .forgeAndRest:
            // Arc up, fall back to the hearth, cool ember → gold. Not debris.
            return [
                makeCell(
                    birth: Float(count) * 4,
                    velocity: 96,
                    scale: 0.34,
                    color: UIColor(red: 1, green: 0.30, blue: 0.02, alpha: 0.95),
                    cool: (red: 0, green: 1.15, blue: 0.85),
                    range: .pi * 0.32
                ),
                makeCell(
                    birth: Float(count) * 3,
                    velocity: 72,
                    scale: 0.22,
                    color: UIColor(red: 0.90, green: 0.22, blue: 0.02, alpha: 0.88),
                    cool: (red: 0.10, green: 1.05, blue: 0.70),
                    range: .pi * 0.28
                )
            ]
        }
    }

    private func makeCell(
        birth: Float,
        velocity: CGFloat,
        scale: CGFloat,
        color: UIColor,
        cool: (red: Float, green: Float, blue: Float),
        range: CGFloat
    ) -> CAEmitterCell {
        let cell = CAEmitterCell()
        cell.birthRate = birth
        cell.lifetime = 0.38
        cell.lifetimeRange = 0.16
        cell.velocity = velocity
        cell.velocityRange = velocity * 0.40
        cell.emissionLongitude = -.pi / 2
        cell.emissionRange = range
        cell.yAcceleration = CGFloat(ForgeSparkBurst.gravity)
        cell.xAcceleration = 0
        cell.scale = scale
        cell.scaleRange = scale * 0.85
        cell.scaleSpeed = -0.55
        cell.spin = 2.4
        cell.spinRange = 6
        cell.color = color.cgColor
        cell.redSpeed = cool.red
        cell.greenSpeed = cool.green
        cell.blueSpeed = cool.blue
        cell.alphaSpeed = -2.1
        cell.contents = Self.chip
        return cell
    }

    /// Elongated ember chip — not a circle. Drawn procedurally.
    private static func makeChip() -> CGImage? {
        let size = CGSize(width: 12, height: 22)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(UIColor(red: 1, green: 0.92, blue: 0.62, alpha: 1).cgColor)
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 6, y: 0.5))
            path.addQuadCurve(to: CGPoint(x: 10.5, y: 10), controlPoint: CGPoint(x: 11, y: 4))
            path.addQuadCurve(to: CGPoint(x: 6, y: 21.5), controlPoint: CGPoint(x: 9.5, y: 18))
            path.addQuadCurve(to: CGPoint(x: 1.5, y: 10), controlPoint: CGPoint(x: 2.5, y: 18))
            path.addQuadCurve(to: CGPoint(x: 6, y: 0.5), controlPoint: CGPoint(x: 1, y: 4))
            path.close()
            path.fill()
        }
        return image.cgImage
    }
}
