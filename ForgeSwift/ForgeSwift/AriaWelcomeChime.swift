import AVFoundation
import CoreGraphics

/// Welcome arrive-sound and the shared raster-mark contract (`shared/aria-mark.json`,
/// used for web parity — see `src/lib/aria-mark.ts`, `shared/brand/aria-mark.png`).
/// iOS's own mark is drawn natively by `PulseSigil` in `AuroraOrbComponents.swift`
/// and no longer renders the 4-lobe ember asset directly — no ring, no glass
/// frame, no crop, on either platform.
/// Pure gates so tests can lock quiet mode and Reduce Motion without audio.
enum AriaWelcomeChime: Sendable {
    static let assetName = "ForgeMark"
    /// 1.0 — show the whole ember. Lockstep with `shared/aria-mark.json`.
    static let cropScale: CGFloat = 1.0 // generic mark — no ARIA-specific crop
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
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.28
        do {
            try ForgePlaybackSession.chime.activate()
            try engine.start()
        } catch {
            return
        }
        self.engine = engine
        stopTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 520_000_000)
            self?.stop()
        }
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
