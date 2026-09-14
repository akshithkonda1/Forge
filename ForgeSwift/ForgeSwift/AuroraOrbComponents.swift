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

/// Procedural ARIA logo: kinetic orange + pearl rings around a glowing white
/// liquid orb. Soft spin at idle; speaking amplitude drives a waveform feel.
/// No PNG, no gooey hearth, no Home readiness chrome. Reduce Motion and
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
        return resolvedState == .speaking ? 1.0 / 20.0 : 1.0 / 12.0
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

/// Orange + pearl kinetic rings with a white liquid core. Hero (≥90pt) draws
/// all five. Compact slots draw the Cove 3-ring. Shape strokes — not Canvas +
/// `.plusLighter` (Simulator MSAA).
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
    private var energy: Double { max(0, min(1, Double(amplitude))) }
    private var drive: Double {
        AriaSigilGeometry.waveformDrive(state: state, amplitude: energy)
    }

    var body: some View {
        let core = AriaSigilGeometry.orbCore(
            time: time,
            state: state,
            amplitude: energy,
            reduceMotion: reduceMotion
        )
        ZStack {
            // Atmospheric depth wash — orange into pearl, not flat fill.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            pearlHot.opacity(0.10 + drive * 0.08),
                            orange.opacity(0.14 + energy * 0.06),
                            orange.opacity(0.03),
                            .clear
                        ],
                        center: .center,
                        startRadius: size * 0.02,
                        endRadius: size * 0.5
                    )
                )

            ForEach(AriaSigilGeometry.visibleRingIndices(size: size), id: \.self) { index in
                let pose = AriaSigilGeometry.liquidEllipse(
                    index: index,
                    time: time,
                    state: state,
                    amplitude: energy,
                    reduceMotion: reduceMotion
                )
                let pearlRing = AriaSigilGeometry.ringIsPearl(index)
                let stroke = pearlRing ? pearlHot : (index == 2 ? orangeLight : orange)
                let line = AriaSigilGeometry.strokeWidth(size: size, index: index)

                // Soft under-glow for depth, then the crisp identity stroke.
                Ellipse()
                    .stroke(
                        stroke.opacity(pose.opacity * 0.35),
                        lineWidth: line + max(1.2, size * 0.018)
                    )
                    .frame(width: size * pose.rx, height: size * pose.ry)
                    .rotationEffect(.radians(pose.rotation))
                Ellipse()
                    .stroke(
                        stroke.opacity(min(1, pose.opacity + (pearlRing ? 0.12 : 0))),
                        lineWidth: line
                    )
                    .frame(width: size * pose.rx, height: size * pose.ry)
                    .rotationEffect(.radians(pose.rotation))
            }

            AriaLiquidOrbCore(
                size: size,
                core: core,
                pearl: pearl,
                pearlHot: pearlHot,
                orange: orange,
                drive: drive
            )
        }
        .frame(width: size, height: size)
        .shadow(color: orange.opacity(0.22 + drive * 0.16), radius: max(4, size * 0.07))
        .shadow(color: pearlHot.opacity(0.12 + core.glow * 0.18), radius: max(3, size * 0.05))
        .allowsHitTesting(false)
    }
}

/// Glowing white orb — liquid squash when speaking so the mark feels like a voice.
private struct AriaLiquidOrbCore: View {
    let size: CGFloat
    let core: AriaSigilGeometry.OrbCorePose
    let pearl: Color
    let pearlHot: Color
    let orange: Color
    let drive: Double

    var body: some View {
        let diameter = size * (size < AriaSigilGeometry.heroMinimumSize ? 0.28 : 0.32)
        ZStack {
            // Outer halo
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            pearlHot.opacity(0.38 + core.glow * 0.28),
                            pearl.opacity(0.16 + drive * 0.1),
                            orange.opacity(0.06 + drive * 0.05),
                            .clear
                        ],
                        center: .center,
                        startRadius: diameter * 0.08,
                        endRadius: diameter * 1.15
                    )
                )
                .frame(width: diameter * 2.05, height: diameter * 2.05)

            // Liquid pearl body
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            pearlHot.opacity(0.95),
                            pearl.opacity(0.88),
                            pearl.opacity(0.55),
                            pearl.opacity(0.18)
                        ],
                        center: UnitPoint(x: 0.38, y: 0.32),
                        startRadius: diameter * 0.02,
                        endRadius: diameter * 0.55
                    )
                )
                .frame(width: diameter, height: diameter)
                .scaleEffect(x: core.sx, y: core.sy)

            // Specular highlight — keeps the core reading as liquid glass.
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            pearlHot.opacity(0.75 * core.highlight),
                            pearlHot.opacity(0.15),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: diameter * 0.22
                    )
                )
                .frame(width: diameter * 0.42, height: diameter * 0.28)
                .offset(x: -diameter * 0.12, y: -diameter * 0.14)
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
