import SwiftUI

enum AROrbState: Equatable {
    case idle, listening, processing, speaking
}

/// Compact circular crop of `AuroraOrbView` for avatars, tabs, and cards.
/// The full orb draws a 1.8× halo; this clips to `size` so it sits in chrome.
struct ARIAIdentityMark: View {
    var state: AROrbState = .idle
    var mood: ARIAMood = .focused
    var size: CGFloat = 40
    var amplitude: Float = 0.22
    var showsPresence: Bool = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AuroraOrbView(state: state, amplitude: amplitude, mood: mood, size: size)
                .frame(width: size, height: size)
                .clipShape(Circle())
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmerPhase: Double = 0
    @State private var rotation: Double = 0
    @State private var glassRotation: Double = 0

    private var effectiveAmplitude: Double {
        let amp = Double(amplitude)
        switch state {
        case .idle: return 0.12
        case .listening: return max(0.38, amp)
        case .processing: return 0.6
        case .speaking: return max(0.68, amp)
        }
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
        case .energized: return Color(hex: "00D2FF")
        case .pushed: return Color(hex: "FF2D55")
        case .focused: return Color(hex: "00D2FF")
        case .calm: return Color(hex: "7B61FF")
        }
    }

    var body: some View {
        if reduceMotion || size < 64 {
            ZStack {
                coreOrb
                innerGlow
                pulsingRing
            }
            .frame(width: size, height: size)
        } else {
            ZStack {
                AuroraWaveCanvas(
                    accent: mood.accentColor,
                    secondary: secondaryColor,
                    amplitude: effectiveAmplitude
                )

                coreOrb
                glassRefraction
                innerGlow
                pulsingRing
                shimmerArc
                particles
            }
            .frame(width: size, height: size)
            .rotationEffect(.degrees(state == .processing ? rotation : 0))
            .onAppear(perform: startAnimations)
        }
    }

    private var coreOrb: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hex: "0A0A0F"),
                            mood.accentColor.opacity(0.35),
                            secondaryColor.opacity(0.15),
                            Color.ember.opacity(0.08)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: size / 2
                    )
                )
                .frame(width: size, height: size)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.06),
                            .clear
                        ],
                        center: UnitPoint(x: 0.35, y: 0.25),
                        startRadius: 0,
                        endRadius: size * 0.4
                    )
                )
                .frame(width: size, height: size)
        }
    }

    private var glassRefraction: some View {
        Ellipse()
            .fill(
                LinearGradient(
                    colors: [
                        secondaryColor.opacity(0.18 + effectiveAmplitude * 0.12),
                        mood.accentColor.opacity(0.08),
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size * 0.7, height: size * 0.45)
            .blur(radius: size * 0.06)
            .offset(y: -size * 0.08)
            .rotationEffect(.degrees(glassRotation))
    }

    private var innerGlow: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color.white.opacity(0.12 + shimmerPhase * 0.08),
                        mood.accentColor.opacity(0.04),
                        .clear
                    ],
                    center: UnitPoint(x: 0.38, y: 0.32),
                    startRadius: 0,
                    endRadius: size * 0.35
                )
            )
            .frame(width: size * 0.6, height: size * 0.6)
            .blendMode(.screen)
    }

    private var pulsingRing: some View {
        let ringSize = size * (1.0 + CGFloat(effectiveAmplitude) * 0.22)
        return ZStack {
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [
                            ringColor.opacity(0.7),
                            secondaryColor.opacity(0.4),
                            ringColor.opacity(0.1),
                            secondaryColor.opacity(0.3),
                            ringColor.opacity(0.7)
                        ],
                        center: .center
                    ),
                    lineWidth: 1.5
                )
                .frame(width: ringSize, height: ringSize)
                .opacity(state == .idle ? 0.4 : 0.9)
            if state != .idle {
                Circle()
                    .stroke(
                        ringColor.opacity(0.15),
                        lineWidth: 0.5
                    )
                    .frame(width: ringSize * 1.12, height: ringSize * 1.12)
            }
        }
    }

    private var shimmerArc: some View {
        Circle()
            .trim(from: 0.0, to: 0.3)
            .stroke(
                LinearGradient(
                    colors: [Color.white.opacity(0.25 + shimmerPhase * 0.15), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
            )
            .frame(width: size * 0.88, height: size * 0.88)
            .rotationEffect(.degrees(glassRotation * 0.7))
    }

    private var particles: some View {
        ForEach(0..<5, id: \.self) { index in
            ForgeOrbitalParticle(
                index: index,
                size: size,
                amplitude: effectiveAmplitude,
                state: state,
                color: index % 2 == 0 ? mood.accentColor : secondaryColor,
                reduceMotion: reduceMotion
            )
        }
    }

    private func startAnimations() {
        guard !reduceMotion else { return }
        let spinDuration = state == .processing ? 2.0 : 4.0
        withAnimation(.linear(duration: spinDuration).repeatForever(autoreverses: false)) {
            rotation = 360
        }
        withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
            shimmerPhase = 1
        }
        withAnimation(.linear(duration: 8.0).repeatForever(autoreverses: false)) {
            glassRotation = 360
        }
    }
}

private struct AuroraWaveCanvas: View {
    let accent: Color
    let secondary: Color
    let amplitude: Double

    private static let configs: [(phase: Double, speed: Double, opacity: Double)] = [
        (0.0, 0.7, 0.18), (1.8, 0.9, 0.28), (3.6, 1.1, 0.22)
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { timeline in
            Canvas { context, canvasSize in
                drawWaves(context: context, size: canvasSize, time: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    private func drawWaves(context: GraphicsContext, size: CGSize, time: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) / 2

        for (index, config) in Self.configs.enumerated() {
            let waveAmp = radius * 0.08 * (1.0 + amplitude * 1.5) * (1.0 + Double(index) * 0.05)
            var path = Path()
            let steps = 24
            for step in 0...steps {
                let angle = Double(step) / Double(steps) * .pi * 2
                let wobble = sin(angle * 3 + time * config.speed + config.phase) * waveAmp
                    + sin(angle * 5 + time * config.speed * 0.6) * waveAmp * 0.3
                let r = radius * 0.82 + wobble
                let point = CGPoint(
                    x: center.x + CGFloat(cos(angle) * r),
                    y: center.y + CGFloat(sin(angle) * r)
                )
                if step == 0 { path.move(to: point) }
                else { path.addLine(to: point) }
            }
            path.closeSubpath()
            let strokeColor = (index % 2 == 0 ? accent : secondary).opacity(config.opacity)
            context.stroke(path, with: .color(strokeColor), lineWidth: 1.2)
        }
    }
}

private struct ForgeOrbitalParticle: View {
    let index: Int
    let size: CGFloat
    let amplitude: Double
    let state: AROrbState
    let color: Color
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { timeline in
            particle(at: timeline.date.timeIntervalSinceReferenceDate)
        }
    }

    private func particle(at time: Double) -> some View {
        let speed = 0.3 + Double(index) * 0.1
        let angle = time * speed + Double(index) * (.pi * 2 / 5)
        let baseRadius = Double(size / 2) * (0.55 + Double(index % 3) * 0.12)
        let scatter = (state == .idle && !reduceMotion) ? 0.0 : amplitude * 18.0
        let radius = baseRadius + scatter
        let dotSize = CGFloat(2 + index % 3)

        return Circle()
            .fill(color.opacity(0.6))
            .frame(width: dotSize, height: dotSize)
            .shadow(color: color.opacity(0.5), radius: 2)
            .offset(x: CGFloat(cos(angle) * radius), y: CGFloat(sin(angle) * radius))
    }
}