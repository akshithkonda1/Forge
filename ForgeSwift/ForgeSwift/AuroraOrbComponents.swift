import SwiftUI
import ForgeCore

/// Compact ARIA mark for avatars, tabs, and cards.
/// The 4-lobe ember (`AriaLogo`) is the identity. Live speech/listen from
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
                    .fill(ForgePalette.ember.opacity(0.9))
                    .frame(width: max(7, size * 0.18), height: max(7, size * 0.18))
                    .offset(x: 1, y: 1)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Living 4-lobe ember. The `AriaLogo` PNG is aspect-fit and never stretched.
/// Motion is uniform scale + hue shimmer + a procedural core pulse.
/// Reduce Motion freezes on the still frame.
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

            Image(AriaWelcomeChime.assetName)
                .interpolation(.high)
                .resizable()
                .scaledToFit()
                .hueRotation(.degrees(hue))
                .brightness(reduceMotion ? 0 : core * 0.85)
                .saturation(1 + breath * 0.12)
                .frame(width: size, height: size)
                .scaleEffect(scale)

            // Procedural ember — reads as alive even when the PNG is still.
            RadialGradient(
                colors: [
                    ForgePalette.emberCore.opacity(0.55 + core * 2.2),
                    ember.opacity(0.28 + core * 1.4),
                    .clear
                ],
                center: .center,
                startRadius: 0,
                endRadius: size * 0.22
            )
            .frame(width: size * 0.46, height: size * 0.46)
            .blendMode(.screen)
            .opacity(reduceMotion ? 0.15 : 0.85)
            .scaleEffect(0.82 + CGFloat(core) * 2.4)
        }
        .frame(width: size, height: size)
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
