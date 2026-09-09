import SwiftUI
import AVFoundation
import Speech
import os

/// Shared dictation engine for Chat + Onboarding.
/// Partial results stream into `recognizedText`; silence or stop finalizes.
@MainActor
final class SpeechManager: ObservableObject {
    @Published var recognizedText: String = ""
    @Published var amplitude: Float = 0.0
    @Published var voiceState: VoiceState = .idle
    @Published var authorizationDenied = false

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var silenceTimer: Timer?
    private var levelTimer: Timer?
    /// Audio-thread gate so amplitude does not hop to MainActor every quantum.
    nonisolated private let amplitudePublishLock = OSAllocatedUnfairLock(initialState: TimeInterval(0))
    nonisolated static let amplitudePublishInterval: TimeInterval = 0.12

    /// ARIA's current mood, mirrored in so dictation paces itself to the
    /// conversation. Calm/supportive moments mean the user is more likely to be
    /// thinking mid-sentence, so we wait longer before deciding they're done.
    var conversationalMood: ARIAMood = .focused

    /// Rolling average of how long the user's utterances run, in words. Someone
    /// who speaks in long thoughts gets a longer grace period than someone
    /// firing off three-word commands.
    private var averageUtteranceWords: Double = 0
    private var utteranceSampleCount: Int = 0

    private var silenceThreshold: TimeInterval {
        var threshold: TimeInterval = {
            switch conversationalMood {
            case .calm, .pushed: return 2.1
            case .focused:       return 1.7
            case .energized:     return 1.45
            }
        }()
        // Long-form speakers pause mid-thought; give them up to ~0.5s more.
        if averageUtteranceWords > 12 {
            threshold += min(0.5, (averageUtteranceWords - 12) * 0.04)
        }
        return min(2.6, threshold)
    }

    private func recordUtteranceLength(_ text: String) {
        let words = Double(text.split(separator: " ").count)
        guard words > 0 else { return }
        utteranceSampleCount += 1
        // Exponential moving average — recent speaking style dominates.
        averageUtteranceWords = utteranceSampleCount == 1
            ? words
            : (averageUtteranceWords * 0.7) + (words * 0.3)
    }

    /// When true, stopListening will not clear recognizedText (caller consumes it).
    private var preserveTranscriptOnStop = false

    var isListening: Bool { voiceState == .listening }

    /// Speak an ARIA reply when the chat orb is in voice mode.
    func speak(_ text: String) {
        AriaPresence.shared.setListening(false)
        AriaPresence.shared.speak(text)
    }

    func startListening() {
        guard speechRecognizer?.isAvailable != false else {
            voiceState = .error("Speech unavailable")
            return
        }

        // Playback and record cannot share the session. If ARIA is mid-line,
        // cut her off so the mic can take the hardware — that's a conversation.
        AriaPresence.shared.stopSpeaking()
        AriaPresence.shared.setThinking(false)

        // Tear down any prior session cleanly
        hardStop(clearText: true)
        recognizedText = ""
        authorizationDenied = false
        voiceState = .listening
        AriaPresence.shared.setListening(true)
        amplitude = 0.15

        Task { [weak self] in
            let status = await Self.requestSpeechAuthorization()
            guard let self else { return }
            switch status {
            case .authorized:
                await self.beginRecognition()
            case .denied, .restricted:
                self.authorizationDenied = true
                self.voiceState = .error("Mic / speech access needed")
            case .notDetermined:
                self.voiceState = .idle
            @unknown default:
                self.voiceState = .idle
            }
        }
    }

    /// Stop listening. If `submit` is true and text exists, leaves `recognizedText` set
    /// and briefly moves through `.processing` → `.idle` so UI can react.
    func stopListening(submit: Bool = true) {
        silenceTimer?.invalidate()
        silenceTimer = nil
        preserveTranscriptOnStop = submit && !recognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if preserveTranscriptOnStop {
            recordUtteranceLength(recognizedText)
            voiceState = .processing
            hardStop(clearText: false)
            FDS.notificationHaptic(.success)
            // Deliver final idle so overlays can fire onRecognized
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(150))
                guard let self else { return }
                self.voiceState = .idle
                self.preserveTranscriptOnStop = false
            }
        } else {
            hardStop(clearText: true)
            voiceState = .idle
            amplitude = 0
        }
    }

    func cancel() {
        hardStop(clearText: true)
        voiceState = .idle
        amplitude = 0
    }

    // MARK: - Private

    private func beginRecognition() async {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .record,
                mode: .measurement,
                options: [.duckOthers, ForgePlaybackSession.bluetoothHFP]
            )
            try await ForgePlaybackSession.setSessionActive(true, notifyOthers: true)
        } catch {
            voiceState = .error("Microphone error")
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = false

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            voiceState = .error("No microphone input")
            return
        }

        inputNode.removeTap(onBus: 0)

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    self.recognizedText = result.bestTranscription.formattedString
                    self.resetSilenceTimer()
                    if result.isFinal {
                        self.stopListening(submit: true)
                        return
                    }
                }
                if let error, (error as NSError).code != 1, (error as NSError).code != 216 {
                    // 1/216 often cancellation — ignore
                    if self.voiceState == .listening {
                        self.voiceState = .error("Couldn't hear that")
                        self.hardStop(clearText: false)
                    }
                }
            }
        }

        do {
            let tapFrames = AVAudioFrameCount(max(4096, (format.sampleRate * 0.15).rounded()))
            #if compiler(>=6.4)
            try inputNode.installAudioTap(onBus: 0, bufferSize: tapFrames, format: format) { [weak self] buffer, _ in
                recognitionRequest.append(AVAudioPCMBuffer(copying: buffer))
                self?.updateAmplitude(from: buffer)
            }
            #else
            inputNode.installTap(onBus: 0, bufferSize: tapFrames, format: format) { [weak self] buffer, _ in
                recognitionRequest.append(buffer)
                self?.updateAmplitude(from: buffer)
            }
            #endif
            audioEngine.prepare()
            try audioEngine.start()
            voiceState = .listening
            startLevelPulseFallback()
        } catch {
            voiceState = .error("Microphone error")
            hardStop(clearText: true)
        }
    }

    /// iOS 27 has no parameterless async `requestAuthorization()`; wrap the
    /// current callback API so callers stay `async` without a fake overload.
    private static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.voiceState == .listening else { return }
                guard !self.recognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                self.stopListening(submit: true)
            }
        }
    }

    #if compiler(>=6.4)
    nonisolated private func updateAmplitude(from buffer: AVReadOnlyAudioPCMBuffer) {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }
        let rms: Float
        // ChannelData holds a ~Escapable Span — not a Sequence. Index it.
        switch buffer.channelData(0) {
        case .float(let samples):
            let n = min(samples.count, frames)
            guard n > 0 else { return }
            var sum: Float = 0
            for i in 0..<n {
                let s = samples[i]
                sum += s * s
            }
            rms = sqrt(sum / Float(n))
        case .int16(let samples):
            let n = min(samples.count, frames)
            guard n > 0 else { return }
            var sum: Float = 0
            for i in 0..<n {
                let f = Float(samples[i]) / Float(Int16.max)
                sum += f * f
            }
            rms = sqrt(sum / Float(n))
        case .int32(let samples):
            let n = min(samples.count, frames)
            guard n > 0 else { return }
            var sum: Float = 0
            for i in 0..<n {
                let f = Float(samples[i]) / Float(Int32.max)
                sum += f * f
            }
            rms = sqrt(sum / Float(n))
        @unknown default:
            return
        }
        pushAmplitude(rms)
    }
    #else
    nonisolated private func updateAmplitude(from buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }
        var sum: Float = 0
        for i in 0..<frameCount {
            let s = channel[i]
            sum += s * s
        }
        pushAmplitude(sqrt(sum / Float(frameCount)))
    }
    #endif

    nonisolated private func pushAmplitude(_ rms: Float) {
        let level = min(1, max(0.08, rms * 12))
        let now = CFAbsoluteTimeGetCurrent()
        let shouldPublish = amplitudePublishLock.withLock { last -> Bool in
            guard now - last >= Self.amplitudePublishInterval else { return false }
            last = now
            return true
        }
        guard shouldPublish else { return }
        Task { @MainActor in
            self.amplitude = level
        }
    }

    /// Gentle pulse when audio level taps are quiet
    private func startLevelPulseFallback() {
        levelTimer?.invalidate()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.voiceState == .listening else { return }
                if self.amplitude < 0.12 {
                    self.amplitude = Float.random(in: 0.12...0.28)
                }
            }
        }
    }

    private func hardStop(clearText: Bool) {
        silenceTimer?.invalidate()
        silenceTimer = nil
        levelTimer?.invalidate()
        levelTimer = nil

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        amplitude = 0
        if clearText { recognizedText = "" }
        AriaPresence.shared.setListening(false)
        ForgePlaybackSession.deactivate()
    }
}
