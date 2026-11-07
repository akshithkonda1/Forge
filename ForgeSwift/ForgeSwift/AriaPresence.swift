import AVFoundation
import CoreGraphics
import Foundation
import Observation
import ForgeCore

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
enum ForgePlaybackSession: Equatable, Sendable {
    case spoken
    /// Workout mic stays live. Chat uses `.spoken` (playback-only).
    case spokenHandsFree
    case sleepMix
    case alarm
    case chime

    /// Hands-free Bluetooth bit. iOS 26's Swift overlay still names this
    /// `allowBluetooth` (deprecated); iOS 27 names it `allowBluetoothHFP`.
    /// Same raw value either way — never emit the deprecated symbol.
    static var bluetoothHFP: AVAudioSession.CategoryOptions {
        #if compiler(>=6.4)
        .allowBluetoothHFP
        #else
        AVAudioSession.CategoryOptions(rawValue: 0x4)
        #endif
    }

    func activate() async throws {
        let session = AVAudioSession.sharedInstance()
        switch self {
        case .spoken:
            try session.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
            )
        case .spokenHandsFree:
            #if compiler(>=6.4)
            try session.setCategory(
                .playAndRecord,
                mode: .spokenAudio,
                options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP, .duckOthers]
            )
            #else
            try session.setCategory(
                .playAndRecord,
                mode: .spokenAudio,
                options: [.defaultToSpeaker, Self.bluetoothHFP, .allowBluetoothA2DP, .duckOthers]
            )
            #endif
        case .sleepMix, .chime:
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        case .alarm:
            try session.setCategory(.playback, mode: .default, options: [])
        }
        try await Self.setSessionActive(true)
    }

    static func deactivate() {
        Task {
            try? await setSessionActive(false, notifyOthers: true)
        }
    }

    /// iOS 26/27: `setActive` on the main thread hangs the UI. Use the async
    /// activate/deactivate overlay instead.
    static func setSessionActive(_ active: Bool, notifyOthers: Bool = false) async throws {
        let session = AVAudioSession.sharedInstance()
        #if compiler(>=6.4)
        if active {
            _ = try await session.activate(options: [])
        } else {
            let options: AVAudioSessionDeactivationOptions = notifyOthers
                ? [.notifyOthersOnDeactivation]
                : []
            _ = try await session.deactivate(options: options)
        }
        #else
        if active {
            try session.setActive(true)
        } else if notifyOthers {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } else {
            try session.setActive(false)
        }
        #endif
    }
}

/// App-wide ARIA voice presence. Welcome, chat, Train “show me how”, and the
/// tab mark all read this so the same Aurora orb moves when she talks.
/// Playback is Kokoro only. There is no `AVSpeechSynthesizer`.
@MainActor
@Observable
final class AriaPresence {
    static let shared = AriaPresence()

    /// Kokoro-82M is ARIA's only voice. `AVSpeechSynthesizer` is never a
    /// fallback mouth and never receives `speak(_:)`.
    static let appleFallbackPlaybackEnabled = false

    private(set) var isSpeaking = false
    private(set) var isListening = false
    private(set) var isThinking = false
    private(set) var didPlayWelcomeChime = false
    var amplitude: Float = 0.18

    var orbState: AROrbState {
        if isSpeaking { return .speaking }
        if isListening { return .listening }
        if isThinking { return .processing }
        return .idle
    }

    /// Held only so a leftover Apple engine from an older session can be
    /// stopped. Nothing in this type allocates or calls `speak(_:)` on it.
    @ObservationIgnored
    private var synthesizerStorage: AVSpeechSynthesizer?
    @ObservationIgnored
    private var kokoroGeneration = 0

    private init() {}

    func setListening(_ on: Bool) { isListening = on }
    func setThinking(_ on: Bool) { isThinking = on }
    func markSpeaking(_ on: Bool) { isSpeaking = on }

    /// Hero marks call this on appear. Tab-sized marks never chime.
    func playWelcomeChimeIfNeeded(size: CGFloat, reduceMotion: Bool) {
        let quiet = AriaContextStore.shared.context.lifestyleTags.contains("quiet_mode:true")
            || AriaContextStore.shared.context.constraints.contains("quiet_mode:true")
        guard AriaWelcomeChime.shouldPlay(
            size: size,
            reduceMotion: reduceMotion,
            quietMode: quiet,
            alreadyPlayed: didPlayWelcomeChime,
            isSpeaking: isSpeaking
        ) else { return }
        didPlayWelcomeChime = true
        Task { @MainActor in
            await Task.yield()
            AriaWelcomeChime.play()
        }
    }

    /// Speaks `text` with on-device Kokoro. There is no cloud mouth and no
    /// Apple fallback. If the engine cannot load, the text stays on screen.
    ///
    /// Pass `interrupt: false` to queue behind a line that is already playing.
    func speak(
        _ text: String,
        interrupt: Bool = true,
        stopAt: AVSpeechBoundary = .immediate,
        session: ForgePlaybackSession = .spoken
    ) {
        _ = stopAt
        guard AriaSpokenMute.allowsSpeech else { return }
        guard AriaSpeechPrep.spokenLine(in: text) != nil else { return }
        guard AriaVoiceMouth.shouldEnqueueKokoro(
            isMuted: false,
            sessionActive: AriaVoiceSession.shared.isActive
        ) || AriaVoiceSession.shared.isActive == false else { return }
        // Settings preview and onboarding may speak without a voice session.
        let sessionActive = AriaVoiceSession.shared.isActive
        if sessionActive && !AriaVoiceMouth.shouldEnqueueKokoro(isMuted: false, sessionActive: true) {
            return
        }
        if interrupt {
            synthesizerStorage?.stopSpeaking(at: .immediate)
            AriaKokoroEngine.stop()
        }
        kokoroGeneration += 1
        let generation = kokoroGeneration
        isSpeaking = true
        let config = AriaVoiceMouth.currentKokoroConfig()
        Task { @MainActor in
            try? await session.activate()
            let started = await AriaKokoroEngine.speak(
                text,
                voiceID: config.voiceID,
                speed: config.speed
            )
            guard generation == kokoroGeneration else { return }
            if started {
                return
            }
            // Kokoro failed: leave the text on screen. Never allocate or
            // speak() AVSpeechSynthesizer — Apple TTS is not a fallback.
            isSpeaking = false
            if !started {
                AriaVoiceProfileStore.shared.noteBusy(true)
            }
            AriaVoiceSession.shared.mouthDidFinish()
        }
    }

    func stopSpeaking() {
        kokoroGeneration += 1
        AriaKokoroEngine.stop()
        synthesizerStorage?.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    /// `AVSpeechSynthesizer.isSpeaking` without allocating. Nil storage is
    /// a Kokoro-only session — never create the Apple engine to ask.
    var appleSynthesizerIsSpeaking: Bool {
        synthesizerStorage?.isSpeaking ?? false
    }

    /// XCTest: a Kokoro-only session must leave this nil after stop / isSpeaking.
    var synthesizerStorageForTests: AVSpeechSynthesizer? { synthesizerStorage }

    func resetSynthesizerStorageForTests() {
        synthesizerStorage?.stopSpeaking(at: .immediate)
        synthesizerStorage?.delegate = nil
        synthesizerStorage = nil
        isSpeaking = false
    }
}
