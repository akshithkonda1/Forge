import Foundation

/// Decisions the Kokoro mouth makes before anything reaches a speaker.
///
/// This is the engine path `AriaKokoroRuntimeSynthesizer` drives. Empty or
/// all-zero PCM is a failed synthesis: ARIA stays silent and the text stays
/// on screen. A normal reply must produce playable samples. Synthesis that
/// returns empty audio is retried exactly once, then fails closed.
public enum AriaKokoroAudioPolicy: Sendable {
    public static let synthesisRetryLimit = 1

    /// Finite, non-zero PCM is the only thing we will play.
    public static func isPlayable(_ samples: [Float]) -> Bool {
        !samples.isEmpty && samples.contains { $0 != 0 && $0.isFinite }
    }

    public static func playableSamples(from samples: [Float]) -> [Float] {
        isPlayable(samples) ? samples : []
    }

    /// Empty audio is never scheduled. The reply is still shown as text.
    public static func shouldPlay(_ samples: [Float]) -> Bool {
        isPlayable(samples)
    }

    public static func decide(_ samples: [Float]) -> AriaKokoroSpeakDecision {
        isPlayable(samples) ? .play : .silentFailure
    }

    /// Real synthesis path: render, then retry empty PCM exactly once.
    ///
    /// Not a stub. Callers pass the Kokoro render (or a test double of that
    /// same render signature). Empty output never becomes a play.
    public static func synthesize(
        text: String,
        voiceID: String,
        speed: Double,
        render: (String, String, Double) async -> [Float]
    ) async -> [Float] {
        var samples = playableSamples(from: await render(text, voiceID, speed))
        if isPlayable(samples) { return samples }
        samples = playableSamples(from: await render(text, voiceID, speed))
        return samples
    }
}

public enum AriaKokoroSpeakDecision: Equatable, Sendable {
    /// Hand the PCM to the local player.
    case play
    /// Stay quiet. The line is already on screen.
    case silentFailure
}

/// Load + synthesize + play for one ARIA line. The iOS synthesizer owns this
/// value so tests and the device mouth cannot drift onto a stub path.
public struct AriaKokoroEnginePath: Equatable, Sendable {
    public var loadState = AriaKokoroLoadState()

    public init() {}

    public mutating func allowRetryAfterLoad() {
        loadState.allowRetryAfterLoad()
    }

    public mutating func prepare(
        modelPresent: Bool,
        load: () async -> Bool
    ) async -> Bool {
        if loadState.isReady { return true }
        guard loadState.shouldLoad(modelPresent: modelPresent) else {
            if !modelPresent { loadState.markMissing() }
            return false
        }
        let loaded = await load()
        if loaded {
            loadState.markLoaded()
        } else if modelPresent {
            loadState.markHardFailure()
        } else {
            loadState.markMissing()
        }
        return loaded
    }

    /// Returns `true` only when at least one playable chunk reached `play`.
    /// Empty PCM is a silent failure, never a play.
    public mutating func speak(
        _ text: String,
        voiceID: String,
        speed: Double,
        modelPresent: Bool,
        load: () async -> Bool,
        render: (String, String, Double) async -> [Float],
        play: ([Float]) async -> Bool
    ) async -> Bool {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return false }
        guard !AriaKokoroVoice.allowsNetworkAtSpeakTime else { return false }
        let ready = await prepare(modelPresent: modelPresent, load: load)
        guard ready else { return false }
        let segments = AriaKokoroLexicon.spokenSegments(in: line)
        guard !segments.isEmpty else { return false }
        var played = false
        for segment in segments {
            let samples = await AriaKokoroAudioPolicy.synthesize(
                text: segment,
                voiceID: voiceID,
                speed: speed,
                render: render
            )
            guard AriaKokoroAudioPolicy.shouldPlay(samples) else { continue }
            if await play(samples) { played = true }
        }
        return played
    }
}
