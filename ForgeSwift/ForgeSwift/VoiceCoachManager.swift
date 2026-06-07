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
    
    private let repository = ForgeRepository.shared

    // Anthropic API fallback
    private let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let apiKey: String = {
        // In production: load from Keychain or environment
        // For now: set via Info.plist key "ANTHROPIC_API_KEY"
        Bundle.main.infoDictionary?["ANTHROPIC_API_KEY"] as? String ?? ""
    }()
    
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
        
        do {
            let response = try await fetchCoachResponse(for: userMessage)
            conversationHistory.append(["role": "assistant", "content": response])
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
    
    // MARK: - Private: Coach API

    private func fetchCoachResponse(for userMessage: String) async throws -> String {
        do {
            return try await repository.sendVoiceTranscript(userMessage)
        } catch {
            return try await callClaude(messages: conversationHistory)
        }
    }

    // MARK: - Private: Claude API fallback

    private func callClaude(messages: [[String: String]]) async throws -> String {
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        let body: [String: Any] = [
            "model": "claude-sonnet-4-5",
            "max_tokens": 150,              // Keep responses short — this is voice
            "system": systemPrompt,
            "messages": messages
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw CoachError.apiError("API returned non-200")
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let first = content.first,
              let text = first["text"] as? String else {
            throw CoachError.parseError
        }
        
        return text
    }
    
    private var systemPrompt: String {
        """
        You are Forge, an elite AI fitness coach speaking to an athlete mid-workout. Your personality: direct, motivating, knowledgeable. Like a world-class personal trainer in their ear.

        Current workout context:
        - Workout: \(workoutContext.workoutName)
        - Exercise: \(workoutContext.exerciseName)
        - Set: \(workoutContext.currentSet) of \(workoutContext.sets)
        - Weight: \(workoutContext.weight) lbs × \(workoutContext.reps) reps
        - Elapsed time: \(workoutContext.elapsedTime)
        - Heart rate: \(workoutContext.heartRate) bpm (Zone \(workoutContext.hrZone))
        - Calories burned: \(workoutContext.calories)
        - Rest time: \(workoutContext.restSeconds)s between sets
        - Exercise notes: \(workoutContext.notes)

        Rules:
        - Respond in 1-3 sentences MAX. This is voice — brevity is everything.
        - No markdown, no lists, no formatting of any kind.
        - Be specific to the exercise and current context, not generic.
        - For form questions, give one concrete, actionable cue.
        - For pain/discomfort, take it seriously and advise accordingly.
        - Match the athlete's energy — if they're crushing it, match that intensity.
        - Never say "Great question!" or any filler. Get straight to it.
        """
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
