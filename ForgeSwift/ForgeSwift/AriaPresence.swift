import AVFoundation
import Observation
import UIKit

enum AROrbState: Equatable, Sendable {
    case idle, listening, processing, speaking
}

/// Clips ARIA's spoken lines before they hit the synthesizer. Pure so tests
/// can pin empty input and the 900-character ceiling without spinning audio.
enum AriaSpeechPrep: Sendable {
    static let characterLimit = 900

    static func clipped(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(characterLimit))
    }
}

/// Playback categories used by ARIA speech, sleep soundscapes, and the wake alarm.
/// One place so those three cannot drift into incompatible session options.
enum ForgePlaybackSession: Sendable {
    case spoken
    case sleepMix
    case alarm

    func activate() throws {
        let session = AVAudioSession.sharedInstance()
        switch self {
        case .spoken:
            try session.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
            )
        case .sleepMix:
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        case .alarm:
            try session.setCategory(.playback, mode: .default, options: [])
        }
        try session.setActive(true)
    }

    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// App-wide ARIA voice presence. Welcome, chat, Train “show me how”, and the
/// tab mark all read this so the same Aurora orb moves when she talks.
@MainActor
@Observable
final class AriaPresence: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = AriaPresence()

    private(set) var isSpeaking = false
    private(set) var isListening = false
    private(set) var isThinking = false
    var amplitude: Float = 0.18

    var orbState: AROrbState {
        if isSpeaking { return .speaking }
        if isListening { return .listening }
        if isThinking { return .processing }
        return .idle
    }

    @ObservationIgnored
    private let synthesizer = AVSpeechSynthesizer()

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    func setListening(_ on: Bool) { isListening = on }
    func setThinking(_ on: Bool) { isThinking = on }
    func markSpeaking(_ on: Bool) { isSpeaking = on }

    func speak(_ text: String) {
        guard let clipped = AriaSpeechPrep.clipped(text) else { return }
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: clipped)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        if UIAccessibility.isVoiceOverRunning {
            utterance.prefersAssistiveTechnologySettings = true
        } else {
            utterance.rate = 0.52
            utterance.pitchMultiplier = 0.95
        }
        try? ForgePlaybackSession.spoken.activate()
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.isSpeaking = false }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.isSpeaking = false }
    }
}
