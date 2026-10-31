import AVFoundation
import Foundation
import ForgeCore
import os

#if canImport(KokoroTTS)
import KokoroTTS
#endif

/// Lazy on-device Kokoro mouth. The only synthesizer ARIA uses.
///
/// Package: `mattmireles/kokoro-coreml` v2.0 / `KokoroTTS` (Apache-2.0),
/// G2P MisakiSwift (Apache-2.0, no eSpeak), weights `hexgrad/Kokoro-82M`.
/// Linked on the iOS app target only — watchOS cannot build MisakiSwift/MLX.
/// Speak never opens a socket. Missing or failed load stays silent with the
/// text on screen. Apple TTS is not a fallback.
@MainActor
enum AriaKokoroEngine {
    static func resetForTests() {
        AriaKokoroRuntimeSynthesizer.shared.resetForTests()
    }

    static func speak(
        _ text: String,
        voiceID: String = AriaKokoroVoice.ariaPreset,
        speed: Double = 1.0
    ) async -> Bool {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return false }
        guard !AriaKokoroVoice.allowsNetworkAtSpeakTime else { return false }
        return await AriaKokoroRuntimeSynthesizer.shared.speak(
            line,
            voiceID: AriaKokoroVoice.sanitizePreset(voiceID),
            speed: speed
        )
    }

    static func stop() {
        AriaKokoroRuntimeSynthesizer.shared.stop()
    }

    static func noteRuntimeBecameAvailable() {
        AriaKokoroRuntimeSynthesizer.shared.allowRetryAfterLoad()
    }
}

/// Injected only by tests. Production always uses KokoroTTS + AVAudioEngine.
struct AriaKokoroEngineTestBackend {
    var modelPresent: Bool
    var load: () async -> Bool
    var render: (String, String, Double) async -> [Float]
    var play: ([Float]) async -> Bool
}

@MainActor
final class AriaKokoroRuntimeSynthesizer {
    static let shared = AriaKokoroRuntimeSynthesizer()
    static let logger = Logger(subsystem: "com.forge.aria", category: "kokoro")

    private var path = AriaKokoroEnginePath()
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var playGeneration = 0
    private var speakGeneration = 0
    private var testBackend: AriaKokoroEngineTestBackend?

    #if canImport(KokoroTTS)
    private var tts: KokoroTTS?
    #endif

    private init() {}

    var loadState: AriaKokoroLoadState { path.loadState }

    func resetForTests() {
        path = AriaKokoroEnginePath()
        testBackend = nil
        stop()
        #if canImport(KokoroTTS)
        tts = nil
        #endif
    }

    func installTestBackend(_ backend: AriaKokoroEngineTestBackend) {
        testBackend = backend
        path = AriaKokoroEnginePath()
    }

    func allowRetryAfterLoad() {
        path.allowRetryAfterLoad()
    }

    func prepare() async -> Bool {
        var enginePath = path
        let ready = await enginePath.prepare(modelPresent: modelIsPresent, load: { [self] in
            await self.loadRuntime()
        })
        path = enginePath
        return ready
    }

    func speak(_ text: String, voiceID: String, speed: Double) async -> Bool {
        speakGeneration += 1
        let generation = speakGeneration
        var enginePath = path
        let spoken = await enginePath.speak(
            text,
            voiceID: voiceID,
            speed: speed,
            modelPresent: modelIsPresent,
            load: { [self] in
                await self.loadRuntime()
            },
            render: { [self] segment, voice, rate in
                await self.renderPCM(segment, voiceID: voice, speed: rate)
            },
            play: { [self] samples in
                guard generation == self.speakGeneration else { return false }
                return await self.play(samples: samples, sampleRate: 24_000, generation: generation)
            }
        )
        path = enginePath
        if !spoken, !path.loadState.isReady {
            Self.logLoadFailure()
        }
        return spoken
    }

    func renderPCM(_ text: String, voiceID: String, speed: Double) async -> [Float] {
        if let testBackend {
            return AriaKokoroAudioPolicy.playableSamples(
                from: await testBackend.render(text, voiceID, speed)
            )
        }
        #if canImport(KokoroTTS)
        guard let tts else { return [] }
        let voice = KokoroVoiceID(AriaKokoroVoice.sanitizePreset(voiceID))
        let options = KokoroSynthesisOptions(
            speed: Float(speed),
            maxChunkSeconds: AriaKokoroDelivery.maxChunkSeconds
        )
        do {
            let audio = try await synthesizeWithFallback(
                tts: tts,
                text: text,
                voice: voice,
                options: options
            )
            return AriaKokoroAudioPolicy.playableSamples(from: audio.samples)
        } catch {
            Self.logger.error("Kokoro synthesize failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
        #else
        _ = text
        _ = voiceID
        _ = speed
        return []
        #endif
    }

    func stop() {
        speakGeneration += 1
        playGeneration += 1
        player?.stop()
        engine?.stop()
        player = nil
        engine = nil
    }

    static func logLoadFailure() {
        logger.error("Kokoro-82M failed to load. Text stays on screen. No fallback voice.")
    }

    private var modelIsPresent: Bool {
        testBackend?.modelPresent ?? AriaKokoroModelStore.shared.hasVerifiedRuntime
    }

    private func loadRuntime() async -> Bool {
        if let testBackend {
            return await testBackend.load()
        }
        return await loadEngine()
    }

    #if canImport(KokoroTTS)
    private func synthesizeWithFallback(
        tts: KokoroTTS,
        text: String,
        voice: KokoroVoiceID,
        options: KokoroSynthesisOptions
    ) async throws -> KokoroAudio {
        do {
            return try await tts.synthesize(text, voice: voice, options: options)
        } catch {
            let fallback = KokoroVoiceID.afHeart
            guard voice != fallback else { throw error }
            return try await tts.synthesize(text, voice: fallback, options: options)
        }
    }
    #endif

    private func loadEngine() async -> Bool {
        #if canImport(KokoroTTS)
        guard let root = AriaKokoroModelStore.shared.resolvedRuntimeURL() else {
            return false
        }
        let compiled = AriaKokoroModelStore.shared.compiledModelsDirectory
        do {
            try FileManager.default.createDirectory(at: compiled, withIntermediateDirectories: true)
            let resources = KokoroResourceProvider.directory(
                root,
                compiledModelsDirectory: compiled
            )
            tts = try await KokoroTTS.load(resources: resources)
            return tts != nil
        } catch {
            Self.logger.error("Kokoro load failed: \(error.localizedDescription, privacy: .public)")
            tts = nil
            return false
        }
        #else
        return false
        #endif
    }

    private func play(samples: [Float], sampleRate: Double, generation: Int) async -> Bool {
        guard generation == speakGeneration else { return false }
        guard AriaKokoroAudioPolicy.shouldPlay(samples) else { return false }
        if let testBackend {
            return await testBackend.play(samples)
        }
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ), let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else { return false }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            if let dst = buffer.floatChannelData?[0], let base = src.baseAddress {
                dst.update(from: base, count: src.count)
            }
        }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        #if compiler(>=6.4)
        do {
            try engine.connectNode(player, to: engine.mainMixerNode, format: format)
        } catch {
            return false
        }
        #else
        engine.connect(player, to: engine.mainMixerNode, format: format)
        #endif
        do {
            engine.prepare()
            try engine.start()
        } catch {
            return false
        }
        self.engine = engine
        self.player = player
        playGeneration += 1
        let playID = playGeneration

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            player.scheduleBuffer(buffer) {
                continuation.resume()
            }
            #if compiler(>=6.4)
            do {
                try player.playAudio()
            } catch {
                continuation.resume()
            }
            #else
            player.play()
            #endif
        }
        if playID == playGeneration {
            player.stop()
            engine.stop()
            if self.player === player {
                self.player = nil
                self.engine = nil
            }
        }
        return generation == speakGeneration
    }
}
