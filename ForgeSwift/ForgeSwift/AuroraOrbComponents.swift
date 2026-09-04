import SwiftUI

/// Compact Aurora orb for avatars, tabs, and cards.
/// Live speech/listen from `AriaPresence` overrides the idle state so every
/// mark moves when ARIA talks. No clip — the halo is part of the identity.
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
                    .fill(Color(hex: "22C55E"))
                    .frame(width: max(7, size * 0.2), height: max(7, size * 0.2))
                    .overlay(Circle().stroke(Color(hex: "080808"), lineWidth: 2))
                    .offset(x: 2, y: 2)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct AuroraOrbView: View {
    let state: AROrbState
    let amplitude: Float
    var mood: ARIAMood = .focused
    var size: CGFloat = 140
    /// When ARIA is speaking or listening, the orb follows `AriaPresence`
    /// instead of the caller’s idle state.
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

    /// Tiny marks still animate; they just draw fewer field samples.
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
        .accessibilityAddTraits(resolvedState == .idle ? [] : .updatesFrequently)
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
        let spin = reduceMotion ? 0 : t * (live == .speaking ? 38 : live == .listening ? 22 : 11)
        let floatY: CGFloat = (!reduceMotion && size >= 90) ? CGFloat(sin(t * 1.05)) * size * 0.022 : 0
        let scale: CGFloat = 1 + CGFloat(breath) * (size >= 90 ? 0.045 : 0.03) + CGFloat(talk) * 0.04

        return ZStack {
            // Soft halo — reads on a 22pt mark and a 148pt welcome orb.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            mood.accentColor.opacity(0.22 + energy * 0.28),
                            secondaryColor.opacity(0.10 + listen * 0.12),
                            .clear
                        ],
                        center: .center,
                        startRadius: size * 0.12,
                        endRadius: size * 0.72
                    )
                )
                .frame(width: size * 1.55, height: size * 1.55)
                .blur(radius: max(4, size * 0.14))
                .scaleEffect(1 + CGFloat(talk) * 0.08 + CGFloat(listen) * 0.05)
                .opacity(reduceMotion ? 0.55 : 0.9)

            AuroraLivingField(
                accent: mood.accentColor,
                secondary: secondaryColor,
                amplitude: energy,
                state: live,
                size: size,
                time: t,
                compact: size < 48
            )

            coreOrb
            coreSpark(energy: energy, breath: breath, talk: talk)
            veil
            pulsingRing(energy: energy, breath: breath, spin: spin, live: live)

            if (live == .speaking || live == .listening) && !reduceMotion {
                ForEach(0..<2, id: \.self) { i in
                    Circle()
                        .stroke(
                            (live == .speaking ? mood.accentColor : Color(hex: "00D2FF"))
                                .opacity(0.34 - Double(i) * 0.10),
                            lineWidth: max(0.8, size * 0.018)
                        )
                        .frame(
                            width: size * (1.08 + CGFloat(i) * 0.14),
                            height: size * (1.08 + CGFloat(i) * 0.14)
                        )
                        .scaleEffect(1 + CGFloat(live == .speaking ? talk : listen) * (0.07 + CGFloat(i) * 0.05))
                        .opacity(0.75 - (live == .speaking ? talk : listen) * 0.25)
                }
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(scale)
        .offset(y: floatY)
    }

    private var ringColor: Color {
        switch mood {
        case .energized, .pushed: return .ember
        case .focused: return .steel
        case .calm: return Color(hex: "A855F7")
        }
    }

    private var secondaryColor: Color {
        switch mood {
        case .energized: return Color(hex: "FFC14A")
        case .pushed: return Color(hex: "FF2D55")
        case .focused: return Color(hex: "6B8CFF")
        case .calm: return Color(hex: "7B61FF")
        }
    }

    private var coreOrb: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color(hex: "030306"),
                        Color(hex: "0A0610").opacity(0.95),
                        mood.accentColor.opacity(0.28),
                        secondaryColor.opacity(0.10),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: size / 2
                )
            )
            .frame(width: size, height: size)
    }

    private func coreSpark(energy: Double, breath: Double, talk: Double) -> some View {
        let spark = size * (0.07 + CGFloat(energy) * 0.055 + CGFloat(talk) * 0.04)
        return ZStack {
            Circle()
                .fill(mood.accentColor.opacity(0.42 + breath * 0.32 + talk * 0.28))
                .frame(width: spark * 2.6, height: spark * 2.6)
                .blur(radius: spark * 0.85)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.82),
                            mood.accentColor.opacity(0.95),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: spark
                    )
                )
                .frame(width: spark, height: spark)
        }
        .offset(y: size * -0.04)
        .blendMode(.screen)
        .opacity(0.58 + breath * 0.42)
    }

    private var veil: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        .clear,
                        Color(hex: "050508").opacity(0.12),
                        Color(hex: "050508").opacity(0.68)
                    ],
                    center: .center,
                    startRadius: size * 0.16,
                    endRadius: size * 0.52
                )
            )
            .frame(width: size, height: size)
            .allowsHitTesting(false)
    }

    private func pulsingRing(energy: Double, breath: Double, spin: Double, live: AROrbState) -> some View {
        let ringSize = size * (0.94 + CGFloat(energy) * 0.16)
        return Circle()
            .stroke(
                AngularGradient(
                    colors: [
                        ringColor.opacity(0.58 + breath * 0.28),
                        secondaryColor.opacity(0.16),
                        .clear,
                        ringColor.opacity(0.22),
                        secondaryColor.opacity(0.42),
                        ringColor.opacity(0.58 + breath * 0.28)
                    ],
                    center: .center
                ),
                lineWidth: live == .idle ? max(1.0, size * 0.022) : max(1.4, size * 0.03)
            )
            .frame(width: ringSize, height: ringSize)
            .rotationEffect(.degrees(spin))
            .opacity(live == .idle ? 0.55 : 0.92)
    }
}

/// Phase-locked nebula, liquid waves, drifting embers. One clock from the parent
/// TimelineView so every size of ARIA feels like the same organism.
private struct AuroraLivingField: View {
    let accent: Color
    let secondary: Color
    let amplitude: Double
    let state: AROrbState
    let size: CGFloat
    let time: Double
    let compact: Bool

    var body: some View {
        Canvas { context, canvasSize in
            drawNebula(context: context, size: canvasSize, time: time)
            if !compact {
                drawWaves(context: context, size: canvasSize, time: time)
            }
            drawEmbers(context: context, size: canvasSize, time: time)
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }

    private func drawNebula(context: GraphicsContext, size: CGSize, time: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let blobs: [(dx: Double, dy: Double, speed: Double, scale: Double, color: Color)] = [
            (0.14, -0.10, 0.22, 0.58, accent),
            (-0.16, 0.12, 0.16, 0.50, secondary),
            (0.04, 0.18, 0.26, 0.44, accent)
        ]
        for blob in blobs {
            let x = center.x + CGFloat(sin(time * blob.speed) * blob.dx) * size.width
            let y = center.y + CGFloat(cos(time * blob.speed * 0.7) * blob.dy) * size.height
            let r = size.width * blob.scale * (0.82 + amplitude * 0.28)
            let rect = CGRect(x: x - r / 2, y: y - r / 2, width: r, height: r * 0.78)
            context.fill(
                Path(ellipseIn: rect),
                with: .color(blob.color.opacity(0.10 + amplitude * 0.10))
            )
        }
    }

    private func drawWaves(context: GraphicsContext, size: CGSize, time: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) / 2
        let configs: [(phase: Double, speed: Double, opacity: Double, harmonic: Double)] = [
            (0.0, 0.42, 0.24, 2.0),
            (1.7, 0.30, 0.17, 3.0),
            (3.4, 0.52, 0.13, 2.5)
        ]
        let steps = size.width < 90 ? 18 : 28
        for (index, config) in configs.enumerated() {
            let waveAmp = radius * 0.11 * (1.0 + amplitude * 1.35)
            var path = Path()
            for step in 0...steps {
                let angle = Double(step) / Double(steps) * .pi * 2
                let wobble = sin(angle * config.harmonic + time * config.speed + config.phase) * waveAmp
                    + sin(angle * (config.harmonic + 1.5) + time * config.speed * 0.55) * waveAmp * 0.35
                let r = radius * 0.76 + wobble
                let point = CGPoint(
                    x: center.x + CGFloat(cos(angle) * r),
                    y: center.y + CGFloat(sin(angle) * r)
                )
                if step == 0 { path.move(to: point) }
                else { path.addLine(to: point) }
            }
            path.closeSubpath()
            let color = (index == 1 ? secondary : accent).opacity(config.opacity)
            context.fill(path, with: .color(color.opacity(0.32)))
            context.stroke(path, with: .color(color), lineWidth: size.width < 90 ? 0.8 : 1.1)
        }
    }

    private func drawEmbers(context: GraphicsContext, size: CGSize, time: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let count = compact ? 3 : (state == .idle ? 5 : 8)
        for i in 0..<count {
            let a = 0.24 + Double(i) * 0.08
            let b = 0.33 + Double(i) * 0.05
            let phase = Double(i) * 1.15
            let rx = Double(size.width) * (0.16 + Double(i % 3) * 0.055) * (1.0 + amplitude * 0.3)
            let ry = Double(size.height) * (0.13 + Double(i % 2) * 0.06) * (1.0 + amplitude * 0.3)
            let x = center.x + CGFloat(sin(time * a + phase) * rx)
            let y = center.y + CGFloat(sin(time * b + phase * 0.7) * ry)
            let fade = 0.32 + 0.52 * (0.5 + 0.5 * sin(time * 0.75 + phase))
            let r = CGFloat(max(0.8, size.width * 0.012) + Double(i % 3) * 0.55)
            let color = i % 2 == 0 ? accent : secondary
            let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
            context.fill(Path(ellipseIn: rect), with: .color(color.opacity(fade)))
        }
    }
}

#Preview("ARIA idle") {
    AuroraOrbView(state: .idle, amplitude: 0.3, size: 148)
        .environment(AriaPresence.shared)
        .preferredColorScheme(.dark)
}

#Preview("ARIA speaking") {
    AuroraOrbView(state: .speaking, amplitude: 0.8, size: 148, followPresence: false)
        .preferredColorScheme(.dark)
}
