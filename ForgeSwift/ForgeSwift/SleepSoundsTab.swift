import SwiftUI
import AVFoundation

/// Generated brown noise + a fade-out timer. No bundled files, no network.
@MainActor
final class SleepWindDownPlayer: ObservableObject {
    static let shared = SleepWindDownPlayer()

    @Published private(set) var isPlaying = false
    @Published private(set) var remainingSeconds = 0

    var remainingLabel: String {
        let m = remainingSeconds / 60
        let s = remainingSeconds % 60
        return String(format: "%d:%02d left", m, s)
    }

    private var engine: AVAudioEngine?
    private var tick: Timer?
    private let brown = BrownNoiseState()

    func start(minutes: Int = 30) {
        stop(deactivateSession: false)
        brown.reset()
        let engine = AVAudioEngine()
        let format = AVAudioFormat(standardFormatWithSampleRate: 22_050, channels: 1)!
        let state = brown
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
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
        } catch {
            return
        }
        self.engine = engine
        remainingSeconds = max(1, minutes) * 60
        isPlaying = true
        tick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.remainingSeconds -= 1
                if self.remainingSeconds <= 0 { self.stop() }
            }
        }
    }

    func stop(deactivateSession: Bool = true) {
        tick?.invalidate()
        tick = nil
        engine?.stop()
        engine = nil
        isPlaying = false
        remainingSeconds = 0
        brown.reset()
        if deactivateSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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

    func start(for alarm: ForgeAlarm) {
        stop(deactivateSession: false)
        SleepWindDownPlayer.shared.stop(deactivateSession: false)
        let ramp = alarm.gradualVolume ? ForgeAlarmStore.shared.volumeRamp : .instant
        tone.reset(rampSeconds: ramp.rampSeconds)
        let engine = AVAudioEngine()
        let format = AVAudioFormat(standardFormatWithSampleRate: 22_050, channels: 1)!
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
    private var t: Double = 0
    private var frames: Int = 0
    private var rampFrames: Int = 8_820

    func reset(rampSeconds: Double) {
        t = 0
        frames = 0
        rampFrames = max(1, Int(rampSeconds * 22_050))
    }

    func nextSample() -> Float {
        frames += 1
        let env = min(1, Float(frames) / Float(rampFrames))
        let s1 = sin(2 * Double.pi * 392 * t)
        let s2 = sin(2 * Double.pi * 523.25 * t)
        t += 1 / 22_050
        if t > 1 { t -= 1 }
        return Float(s1 * 0.34 + s2 * 0.22) * env
    }
}

/// Audio-thread integrator. Isolated from UI so the render callback stays off MainActor.
private final class BrownNoiseState: @unchecked Sendable {
    private var last: Float = 0

    func reset() { last = 0 }

    func nextSample() -> Float {
        let white = Float.random(in: -1...1)
        last = (last + (0.02 * white)) * 0.98
        return max(-1, min(1, last * 0.45))
    }
}

struct SleepSoundsTab: View {
    @State private var activeSounds: [(sound: SleepSoundItem, volume: Double)] = []
    @State private var selectedCategory: SleepSoundCategory? = nil
    @State private var sleepTimer: Int = 0      // 0 = off
    @State private var timerRemaining: Int = 0
    @State private var showMixer = false

    let timerOptions = [0, 15, 30, 45, 60, 90]

    var filtered: [SleepSoundItem] {
        guard let cat = selectedCategory else { return allSleepSounds }
        return allSleepSounds.filter { $0.category == cat }
    }

    func isActive(_ sound: SleepSoundItem) -> Bool {
        activeSounds.contains { $0.sound.id == sound.id }
    }

    func toggleSound(_ sound: SleepSoundItem) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if let i = activeSounds.firstIndex(where: { $0.sound.id == sound.id }) {
            activeSounds.remove(at: i)
        } else if activeSounds.count < 3 {
            activeSounds.append((sound: sound, volume: 0.75))
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                // Now playing mini bar
                if !activeSounds.isEmpty {
                    NowPlayingBar(
                        sounds: activeSounds,
                        onMixerTap: { withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { showMixer.toggle() } },
                        onStop: { withAnimation { activeSounds.removeAll() } }
                    )

                    if showMixer {
                        SoundMixerPanel(activeSounds: $activeSounds)
                            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                    }
                }

                // Sleep timer
                EditorSection(title: "SLEEP TIMER") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(timerOptions, id: \.self) { mins in
                                Button {
                                    sleepTimer = mins
                                    UISelectionFeedbackGenerator().selectionChanged()
                                } label: {
                                    Text(mins == 0 ? "Off" : "\(mins)m")
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

                // Category filter
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

                // Capacity hint
                if activeSounds.count >= 3 {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle").font(.system(size: 12))
                        Text("Mix up to 3 sounds at once")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.textMuted)
                }

                // Sound grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(filtered) { sound in
                        SoundCard(sound: sound, isActive: isActive(sound), onTap: { toggleSound(sound) })
                            .opacity(activeSounds.count >= 3 && !isActive(sound) ? 0.4 : 1)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 100)
        }
    }
}

struct NowPlayingBar: View {
    let sounds: [(sound: SleepSoundItem, volume: Double)]
    let onMixerTap: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: -8) {
                ForEach(sounds.prefix(3), id: \.sound.id) { item in
                    ZStack {
                        Circle().fill(item.sound.color.opacity(0.2)).frame(width: 32, height: 32)
                        Image(systemName: item.sound.icon).font(.system(size: 13)).foregroundColor(item.sound.color)
                    }
                    .overlay(Circle().stroke(Color.background, lineWidth: 2))
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(sounds.map { $0.sound.name }.joined(separator: " · "))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)

                // Animated waveform indicator
                SoundWaveformBadge()
            }

            Spacer()

            Button(action: onMixerTap) {
                Image(systemName: "slider.horizontal.3").font(.system(size: 14)).foregroundColor(Color(hex: "6366F1"))
                    .frame(width: 36, height: 36).background(Color(hex: "6366F1").opacity(0.12)).clipShape(Circle())
            }
            Button(action: onStop) {
                Image(systemName: "stop.fill").font(.system(size: 14)).foregroundColor(.textTertiary)
                    .frame(width: 36, height: 36).background(Color.surfaceElevated).clipShape(Circle())
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Color.surface)
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(hex: "6366F1").opacity(0.3), lineWidth: 1))
        .shadow(color: Color(hex: "6366F1").opacity(0.1), radius: 12, y: 4)
    }
}

struct SoundWaveformBadge: View {
    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<6, id: \.self) { i in
                    let h = 4 + 8 * abs(sin(t * 3 + Double(i) * 0.7))
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color(hex: "6366F1").opacity(0.7))
                        .frame(width: 2, height: CGFloat(h))
                }
            }
        }
    }
}

struct SoundMixerPanel: View {
    @Binding var activeSounds: [(sound: SleepSoundItem, volume: Double)]

    var body: some View {
        VStack(spacing: 14) {
            Text("MIXER")
                .font(.system(size: 10, weight: .black))
                .foregroundColor(.textTertiary)
                .tracking(2.5)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(Array(activeSounds.enumerated()), id: \.offset) { index, item in
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(item.sound.color.opacity(0.18)).frame(width: 36, height: 36)
                        Image(systemName: item.sound.icon).font(.system(size: 14)).foregroundColor(item.sound.color)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.sound.name).font(.system(size: 13, weight: .semibold)).foregroundColor(.textPrimary)
                        Slider(value: $activeSounds[index].volume, in: 0...1)
                            .tint(item.sound.color)
                    }
                    Button {
                        withAnimation { 
                            _ = activeSounds.remove(at: index)
                        }
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundColor(.textMuted)
                            .frame(width: 28, height: 28).background(Color.surfaceElevated).clipShape(Circle())
                    }
                }
            }
        }
        .padding(16)
        .background(Color.surface)
        .cornerRadius(16)
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: "6366F1").opacity(0.25), lineWidth: 1)
        }
    }
}

struct SoundCard: View {
    let sound: SleepSoundItem
    let isActive: Bool
    let onTap: () -> Void
    @State private var pressed = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(sound.color.opacity(isActive ? 0.25 : 0.12))
                        .frame(width: 56, height: 56)
                        .shadow(color: isActive ? sound.color.opacity(0.4) : .clear, radius: 12)

                    if isActive {
                        // Animated waveform replaces icon while playing
                        TimelineView(.animation) { tl in
                            let t = tl.date.timeIntervalSinceReferenceDate
                            HStack(spacing: 3) {
                                ForEach(0..<5, id: \.self) { i in
                                    let h = 8 + 14 * abs(sin(t * 2.5 + Double(i) * 0.8))
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(sound.color)
                                        .frame(width: 3, height: CGFloat(h))
                                }
                            }
                        }
                    } else {
                        Image(systemName: sound.icon)
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(sound.color)
                    }
                }

                VStack(spacing: 3) {
                    Text(sound.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Text(sound.category.rawValue)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(sound.color.opacity(0.8))
                }

                if isActive {
                    Text("Playing")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(sound.color)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(sound.color.opacity(0.12))
                        .cornerRadius(20)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(Color.surface)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isActive ? sound.color.opacity(0.5) : Color.borderColor.opacity(0.4), lineWidth: isActive ? 1.5 : 1)
            )
            .shadow(color: isActive ? sound.color.opacity(0.2) : .black.opacity(0.04), radius: isActive ? 14 : 6, y: isActive ? 6 : 3)
            .scaleEffect(pressed ? 0.95 : 1)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded   { _ in pressed = false }
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
    }
}
