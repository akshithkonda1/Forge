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

/// Procedural ARIA logo: three rounded hexagons orbiting a smart-metal sun.
/// Tight nest, per-ring planetary rates, futuristic dual-stroke glow.
/// No PNG, no gooey hearth, no readiness chrome. Reduce Motion and
/// `forgeMinimalAnimation` freeze at `AriaSigilGeometry.stillPose`.
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
        // Slightly denser samples while talking so the liquid waveform reads.
        return resolvedState == .speaking ? 1.0 / 24.0 : 1.0 / 12.0
    }

    var body: some View {
        // Mood stays on the call-site API. Identity does not recolor from mood.
        let _ = mood
        TimelineView(.animation(
            minimumInterval: tick,
            paused: frozen
        )) { timeline in
            let t = frozen ? AriaSigilGeometry.stillPose : timeline.date.timeIntervalSinceReferenceDate
            AriaRingFieldView(
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
        .accessibilityAddTraits(resolvedState == .idle ? AccessibilityTraits() : .updatesFrequently)
        .onAppear {
            presence.playWelcomeChimeIfNeeded(size: size, reduceMotion: reduceMotion)
        }
    }
}

/// Three rounded hexagons in a tight planetary nest around the orb.
/// Dual-stroke glow; frost / orange / pearl accents. Shape strokes —
/// not Canvas + `.plusLighter`.
private struct AriaRingFieldView: View {
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
    private var steel: Color { Color(hex: AriaSigilPalette.steelHex) }
    private var energy: Double { max(0, min(1, Double(amplitude))) }
    private var drive: Double {
        AriaSigilGeometry.waveformDrive(state: state, amplitude: energy)
    }

    /// Futuristic hue rhythm: pearl → frost → forge orange.
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
            // Orbital halo — cool core bloom into warm forge wash.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            pearlHot.opacity(0.14 + drive * 0.10),
                            frost.opacity(0.08 + energy * 0.05),
                            orange.opacity(0.12 + energy * 0.06),
                            orange.opacity(0.02),
                            .clear
                        ],
                        center: .center,
                        startRadius: size * 0.03,
                        endRadius: size * 0.46
                    )
                )

            // Faint orbital plane disc behind the nest.
            Ellipse()
                .stroke(
                    steel.opacity(0.10 + drive * 0.08),
                    lineWidth: max(0.6, size * 0.004)
                )
                .frame(width: size * 0.72, height: size * 0.22)
                .rotationEffect(.degrees(12))
                .blur(radius: 0.4)

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
                AriaRoundedHexagon(roundness: AriaSigilGeometry.cornerRoundness)
                    .stroke(
                        stroke.opacity(pose.opacity * 0.28),
                        lineWidth: max(1.6, line * 2.1)
                    )
                    .blur(radius: max(0.6, size * 0.008))
                    .frame(width: size * pose.rx, height: size * pose.ry)
                    .rotationEffect(.radians(pose.rotation))
                // Crisp futuristic wire.
                AriaRoundedHexagon(roundness: AriaSigilGeometry.cornerRoundness)
                    .stroke(
                        stroke.opacity(min(1, pose.opacity + 0.08)),
                        lineWidth: line
                    )
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
        .shadow(color: frost.opacity(0.12 + drive * 0.10), radius: max(3, size * 0.045))
        .shadow(color: orange.opacity(0.20 + drive * 0.14), radius: max(4, size * 0.07))
        .shadow(color: pearlHot.opacity(0.18 + core.glow * 0.22), radius: max(5, size * 0.055))
        .allowsHitTesting(false)
    }
}


/// Flat-top hexagon with rounded corners — reads as soft hex / rounded ellipse.
private struct AriaRoundedHexagon: Shape {
    /// Corner softness as a fraction of circumradius (0…~0.4).
    var roundness: Double = 0.28

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        guard radius > 0.5 else { return Path() }

        let verts: [CGPoint] = (0..<6).map { i in
            let angle = CGFloat(i) * (.pi / 3) // flat-top
            return CGPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )
        }

        let corner = min(radius * CGFloat(max(0, min(0.42, roundness))), radius * 0.42)
        var path = Path()
        for i in 0..<6 {
            let prev = verts[(i + 5) % 6]
            let curr = verts[i]
            let next = verts[(i + 1) % 6]
            let toPrev = CGPoint(x: prev.x - curr.x, y: prev.y - curr.y)
            let toNext = CGPoint(x: next.x - curr.x, y: next.y - curr.y)
            let lenPrev = hypot(toPrev.x, toPrev.y)
            let lenNext = hypot(toNext.x, toNext.y)
            guard lenPrev > 0.001, lenNext > 0.001 else { continue }
            let dPrev = min(corner, lenPrev * 0.45)
            let dNext = min(corner, lenNext * 0.45)
            let p1 = CGPoint(
                x: curr.x + toPrev.x / lenPrev * dPrev,
                y: curr.y + toPrev.y / lenPrev * dPrev
            )
            let p2 = CGPoint(
                x: curr.x + toNext.x / lenNext * dNext,
                y: curr.y + toNext.y / lenNext * dNext
            )
            if i == 0 {
                path.move(to: p1)
            } else {
                path.addLine(to: p1)
            }
            path.addQuadCurve(to: p2, control: curr)
        }
        path.closeSubpath()
        return path
    }
}

/// White smart-metal orb — mercury sheen + vibrating waveform ripples when talking.
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
        let diameter = size * (size < AriaSigilGeometry.heroMinimumSize ? 0.26 : 0.29)
        let sheen = core.sheenAngle
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            pearlHot.opacity(0.42 + core.glow * 0.32),
                            metalCool.opacity(0.18 + drive * 0.12),
                            orange.opacity(0.05 + drive * 0.04),
                            .clear
                        ],
                        center: .center,
                        startRadius: diameter * 0.06,
                        endRadius: diameter * 1.2
                    )
                )
                .frame(width: diameter * 2.1, height: diameter * 2.1)

            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            pearlHot.opacity(0.98),
                            metalCool.opacity(0.92),
                            pearl.opacity(0.78),
                            metalMid.opacity(0.42),
                            pearl.opacity(0.12)
                        ],
                        center: UnitPoint(x: 0.34 + core.metalWarp * 0.04, y: 0.30),
                        startRadius: diameter * 0.015,
                        endRadius: diameter * 0.58
                    )
                )
                .frame(width: diameter, height: diameter)
                .scaleEffect(x: core.sx, y: core.sy)

            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [
                            .clear,
                            pearlHot.opacity(0.55 * core.highlight * (0.45 + 0.55 * drive)),
                            pearlHot.opacity(0.18),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: diameter * 0.78, height: diameter * 0.34)
                .rotationEffect(.radians(sheen * 0.35))
                .offset(y: -diameter * 0.06 + CGFloat(core.metalWarp) * diameter * 0.04)
                .scaleEffect(x: core.sx, y: core.sy)
                .blendMode(.screen)

            ForEach(0..<3, id: \.self) { ring in
                let phase = Double(ring) * 0.33
                let pulse = 0.55 + 0.45 * sin(sheen + phase * .pi * 2)
                let scale = 0.42 + Double(ring) * 0.18 + core.ripple * 0.16 * pulse
                Ellipse()
                    .stroke(
                        pearlHot.opacity((0.10 + drive * 0.28) * pulse * (1.0 - Double(ring) * 0.18)),
                        lineWidth: max(0.7, diameter * 0.012)
                    )
                    .frame(
                        width: diameter * scale * (1.0 + abs(core.metalWarp) * 0.08),
                        height: diameter * scale * (1.0 - abs(core.metalWarp) * 0.06)
                    )
                    .scaleEffect(x: core.sx, y: core.sy)
            }

            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            pearlHot.opacity(0.9 * core.highlight),
                            pearlHot.opacity(0.2),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: diameter * 0.2
                    )
                )
                .frame(width: diameter * 0.36, height: diameter * 0.22)
                .offset(
                    x: -diameter * 0.14 + CGFloat(sin(sheen)) * diameter * 0.03 * drive,
                    y: -diameter * 0.16
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

#Preview("ARIA still-pose") {
    ZStack {
        Color(hex: "07060A").ignoresSafeArea()
        AuroraOrbView(state: .idle, amplitude: 0.3, size: 168, followPresence: false)
            .environment(\.forgeMinimalAnimation, true)
    }
    .preferredColorScheme(.dark)
}
