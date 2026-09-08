import AVFoundation
import CoreGraphics

/// Welcome arrive-sound and the shared still-frame mark contract
/// (`shared/aria-mark.json`, `shared/brand/aria-mark.png`).
/// Live ARIA is a procedural 4-lobe ember (`AuroraOrbView` / web canvas).
/// The PNG stays on disk as the Reduce Motion / fallback still.
/// Pure gates so tests can lock quiet mode and Reduce Motion without audio.
enum AriaWelcomeChime: Sendable {
    static let assetName = "AriaLogo"
    /// 1.0 — show the whole ember. Lockstep with `shared/aria-mark.json`.
    static let cropScale: CGFloat = 1.0
    static let heroMinimumSize: CGFloat = 90

    static func shouldPlay(
        size: CGFloat,
        reduceMotion: Bool,
        quietMode: Bool,
        alreadyPlayed: Bool,
        isSpeaking: Bool = false
    ) -> Bool {
        size >= heroMinimumSize
            && !reduceMotion
            && !quietMode
            && !alreadyPlayed
            && !isSpeaking
    }

    @MainActor
    static func play() {
        ChimePlayer.shared.start()
    }
}

/// Two-note gold chime. Mixes with speech; does not steal the spoken session.
@MainActor
private final class ChimePlayer {
    static let shared = ChimePlayer()

    private var engine: AVAudioEngine?
    private var stopTask: Task<Void, Never>?

    func start() {
        stop()
        // First SwiftUI layout is mid-CATransaction. Touching `mainMixerNode`
        // then trips an AudioUnit RemoteIO RPC timeout on iOS 27 Simulator
        // and aborts the process — black screen, no catch.
        stopTask = Task { @MainActor [weak self] in
            await Task.yield()
            try? await Task.sleep(nanoseconds: 80_000_000)
            self?.startEngine()
        }
    }

    private func startEngine() {
        #if targetEnvironment(simulator)
        // iOS 27 Simulator RemoteIO times out inside `mainMixerNode` and
        // aborts the process. Device playback is unchanged.
        return
        #else
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 22_050, channels: 1) else { return }
        let renderer = BellRenderer()
        let engine = AVAudioEngine()
        let source = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for buffer in buffers {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                renderer.render(into: data, frames: Int(frameCount))
            }
            return noErr
        }
        do {
            try ForgePlaybackSession.chime.activate()
            engine.attach(source)
            #if compiler(>=6.4)
            try engine.connectNode(source, to: engine.mainMixerNode, format: format)
            #else
            engine.connect(source, to: engine.mainMixerNode, format: format)
            #endif
            try engine.start()
            engine.mainMixerNode.outputVolume = 0.28
        } catch {
            return
        }
        self.engine = engine
        stopTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 520_000_000)
            self?.stop()
        }
        #endif
    }

    func stop() {
        stopTask?.cancel()
        stopTask = nil
        engine?.stop()
        engine = nil
    }
}

private final class BellRenderer: @unchecked Sendable {
    private let sampleRate: Double = 22_050
    private var frame: Int = 0
    private let notes: [(start: Double, freq: Double, dur: Double)] = [
        (0.00, 523.25, 0.22),
        (0.14, 784.00, 0.32),
    ]

    func render(into data: UnsafeMutablePointer<Float>, frames: Int) {
        for i in 0..<frames {
            let t = Double(frame) / sampleRate
            var sample: Double = 0
            for note in notes {
                let age = t - note.start
                guard age >= 0, age < note.dur else { continue }
                let env = sin((age / note.dur) * .pi) * exp(-age * 4.2)
                sample += sin(2 * .pi * note.freq * age) * env * 0.38
            }
            data[i] = Float(max(-1, min(1, sample)))
            frame += 1
        }
    }
}
