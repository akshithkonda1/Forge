import SwiftUI

enum AROrbState: Equatable {
    case idle, listening, processing, speaking
}

struct AuroraOrbView: View {
    let state: AROrbState
    let amplitude: Float
    var mood: ARIAMood = .focused
    var size: CGFloat = 140

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmerPhase: Double = 0
    @State private var rotation: Double = 0

    private var effectiveAmplitude: Double {
        let amp = Double(amplitude)
        switch state {
        case .idle: return 0.1
        case .listening: return max(0.35, amp)
        case .processing: return 0.55
        case .speaking: return max(0.65, amp)
        }
    }

    private var ringColor: Color {
        switch mood {
        case .energized, .pushed: return .ember
        case .focused: return .steel
        case .calm: return Color.violet
        }
    }

    var body: some View {
        ZStack {
            AuroraWaveCanvas(
                accent: mood.accentColor,
                amplitude: effectiveAmplitude
            )

            coreOrb

            pulsingRing

            outerHalo

            shimmerCore

            particles
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(state == .processing && !reduceMotion ? rotation : 0))
        .onAppear(perform: startAnimations)
    }

    private var coreOrb: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color(hex: "0D0D0D"),
                        mood.accentColor.opacity(0.4),
                        Color.ember.opacity(0.2)
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: size / 2
                )
            )
            .frame(width: size, height: size)
    }

    private var pulsingRing: some View {
        let ringSize = size * (1.0 + CGFloat(effectiveAmplitude) * 0.25)
        return Circle()
            .stroke(
                LinearGradient(
                    colors: [ringColor.opacity(0.8), ringColor.opacity(0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 2
            )
            .frame(width: ringSize, height: ringSize)
            .opacity(state == .idle ? 0.35 : 0.85)
    }

    private var outerHalo: some View {
        Circle()
            .stroke(ringColor.opacity(0.5), lineWidth: 1)
            .frame(width: size * 1.8, height: size * 1.8)
            .opacity(max(0, 0.6 - effectiveAmplitude * 0.5))
    }

    private var shimmerCore: some View {
        Circle()
            .fill(Color.white.opacity(0.15 + shimmerPhase * 0.2))
            .frame(width: size * 0.18, height: size * 0.18)
            .blur(radius: 2)
    }

    private var particles: some View {
        ForEach(0..<8, id: \.self) { index in
            ForgeOrbitalParticle(
                index: index,
                size: size,
                amplitude: effectiveAmplitude,
                state: state,
                color: mood.accentColor,
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
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            shimmerPhase = 1
        }
    }
}

private struct AuroraWaveCanvas: View {
    let accent: Color
    let amplitude: Double

    private static let configs: [(phase: Double, speed: Double, opacity: Double)] = [
        (0.0, 0.8, 0.15), (0.9, 1.0, 0.22), (1.8, 1.1, 0.28),
        (2.6, 1.2, 0.34), (3.4, 1.3, 0.40), (4.2, 1.4, 0.45)
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
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
            let steps = 32
            for step in 0...steps {
                let angle = Double(step) / Double(steps) * .pi * 2
                let wobble = sin(angle * 3 + time * config.speed + config.phase) * waveAmp
                let r = radius * 0.82 + wobble
                let point = CGPoint(
                    x: center.x + CGFloat(cos(angle) * r),
                    y: center.y + CGFloat(sin(angle) * r)
                )
                if step == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            path.closeSubpath()
            let strokeColor = accent.opacity(config.opacity)
            context.stroke(path, with: .color(strokeColor), lineWidth: 1.5)
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
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            particle(at: timeline.date.timeIntervalSinceReferenceDate)
        }
    }

    private func particle(at time: Double) -> some View {
        let speed = 0.4 + Double(index) * 0.08
        let angle = time * speed + Double(index) * (.pi / 4)
        let baseRadius = Double(size / 2) * (0.6 + Double(index % 3) * 0.1)
        let scatter = (state == .idle && !reduceMotion) ? 0.0 : amplitude * 20.0
        let radius = baseRadius + scatter
        let dotSize = CGFloat(4 + index % 3)

        return Circle()
            .fill(color.opacity(0.7))
            .frame(width: dotSize, height: dotSize)
            .offset(x: CGFloat(cos(angle) * radius), y: CGFloat(sin(angle) * radius))
    }
}