import SwiftUI

/// Compact ARIA mark for avatars, tabs, and cards.
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
                    .fill(Color(hex: AriaSigilPalette.forgeOrangeHex).opacity(0.9))
                    .frame(width: max(7, size * 0.18), height: max(7, size * 0.18))
                    .offset(x: 1, y: 1)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Procedural ARIA logo: living soft-hex nest around a smaller smart-metal sun.
/// Idle stays gently liquid; speaking deepens waves and planetary orbits.
/// Reduce Motion / `forgeMinimalAnimation` freeze at `AriaSigilGeometry.stillPose`.
struct AuroraOrbView: View {
    let state: AROrbState
    let amplitude: Float
    var mood: ARIAMood = .focused
    var size: CGFloat = 140
    var followPresence: Bool = false

    private let presence = AriaPresence.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.forgeMinimalAnimation) private var minimalAnimation
    @Environment(\.scenePhase) private var scenePhase

    private var resolvedState: AROrbState {
        followPresence && presence.orbState != .idle ? presence.orbState : state
    }

    private var frozen: Bool {
        reduceMotion || minimalAnimation || scenePhase != .active
    }

    private var tick: Double {
        if frozen { return 1 }
        // Denser samples while talking so the liquid waveform reads.
        return resolvedState == .speaking ? 1.0 / 30.0 : 1.0 / 20.0
    }

    var body: some View {
        // Mood stays on the call-site API. Identity does not recolor from mood.
        let _ = mood
        TimelineView(.animation(minimumInterval: tick, paused: frozen)) { timeline in
            let t = frozen
                ? AriaSigilGeometry.stillPose
                : timeline.date.timeIntervalSinceReferenceDate
            AriaNestFieldView(
                time: t,
                state: resolvedState,
                amplitude: amplitude,
                size: size,
                reduceMotion: frozen
            )
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            resolvedState == .speaking ? "ARIA speaking"
                : resolvedState == .listening ? "ARIA listening"
                : "ARIA"
        )
        .accessibilityAddTraits(resolvedState == .idle ? [] : .updatesFrequently)
        .onAppear {
            presence.playWelcomeChimeIfNeeded(size: size, reduceMotion: reduceMotion)
        }
    }
}

/// Soft-hex liquid nest + smaller metal sun, with warm hearth glow and orbital plane.
private struct AriaNestFieldView: View {
    let time: TimeInterval
    let state: AROrbState
    let amplitude: Float
    let size: CGFloat
    let reduceMotion: Bool

    private var orange: Color { Color(hex: AriaSigilPalette.forgeOrangeHex) }
    private var orangeLight: Color { Color(hex: AriaSigilGeometry.brandHueLightHex) }
    private var pearl: Color { Color(hex: AriaSigilPalette.pearlHex) }
    private var pearlHot: Color { Color(hex: AriaSigilPalette.pearlHotHex) }
    private var frost: Color { Color(hex: AriaSigilPalette.frostHex) }
    private var hearth: Color { Color(hex: AriaSigilPalette.hearthGlowHex) }
    private var energy: Double { max(0, min(1, Double(amplitude))) }
    private var drive: Double {
        AriaSigilGeometry.waveformDrive(state: state, amplitude: energy)
    }

    /// Reference hue rhythm: pearl → frost → forge orange.
    private func ringStroke(index: Int) -> Color {
        switch index {
        case 0: return pearlHot
        case 1: return frost
        default: return orange
        }
    }

    var body: some View {
        let core = AriaSigilGeometry.orbCore(
            time: time,
            state: state,
            amplitude: energy,
            reduceMotion: reduceMotion
        )
        ZStack {
            // Warm hearth bloom — mahogany wash behind the nest.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            hearth.opacity(0.55 + drive * 0.18),
                            hearth.opacity(0.28 + energy * 0.10),
                            orange.opacity(0.10 + drive * 0.06),
                            .clear
                        ],
                        center: .center,
                        startRadius: size * 0.02,
                        endRadius: size * 0.52
                    )
                )
                .blur(radius: size * 0.04)
                .scaleEffect(1.0 + 0.03 * sin(time * 0.7))

            // Cool pearl core bloom into warm forge wash.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            pearlHot.opacity(0.16 + drive * 0.10),
                            frost.opacity(0.08 + energy * 0.05),
                            orange.opacity(0.10 + energy * 0.05),
                            .clear
                        ],
                        center: .center,
                        startRadius: size * 0.02,
                        endRadius: size * 0.42
                    )
                )

            // Faint orbital plane — thin tilted ellipse from the reference.
            Ellipse()
                .stroke(
                    frost.opacity(0.14 + drive * 0.10),
                    lineWidth: max(0.55, size * 0.0035)
                )
                .frame(width: size * 0.92, height: size * 0.18)
                .rotationEffect(.degrees(16 + (reduceMotion ? 0 : sin(time * 0.22) * 3)))
                .blur(radius: 0.35)

            ForEach(AriaSigilGeometry.visibleRingIndices(size: size), id: \.self) { index in
                let pose = AriaSigilGeometry.liquidEllipse(
                    index: index,
                    time: time,
                    state: state,
                    amplitude: energy,
                    reduceMotion: reduceMotion
                )
                let stroke = ringStroke(index: index)
                let line = AriaSigilGeometry.strokeWidth(size: size, index: index)

                // Soft outer bloom.
                AriaLiquidNestRing(
                    roundness: AriaSigilGeometry.cornerRoundness,
                    wavePhase: pose.wavePhase,
                    waveAmp: pose.waveAmp
                )
                .stroke(stroke.opacity(pose.opacity * 0.30), lineWidth: max(1.7, line * 2.2))
                .blur(radius: max(0.7, size * 0.009))
                .frame(width: size * pose.rx, height: size * pose.ry)
                .rotationEffect(.radians(pose.rotation))

                // Crisp living wire.
                AriaLiquidNestRing(
                    roundness: AriaSigilGeometry.cornerRoundness,
                    wavePhase: pose.wavePhase,
                    waveAmp: pose.waveAmp
                )
                .stroke(stroke.opacity(min(1, pose.opacity + 0.08)), lineWidth: line)
                .frame(width: size * pose.rx, height: size * pose.ry)
                .rotationEffect(.radians(pose.rotation))
            }

            AriaSmartMetalOrb(
                size: size,
                core: core,
                pearl: pearl,
                pearlHot: pearlHot,
                orange: orange,
                drive: drive
            )
        }
        .frame(width: size, height: size)
        .shadow(color: frost.opacity(0.10 + drive * 0.08), radius: max(3, size * 0.04))
        .shadow(color: orange.opacity(0.18 + drive * 0.14), radius: max(4, size * 0.07))
        .shadow(color: pearlHot.opacity(0.16 + core.glow * 0.20), radius: max(5, size * 0.05))
        .allowsHitTesting(false)
    }
}

/// Soft-hex nest ring with liquid radial undulation (animatable via TimelineView).
private struct AriaLiquidNestRing: Shape {
    /// Corner softness as a fraction of circumradius (0…~0.4).
    var roundness: Double = 0.34
    var wavePhase: Double = 0
    var waveAmp: Double = 0.03

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let baseRadius = min(rect.width, rect.height) / 2
        guard baseRadius > 0.5 else { return Path() }

        // Sample a rounded hex, then add multi-harmonic radial liquid waves.
        let samples = 72
        var points: [CGPoint] = []
        points.reserveCapacity(samples)
        let soft = max(0.12, min(0.42, roundness))

        for i in 0..<samples {
            let t = Double(i) / Double(samples)
            let angle = t * .pi * 2
            // Soft-hex silhouette: mix circle with 6-fold bias.
            let hexBias = 1.0 + (1.0 - soft) * 0.10 * cos(6 * angle)
            // Living liquid: primary 6-lobe wave + slower traveling harmonics.
            let liquid =
                1.0
                + waveAmp * (
                    0.55 * sin(6 * angle + wavePhase)
                    + 0.28 * sin(3 * angle - wavePhase * 1.35)
                    + 0.17 * sin(9 * angle + wavePhase * 0.72)
                )
            let r = baseRadius * hexBias * liquid
            points.append(
                CGPoint(
                    x: center.x + CGFloat(r * cos(angle)),
                    y: center.y + CGFloat(r * sin(angle))
                )
            )
        }

        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}

/// White smart-metal sun — smaller pearl core with mercury sheen and voice ripples.
private struct AriaSmartMetalOrb: View {
    let size: CGFloat
    let core: AriaSigilGeometry.OrbCorePose
    let pearl: Color
    let pearlHot: Color
    let orange: Color
    let drive: Double

    private var metalCool: Color { Color(hex: "E8EEF4") }
    private var metalMid: Color { Color(hex: "C9D2DC") }

    var body: some View {
        let diameter = size * core.diameter
        let sheen = core.sheenAngle
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            pearlHot.opacity(0.48 + core.glow * 0.30),
                            metalCool.opacity(0.16 + drive * 0.10),
                            orange.opacity(0.05 + drive * 0.04),
                            .clear
                        ],
                        center: .center,
                        startRadius: diameter * 0.05,
                        endRadius: diameter * 1.35
                    )
                )
                .frame(width: diameter * 2.2, height: diameter * 2.2)

            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            pearlHot.opacity(0.99),
                            metalCool.opacity(0.94),
                            pearl.opacity(0.80),
                            metalMid.opacity(0.40),
                            pearl.opacity(0.10)
                        ],
                        center: UnitPoint(x: 0.34 + core.metalWarp * 0.04, y: 0.28),
                        startRadius: diameter * 0.012,
                        endRadius: diameter * 0.58
                    )
                )
                .frame(width: diameter, height: diameter)
                .scaleEffect(x: core.sx, y: core.sy)

            // Specular band.
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [
                            .clear,
                            pearlHot.opacity(0.58 * core.highlight * (0.45 + 0.55 * drive)),
                            pearlHot.opacity(0.16),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: diameter * 0.72, height: diameter * 0.30)
                .rotationEffect(.radians(sheen * 0.32))
                .offset(y: -diameter * 0.07 + CGFloat(core.metalWarp) * diameter * 0.04)
                .scaleEffect(x: core.sx, y: core.sy)
                .blendMode(.screen)

            // Voice / breath ripples on the metal surface.
            ForEach(0..<3, id: \.self) { ring in
                let phase = Double(ring) * 0.33
                let pulse = 0.55 + 0.45 * sin(sheen + phase * .pi * 2)
                let scale = 0.40 + Double(ring) * 0.17 + core.ripple * 0.15 * pulse
                Ellipse()
                    .stroke(
                        pearlHot.opacity((0.08 + drive * 0.26) * pulse * (1.0 - Double(ring) * 0.18)),
                        lineWidth: max(0.6, diameter * 0.012)
                    )
                    .frame(
                        width: diameter * scale * (1.0 + abs(core.metalWarp) * 0.08),
                        height: diameter * scale * (1.0 - abs(core.metalWarp) * 0.06)
                    )
                    .scaleEffect(x: core.sx, y: core.sy)
            }

            // Hot specular highlight (upper-left).
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            pearlHot.opacity(0.95 * core.highlight),
                            pearlHot.opacity(0.18),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: diameter * 0.18
                    )
                )
                .frame(width: diameter * 0.34, height: diameter * 0.20)
                .offset(
                    x: -diameter * 0.13 + CGFloat(sin(sheen)) * diameter * 0.025 * drive,
                    y: -diameter * 0.15
                )
                .scaleEffect(x: core.sx, y: core.sy)
        }
    }
}

// MARK: - Retired gooey hearth (unused — do not ship as the brand mark)

/// Legacy 4-lobe additive ember. Kept so a future cleanup can delete it in one
/// place. Not referenced by `AuroraOrbView` / `ARIAIdentityMark`.
enum AriaSigilEmberLegacy: Sendable {
    static let lobeCount: Int = 4
    static let hearthHex = "FF6A1A"
}

#Preview("ARIA idle") {
    ZStack {
        Color(hex: "000000").ignoresSafeArea()
        AuroraOrbView(state: .idle, amplitude: 0.28, size: 220)
    }
    .environment(AriaPresence.shared)
    .preferredColorScheme(.dark)
}

#Preview("ARIA speaking") {
    ZStack {
        Color(hex: "000000").ignoresSafeArea()
        AuroraOrbView(state: .speaking, amplitude: 0.85, size: 220, followPresence: false)
    }
    .preferredColorScheme(.dark)
}

#Preview("ARIA compact") {
    ZStack {
        Color(hex: "000000").ignoresSafeArea()
        HStack(spacing: 24) {
            AuroraOrbView(state: .idle, amplitude: 0.2, size: 22, followPresence: false)
            AuroraOrbView(state: .idle, amplitude: 0.2, size: 44, followPresence: false)
            AuroraOrbView(state: .listening, amplitude: 0.5, size: 58, followPresence: false)
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("ARIA still-pose") {
    ZStack {
        Color(hex: "000000").ignoresSafeArea()
        AuroraOrbView(state: .idle, amplitude: 0.3, size: 220, followPresence: false)
            .environment(\.forgeMinimalAnimation, true)
    }
    .preferredColorScheme(.dark)
}
