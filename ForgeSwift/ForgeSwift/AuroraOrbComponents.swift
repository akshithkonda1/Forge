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

    private let waveConfigs: [(phase: Double, speed: Double, opacity: Double)] = [
        (0.0, 0.8, 0.15), (0.9, 1.0, 0.22), (1.8, 1.1, 0.28),
        (2.6, 1.2, 0.34), (3.4, 1.3, 0.40), (4.2, 1.4, 0.45)
    ]

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
        case .calm: return Color(hex: "A855F7")
        }
    }

    var body: some View {
        ZStack {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                Canvas { context, canvasSize in
                    let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                    let radius = min(canvasSize.width, canvasSize.height) / 2
                    for (index, config) in waveConfigs.enumerated() {
                        let waveAmp = radius * 0.08 * (1.0 + effectiveAmplitude * 1.5) * (1.0 + Double(index) * 0.05)
                        var path = Path()
                        let steps = 48
                        for step in 0...steps {
                            let angle = Double(step) / Double(steps) * .pi * 2
                            let wobble = sin(angle * 3 + t * config.speed + config.phase) * waveAmp
                            let r = radius * 0.82 + wobble
                            let point = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
                            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
                        }
                        path.closeSubpath()
                        context.stroke(path, with: .color(mood.accentColor.opacity(config.opacity)), lineWidth: 1.5)
                    }
                }
            }

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "0D0D0D"), mood.accentColor.opacity(0.4), Color.ember.opacity(0.2)],
                        center: .center,
                        startRadius: 0,
                        endRadius: size / 2
                    )
                )
                .frame(width: size, height: size)

            Circle()
                .stroke(
                    LinearGradient(colors: [ringColor.opacity(0.8), ringColor.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 2
                )
                .frame(width: size * (1.0 + CGFloat(effectiveAmplitude) * 0.25), height: size * (1.0 + CGFloat(effectiveAmplitude) * 0.25))
                .opacity(state == .idle ? 0.35 : 0.85)

            Circle()
                .stroke(ringColor.opacity(0.5), lineWidth: 1)
                .frame(width: size * 1.8, height: size * 1.8)
                .opacity(max(0, 0.6 - effectiveAmplitude * 0.5))

            Circle()
                .fill(Color.white.opacity(0.15 + shimmerPhase * 0.2))
                .frame(width: size * 0.18, height: size * 0.18)
                .blur(radius: 2)

            ForEach(0..<8, id: \.self) { index in
                ForgeOrbitalParticle(index: index, size: size, amplitude: effectiveAmplitude, state: state, color: mood.accentColor, reduceMotion: reduceMotion)
            }
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(state == .processing && !reduceMotion ? rotation : 0))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: state == .processing ? 2.0 : 4.0).repeatForever(autoreverses: false)) { rotation = 360 }
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) { shimmerPhase = 1 }
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
            let t = timeline.date.timeIntervalSinceReferenceDate
            let speed = 0.4 + Double(index) * 0.08
            let angle = t * speed + Double(index) * (.pi / 4)
            let baseRadius = (size / 2) * (0.6 + CGFloat(index % 3) * 0.1)
            let scatter = state == .idle && !reduceMotion ? 0 : CGFloat(amplitude) * 20
            Circle()
                .fill(color.opacity(0.7))
                .frame(width: CGFloat(4 + index % 3), height: CGFloat(4 + index % 3))
                .offset(x: cos(angle) * (Double(baseRadius) + Double(scatter)), y: sin(angle) * (Double(baseRadius) + Double(scatter)))
        }
    }
}