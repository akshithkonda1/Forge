import SwiftUI
import AVFoundation

/// Generated soundscapes — café, noise colors, lo-fi, nature. No bundled files.
@MainActor
final class SleepWindDownPlayer: ObservableObject {
    static let shared = SleepWindDownPlayer()

    @Published private(set) var isPlaying = false
    @Published private(set) var remainingSeconds = 0
    @Published private(set) var kind: SleepSoundKind = {
        SleepSoundKind(rawValue: UserDefaults.standard.string(forKey: SleepSoundKind.storageKey) ?? "") ?? .brown
    }()
    @Published var volume: Double = 0.75 {
        didSet { engine?.mainMixerNode.outputVolume = Float(volume) }
    }

    var remainingLabel: String {
        let m = remainingSeconds / 60
        let s = remainingSeconds % 60
        return String(format: "%d:%02d left", m, s)
    }

    private var engine: AVAudioEngine?
    private var countdown: Task<Void, Never>?
    private var interruptionObserver: NSObjectProtocol?
    private var wasInterrupted = false
    private let synth = SoundscapeState()

    private init() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            Task { @MainActor in self?.handleInterruption(note) }
        }
    }

    func start(kind: SleepSoundKind? = nil, minutes: Int = 30) {
        if let kind {
            self.kind = kind
            UserDefaults.standard.set(kind.rawValue, forKey: SleepSoundKind.storageKey)
        }
        stop(deactivateSession: false)
        synth.reset(kind: self.kind)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 22_050, channels: 1) else { return }
        let engine = AVAudioEngine()
        let state = synth
        let source = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for buffer in buffers {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                for i in 0..<Int(frameCount) {
                    data[i] = state.nextSample()
                }
            }
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = Float(volume)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
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
        synth.reset(kind: kind)
        if deactivateSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func startCountdown() {
        countdown?.cancel()
        countdown = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                remainingSeconds -= 1
                if remainingSeconds <= 0 { stop() }
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
                try AVAudioSession.sharedInstance().setActive(true)
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
final class SleepWakePlayer: ObservableObject {
    static let shared = SleepWakePlayer()

    @Published private(set) var isPlaying = false

    private var engine: AVAudioEngine?
    private let tone = WakeToneState()

    private init() {}

    func start(for alarm: ForgeAlarm) {
        stop(deactivateSession: false)
        SleepWindDownPlayer.shared.stop(deactivateSession: false)
        let ramp = alarm.gradualVolume ? ForgeAlarmStore.shared.volumeRamp : .instant
        tone.reset(rampSeconds: ramp.rampSeconds)
        let engine = AVAudioEngine()
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 22_050, channels: 1) else { return }
        let state = tone
        let source = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for buffer in buffers {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                for i in 0..<Int(frameCount) {
                    data[i] = state.nextSample()
                }
            }
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
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
        tone.reset(rampSeconds: 0.4)
        if deactivateSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}

/// Audio-thread oscillator. Isolated from UI so the render callback stays off MainActor.
private final class WakeToneState: @unchecked Sendable {
    private let lock = NSLock()
    private var t: Double = 0
    private var frames: Int = 0
    private var rampFrames: Int = 8_820

    func reset(rampSeconds: Double) {
        lock.lock()
        defer { lock.unlock() }
        t = 0
        frames = 0
        rampFrames = max(1, Int(rampSeconds * 22_050))
    }

    func nextSample() -> Float {
        lock.lock()
        defer { lock.unlock() }
        frames += 1
        let env = min(1, Float(frames) / Float(rampFrames))
        let s1 = sin(2 * Double.pi * 392 * t)
        let s2 = sin(2 * Double.pi * 523.25 * t)
        t += 1 / 22_050
        if t > 1 { t -= 1 }
        return Float(s1 * 0.34 + s2 * 0.22) * env
    }
}

/// Audio-thread soundscape. Isolated from UI so the render callback stays off MainActor.
private final class SoundscapeState: @unchecked Sendable {
    private let lock = NSLock()
    private var kind: SleepSoundKind = .brown
    private var t: Double = 0
    private var frames: Int = 0
    private var brown: Float = 0
    private var pink: [Float] = Array(repeating: 0, count: 7)
    private var eventAt: Int = 8_000
    private var eventAmp: Float = 0
    private var lofiPhase: Int = 0

    private let sr: Double = 22_050

    func reset(kind: SleepSoundKind) {
        lock.lock()
        defer { lock.unlock() }
        self.kind = kind
        t = 0
        frames = 0
        brown = 0
        pink = Array(repeating: 0, count: 7)
        eventAt = 6_000
        eventAmp = 0
        lofiPhase = 0
    }

    func nextSample() -> Float {
        lock.lock()
        defer { lock.unlock() }
        frames += 1
        t += 1 / sr
        if t > 64 { t -= 64 }
        let white = Float.random(in: -1...1)
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
                eventAt = frames + Int.random(in: 12_000...40_000)
            }
            eventAmp *= 0.992
            let chirp = Float(sin(2 * Double.pi * 2400 * t)) * eventAmp
            return s + chirp
        case .thunder:
            var s = pinkVal * 0.14 + brownClamped * 0.2
            if frames >= eventAt {
                eventAmp = 0.55
                eventAt = frames + Int.random(in: 30_000...90_000)
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
                eventAmp = Float.random(in: 0.12...0.28)
                eventAt = frames + Int.random(in: 8_000...22_000)
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
                eventAt = frames + Int.random(in: 14_000...36_000)
            }
            eventAmp *= 0.9994
            let freqs: [Double] = [523.25, 587.33, 659.25, 783.99]
            let f = freqs[(frames / 18_000) % freqs.count]
            return Float(sin(2 * Double.pi * f * t)) * eventAmp
        case .lofi:
            lofiPhase += 1
            let beat = 18_900 // ~70 BPM at 22050
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

    private func pinkNoise(_ white: Float) -> Float {
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
}

struct SleepSoundsTab: View {
    @ObservedObject private var player = SleepWindDownPlayer.shared
    @State private var selectedCategory: SleepSoundCategory? = nil
    @State private var sleepTimer: Int = 30

    let timerOptions = [15, 30, 45, 60, 90]

    private var libraryGroups: [(category: SleepSoundCategory, items: [SleepSoundItem])] {
        let cats = selectedCategory.map { [$0] } ?? Array(SleepSoundCategory.allCases)
        return cats.compactMap { cat in
            let items = allSleepSounds.filter { $0.category == cat }
            return items.isEmpty ? nil : (cat, items)
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                if player.isPlaying {
                    nowPlaying
                }

                EditorSection(title: "TIMER") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(timerOptions, id: \.self) { mins in
                                Button {
                                    sleepTimer = mins
                                    UISelectionFeedbackGenerator().selectionChanged()
                                } label: {
                                    Text("\(mins)m")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(sleepTimer == mins ? .white : .textTertiary)
                                        .padding(.horizontal, 14).padding(.vertical, 8)
                                        .background(sleepTimer == mins ? Color(hex: "6366F1") : Color.surface)
                                        .cornerRadius(20)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                EditorSection(title: "LIBRARY") {
                    Text("Pick one. Each is generated on this phone — café chatter, noise colors, lo-fi, nature. No account, no files.")
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                EditorSection(title: "CATEGORIES") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { selectedCategory = nil }
                            } label: {
                                Text("All")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(selectedCategory == nil ? .white : .textTertiary)
                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                    .background(selectedCategory == nil ? Color(hex: "6366F1") : Color.surface)
                                    .cornerRadius(20)
                            }
                            .buttonStyle(.plain)

                            ForEach(SleepSoundCategory.allCases, id: \.self) { cat in
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                        selectedCategory = selectedCategory == cat ? nil : cat
                                    }
                                } label: {
                                    Text(cat.rawValue)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(selectedCategory == cat ? .white : .textTertiary)
                                        .padding(.horizontal, 14).padding(.vertical, 8)
                                        .background(selectedCategory == cat ? Color(hex: "6366F1") : Color.surface)
                                        .cornerRadius(20)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(libraryGroups, id: \.category) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(group.category.rawValue.uppercased())
                                .font(.system(size: 11, weight: .bold))
                                .tracking(1.1)
                                .foregroundColor(.textMuted)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(group.items) { sound in
                                SoundLibraryRow(
                                    sound: sound,
                                    isActive: player.isPlaying && player.kind == sound.kind,
                                    onTap: {
                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                        if player.isPlaying, player.kind == sound.kind {
                                            player.stop()
                                        } else {
                                            player.start(kind: sound.kind, minutes: sleepTimer)
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 100)
        }
    }

    private var nowPlaying: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(player.kind.color.opacity(0.2)).frame(width: 44, height: 44)
                    Image(systemName: player.kind.icon).font(.system(size: 16)).foregroundColor(player.kind.color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.kind.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    HStack(spacing: 8) {
                        SoundWaveformBadge()
                        Text(player.remainingLabel)
                            .font(.system(size: 12))
                            .foregroundColor(.textTertiary)
                            .monospacedDigit()
                    }
                }
                Spacer()
                Button {
                    player.stop()
                } label: {
                    Text("Stop")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.danger.opacity(0.85))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 10) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.textMuted)
                Slider(value: $player.volume, in: 0...1)
                    .tint(player.kind.color)
                    .accessibilityLabel("Volume")
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.textMuted)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Color.surface)
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(hex: "6366F1").opacity(0.3), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Now playing \(player.kind.displayName), \(player.remainingLabel)")
    }
}

struct SoundLibraryRow: View {
    let sound: SleepSoundItem
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(sound.color.opacity(isActive ? 0.28 : 0.12))
                        .frame(width: 52, height: 52)
                    Image(systemName: isActive ? "pause.fill" : sound.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(sound.color)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(sound.name)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.textPrimary)
                        Spacer()
                        Text(sound.category.rawValue.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.8)
                            .foregroundColor(.textMuted)
                    }
                    Text(sound.blurb)
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(14)
            .background(isActive ? sound.color.opacity(0.10) : Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isActive ? sound.color.opacity(0.45) : Color.borderColor.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(sound.name). \(sound.blurb)")
        .accessibilityHint(isActive ? "Stops playback" : "Plays this sound")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

struct SoundWaveformBadge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: reduceMotion)) { tl in
            let t = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<6, id: \.self) { i in
                    let h = reduceMotion ? 8.0 : 4 + 8 * abs(sin(t * 3 + Double(i) * 0.7))
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color(hex: "6366F1").opacity(0.7))
                        .frame(width: 2, height: CGFloat(h))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
