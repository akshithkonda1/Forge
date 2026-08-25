import Foundation
import AVFoundation
import Speech
import Combine

// MARK: - Voice Coach Manager

@MainActor
@Observable
final class VoiceCoachManager: NSObject {
    
    // MARK: - State
    
    var isListening: Bool = false
    var isSpeaking: Bool = false
    var isThinking: Bool = false
    var lastCoachMessage: String = ""
    var transcribedText: String = ""
    var error: String? = nil
    var isVoiceEnabled: Bool = true
    
    // MARK: - Private
    
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    // Silence detection
    private var silenceTimer: Timer?
    private let silenceThreshold: TimeInterval = 1.8
    
    // Context passed in from ActiveWorkoutView
    private var workoutContext: WorkoutContext = .empty
    
    // Conversation history for Claude
    private var conversationHistory: [[String: String]] = []
    
    // Forge's own backend. This used to be a direct POST to api.anthropic.com
    // with a key read from Info.plist — an extractable secret in any build that
    // set one, and a request that skipped auth, sanitization, the model router
    // and every cost control. Nothing on screen instantiates this manager today,
    // which made it easy to miss; the code still shipped in the binary, and dead
    // code is what gets wired up later without anyone re-auditing it.
    
    // MARK: - Init
    
    override init() {
        super.init()
        speechSynthesizer.delegate = self
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        setupAudioSession()
    }
    
    // MARK: - Public API
    
    /// Update workout context so Claude always has fresh data
    func updateContext(_ context: WorkoutContext) {
        self.workoutContext = context
    }
    
    /// Speak a proactive message at a key workout moment
    func announceWorkoutStart() {
        let msg = "Let's go. \(workoutContext.workoutName). First up — \(workoutContext.exerciseName). \(workoutContext.sets) sets of \(workoutContext.reps) at \(workoutContext.weight). Lock in."
        speak(msg)
    }
    
    func announceSetComplete(setNumber: Int, totalSets: Int, restSeconds: Int) {
        let isLast = setNumber >= totalSets
        if isLast {
            let msg = "Set \(setNumber) done. Moving on. Rest up."
            speak(msg)
        } else {
            let remaining = totalSets - setNumber
            let msg = "Set \(setNumber) down, \(remaining) to go. \(restSeconds) seconds."
            speak(msg)
        }
    }
    
    func announceRestOver(nextExerciseName: String) {
        speak("Rest over. \(nextExerciseName) — let's go.")
    }
    
    func announceWorkoutComplete(duration: String, calories: Int) {
        speak("That's a wrap. \(duration) of work, \(calories) calories burned. Well done.")
    }
    
    func announceHRWarning(hr: Int) {
        speak("Heart rate at \(hr). Take an extra 30 seconds before the next set.")
    }
    
    /// Start listening for user voice input
    func startListening() {
        guard isVoiceEnabled else { return }
        guard !audioEngine.isRunning else { return }
        
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard status == .authorized else { return }
            Task { @MainActor in
                self?.beginRecognition()
            }
        }
    }
    
    /// Stop listening
    func stopListening() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
        transcribedText = ""
    }
    
    /// Ask Claude anything with current workout context
    func askClaude(_ userMessage: String) async {
        guard isVoiceEnabled else { return }
        isThinking = true
        
        conversationHistory.append(["role": "user", "content": userMessage])
        trimConversationHistory()

        do {
            let response = try await askForge(userMessage)
            conversationHistory.append(["role": "assistant", "content": response])
            trimConversationHistory()
            lastCoachMessage = response
            isThinking = false
            speak(response)
        } catch {
            isThinking = false
            self.error = error.localizedDescription
        }
    }
    
    func toggleVoice() {
        isVoiceEnabled.toggle()
        if !isVoiceEnabled {
            stopListening()
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
    }
    
    func clearHistory() {
        conversationHistory = []
    }

    /// Mid-workout coaching only needs the last few exchanges; anything older
    /// just inflates every request. Keeps the window at 12 turns.
    private func trimConversationHistory() {
        let maxTurns = 12
        guard conversationHistory.count > maxTurns else { return }
        conversationHistory = Array(conversationHistory.suffix(maxTurns))
    }
    
    // MARK: - Private: Speech Recognition
    
    private func beginRecognition() {
        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        setupAudioSession()
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = false
        
        let inputNode = audioEngine.inputNode
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            
            if let result {
                let text = result.bestTranscription.formattedString
                Task { @MainActor in
                    self.transcribedText = text
                    self.resetSilenceTimer()
                }
            }
            
            if error != nil || (result?.isFinal == true) {
                Task { @MainActor in
                    self.stopListening()
                    if !self.transcribedText.isEmpty {
                        let captured = self.transcribedText
                        self.transcribedText = ""
                        await self.askClaude(captured)
                    }
                }
            }
        }
        
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        
        do {
            try audioEngine.start()
            isListening = true
        } catch {
            self.error = "Microphone error: \(error.localizedDescription)"
        }
    }
    
    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.transcribedText.isEmpty else { return }
                let captured = self.transcribedText
                self.stopListening()
                await self.askClaude(captured)
            }
        }
    }
    
    // MARK: - Private: TTS
    
    private func speak(_ text: String) {
        guard isVoiceEnabled else { return }
        
        // Don't interrupt — queue it
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .word)
        }
        
        lastCoachMessage = text
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.52          // Slightly faster than default — confident, not robotic
        utterance.pitchMultiplier = 0.95
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.1
        
        // Pause music/audio ducking
        try? AVAudioSession.sharedInstance().setCategory(
            .playback,
            options: [.duckOthers, .allowBluetoothA2DP]
        )
        
        speechSynthesizer.speak(utterance)
        isSpeaking = true
    }
    
    // MARK: - Private: ARIA backend

    /// One authenticated chat turn against Forge's own API.
    ///
    /// The system prompt is deliberately no longer sent from here. ARIA's
    /// persona and the security law live server-side in `live_system_prompt()`,
    /// so a client cannot define — or quietly drift from — the rules the model
    /// answers under. Conversation continuity is the server's job too, via the
    /// relationship/context engine; `conversationHistory` is kept only for the
    /// on-screen transcript.
    private func askForge(_ message: String) async throws -> String {
        guard let url = URL(string: "ai/chat", relativeTo: AriaService.shared.baseURL) else {
            throw CoachError.apiError("This build isn't pointed at a Forge server.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "message": message,
            "voice_mode": true,
            "context": ["workout": workoutContext.contextLine],
        ])

        let (data, _) = try await ForgeAPI.send(request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CoachError.parseError
        }
        let text = (json["message"] as? String) ?? (json["prose_summary"] as? String) ?? ""
        guard !text.isEmpty else { throw CoachError.parseError }
        return text
    }

    
    // MARK: - Audio Session
    
    private func setupAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(
            .playAndRecord,
            mode: .default,
            options: [.defaultToSpeaker, .allowBluetoothA2DP, .duckOthers]
        )
        try? AVAudioSession.sharedInstance().setActive(true)
    }
    
    // MARK: - Errors
    
    enum CoachError: Error {
        case apiError(String)
        case parseError
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension VoiceCoachManager: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            // Restore audio session for recording after speaking
            try? AVAudioSession.sharedInstance().setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetoothA2DP, .duckOthers]
            )
        }
    }
}

// MARK: - Workout Context

extension WorkoutContext {
    /// Facts for the server to reason over — not instructions for the model.
    ///
    /// The client used to send a full system prompt telling ARIA who to be. That
    /// belongs server-side with the security law, so all that travels now is the
    /// state of the set in front of the athlete.
    var contextLine: String {
        var parts: [String] = []
        if !workoutName.isEmpty { parts.append("Workout: \(workoutName)") }
        if !exerciseName.isEmpty { parts.append("Exercise: \(exerciseName)") }
        parts.append("Set \(currentSet) of \(sets)")
        if !weight.isEmpty || !reps.isEmpty { parts.append("\(weight) × \(reps)") }
        if !elapsedTime.isEmpty { parts.append("Elapsed \(elapsedTime)") }
        if heartRate > 0 { parts.append("HR \(heartRate) bpm (Zone \(hrZone))") }
        if restSeconds > 0 { parts.append("Rest \(restSeconds)s") }
        if !notes.isEmpty { parts.append("Notes: \(notes)") }
        return parts.joined(separator: " · ")
    }
}

struct WorkoutContext {
    var workoutName: String
    var exerciseName: String
    var currentSet: Int
    var sets: Int
    var reps: String
    var weight: String
    var elapsedTime: String
    var heartRate: Int
    var hrZone: Int
    var calories: Int
    var restSeconds: Int
    var notes: String
    
    static let empty = WorkoutContext(
        workoutName: "",
        exerciseName: "",
        currentSet: 1,
        sets: 1,
        reps: "",
        weight: "",
        elapsedTime: "00:00",
        heartRate: 0,
        hrZone: 1,
        calories: 0,
        restSeconds: 90,
        notes: ""
    )
}
