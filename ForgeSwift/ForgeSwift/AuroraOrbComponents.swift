import SwiftUI
import AVFoundation

enum AROrbState: Equatable {
    case idle, listening, processing, speaking
}

/// App-wide ARIA voice presence. Welcome, chat, Train “show me how”, and the
/// tab mark all read this so the same Aurora orb moves when she talks.
@MainActor
final class AriaPresence: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = AriaPresence()

    @Published private(set) var isSpeaking = false
    @Published private(set) var isListening = false
    @Published private(set) var isThinking = false
    @Published var amplitude: Float = 0.18

    var orbState: AROrbState {
        if isSpeaking { return .speaking }
        if isListening { return .listening }
        if isThinking { return .processing }
        return .idle
    }

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func setListening(_ on: Bool) { isListening = on }
    func setThinking(_ on: Bool) { isThinking = on }
    func markSpeaking(_ on: Bool) { isSpeaking = on }

    func speak(_ text: String) {
        let clipped = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clipped.isEmpty else { return }
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .word) }
        let utterance = AVSpeechUtterance(string: String(clipped.prefix(900)))
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.52
        utterance.pitchMultiplier = 0.95
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .word)
        isSpeaking = false
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}

/// Compact Aurora orb for avatars, tabs, and cards.
/// Live speech/listen from `AriaPresence` overrides the idle state so every
/// mark moves when ARIA talks.
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
    /// When ARIA is speaking or listening, the orb follows `AriaPresence`
    /// instead of the caller’s idle state.
    var followPresence: Bool = false

    @ObservedObject private var presence = AriaPresence.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breath: Double = 0

    private var resolvedState: AROrbState {
        followPresence && presence.orbState != .idle ? presence.orbState : state
    }

    private var resolvedAmplitude: Float {
        if followPresence, presence.isSpeaking { return max(amplitude, 0.72) }
        return amplitude
    }

    private var effectiveAmplitude: Double {
        let amp = Double(resolvedAmplitude)
        switch resolvedState {
        case .idle: return 0.16 + breath * 0.08
        case .listening: return max(0.42, amp)
        case .processing: return 0.55 + breath * 0.12
        case .speaking: return max(0.7, amp)
        }
    }

    private var ringColor: Color {
        switch mood {
        case .energized, .pushed: return .ember
        case .focused: return .steel
        case .calm: return Color(hex: "A855F7")
        }
    }

    /// Glints, not the whole identity. Ember stays the soul; these are the
    /// flashes you only catch if you're watching.
    private var secondaryColor: Color {
        switch mood {
        case .energized: return Color(hex: "FFC14A")
        case .pushed: return Color(hex: "FF2D55")
        case .focused: return Color(hex: "6B8CFF")
        case .calm: return Color(hex: "7B61FF")
        }
    }

    var body: some View {
        Group {
            if reduceMotion || size < 64 {
                ZStack {
                    coreOrb
                    coreSpark
                    veil
                    pulsingRing
                }
                .frame(width: size, height: size)
            } else {
                ZStack {
                    AuroraLivingField(
                        accent: mood.accentColor,
                        secondary: secondaryColor,
                        amplitude: effectiveAmplitude,
                        state: resolvedState,
                        size: size
                    )

                    coreOrb
                    coreSpark
                    veil
                    pulsingRing
                }
                .frame(width: size, height: size)
                .scaleEffect(1.0 + CGFloat(breath) * 0.035)
                .onAppear(perform: startBreath)
                .onChange(of: resolvedState) { _, _ in startBreath() }
            }
        }
        .accessibilityLabel(
            resolvedState == .speaking ? "ARIA speaking"
                : resolvedState == .listening ? "ARIA listening"
                : "ARIA"
        )
    }

    private var coreOrb: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color(hex: "030306"),
                        Color(hex: "0A0610").opacity(0.95),
                        mood.accentColor.opacity(0.22),
                        secondaryColor.opacity(0.08),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: size / 2
                )
            )
            .frame(width: size, height: size)
    }

    /// A star in the void. The thing you notice after a second, not first.
    private var coreSpark: some View {
        let spark = size * (0.07 + CGFloat(effectiveAmplitude) * 0.05)
        return ZStack {
            Circle()
                .fill(mood.accentColor.opacity(0.45 + breath * 0.25))
                .frame(width: spark * 2.4, height: spark * 2.4)
                .blur(radius: spark * 0.8)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.7),
                            mood.accentColor.opacity(0.9),
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
        .opacity(0.55 + breath * 0.45)
    }

    /// Darkens the rim so the spark recedes. Mystery is what's hidden.
    private var veil: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        .clear,
                        Color(hex: "050508").opacity(0.15),
                        Color(hex: "050508").opacity(0.72)
                    ],
                    center: .center,
                    startRadius: size * 0.18,
                    endRadius: size * 0.52
                )
            )
            .frame(width: size, height: size)
            .allowsHitTesting(false)
    }

    private var pulsingRing: some View {
        let ringSize = size * (0.96 + CGFloat(effectiveAmplitude) * 0.18)
        return Circle()
            .stroke(
                AngularGradient(
                    colors: [
                        ringColor.opacity(0.55 + breath * 0.2),
                        secondaryColor.opacity(0.12),
                        .clear,
                        ringColor.opacity(0.18),
                        secondaryColor.opacity(0.35),
                        ringColor.opacity(0.55 + breath * 0.2)
                    ],
                    center: .center
                ),
                lineWidth: resolvedState == .idle ? 1.0 : 1.6
            )
            .frame(width: ringSize, height: ringSize)
            .opacity(resolvedState == .idle ? 0.45 : 0.85)
    }

    private func startBreath() {
        guard !reduceMotion else { return }
        breath = 0
        let duration: Double
        switch resolvedState {
        case .idle: duration = 4.6
        case .listening: duration = 2.2
        case .processing: duration = 1.6
        case .speaking: duration = 1.8
        }
        withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
            breath = 1
        }
    }
}

/// One 12 fps field: nebula, liquid waves, drifting embers. Phase-locked so
/// the motion reads as one organism instead of stacked loops.
private struct AuroraLivingField: View {
    let accent: Color
    let secondary: Color
    let amplitude: Double
    let state: AROrbState
    let size: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { timeline in
            Canvas { context, canvasSize in
                let t = timeline.date.timeIntervalSinceReferenceDate
                drawNebula(context: context, size: canvasSize, time: t)
                drawWaves(context: context, size: canvasSize, time: t)
                drawEmbers(context: context, size: canvasSize, time: t)
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }

    private func drawNebula(context: GraphicsContext, size: CGSize, time: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let blobs: [(dx: Double, dy: Double, speed: Double, scale: Double, color: Color)] = [
            (0.12, -0.08, 0.18, 0.55, accent),
            (-0.14, 0.10, 0.13, 0.48, secondary),
            (0.02, 0.16, 0.21, 0.42, accent)
        ]
        for blob in blobs {
            let x = center.x + CGFloat(sin(time * blob.speed) * blob.dx) * size.width
            let y = center.y + CGFloat(cos(time * blob.speed * 0.7) * blob.dy) * size.height
            let r = size.width * blob.scale * (0.85 + amplitude * 0.2)
            let rect = CGRect(x: x - r / 2, y: y - r / 2, width: r, height: r * 0.78)
            context.fill(
                Path(ellipseIn: rect),
                with: .color(blob.color.opacity(0.07 + amplitude * 0.06))
            )
        }
    }

    private func drawWaves(context: GraphicsContext, size: CGSize, time: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) / 2
        let configs: [(phase: Double, speed: Double, opacity: Double, harmonic: Double)] = [
            (0.0, 0.38, 0.22, 2.0),
            (1.7, 0.27, 0.16, 3.0),
            (3.4, 0.46, 0.12, 2.5)
        ]

        for (index, config) in configs.enumerated() {
            let waveAmp = radius * 0.10 * (1.0 + amplitude * 1.4)
            var path = Path()
            let steps = 28
            for step in 0...steps {
                let angle = Double(step) / Double(steps) * .pi * 2
                let wobble = sin(angle * config.harmonic + time * config.speed + config.phase) * waveAmp
                    + sin(angle * (config.harmonic + 1.5) + time * config.speed * 0.55) * waveAmp * 0.35
                let r = radius * 0.78 + wobble
                let point = CGPoint(
                    x: center.x + CGFloat(cos(angle) * r),
                    y: center.y + CGFloat(sin(angle) * r)
                )
                if step == 0 { path.move(to: point) }
                else { path.addLine(to: point) }
            }
            path.closeSubpath()
            let color = (index == 1 ? secondary : accent).opacity(config.opacity)
            context.fill(path, with: .color(color.opacity(0.35)))
            context.stroke(path, with: .color(color), lineWidth: 1.1)
        }
    }

    private func drawEmbers(context: GraphicsContext, size: CGSize, time: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let count = state == .idle ? 4 : 6
        for i in 0..<count {
            let a = 0.22 + Double(i) * 0.07
            let b = 0.31 + Double(i) * 0.05
            let phase = Double(i) * 1.1
            let rx = Double(size.width) * (0.18 + Double(i % 3) * 0.06) * (1.0 + amplitude * 0.25)
            let ry = Double(size.height) * (0.14 + Double(i % 2) * 0.07) * (1.0 + amplitude * 0.25)
            let x = center.x + CGFloat(sin(time * a + phase) * rx)
            let y = center.y + CGFloat(sin(time * b + phase * 0.7) * ry)
            let fade = 0.35 + 0.45 * (0.5 + 0.5 * sin(time * 0.6 + phase))
            let r = CGFloat(1.4 + Double(i % 3) * 0.7)
            let color = i % 2 == 0 ? accent : secondary
            let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
            context.fill(Path(ellipseIn: rect), with: .color(color.opacity(fade)))
        }
    }
}
