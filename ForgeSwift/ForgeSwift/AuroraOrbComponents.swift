import SwiftUI
import ForgeCore

/// Compact ARIA mark for avatars, tabs, and cards.
/// Pulse — a core, fed by cracks, ringed by a corona — is the identity. Live
/// speech/listen from `AriaPresence` overrides idle so every mark breathes
/// when she talks.
struct ARIAIdentityMark: View {
    var state: AROrbState = .idle
    var mood: ARIAMood = .focused
    var size: CGFloat = 40
    var amplitude: Float = 0.22
    var showsPresence: Bool = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AuroraOrbView(
                state: state,
                amplitude: amplitude,
                mood: mood,
                size: size,
                followPresence: true
            )
            if showsPresence {
                Circle()
                    .fill(ForgePalette.ember.opacity(0.9))
                    .frame(width: max(7, size * 0.18), height: max(7, size * 0.18))
                    .offset(x: 1, y: 1)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Pulse: a void core threaded with glowing cracks, ringed by a corona the
/// cracks feed — drawn natively, no image asset. SwiftUI beats the core,
/// runs light out along the veins a beat behind it, and shifts iridescence.
/// Motion is uniform scale only — never stretch. Reduce Motion freezes on
/// the still frame.
struct AuroraOrbView: View {
    let state: AROrbState
    let amplitude: Float
    var mood: ARIAMood = .focused
    var size: CGFloat = 140
    var followPresence: Bool = false

    private let presence = AriaPresence.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var resolvedState: AROrbState {
        followPresence && presence.orbState != .idle ? presence.orbState : state
    }

    private var resolvedAmplitude: Float {
        if followPresence, presence.isSpeaking { return max(amplitude, 0.72) }
        if followPresence, presence.isListening { return max(amplitude, max(presence.amplitude, 0.42)) }
        return amplitude
    }

    private var tick: Double {
        if reduceMotion { return 1 }
        return 1.0 / 24.0
    }

    var body: some View {
        TimelineView(.animation(
            minimumInterval: tick,
            paused: reduceMotion || scenePhase != .active
        )) { timeline in
            let t = reduceMotion ? AriaSigilGeometry.stillPose : timeline.date.timeIntervalSinceReferenceDate
            orb(at: t)
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            resolvedState == .speaking ? "ARIA speaking"
                : resolvedState == .listening ? "ARIA listening"
                : "ARIA"
        )
        .accessibilityAddTraits(resolvedState == .idle ? AccessibilityTraits() : .updatesFrequently)
        .onAppear {
            presence.playWelcomeChimeIfNeeded(size: size, reduceMotion: reduceMotion)
        }
    }

    private func orb(at t: TimeInterval) -> some View {
        let live = resolvedState
        let breath = AriaSigilGeometry.breath(time: t, state: live, reduceMotion: reduceMotion)
        let core = AriaSigilGeometry.corePulse(time: t, state: live, reduceMotion: reduceMotion)
        let hue = AriaSigilGeometry.hueShiftDegrees(time: t, state: live, reduceMotion: reduceMotion)
        let glow = AriaSigilGeometry.glowOpacity(state: live, breath: breath)
        let veinPulse = AriaSigilGeometry.veinPulse(time: t, state: live, reduceMotion: reduceMotion)
        let sparkTwinkles = (0..<3).map {
            AriaSigilGeometry.sparkTwinkle(time: t, index: $0, reduceMotion: reduceMotion)
        }
        let talkBoost = (!reduceMotion && live == .speaking)
            ? Double(resolvedAmplitude) * 0.008
            : 0
        let scale = CGFloat(AriaSigilGeometry.uniformScale(breath: breath, reduceMotion: reduceMotion) + talkBoost)

        let ember = ForgePalette.ember
        let teal = ForgePalette.teal
        let wash: Color = {
            switch live {
            case .listening: return teal
            case .speaking: return ember
            case .processing: return ForgePalette.steel
            case .idle: return ember
            }
        }()

        return ZStack {
            RadialGradient(
                colors: [
                    wash.opacity(0.28 + glow * 0.2 + core * 0.9),
                    teal.opacity(0.08),
                    .clear
                ],
                center: .center,
                startRadius: size * 0.04,
                endRadius: size * 0.55
            )
            .frame(width: size * 1.12, height: size * 1.12)
            .blur(radius: max(6, size * 0.16))
            .opacity(reduceMotion ? 0.28 : 0.95)
            .scaleEffect(scale)

            PulseSigil(wash: wash, glow: glow, core: core, veinPulse: veinPulse, sparkTwinkles: sparkTwinkles)
                .hueRotation(.degrees(hue))
                .saturation(1 + breath * 0.12)
                .frame(width: size, height: size)
                .scaleEffect(scale)
        }
        .frame(width: size, height: size)
    }
}

/// The struck-and-cooling core: a void disc, seven cracks fed from a single
/// bright center, a corona where the cracks reach the rim, and three embers
/// catching where the light escapes. Drawn, not photographed — colors come
/// from `ForgePalette` like the rest of the app.
private struct PulseSigil: View {
    let wash: Color
    let glow: Double
    let core: Double
    let veinPulse: Double
    let sparkTwinkles: [Double]

    /// Fractional (0...1) coordinates, scaled to the canvas at draw time.
    /// Two of the seven branch off a main vein partway out, so the pattern
    /// reads as a root system rather than a symmetric asterisk.
    private static let veins: [(start: CGPoint, control: CGPoint, end: CGPoint, isBranch: Bool)] = [
        (CGPoint(x: 0.50, y: 0.50), CGPoint(x: 0.40, y: 0.38), CGPoint(x: 0.36, y: 0.20), false),
        (CGPoint(x: 0.42, y: 0.32), CGPoint(x: 0.34, y: 0.28), CGPoint(x: 0.26, y: 0.22), true),
        (CGPoint(x: 0.50, y: 0.50), CGPoint(x: 0.66, y: 0.42), CGPoint(x: 0.82, y: 0.46), false),
        (CGPoint(x: 0.50, y: 0.50), CGPoint(x: 0.60, y: 0.64), CGPoint(x: 0.70, y: 0.82), false),
        (CGPoint(x: 0.62, y: 0.70), CGPoint(x: 0.72, y: 0.74), CGPoint(x: 0.80, y: 0.68), true),
        (CGPoint(x: 0.50, y: 0.50), CGPoint(x: 0.34, y: 0.60), CGPoint(x: 0.24, y: 0.78), false),
        (CGPoint(x: 0.50, y: 0.50), CGPoint(x: 0.30, y: 0.44), CGPoint(x: 0.16, y: 0.42), false),
    ]

    /// Where three of the veins meet the rim — matches indices 2, 1, 4 above.
    private static let sparkPoints: [CGPoint] = [
        CGPoint(x: 0.82, y: 0.46), CGPoint(x: 0.26, y: 0.22), CGPoint(x: 0.80, y: 0.68),
    ]

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let center = CGPoint(x: w * 0.5, y: h * 0.5)
            func point(_ p: CGPoint) -> CGPoint { CGPoint(x: w * p.x, y: h * p.y) }

            context.fill(
                Path(ellipseIn: CGRect(x: center.x - w * 0.38, y: center.y - h * 0.38, width: w * 0.76, height: h * 0.76)),
                with: .radialGradient(
                    Gradient(colors: [ForgePalette.surfaceElevated, ForgePalette.background]),
                    center: center, startRadius: 0, endRadius: w * 0.4
                )
            )

            let coronaPath = Path(ellipseIn: CGRect(x: center.x - w * 0.40, y: center.y - h * 0.40, width: w * 0.80, height: h * 0.80))
            var corona = context
            corona.addFilter(.blur(radius: max(2, w * 0.05)))
            corona.stroke(coronaPath, with: .color(wash.opacity(0.30 + glow * 0.28)), lineWidth: w * 0.08)
            context.stroke(
                coronaPath,
                with: .color(ForgePalette.amber.opacity(0.35)),
                lineWidth: max(0.6, w * 0.01)
            )

            var veinLayer = context
            veinLayer.addFilter(.blur(radius: max(0.5, w * 0.006)))
            let veinAlpha = 0.45 + veinPulse * 0.5
            for vein in Self.veins {
                var path = Path()
                path.move(to: point(vein.start))
                path.addQuadCurve(to: point(vein.end), control: point(vein.control))
                let color = vein.isBranch ? ForgePalette.amber : wash
                veinLayer.stroke(
                    path,
                    with: .color(color.opacity(veinAlpha * (vein.isBranch ? 0.8 : 1))),
                    style: StrokeStyle(lineWidth: max(0.8, w * (vein.isBranch ? 0.012 : 0.017)), lineCap: .round)
                )
            }

            for (index, p) in Self.sparkPoints.enumerated() {
                let twinkle = sparkTwinkles[index]
                let sparkPoint = point(p)
                let r = w * 0.018
                context.fill(
                    Path(ellipseIn: CGRect(x: sparkPoint.x - r, y: sparkPoint.y - r, width: r * 2, height: r * 2)),
                    with: .color(ForgePalette.emberCore.opacity(0.25 + twinkle * 0.7))
                )
            }

            let coreRadius = w * (0.075 + core * 0.9)
            var coreGlow = context
            coreGlow.addFilter(.blur(radius: w * 0.018))
            coreGlow.fill(
                Path(ellipseIn: CGRect(x: center.x - coreRadius, y: center.y - coreRadius, width: coreRadius * 2, height: coreRadius * 2)),
                with: .radialGradient(
                    Gradient(colors: [ForgePalette.emberCore, wash, wash.opacity(0)]),
                    center: center, startRadius: 0, endRadius: coreRadius
                )
            )
        }
    }
}

#Preview("ARIA idle") {
    ZStack {
        Color(hex: "07060A").ignoresSafeArea()
        AuroraOrbView(state: .idle, amplitude: 0.3, size: 168)
    }
    .environment(AriaPresence.shared)
    .preferredColorScheme(.dark)
}

#Preview("ARIA speaking") {
    ZStack {
        Color(hex: "07060A").ignoresSafeArea()
        AuroraOrbView(state: .speaking, amplitude: 0.8, size: 168, followPresence: false)
    }
    .preferredColorScheme(.dark)
}

#Preview("ARIA compact") {
    ZStack {
        Color(hex: "07060A").ignoresSafeArea()
        HStack(spacing: 24) {
            AuroraOrbView(state: .idle, amplitude: 0.2, size: 22, followPresence: false)
            AuroraOrbView(state: .idle, amplitude: 0.2, size: 44, followPresence: false)
            AuroraOrbView(state: .listening, amplitude: 0.5, size: 58, followPresence: false)
        }
    }
    .preferredColorScheme(.dark)
}
