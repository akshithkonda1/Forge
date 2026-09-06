import SwiftUI

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
                    .fill(Color(hex: AriaSigilPalette.emberHex).opacity(0.9))
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
/// runs light out along the veins a beat behind it, shifts iridescence, and
/// undulates the whole mark. Reduce Motion freezes on the still frame.
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

    /// Tiny marks still animate; they just tick less often.
    private var tick: Double {
        if reduceMotion { return 1 }
        if size < 36 { return 1.0 / 16.0 }
        if size < 80 { return 1.0 / 20.0 }
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
        let edge = AriaSigilGeometry.edgeUndulation(time: t, reduceMotion: reduceMotion)
        let glow = AriaSigilGeometry.glowOpacity(state: live, breath: breath)
        let veinPulse = AriaSigilGeometry.veinPulse(time: t, state: live, reduceMotion: reduceMotion)
        let sparkTwinkles = (0..<3).map {
            AriaSigilGeometry.sparkTwinkle(time: t, index: $0, reduceMotion: reduceMotion)
        }
        let amp = Double(resolvedAmplitude)
        let energy = max(amp, 0.16) * 0.08
        let scale: CGFloat = 1
            + CGFloat(breath) * CGFloat(AriaSigilGeometry.breathScale)
            + CGFloat(core) * 0.45
            + CGFloat(energy) * 0.04
        let floatY: CGFloat = (!reduceMotion && size >= 90)
            ? CGFloat(sin(t * 0.7)) * size * 0.012
            : 0

        let ember = Color(hex: AriaSigilPalette.emberHex)
        let teal = Color(hex: AriaSigilPalette.tealHex)
        let wash: Color = {
            switch live {
            case .listening: return teal
            case .speaking: return ember
            case .processing: return Color(hex: AriaSigilPalette.photonPrimary(for: mood))
            case .idle: return ember
            }
        }()

        return ZStack {
            // Ambient bleed — reaches past the mark's own frame into the UI around it.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            wash.opacity(0.20 + glow * 0.16 + core * 1.8),
                            teal.opacity(0.05),
                            .clear
                        ],
                        center: .center,
                        startRadius: size * 0.06,
                        endRadius: size * 0.58
                    )
                )
                .frame(width: size * 1.22, height: size * 1.22)
                .blur(radius: max(4, size * 0.13))
                .opacity(reduceMotion ? 0.32 : 0.88)

            PulseSigil(wash: wash, glow: glow, core: core, veinPulse: veinPulse, sparkTwinkles: sparkTwinkles)
                .scaleEffect(x: 1 + CGFloat(edge.x), y: 1 + CGFloat(edge.y))
                .hueRotation(.degrees(hue))
                .saturation(1 + breath * 0.05)
                .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
        .scaleEffect(scale)
        .offset(y: floatY)
    }
}

/// The struck-and-cooling core: a void disc, seven cracks fed from a single
/// bright center, a corona where the cracks reach the rim, and three embers
/// catching where the light escapes. Drawn, not photographed — the metals-
/// and-void palette lives natively instead of tinting a raster asset.
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
                    Gradient(colors: [Color(hex: "22262E"), Color(hex: "0A0B0E")]),
                    center: center, startRadius: 0, endRadius: w * 0.4
                )
            )

            let coronaPath = Path(ellipseIn: CGRect(x: center.x - w * 0.40, y: center.y - h * 0.40, width: w * 0.80, height: h * 0.80))
            var corona = context
            corona.addFilter(.blur(radius: max(2, w * 0.05)))
            corona.stroke(coronaPath, with: .color(wash.opacity(0.30 + glow * 0.35)), lineWidth: w * 0.08)
            context.stroke(
                coronaPath,
                with: .color(Color(hex: AriaSigilPalette.goldHex).opacity(0.35)),
                lineWidth: max(0.6, w * 0.01)
            )

            var veinLayer = context
            veinLayer.addFilter(.blur(radius: max(0.5, w * 0.006)))
            let veinAlpha = 0.45 + veinPulse * 0.5
            for vein in Self.veins {
                var path = Path()
                path.move(to: point(vein.start))
                path.addQuadCurve(to: point(vein.end), control: point(vein.control))
                let color = vein.isBranch ? Color(hex: AriaSigilPalette.goldHotHex) : wash
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
                    with: .color(Color(hex: AriaSigilPalette.ivoryHex).opacity(0.25 + twinkle * 0.7))
                )
            }

            let coreRadius = w * (0.075 + core * 0.9)
            var coreGlow = context
            coreGlow.addFilter(.blur(radius: w * 0.018))
            coreGlow.fill(
                Path(ellipseIn: CGRect(x: center.x - coreRadius, y: center.y - coreRadius, width: coreRadius * 2, height: coreRadius * 2)),
                with: .radialGradient(
                    Gradient(colors: [.white.opacity(0.9), wash, wash.opacity(0)]),
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
