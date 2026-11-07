import AVFoundation
import Foundation
import ForgeCore
import os

/// Lazy on-device Kokoro mouth. The only synthesizer ARIA uses.
///
/// Intended package: `mattmireles/kokoro-coreml` / `KokoroTTS` (Apache-2.0),
/// weights `hexgrad/Kokoro-82M` (Apache-2.0). The package is iOS-only and
/// watchOS cannot link it, so this file uses `canImport` and a bundled
/// starter model. First speak loads the engine. Hugging Face is never
/// contacted at speak time — Dummy / offline stay offline. If the model
/// is missing or load fails, we log locally and leave the text on screen.
/// Apple TTS is not a fallback.
@MainActor
enum AriaKokoroEngine {
    static var synthesizer: any AriaKokoroSynthesizing = AriaKokoroRuntimeSynthesizer.shared

    static func resetForTests(using replacement: (any AriaKokoroSynthesizing)? = nil) {
        synthesizer = replacement ?? AriaKokoroRuntimeSynthesizer.shared
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
        let ready = await synthesizer.prepare()
        guard ready else {
            AriaKokoroRuntimeSynthesizer.logLoadFailure()
            return false
        }
        return await synthesizer.speak(
            line,
            voiceID: AriaKokoroVoice.sanitizePreset(voiceID),
            speed: speed
        )
    }

    static func stop() {
        synthesizer.stop()
    }
}

@MainActor
protocol AriaKokoroSynthesizing: AnyObject {
    func prepare() async -> Bool
    func speak(_ text: String, voiceID: String, speed: Double) async -> Bool
    func stop()
}

@MainActor
final class AriaKokoroRuntimeSynthesizer: AriaKokoroSynthesizing {
    static let shared = AriaKokoroRuntimeSynthesizer()
    static let logger = Logger(subsystem: "com.forge.aria", category: "kokoro")

    private var loaded = false
    private var loadFailed = false
    private var player: AVAudioPlayer?

    private init() {}

    func resetForTests() {
        loaded = false
        loadFailed = false
        player?.stop()
        player = nil
    }

    func prepare() async -> Bool {
        if loaded { return true }
        if loadFailed { return false }
        loaded = await Self.loadBundledEngine()
        loadFailed = !loaded
        if loadFailed {
            Self.logLoadFailure()
        }
        return loaded
    }

    func speak(_ text: String, voiceID: String, speed: Double) async -> Bool {
        _ = text
        _ = voiceID
        _ = speed
        #if canImport(KokoroTTS)
        return await synthesizeWithPackage()
        #else
        return false
        #endif
    }

    func stop() {
        player?.stop()
        player = nil
    }

    static func logLoadFailure() {
        logger.error("Kokoro-82M failed to load. Text stays on screen. No fallback voice.")
    }

    /// Bundle-only. A missing starter model is a quiet failure, not a download.
    private static func loadBundledEngine() async -> Bool {
        #if canImport(KokoroTTS)
        if Bundle.main.url(forResource: "kokoro-82m-starter", withExtension: "bundle") != nil {
            return true
        }
        return false
        #else
        return false
        #endif
    }

    #if canImport(KokoroTTS)
    private func synthesizeWithPackage() async -> Bool {
        // Linked in a later iOS-target pin of kokoro-coreml. Until then the
        // canImport path is compile-time false and speak fails closed.
        return false
    }
    #endif
}
