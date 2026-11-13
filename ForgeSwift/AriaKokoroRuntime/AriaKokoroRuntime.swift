import AVFoundation
import Foundation
import ForgeCore
import KokoroTTS
import os

/// Dynamic framework mouth. The app embeds this image and does not link it.
/// `AriaVoiceEngineRegistry` loads it on first speak via `Bundle.load`.
@objc(AriaKokoroRuntimePrincipal)
public final class AriaKokoroRuntimePrincipal: NSObject, AriaVoiceEngine {
    public let id = AriaVoiceEngineID.kokoro
    private static let logger = Logger(subsystem: "com.forge.aria", category: "kokoro.runtime")

    private var tts: KokoroTTS?
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var playGeneration = 0

    public override init() {
        super.init()
    }

    public func speak(_ text: String, voiceID: String, speed: Double) async -> Bool {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return false }
        guard await loadEngine() else { return false }
        let samples = await renderPCM(line, voiceID: voiceID, speed: speed)
        guard AriaKokoroAudioPolicy.shouldPlay(samples) else { return false }
        return await play(samples: samples, sampleRate: 24_000)
    }

    public func stop() {
        playGeneration += 1
        player?.stop()
        engine?.stop()
        player = nil
        engine = nil
    }

    private func loadEngine() async -> Bool {
        if tts != nil { return true }
        guard let root = runtimeRoot() else { return false }
        let compiled = applicationSupportRoot().appendingPathComponent("compiled", isDirectory: true)
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
    }

    private func renderPCM(_ text: String, voiceID: String, speed: Double) async -> [Float] {
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
    }

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

    private func play(samples: [Float], sampleRate: Double) async -> Bool {
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
        return true
    }

    private func runtimeRoot() -> URL? {
        var roots: [URL] = []
        if let bundled = bundledRuntimeURL() { roots.append(bundled) }
        roots.append(applicationSupportRoot())
        return AriaKokoroRuntimeLocator(roots: roots).resolvedRoot { url in
            FileManager.default.fileExists(atPath: url.path)
        }
    }

    private func bundledRuntimeURL() -> URL? {
        if let url = Bundle.main.url(
            forResource: AriaKokoroDelivery.bundleResourceName,
            withExtension: AriaKokoroDelivery.bundleResourceExtension
        ) {
            return url
        }
        if let manifest = Bundle.main.url(
            forResource: "KokoroRuntimeManifest",
            withExtension: "json"
        ) {
            return manifest.deletingLastPathComponent()
        }
        return nil
    }

    private func applicationSupportRoot() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return AriaKokoroDelivery.applicationSupportRoot(base: base)
    }
}
