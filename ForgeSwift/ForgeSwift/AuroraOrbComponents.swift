import SwiftUI

/// Compact ARIA mark for avatars, tabs, and cards.
/// The fluid ember blob is the identity. Live speech/listen from
/// `AriaPresence` overrides idle so every mark breathes when she talks.
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

/// The gooey iridescent ember — photo only, no ring, no glass frame.
/// SwiftUI breathes the orange core, shifts iridescence, and undulates
/// the lobes. Reduce Motion freezes on the still frame.
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
            // Ambient wash — a glow, never a ring stroke.
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

            Image(AriaWelcomeChime.assetName)
                .interpolation(.high)
                .resizable()
                .scaledToFit()
                .scaleEffect(AriaWelcomeChime.cropScale)
                .scaleEffect(x: 1 + CGFloat(edge.x), y: 1 + CGFloat(edge.y))
                .hueRotation(.degrees(hue))
                .brightness(core * 0.55)
                .saturation(1 + breath * 0.05)
                .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
        .scaleEffect(scale)
        .offset(y: floatY)
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
