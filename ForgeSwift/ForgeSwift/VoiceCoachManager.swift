import Foundation
import AVFoundation
import Speech
import Combine

// MARK: - Voice Coach Manager

@MainActor
@Observable
final class VoiceCoachManager: NSObject {

    var isListening: Bool = false
    var isSpeaking: Bool = false
    var isThinking: Bool = false
    var lastCoachMessage: String = ""
    var transcribedText: String = ""
    var error: String? = nil
    var isVoiceEnabled: Bool = true

    private let speechSynthesizer = AVSpeechSynthesizer()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var silenceTimer: Timer?
    private let silenceThreshold: TimeInterval = 1.8
    private var workoutContext: WorkoutContext = .empty
    private let repository = ForgeRepository.shared

    override init() {
        super.init()
        speechSynthesizer.delegate = self
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        setupAudioSession()
    }

    func updateContext(_ context: WorkoutContext) {
        self.workoutContext = context
    }

    func announceWorkoutStart() {
        let msg = "Let's go. \(workoutContext.workoutName). First up — \(workoutContext.exerciseName). \(workoutContext.sets) sets of \(workoutContext.reps) at \(workoutContext.weight). Lock in."
        speak(msg)
    }

    func announceSetComplete(setNumber: Int, totalSets: Int, restSeconds: Int) {
        let isLast = setNumber >= totalSets
        if isLast {
            speak("Set \(setNumber) done. Moving on. Rest up.")
        } else {
            let remaining = totalSets - setNumber
            speak("Set \(setNumber) down, \(remaining) to go. \(restSeconds) seconds.")
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

    func askClaude(_ userMessage: String) async {
        guard isVoiceEnabled else { return }
        isThinking = true

        do {
            let response = try await repository.sendVoiceTranscript(userMessage)
            lastCoachMessage = response
            isThinking = false
            speak(response)
        } catch {
            isThinking = false
            let fallback = "Coach unavailable right now. Keep going — you've got this."
            lastCoachMessage = fallback
            speak(fallback)
        }
    }

    func toggleVoice() {
        isVoiceEnabled.toggle()
        if !isVoiceEnabled {
            stopListening()
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
    }

    private func beginRecognition() {
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

    private func speak(_ text: String) {
        guard isVoiceEnabled else { return }

        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .word)
        }

        lastCoachMessage = text

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.52
        utterance.pitchMultiplier = 0.95
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.1

        try? AVAudioSession.sharedInstance().setCategory(
            .playback,
            options: [.duckOthers, .allowBluetoothA2DP]
        )

        speechSynthesizer.speak(utterance)
        isSpeaking = true
    }

    private func setupAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(
            .playAndRecord,
            mode: .default,
            options: [.defaultToSpeaker, .allowBluetoothA2DP, .duckOthers]
        )
        try? AVAudioSession.sharedInstance().setActive(true)
    }
}

extension VoiceCoachManager: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            try? AVAudioSession.sharedInstance().setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetoothA2DP, .duckOthers]
            )
        }
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