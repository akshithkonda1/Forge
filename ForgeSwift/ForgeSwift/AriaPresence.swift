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
@MainActor
@Observable
final class AriaPresence: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = AriaPresence()

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

    @ObservationIgnored
    private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored
    private var fishPlayer: AVAudioPlayer?
    @ObservationIgnored
    private var fishGeneration = 0

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

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

    /// Speaks `text` as the dummy/local fill-in while a character session is
    /// active. Production live ARIA is ConvAI — this never enqueues Apple TTS
    /// as her live mouth. Onboarding, welcome, and Train stay quiet until a
    /// voice session starts or they unmute.
    ///
    /// Pass `interrupt: false` to queue behind a line that is already playing.
    func speak(
        _ text: String,
        interrupt: Bool = true,
        stopAt: AVSpeechBoundary = .immediate,
        session: ForgePlaybackSession = .spoken
    ) {
        guard AriaSpokenMute.allowsSpeech else { return }
        guard AriaSpeechPrep.spokenLine(in: text) != nil else { return }
        let fish = AriaVoiceMouth.currentFishAudioConfig()
        if AriaVoiceMouth.shouldEnqueueFishAudio(isMuted: false, hasKey: fish.isConfigured) {
            speakViaFishAudio(text, config: fish, interrupt: interrupt, session: session)
            return
        }
        if AriaVoiceMouth.shouldEnqueueFishAudioViaBackend(
            isMuted: false,
            hasLocalKey: fish.isConfigured,
            backendReachable: AriaFishAudioVoice.isBackendReachable(AriaService.shared.baseURL)
        ) {
            speakViaFishAudioBackend(text, interrupt: interrupt, session: session)
            return
        }
        let transport = AriaVoiceSession.shared.activeTransport
        guard AriaVoiceMouth.shouldEnqueueAppleUtterance(
            isMuted: false,
            sessionActive: AriaVoiceSession.shared.isActive,
            transport: transport
        ) else { return }
        guard AriaSpokenVoice.hasInstalledIdentity() else {
            AriaNeuralVoiceGate.shared.requestPromptIfNeeded()
            return
        }
        let started = AriaSpeechPrep.enqueue(
            text,
            on: synthesizer,
            interrupt: interrupt,
            stopAt: stopAt,
            session: session
        )
        guard started else { return }
        isSpeaking = true
    }

    func stopSpeaking() {
        fishGeneration += 1
        fishPlayer?.stop()
        fishPlayer = nil
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    /// Local Fish key (Dummy / Device Hub). Failure stays silent.
    private func speakViaFishAudio(
        _ text: String,
        config: AriaFishAudioVoice.Config,
        interrupt: Bool,
        session: ForgePlaybackSession
    ) {
        guard let request = AriaFishAudioVoice.makeRequest(text: text, config: config) else { return }
        playFishAudio(request: request, interrupt: interrupt, session: session, viaBackend: false)
    }

    /// Hex: Lambda holds `FISH_AUDIO_API_KEY`. Dummy-offline never reaches here.
    private func speakViaFishAudioBackend(
        _ text: String,
        interrupt: Bool,
        session: ForgePlaybackSession
    ) {
        guard let request = AriaFishAudioVoice.makeBackendRequest(
            text: text,
            baseURL: AriaService.shared.baseURL
        ) else { return }
        playFishAudio(request: request, interrupt: interrupt, session: session, viaBackend: true)
    }

    private func playFishAudio(
        request: URLRequest,
        interrupt: Bool,
        session: ForgePlaybackSession,
        viaBackend: Bool
    ) {
        if interrupt {
            synthesizer.stopSpeaking(at: .immediate)
            fishPlayer?.stop()
            fishPlayer = nil
        }
        fishGeneration += 1
        let generation = fishGeneration
        isSpeaking = true
        Task { @MainActor in
            try? await session.activate()
            do {
                let data: Data
                if viaBackend {
                    let (payload, _) = try await ForgeAPI.send(request)
                    guard generation == fishGeneration else { return }
                    guard let speech = AriaFishAudioVoice.decodeBackendSpeech(payload) else {
                        isSpeaking = false
                        return
                    }
                    data = speech.audio
                } else {
                    let (payload, response) = try await URLSession.shared.data(for: request)
                    guard generation == fishGeneration else { return }
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200, !payload.isEmpty else {
                        isSpeaking = false
                        return
                    }
                    data = payload
                }
                let player = try AVAudioPlayer(data: data)
                player.prepareToPlay()
                fishPlayer = player
                player.play()
                let nanos = UInt64(max(0.35, player.duration) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                guard generation == fishGeneration else { return }
                if fishPlayer === player {
                    fishPlayer = nil
                    isSpeaking = false
                    AriaVoiceSession.shared.mouthDidFinish()
                }
            } catch {
                guard generation == fishGeneration else { return }
                isSpeaking = false
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            // A queued interview line may still be in the synthesizer.
            if !self.synthesizer.isSpeaking {
                self.isSpeaking = false
                AriaVoiceSession.shared.mouthDidFinish()
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if !self.synthesizer.isSpeaking { self.isSpeaking = false }
        }
    }
}
