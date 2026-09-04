import AVFoundation
import Observation
import os

/// Generated café / noise / lo-fi / nature beds. Observation (not Combine) so
/// Tonight and the library both redraw from the same singleton without
/// `@StateObject` on a shared instance.
@MainActor
@Observable
final class SleepWindDownPlayer {
    static let shared = SleepWindDownPlayer()

    private(set) var isPlaying = false
    private(set) var remainingSeconds = 0
    private(set) var kind: SleepSoundKind = SleepSoundKind.stored ?? .brown
    var volume: Double = 0.75 {
        didSet { engine?.mainMixerNode.outputVolume = Float(volume) }
    }

    var remainingLabel: String {
        let m = remainingSeconds / 60
        let s = remainingSeconds % 60
        return String(format: "%d:%02d left", m, s)
    }

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var countdown: Task<Void, Never>?
    @ObservationIgnored private var interruptionTask: Task<Void, Never>?
    @ObservationIgnored private var wasInterrupted = false
    @ObservationIgnored private let renderer = SoundscapeRenderer()

    private init() {
        interruptionTask = Task { @MainActor [weak self] in
            let stream = NotificationCenter.default.notifications(
                named: AVAudioSession.interruptionNotification,
                object: AVAudioSession.sharedInstance()
            )
            for await note in stream {
                self?.handleInterruption(note)
            }
        }
    }

    func start(kind: SleepSoundKind? = nil, minutes: Int = 30) {
        if let kind {
            self.kind = kind
            kind.persist()
        }
        stop(deactivateSession: false)
        renderer.reset(kind: self.kind)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 22_050, channels: 1) else { return }
        let engine = AVAudioEngine()
        let renderer = self.renderer
        let source = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for buffer in buffers {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                renderer.render(into: data, frames: Int(frameCount))
            }
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = Float(volume)
        do {
            try ForgePlaybackSession.sleepMix.activate()
            try engine.start()
        } catch {
            return
        }
        self.engine = engine
        remainingSeconds = max(1, minutes) * 60
        isPlaying = true
        wasInterrupted = false
        startCountdown()
    }

    func stop(deactivateSession: Bool = true) {
        countdown?.cancel()
        countdown = nil
        wasInterrupted = false
        engine?.stop()
        engine = nil
        isPlaying = false
        remainingSeconds = 0
        renderer.reset(kind: kind)
        if deactivateSession {
            ForgePlaybackSession.deactivate()
        }
    }

    private func startCountdown() {
        countdown?.cancel()
        countdown = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
                guard let self, self.isPlaying else { return }
                remainingSeconds -= 1
                if remainingSeconds <= 0 {
                    stop()
                    return
                }
            }
        }
    }

    private func handleInterruption(_ note: Notification) {
        guard
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: raw)
        else { return }
        switch type {
        case .began:
            guard isPlaying else { return }
            wasInterrupted = true
            countdown?.cancel()
            countdown = nil
            engine?.pause()
        case .ended:
            guard wasInterrupted, isPlaying else { return }
            wasInterrupted = false
            let options = AVAudioSession.InterruptionOptions(
                rawValue: note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            )
            guard options.contains(.shouldResume) else { return }
            do {
                try ForgePlaybackSession.sleepMix.activate()
                try engine?.start()
                startCountdown()
            } catch {
                stop()
            }
        @unknown default:
            break
        }
    }
}

/// Rising two-tone. Stops wind-down first so the alarm is the only thing in the room.
@MainActor
@Observable
final class SleepWakePlayer {
    static let shared = SleepWakePlayer()

    private(set) var isPlaying = false

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private let renderer = WakeToneRenderer()

    private init() {}

    func start(for alarm: ForgeAlarm) {
        stop(deactivateSession: false)
        SleepWindDownPlayer.shared.stop(deactivateSession: false)
        let ramp = alarm.gradualVolume ? ForgeAlarmStore.shared.volumeRamp : .instant
        renderer.reset(rampSeconds: ramp.rampSeconds)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 22_050, channels: 1) else { return }
        let engine = AVAudioEngine()
        let renderer = self.renderer
        let source = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for buffer in buffers {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                renderer.render(into: data, frames: Int(frameCount))
            }
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        do {
            try ForgePlaybackSession.alarm.activate()
            try engine.start()
        } catch {
            return
        }
        self.engine = engine
        isPlaying = true
    }

    func ensurePlaying(for alarm: ForgeAlarm) {
        if isPlaying { return }
        start(for: alarm)
    }

    func stop(deactivateSession: Bool = true) {
        engine?.stop()
        engine = nil
        isPlaying = false
        renderer.reset(rampSeconds: 0.4)
        if deactivateSession {
            ForgePlaybackSession.deactivate()
        }
    }
}

// MARK: - Realtime DSP

/// One unfair lock per render quantum — not per sample — so the audio thread
/// does not bounce the lock thousands of times a callback.
final class SoundscapeRenderer: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: SoundscapeDSP())

    func reset(kind: SleepSoundKind) {
        lock.withLock { $0.reset(kind: kind) }
    }

    func render(into data: UnsafeMutablePointer<Float>, frames: Int) {
        lock.withLock { dsp in
            for i in 0..<frames {
                data[i] = dsp.nextSample()
            }
        }
    }
}

final class WakeToneRenderer: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: WakeToneDSP())

    func reset(rampSeconds: Double) {
        lock.withLock { $0.reset(rampSeconds: rampSeconds) }
    }

    func render(into data: UnsafeMutablePointer<Float>, frames: Int) {
        lock.withLock { dsp in
            for i in 0..<frames {
                data[i] = dsp.nextSample()
            }
        }
    }
}

/// Deterministic LCG — `Float.random` can allocate and is not realtime-safe.
struct SoundscapeDSP: Sendable {
    var kind: SleepSoundKind = .brown
    var t: Double = 0
    var frames: Int = 0
    var brown: Float = 0
    var pink: [Float] = Array(repeating: 0, count: 7)
    var eventAt: Int = 8_000
    var eventAmp: Float = 0
    var lofiPhase: Int = 0
    var rng: UInt32 = 0xA5A5_1234

    private let sr: Double = 22_050

    mutating func reset(kind: SleepSoundKind) {
        self.kind = kind
        t = 0
        frames = 0
        brown = 0
        pink = Array(repeating: 0, count: 7)
        eventAt = 6_000
        eventAmp = 0
        lofiPhase = 0
        let idx = UInt32(SleepSoundKind.allCases.firstIndex(of: kind) ?? 0)
        rng = 0xA5A5_1234 &+ idx &* 97
    }

    mutating func nextSample() -> Float {
        max(-1, min(1, rawSample()))
    }

    private mutating func rawSample() -> Float {
        frames += 1
        t += 1 / sr
        if t > 64 { t -= 64 }
        let white = nextWhite()
        brown = (brown + (0.02 * white)) * 0.98
        let brownClamped = max(-1, min(1, brown * 0.45))
        let pinkVal = pinkNoise(white)
        switch kind {
        case .white:
            return white * 0.18
        case .brown:
            return brownClamped
        case .pink:
            return pinkVal * 0.28
        case .fan:
            let lfo = Float(0.72 + 0.28 * sin(t * 0.35))
            return brownClamped * lfo * 0.9
        case .rain:
            let drop = white * white > 0.92 ? white * 0.35 : white * 0.08
            return (pinkVal * 0.22) + drop * 0.15
        case .ocean:
            let swell = Float(0.45 + 0.55 * sin(t * 0.22))
            return brownClamped * swell * 0.85 + pinkVal * 0.08 * swell
        case .forest:
            var s = pinkVal * 0.16 + brownClamped * 0.12
            if frames == eventAt {
                eventAmp = 0.18
                eventAt = frames + boundedInt(12_000...40_000)
            }
            eventAmp *= 0.992
            let chirp = Float(sin(2 * Double.pi * 2400 * t)) * eventAmp
            return s + chirp
        case .thunder:
            var s = pinkVal * 0.14 + brownClamped * 0.2
            if frames >= eventAt {
                eventAmp = 0.55
                eventAt = frames + boundedInt(30_000...90_000)
            }
            eventAmp *= 0.9992
            s += brownClamped * eventAmp
            return s
        case .fireplace:
            let crack = white * white > 0.97 ? abs(white) * 0.4 : 0
            return brownClamped * 0.55 + crack
        case .cafe:
            let room = pinkVal * 0.22 + brownClamped * 0.12
            let murmur = Float(sin(2 * Double.pi * 180 * t) * 0.04 + sin(2 * Double.pi * 240 * t) * 0.03)
            if frames >= eventAt {
                eventAmp = boundedFloat(0.12...0.28)
                eventAt = frames + boundedInt(8_000...22_000)
            }
            eventAmp *= 0.96
            let cup = Float(sin(2 * Double.pi * 1800 * t)) * eventAmp
            return room + murmur + cup
        case .tibetan:
            let env = Float(0.5 + 0.5 * sin(t * 0.15))
            return Float(sin(2 * Double.pi * 220 * t) * 0.18 + sin(2 * Double.pi * 330 * t) * 0.08) * env
        case .chimes:
            if frames >= eventAt {
                eventAmp = 0.22
                eventAt = frames + boundedInt(14_000...36_000)
            }
            eventAmp *= 0.9994
            let freqs: [Double] = [523.25, 587.33, 659.25, 783.99]
            let f = freqs[(frames / 18_000) % freqs.count]
            return Float(sin(2 * Double.pi * f * t)) * eventAmp
        case .lofi:
            lofiPhase += 1
            let beat = 18_900
            let pos = lofiPhase % beat
            let kick = pos < 900 ? Float(sin(2 * Double.pi * 55 * t)) * (1 - Float(pos) / 900) * 0.45 : 0
            let snarePos = (lofiPhase + beat / 2) % beat
            let snare = snarePos < 500 ? white * (1 - Float(snarePos) / 500) * 0.18 : 0
            let pad = Float(sin(2 * Double.pi * 196 * t) * 0.07 + sin(2 * Double.pi * 246.94 * t) * 0.05)
            let vinyl = white * white > 0.995 ? white * 0.08 : white * 0.012
            return kick + snare + pad + vinyl
        case .binaural:
            return Float(sin(2 * Double.pi * 200 * t) * 0.14 + sin(2 * Double.pi * 206 * t) * 0.14)
        case .hz432:
            return Float(sin(2 * Double.pi * 432 * t)) * 0.12 + brownClamped * 0.08
        case .deepFocus:
            let pulse = Float(0.55 + 0.45 * sin(t * 0.4))
            return (Float(sin(2 * Double.pi * 110 * t)) * 0.12 + brownClamped * 0.1) * pulse
        }
    }

    private mutating func pinkNoise(_ white: Float) -> Float {
        pink[0] = 0.99886 * pink[0] + white * 0.0555179
        pink[1] = 0.99332 * pink[1] + white * 0.0750759
        pink[2] = 0.96900 * pink[2] + white * 0.1538520
        pink[3] = 0.86650 * pink[3] + white * 0.3104856
        pink[4] = 0.55000 * pink[4] + white * 0.5329522
        pink[5] = -0.7616 * pink[5] - white * 0.0168980
        let v = pink[0] + pink[1] + pink[2] + pink[3] + pink[4] + pink[5] + pink[6] + white * 0.5362
        pink[6] = white * 0.115926
        return v * 0.11
    }

    mutating func nextWhite() -> Float {
        rng = rng &* 1_664_525 &+ 1_013_904_223
        let bits = (rng >> 8) & 0x00FF_FFFF
        return Float(bits) / 16_777_216.0 * 2 - 1
    }

    private mutating func nextUnit() -> Float {
        rng = rng &* 1_664_525 &+ 1_013_904_223
        let bits = (rng >> 8) & 0x00FF_FFFF
        return Float(bits) / 16_777_216.0
    }

    private mutating func boundedInt(_ range: ClosedRange<Int>) -> Int {
        let span = range.upperBound - range.lowerBound + 1
        guard span > 0 else { return range.lowerBound }
        let offset = min(span - 1, Int(Double(nextUnit()) * Double(span)))
        return range.lowerBound + offset
    }

    private mutating func boundedFloat(_ range: ClosedRange<Float>) -> Float {
        range.lowerBound + nextUnit() * (range.upperBound - range.lowerBound)
    }
}

struct WakeToneDSP: Sendable {
    var t: Double = 0
    var frames: Int = 0
    var rampFrames: Int = 8_820

    mutating func reset(rampSeconds: Double) {
        t = 0
        frames = 0
        rampFrames = max(1, Int(rampSeconds * 22_050))
    }

    mutating func nextSample() -> Float {
        frames += 1
        let env = min(1, Float(frames) / Float(rampFrames))
        let s1 = sin(2 * Double.pi * 392 * t)
        let s2 = sin(2 * Double.pi * 523.25 * t)
        t += 1 / 22_050
        if t > 1 { t -= 1 }
        return max(-1, min(1, Float(s1 * 0.34 + s2 * 0.22) * env))
    }
}

extension SleepSoundKind {
    static var stored: SleepSoundKind? {
        SleepSoundKind(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "")
    }

    func persist() {
        UserDefaults.standard.set(rawValue, forKey: SleepSoundKind.storageKey)
    }
}
