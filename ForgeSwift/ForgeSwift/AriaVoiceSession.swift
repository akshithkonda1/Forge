import AVFoundation
import Foundation

/// Character voice session. Unmute / the voice orb start this.
///
/// Transport uses the same two gates as `AriaService.sendMessage`, in the same
/// order, and never silently upgrades dummy → cloud. Dummy and local testing
/// stay on-device (SpeechManager STT + dummy/local brain via chat). Live opens
/// ElevenLabs ConvAI with a short-lived signed URL from Forge — the API key
/// never lands on the phone.
@MainActor
@Observable
final class AriaVoiceSession {
    static let shared = AriaVoiceSession()

    enum Phase: Equatable, Sendable {
        case idle, listening, thinking, speaking
    }

    private(set) var isActive = false
    private(set) var transport: AriaVoiceTransport?
    private(set) var phase: Phase = .idle
    private(set) var lastError: String?

    @ObservationIgnored
    private weak var store: AppStore?
    @ObservationIgnored
    private weak var speech: SpeechManager?
    @ObservationIgnored
    private var liveSocket: AriaLiveConvAIClient?
    @ObservationIgnored
    private var startGeneration = 0
    @ObservationIgnored
    private var capturesMic = false

    var activeTransport: AriaVoiceTransport? { isActive ? transport : nil }

    private init() {}

    func start(store: AppStore, speech: SpeechManager, captureMic: Bool = true) {
        if isActive, self.store === store, self.speech === speech {
            if captureMic { capturesMic = true }
            if captureMic, transport?.usesOnDeviceBrain == true {
                speech.startListening()
            }
            return
        }
        stop()
        self.store = store
        self.speech = speech
        capturesMic = captureMic
        let chosen = AriaVoiceTransport.resolveCurrent()
        transport = chosen
        isActive = true
        lastError = nil
        startGeneration += 1
        let generation = startGeneration
        applyPhase(captureMic ? .listening : .thinking)

        if chosen.requiresNetwork, AriaSpokenMute.allowsSpeech {
            Task { await self.startLive(generation: generation) }
            return
        }

        // Dummy, local testing, or muted-live (text via STT, no ConvAI).
        if captureMic {
            speech.startListening()
        }
    }

    func stop() {
        startGeneration += 1
        liveSocket?.close()
        liveSocket = nil
        capturesMic = false
        speech?.cancel()
        isActive = false
        transport = nil
        applyPhase(.idle)
        AriaPresence.shared.setListening(false)
        AriaPresence.shared.setThinking(false)
        AriaPresence.shared.stopSpeaking()
    }

    func mute() {
        liveSocket?.close()
        liveSocket = nil
        AriaPresence.shared.stopSpeaking()
        if isActive {
            applyPhase(.listening)
        }
    }

    func unmute() {
        guard isActive, let transport else { return }
        guard AriaSpokenMute.allowsSpeech else { return }
        if transport.requiresNetwork {
            startGeneration += 1
            let generation = startGeneration
            speech?.cancel()
            Task { await self.startLive(generation: generation) }
        }
    }

    /// After chat lands a trainer reply on dummy/local, play the DEBUG fill-in.
    /// Live ConvAI is already the mouth — do not also enqueue Apple TTS.
    func speakChatReply(_ reply: AriaResponse) {
        guard isActive else { return }
        guard AriaSpokenMute.allowsSpeech else { return }
        let line = AriaVoiceMouth.spokenLine(from: reply)
        guard !line.isEmpty else { return }
        applyPhase(.speaking)
        speech?.voiceState = .speaking
        AriaPresence.shared.speak(line)
        if transport?.requiresNetwork == true {
            // ConvAI is the mouth. Apple fill-in did not run.
            return
        }
        if !AriaPresence.shared.isSpeaking {
            markListening()
        }
    }

    /// Dummy fill-in finished (or was silent). Resume listening for the next turn.
    func mouthDidFinish() {
        guard isActive, phase == .speaking else { return }
        guard transport?.usesOnDeviceBrain == true else { return }
        markListening()
    }

    func markThinking() {
        guard isActive else { return }
        applyPhase(.thinking)
        speech?.voiceState = .processing
    }

    func markListening() {
        guard isActive else { return }
        applyPhase(.listening)
        speech?.voiceState = .listening
        if capturesMic, transport?.usesOnDeviceBrain == true {
            speech?.startListening()
        }
    }

    private func applyPhase(_ phase: Phase) {
        self.phase = phase
        switch phase {
        case .idle:
            AriaPresence.shared.setListening(false)
            AriaPresence.shared.setThinking(false)
        case .listening:
            AriaPresence.shared.setThinking(false)
            AriaPresence.shared.setListening(true)
        case .thinking:
            AriaPresence.shared.setListening(false)
            AriaPresence.shared.setThinking(true)
        case .speaking:
            AriaPresence.shared.setListening(false)
            AriaPresence.shared.setThinking(false)
            AriaPresence.shared.markSpeaking(true)
        }
    }

    private func startLive(generation: Int) async {
        applyPhase(.thinking)
        do {
            let bootstrap = try await Self.fetchLiveBootstrap()
            guard generation == startGeneration else { return }
            if let key = ProcessInfo.processInfo.environment["ELEVENLABS_API_KEY"],
               AriaVoiceBootstrap.signedURLLooksLikeAPIKey(bootstrap.signedURL, apiKey: key) {
                throw AriaVoiceSessionError.leakedAPIKey
            }
            guard let url = URL(string: bootstrap.signedURL),
                  url.scheme == "wss" || url.scheme == "ws" else {
                throw AriaVoiceSessionError.invalidSignedURL
            }
            let client = AriaLiveConvAIClient()
            liveSocket = client
            try await client.connect(
                signedURL: url,
                promptContext: bootstrap.promptContext,
                onEvent: { [weak self] event in
                    Task { @MainActor in
                        self?.handleLiveEvent(event, generation: generation)
                    }
                }
            )
            guard generation == startGeneration else {
                client.close()
                return
            }
            applyPhase(.listening)
            speech?.voiceState = .listening
        } catch {
            guard generation == startGeneration else { return }
            // Live failure is silence — never Zoe, never a dummy upgrade.
            lastError = "Voice session unavailable."
            liveSocket?.close()
            liveSocket = nil
            applyPhase(.idle)
            speech?.voiceState = .idle
        }
    }

    private func handleLiveEvent(_ event: AriaLiveConvAIClient.Event, generation: Int) {
        guard generation == startGeneration, isActive else { return }
        switch event {
        case .userTranscript(let text):
            speech?.recognizedText = text
        case .agentTranscript:
            applyPhase(.speaking)
            speech?.voiceState = .speaking
        case .audio:
            applyPhase(.speaking)
            speech?.voiceState = .speaking
            AriaPresence.shared.markSpeaking(true)
        case .interrupted:
            AriaPresence.shared.stopSpeaking()
            applyPhase(.listening)
            speech?.voiceState = .listening
        case .toolCall(let call):
            Task { await self.runLiveTool(call, generation: generation) }
        case .ping:
            break
        case .closed:
            if generation == startGeneration {
                applyPhase(.idle)
                speech?.voiceState = .idle
                AriaPresence.shared.markSpeaking(false)
            }
        }
    }

    private func runLiveTool(_ call: AriaLiveConvAIClient.ToolCall, generation: Int) async {
        applyPhase(.thinking)
        speech?.voiceState = .processing
        do {
            let result = try await Self.postVoiceTool(message: call.message)
            guard generation == startGeneration else { return }
            liveSocket?.sendToolResult(callID: call.id, result: result, isError: false)
            applyPhase(.speaking)
        } catch {
            guard generation == startGeneration else { return }
            liveSocket?.sendToolResult(callID: call.id, result: "unavailable", isError: true)
            applyPhase(.listening)
            speech?.voiceState = .listening
        }
    }

    static func fetchLiveBootstrap() async throws -> AriaVoiceLiveBootstrap {
        let url = AriaService.shared.baseURL.appendingPathComponent("ai/voice/bootstrap")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, _) = try await ForgeAPI.send(request)
        let decoded = try JSONDecoder().decode(AriaVoiceLiveBootstrap.self, from: data)
        if decoded.signedURL.isEmpty {
            throw AriaVoiceSessionError.invalidSignedURL
        }
        return decoded
    }

    static func postVoiceTool(message: String) async throws -> String {
        let url = AriaService.shared.baseURL.appendingPathComponent("ai/voice/tool")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(VoiceToolRequest(message: message))
        let (data, _) = try await ForgeAPI.send(request)
        let payload = try JSONDecoder().decode(VoiceToolResponse.self, from: data)
        let result = payload.result?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !result.isEmpty { return result }
        return payload.proseSummary ?? payload.message ?? ""
    }
}

enum AriaVoiceSessionError: Error {
    case leakedAPIKey
    case invalidSignedURL
}

private struct VoiceToolRequest: Encodable {
    var message: String
}

private struct VoiceToolResponse: Decodable {
    var result: String?
    var proseSummary: String?
    var message: String?

    enum CodingKeys: String, CodingKey {
        case result
        case proseSummary = "prose_summary"
        case message
    }
}

/// Sends ConvAI mic frames off the main actor so each audio quantum does not
/// hop to MainActor for base64 + JSON.
private actor ConvAIMicSender {
    private weak var task: URLSessionWebSocketTask?

    func attach(_ task: URLSessionWebSocketTask?) {
        self.task = task
    }

    func sendPCM(_ data: Data) async {
        let b64 = data.base64EncodedString()
        guard let payload = try? JSONSerialization.data(withJSONObject: ["user_audio_chunk": b64]),
              let text = String(data: payload, encoding: .utf8),
              let task else { return }
        try? await task.send(.string(text))
    }
}

/// ElevenLabs ConvAI WebSocket. Lives here so `AriaCharacterVoice` stays
/// network-free. Dummy transport never constructs this.
@MainActor
final class AriaLiveConvAIClient: NSObject, URLSessionWebSocketDelegate {
    enum Event {
        case userTranscript(String)
        case agentTranscript(String)
        case audio
        case interrupted
        case toolCall(ToolCall)
        case ping
        case closed
    }

    struct ToolCall {
        var id: String
        var message: String
    }

    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var onEvent: ((Event) -> Void)?
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private let outFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)
    private let micSender = ConvAIMicSender()

    func connect(
        signedURL: URL,
        promptContext: String?,
        onEvent: @escaping (Event) -> Void
    ) async throws {
        self.onEvent = onEvent
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session
        let task = session.webSocketTask(with: signedURL)
        self.task = task
        await micSender.attach(task)
        task.resume()
        try await sendJSON([
            "type": "conversation_initiation_client_data",
            "conversation_config_override": [
                "agent": [
                    "prompt": [
                        "prompt": promptContext ?? ""
                    ]
                ]
            ]
        ])
        listen()
        try startMic()
    }

    func sendToolResult(callID: String, result: String, isError: Bool) {
        Task {
            try? await sendJSON([
                "type": "client_tool_result",
                "tool_call_id": callID,
                "result": result,
                "is_error": isError
            ])
        }
    }

    func close() {
        stopMic()
        Task { await micSender.attach(nil) }
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
        onEvent?(.closed)
        onEvent = nil
        AriaPresence.shared.markSpeaking(false)
    }

    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        Task { @MainActor in
            self.onEvent?(.closed)
        }
    }

    private func listen() {
        task?.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .failure:
                    self.onEvent?(.closed)
                case .success(let message):
                    self.handle(message)
                    self.listen()
                }
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .data(let d): data = d
        case .string(let s): data = Data(s.utf8)
        @unknown default: return
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let type = obj["type"] as? String ?? ""
        switch type {
        case "ping":
            if let event = obj["ping_event"] as? [String: Any], let eventID = event["event_id"] {
                Task { try? await sendJSON(["type": "pong", "event_id": eventID]) }
            }
            onEvent?(.ping)
        case "user_transcript":
            let text = ((obj["user_transcription_event"] as? [String: Any])?["user_transcript"] as? String) ?? ""
            if !text.isEmpty { onEvent?(.userTranscript(text)) }
        case "agent_response":
            let text = ((obj["agent_response_event"] as? [String: Any])?["agent_response"] as? String) ?? ""
            if !text.isEmpty { onEvent?(.agentTranscript(text)) }
        case "audio":
            if let event = obj["audio_event"] as? [String: Any],
               let b64 = event["audio_base_64"] as? String {
                playBase64Audio(b64)
            }
            onEvent?(.audio)
        case "interruption":
            player?.stop()
            onEvent?(.interrupted)
        case "client_tool_call":
            if let call = obj["client_tool_call"] as? [String: Any] {
                let id = call["tool_call_id"] as? String ?? UUID().uuidString
                let params = call["parameters"] as? [String: Any] ?? [:]
                let message = params["message"] as? String
                    ?? params["query"] as? String
                    ?? ""
                onEvent?(.toolCall(ToolCall(id: id, message: message)))
            }
        default:
            break
        }
    }

    private func sendJSON(_ payload: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let text = String(data: data, encoding: .utf8), let task else { return }
        try await task.send(.string(text))
    }

    private func startMic() throws {
        let engine = AVAudioEngine()
        try ForgePlaybackSession.spokenHandsFree.activate()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            throw AriaVoiceSessionError.invalidSignedURL
        }
        input.removeTap(onBus: 0)
        #if compiler(>=6.4)
        try input.installAudioTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            let pcm = AVAudioPCMBuffer(copying: buffer)
            guard let data = AriaLiveConvAIClient.int16MonoData(from: pcm) else { return }
            Task { @MainActor in
                self?.sendBase64Chunk(data)
            }
        }
        #else
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let data = AriaLiveConvAIClient.int16MonoData(from: buffer) else { return }
            Task { await sender.sendPCM(data) }
        }
        #endif
        let player = AVAudioPlayerNode()
        engine.attach(player)
        #if compiler(>=6.4)
        if let outFormat {
            try engine.connectNode(player, to: engine.mainMixerNode, format: outFormat)
        } else {
            try engine.connectNode(player, to: engine.mainMixerNode, format: nil)
        }
        #else
        if let outFormat {
            engine.connect(player, to: engine.mainMixerNode, format: outFormat)
        } else {
            engine.connect(player, to: engine.mainMixerNode, format: nil)
        }
        #endif
        engine.prepare()
        try engine.start()
        #if compiler(>=6.4)
        try player.playAudio()
        #else
        player.play()
        #endif
        self.engine = engine
        self.player = player
    }

    private func stopMic() {
        engine?.inputNode.removeTap(onBus: 0)
        player?.stop()
        engine?.stop()
        engine = nil
        player = nil
    }

    private func playBase64Audio(_ b64: String) {
        guard let data = Data(base64Encoded: b64), let outFormat, let player else { return }
        let frameCount = AVAudioFrameCount(data.count / 2)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount
        data.withUnsafeBytes { raw in
            if let dst = buffer.int16ChannelData?[0], let src = raw.bindMemory(to: Int16.self).baseAddress {
                dst.update(from: src, count: Int(frameCount))
            }
        }
        player.scheduleBuffer(buffer, completionHandler: nil)
        AriaPresence.shared.markSpeaking(true)
    }

    nonisolated private static func int16MonoData(from buffer: AVAudioPCMBuffer) -> Data? {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return nil }
        if let ch = buffer.int16ChannelData {
            return Data(bytes: ch[0], count: frames * 2)
        }
        if let ch = buffer.floatChannelData {
            var out = [Int16](repeating: 0, count: frames)
            let src = ch[0]
            for i in 0..<frames {
                let clamped = max(-1, min(1, src[i]))
                out[i] = Int16(clamped * Float(Int16.max))
            }
            return out.withUnsafeBytes { Data($0) }
        }
        return nil
    }
}
