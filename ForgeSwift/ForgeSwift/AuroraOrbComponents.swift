import SwiftUI

/// Compact ARIA mark for avatars, tabs, and cards.
/// The circular logo crop is the identity. Live speech/listen from
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
                    .stroke(Color(hex: AriaSigilPalette.goldHex), lineWidth: max(1.0, size * 0.045))
                    .frame(width: max(7, size * 0.18), height: max(7, size * 0.18))
                    .offset(x: 1, y: 1)
                    .opacity(0.85)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The provided circular core (gold orb + rings), circle-clipped so the
/// glass squircle and floor glow stay outside the mark. SwiftUI only
/// breathes and glows around the photo — it does not redraw the logo.
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
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
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
        let amp = Double(resolvedAmplitude)
        let breathHz: Double = {
            switch live {
            case .idle: return 1.15
            case .listening: return 2.4
            case .processing: return 3.2
            case .speaking: return 1.9
            }
        }()
        let breath = reduceMotion ? 0.45 : (0.5 + 0.5 * sin(t * breathHz))
        let talk = live == .speaking && !reduceMotion ? (0.55 + 0.45 * abs(sin(t * 10.5))) : 0
        let listen = live == .listening && !reduceMotion ? (0.5 + 0.5 * abs(sin(t * 3.4))) : 0
        let energy = max(amp, 0.16 + breath * 0.10) + talk * 0.22 + listen * 0.12
        let spin = reduceMotion ? 0 : t * (live == .speaking ? 38 : live == .listening ? 22 : live == .processing ? 48 : 11)
        let floatY: CGFloat = (!reduceMotion && size >= 90) ? CGFloat(sin(t * 1.05)) * size * 0.022 : 0
        let scale: CGFloat = 1 + CGFloat(breath) * (size >= 90 ? 0.045 : 0.03) + CGFloat(talk) * 0.04

        let gold = Color(hex: AriaSigilPalette.goldHex)
        let teal = Color(hex: "3EC8C8")
        let glow: Color = {
            switch live {
            case .listening: return teal
            case .speaking: return gold
            case .processing: return Color(hex: AriaSigilPalette.photonPrimary(for: mood))
            case .idle: return gold
            }
        }()

        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            glow.opacity(0.28 + energy * 0.22 + talk * 0.18),
                            teal.opacity(0.08 + listen * 0.12),
                            .clear
                        ],
                        center: .center,
                        startRadius: size * 0.10,
                        endRadius: size * 0.72
                    )
                )
                .frame(width: size * 1.48, height: size * 1.48)
                .blur(radius: max(3, size * 0.12))
                .opacity(reduceMotion ? 0.4 : 0.95)

            Image(AriaWelcomeChime.assetName)
                .resizable()
                .scaledToFill()
                .scaleEffect(AriaWelcomeChime.cropScale)
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(
                            glow.opacity(0.18 + breath * 0.22 + talk * 0.20),
                            lineWidth: max(0.8, size * 0.018)
                        )
                )

            if !reduceMotion {
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [
                                glow.opacity(0.0),
                                glow.opacity(0.45 + breath * 0.25),
                                teal.opacity(live == .listening ? 0.55 : 0.12),
                                glow.opacity(0.0)
                            ],
                            center: .center
                        ),
                        lineWidth: max(1.1, size * 0.028)
                    )
                    .frame(
                        width: size * (0.98 + CGFloat(energy) * 0.06),
                        height: size * (0.98 + CGFloat(energy) * 0.06)
                    )
                    .rotationEffect(.degrees(spin))
                    .opacity(live == .idle ? 0.42 : 0.78)
            }
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
