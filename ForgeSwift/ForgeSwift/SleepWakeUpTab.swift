import SwiftUI

@MainActor
final class SleepWakeStore: ObservableObject {
    static let shared = SleepWakeStore()

    @Published var isRinging = false
    @Published private(set) var current: ForgeAlarm?
    @Published private(set) var snoozeCount = 0
    @Published private(set) var startedAt = Date()

    var remainingSnoozes: Int { max(0, SleepWakeEngine.maxSnoozes - snoozeCount) }

    func ring(_ alarm: ForgeAlarm) {
        if isRinging, current?.id == alarm.id {
            SleepWakePlayer.shared.ensurePlaying(for: alarm)
            return
        }
        current = alarm
        snoozeCount = 0
        startedAt = Date()
        isRinging = true
        SleepWindDownPlayer.shared.stop(deactivateSession: false)
        SleepWakePlayer.shared.start(for: alarm)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    func ringFromNotification(alarmID: UUID?) {
        let alarm = ForgeAlarmStore.shared.alarm(id: alarmID)
            ?? ForgeAlarmStore.shared.next
            ?? ForgeAlarm()
        ring(alarm)
    }

    func dismiss() {
        isRinging = false
        current = nil
        SleepWakePlayer.shared.stop()
    }

    func snooze() {
        guard let alarm = current, SleepWakeEngine.canSnooze(count: snoozeCount) else { return }
        snoozeCount += 1
        isRinging = false
        SleepWakePlayer.shared.stop()
        Task { await SleepAlarmScheduler.scheduleSnooze(alarm: alarm) }
    }

    func handleSnoozeAction(alarmID: UUID?) async {
        let alarm = ForgeAlarmStore.shared.alarm(id: alarmID)
            ?? current
            ?? ForgeAlarmStore.shared.next
            ?? ForgeAlarm()
        if !SleepWakeEngine.canSnooze(count: snoozeCount) {
            ring(alarm)
            return
        }
        snoozeCount += 1
        isRinging = false
        SleepWakePlayer.shared.stop()
        await SleepAlarmScheduler.scheduleSnooze(alarm: alarm)
    }
}

struct SleepWakeScreen: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var wake = SleepWakeStore.shared
    @ObservedObject private var alarms = ForgeAlarmStore.shared
    @State private var doneRoutine: Set<UUID> = []
    @State private var tick = Date()

    private var alarm: ForgeAlarm { wake.current ?? ForgeAlarm() }

    private var progress: Double {
        min(1, Date().timeIntervalSince(wake.startedAt) / 24)
    }

    private var clock: String {
        tick.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        ZStack {
            sunrise
            VStack(spacing: 28) {
                Spacer()
                VStack(spacing: 8) {
                    Text(clock)
                        .font(.system(size: 72, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .monospacedDigit()
                    Text(alarm.label)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.72))
                    Text(SleepWakeCoach.morningPrompt(
                        sleepScore: store.sleepData.first?.score,
                        lastNightHours: store.sleepData.first?.totalHours
                    ))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .padding(.top, 6)
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(alarms.routine.filter(\.isEnabled).prefix(3)) { item in
                        Button {
                            if doneRoutine.contains(item.id) { doneRoutine.remove(item.id) }
                            else { doneRoutine.insert(item.id) }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: doneRoutine.contains(item.id) ? "checkmark.circle.fill" : item.icon)
                                    .foregroundColor(doneRoutine.contains(item.id) ? .white : .white.opacity(0.7))
                                Text(item.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                Spacer()
                                Text("\(item.duration) min")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.55))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(doneRoutine.contains(item.id) ? 0.22 : 0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)

                HoldToWakeButton { wake.dismiss() }

                if wake.remainingSnoozes > 0 {
                    Button {
                        wake.snooze()
                    } label: {
                        Text("Snooze \(alarm.snoozeMinutes) min · \(wake.remainingSnoozes) left")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Snooze. \(wake.remainingSnoozes) remaining.")
                } else {
                    Text("No snoozes left. Get up.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.55))
                }

                Button {
                    let prompt = SleepWakeCoach.morningPrompt(
                        sleepScore: store.sleepData.first?.score,
                        lastNightHours: store.sleepData.first?.totalHours
                    )
                    wake.dismiss()
                    store.openChat(with: prompt, voice: false)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                        Text("Ask ARIA to start the morning")
                    }
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.88))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 36)
            }
        }
        .interactiveDismissDisabled()
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { tick = $0 }
        .onAppear {
            SleepWakePlayer.shared.ensurePlaying(for: alarm)
        }
    }

    private var sunrise: some View {
        let t = alarms.sunriseEnabled ? progress : 0.12
        return ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.05, blue: 0.10),
                    Color(red: 0.55 + 0.2 * t, green: 0.28 + 0.25 * t, blue: 0.12 + 0.15 * t),
                    Color(red: 0.98, green: 0.62 + 0.2 * t, blue: 0.28 + 0.25 * t)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [Color(hex: "F59E0B").opacity(0.15 + 0.55 * t), .clear],
                center: UnitPoint(x: 0.5, y: 0.78),
                startRadius: 10,
                endRadius: 280
            )
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 1.0), value: t)
    }
}

struct HoldToWakeButton: View {
    let action: () -> Void
    @State private var progress: CGFloat = 0
    @State private var holdTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.14))
            Capsule()
                .fill(Color.white.opacity(0.32))
                .frame(width: 280 * progress)
            Text(progress > 0.05 ? "Keep holding" : "Hold — I'm up")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
        }
        .frame(width: 280, height: 58)
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in beginHold() }
                .onEnded { _ in cancelHold() }
        )
        .accessibilityLabel("Hold to dismiss. I'm up.")
    }

    private func beginHold() {
        guard holdTask == nil else { return }
        withAnimation(.linear(duration: 1.2)) { progress = 1 }
        holdTask = Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            action()
        }
    }

    private func cancelHold() {
        holdTask?.cancel()
        holdTask = nil
        withAnimation(.easeOut(duration: 0.18)) { progress = 0 }
    }
}

struct WakeUpTab: View {
    @EnvironmentObject private var hkService: HealthKitSleepService
    @EnvironmentObject private var appStore: AppStore
    @ObservedObject private var store = ForgeAlarmStore.shared
    @State private var sunriseDuration = 20
    @State private var colorTemp = 0.5

    private var coach: SleepWakeCoach {
        SleepWakeCoach.make(
            alarms: store.alarms,
            sleepScore: appStore.sleepData.first?.score,
            lastNightHours: appStore.sleepData.first?.totalHours
        )
    }

    var body: some View {
        VStack(spacing: 20) {
            NextWakePlanCard(coach: coach)

            if store.next != nil {
                SmartWakeCard(
                    enabled: Binding(
                        get: { store.next?.isSmartWake ?? false },
                        set: { on in
                            guard var next = store.next else { return }
                            next.isSmartWake = on
                            store.upsert(next)
                        }
                    ),
                    windowMinutes: Binding(
                        get: { store.next?.smartWakeWindow ?? 30 },
                        set: { mins in
                            guard var next = store.next else { return }
                            next.smartWakeWindow = mins
                            store.upsert(next)
                        }
                    )
                )
            }

            AdaptiveSunriseCard(
                config: hkService.currentSunriseConfig,
                enabled: Binding(
                    get: { store.sunriseEnabled },
                    set: { store.setSunriseEnabled($0) }
                ),
                duration: $sunriseDuration,
                colorTemp: $colorTemp
            )

            VolumeRampCard(curve: Binding(
                get: { store.volumeRamp },
                set: { store.setVolumeRamp($0) }
            ))

            MorningRoutineCard(items: Binding(
                get: { store.routine },
                set: { store.setRoutine($0) }
            ))
        }
        .onAppear {
            let config = hkService.currentSunriseConfig
            sunriseDuration = config.durationMinutes
            colorTemp = config.colorTemp
        }
    }
}

struct NextWakePlanCard: View {
    let coach: SleepWakeCoach
    @EnvironmentObject private var store: AppStore

    var body: some View {
        WakeUpSection(icon: "sun.horizon.fill", title: "This wake", color: Color(hex: "F59E0B")) {
            VStack(alignment: .leading, spacing: 10) {
                Text(coach.headline)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
                Text(coach.cue)
                    .font(.system(size: 13))
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let smart = coach.smartFire, let hard = coach.hardFire {
                    Text("Smart \(smart.formatted(date: .omitted, time: .shortened))  ·  Hard \(hard.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textTertiary)
                }
                Button {
                    store.openChat(with: coach.ariaPrompt, voice: false)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                        Text("Ask ARIA about this morning")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.ember)
                    .padding(12)
                    .background(Color.ember.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct SmartWakeCard: View {
    @Binding var enabled: Bool
    @Binding var windowMinutes: Int

    var body: some View {
        VStack(spacing: 0) {
            WakeUpSection(icon: "waveform.path.ecg", title: "Smart Wake", color: .steel) {
                VStack(spacing: 14) {
                    Toggle(isOn: $enabled) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Wake during lightest sleep")
                                .font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
                            Text("Detects your sleep cycle and wakes you at the optimal moment")
                                .font(.system(size: 12)).foregroundColor(.textTertiary).lineSpacing(3)
                        }
                    }
                    .tint(.steel)

                    if enabled {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Detection window")
                                .font(.system(size: 12, weight: .semibold)).foregroundColor(.textSecondary)
                            HStack(spacing: 10) {
                                ForEach([15, 30, 45], id: \.self) { mins in
                                    Button {
                                        windowMinutes = mins
                                        UISelectionFeedbackGenerator().selectionChanged()
                                    } label: {
                                        VStack(spacing: 4) {
                                            Text("\(mins)")
                                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                                .foregroundColor(windowMinutes == mins ? .white : .textPrimary)
                                            Text("min")
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundColor(windowMinutes == mins ? .white.opacity(0.7) : .textTertiary)
                                        }
                                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                                        .background(windowMinutes == mins ? Color.steel : Color.surfaceElevated)
                                        .cornerRadius(14)
                                        .shadow(color: windowMinutes == mins ? Color.steel.opacity(0.35) : .clear, radius: 8, y: 4)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            // Visual representation
                            HStack(spacing: 0) {
                                Spacer()
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 6).fill(Color.borderColor.opacity(0.3)).frame(height: 8)
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(LinearGradient(colors: [Color.steel.opacity(0.3), Color.steel], startPoint: .leading, endPoint: .trailing))
                                        .frame(width: CGFloat(windowMinutes) / 45 * 200, height: 8)
                                }
                                .frame(width: 200)
                                VStack(alignment: .trailing, spacing: 2) {
                                    Image(systemName: "alarm.fill").font(.system(size: 12)).foregroundColor(.ember)
                                    Text("Alarm").font(.system(size: 9, weight: .medium)).foregroundColor(.textMuted)
                                }
                                .padding(.leading, 6)
                            }
                            .padding(.top, 4)
                        }
                        .padding(12).background(Color.steel.opacity(0.06)).cornerRadius(12)
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                    }
                }
            }
        }
    }
}

struct SunriseSimulationCard: View {
    @Binding var enabled: Bool
    @Binding var duration: Int
    @Binding var colorTemp: Double   // 0=warm 2700K, 1=cool 5000K

    private var displayColor: Color {
        Color(
            red: 1.0,
            green: 0.6 + colorTemp * 0.35,
            blue: 0.3 + colorTemp * 0.7
        ).opacity(0.9)
    }

    var body: some View {
        WakeUpSection(icon: "sunrise.fill", title: "Sunrise Simulation", color: Color(hex: "F59E0B")) {
            VStack(spacing: 16) {
                Toggle(isOn: $enabled) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Gradual light increase")
                            .font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
                        Text("Mimics a natural sunrise to gently bring you out of sleep")
                            .font(.system(size: 12)).foregroundColor(.textTertiary)
                    }
                }
                .tint(Color(hex: "F59E0B"))

                if enabled {
                    VStack(spacing: 14) {
                        // Duration
                        HStack {
                            Text("Duration").font(.system(size: 13, weight: .semibold)).foregroundColor(.textSecondary)
                            Spacer()
                            HStack(spacing: 4) {
                                Text("\(duration) min")
                                    .font(.system(size: 14, weight: .bold)).foregroundColor(.textPrimary)
                                Stepper("", value: $duration, in: 5...60, step: 5)
                                    .labelsHidden().tint(Color(hex: "F59E0B"))
                            }
                        }

                        // Color temperature
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Color Temperature").font(.system(size: 13, weight: .semibold)).foregroundColor(.textSecondary)
                                Spacer()
                                Text(colorTemp < 0.3 ? "2700K Warm" : colorTemp < 0.7 ? "3500K Neutral" : "5000K Cool")
                                    .font(.system(size: 12, weight: .semibold)).foregroundColor(displayColor)
                            }

                            // Gradient slider preview
                            ZStack(alignment: .bottom) {
                                LinearGradient(
                                    colors: [Color(hex: "FF8C42"), Color(hex: "FFD166"), Color(hex: "FEFAE0"), Color(hex: "C8E6FF")],
                                    startPoint: .leading, endPoint: .trailing
                                )
                                .frame(height: 24).cornerRadius(12)

                                Slider(value: $colorTemp)
                                    .tint(.clear)
                                    .padding(.horizontal, 2)
                            }
                        }

                        // Preview
                        HStack(spacing: 8) {
                            ForEach(Array(stride(from: 0.1, through: 1.0, by: 0.18)), id: \.self) { t in
                                Circle()
                                    .fill(Color(
                                        red: 1.0,
                                        green: 0.4 + t * 0.55,
                                        blue: 0.1 + t * 0.85
                                    ))
                                    .frame(width: 8, height: 8)
                                    .frame(maxWidth: .infinity)
                                    .opacity(0.3 + t * 0.7)
                            }
                        }
                        .frame(height: 16)
                        .padding(.horizontal, 4)
                        .overlay(alignment: .leading) {
                            Text("Start").font(.system(size: 9, weight: .medium)).foregroundColor(.textMuted)
                        }
                        .overlay(alignment: .trailing) {
                            Text("Full").font(.system(size: 9, weight: .medium)).foregroundColor(.textMuted)
                        }
                    }
                    .padding(12).background(Color(hex: "F59E0B").opacity(0.06)).cornerRadius(12)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                }
            }
        }
    }
}

struct VolumeRampCard: View {
    @Binding var curve: VolumeRampCurve

    var body: some View {
        WakeUpSection(icon: "speaker.wave.3.fill", title: "Volume Ramp", color: .ember) {
            VStack(spacing: 12) {
                ForEach(VolumeRampCurve.allCases, id: \.self) { option in
                    Button {
                        curve = option
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle().fill(curve == option ? Color.ember.opacity(0.15) : Color.surfaceElevated)
                                    .frame(width: 38, height: 38)
                                Image(systemName: option.icon)
                                    .font(.system(size: 15))
                                    .foregroundColor(curve == option ? .ember : .textTertiary)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(option.rawValue).font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
                                Text(option.description).font(.system(size: 12)).foregroundColor(.textTertiary)
                            }
                            Spacer()
                            if curve == option {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 18)).foregroundColor(.ember)
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(curve == option ? Color.ember.opacity(0.07) : Color.surfaceElevated)
                        .cornerRadius(14)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(curve == option ? Color.ember.opacity(0.4) : Color.borderColor.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }

                // Visual curve preview
                VolumeRampPreview(curve: curve)
            }
        }
    }
}

struct VolumeRampPreview: View {
    let curve: VolumeRampCurve

    private func height(for x: CGFloat) -> CGFloat {
        switch curve {
        case .instant: return x > 0.02 ? 1.0 : 0
        case .gentle:  return min(1.0, x * 6.67)
        case .gradual: return x * x
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Volume preview")
                .font(.system(size: 11, weight: .medium)).foregroundColor(.textMuted)
            GeometryReader { geo in
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(0..<80, id: \.self) { i in
                        let x = CGFloat(i) / 79
                        let h = height(for: x)
                        Rectangle()
                            .fill(Color.ember.opacity(0.3 + h * 0.5))
                            .frame(width: geo.size.width / 80, height: geo.size.height * h)
                    }
                }
                .animation(.easeInOut(duration: 0.4), value: curve)
            }
            .frame(height: 44)
            .cornerRadius(6)
        }
        .padding(12).background(Color.surfaceElevated).cornerRadius(12)
    }
}

struct MorningRoutineCard: View {
    @Binding var items: [RoutineItem]
    @State private var editMode = false

    var totalMinutes: Int { items.filter { $0.isEnabled }.reduce(0) { $0 + $1.duration } }

    var body: some View {
        WakeUpSection(icon: "checklist", title: "Morning Routine", color: .success) {
            VStack(spacing: 12) {
                HStack {
                    Text("Total: \(totalMinutes) min")
                        .font(.system(size: 12, weight: .semibold)).foregroundColor(.textSecondary)
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { editMode.toggle() }
                    } label: {
                        Text(editMode ? "Done" : "Edit")
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(.success)
                    }
                }

                ForEach($items) { $item in
                    HStack(spacing: 12) {
                        // Drag handle (visible in edit mode)
                        if editMode {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 14)).foregroundColor(.textMuted)
                        }

                        Toggle(isOn: $item.isEnabled) {
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle().fill(item.isEnabled ? Color.success.opacity(0.15) : Color.surfaceElevated)
                                        .frame(width: 36, height: 36)
                                    Image(systemName: item.icon)
                                        .font(.system(size: 14))
                                        .foregroundColor(item.isEnabled ? .success : .textMuted)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(item.isEnabled ? .textPrimary : .textTertiary)
                                    Text("\(item.duration) min")
                                        .font(.system(size: 11))
                                        .foregroundColor(.textMuted)
                                }
                            }
                        }
                        .tint(.success)

                        if editMode {
                            Stepper("", value: $item.duration, in: 1...60, step: 1).labelsHidden()
                                .tint(.success)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Color.surfaceElevated).cornerRadius(12)
                    .animation(.spring(response: 0.3, dampingFraction: 0.72), value: item.isEnabled)
                }
                .onMove { from, to in items.move(fromOffsets: from, toOffset: to) }
                .animation(.spring(response: 0.4, dampingFraction: 0.75), value: items.map { $0.id })
            }
        }
    }
}

struct WakeGreetingCard: View {
    @EnvironmentObject private var store: AppStore

    @State private var greeting = ""
    @State private var showWeather = true
    @State private var showWorkout = true
    @State private var showSleepScore = true

    private var firstName: String {
        store.userProfile.name.components(separatedBy: " ").first ?? ""
    }

    /// The greeting this person would write for themselves, not the one the
    /// demo shipped with. It used to read "Good morning, Akshith" for everybody.
    private var defaultGreeting: String {
        firstName.isEmpty ? "Good morning 🌅" : "Good morning, \(firstName) 🌅"
    }

    var body: some View {
        WakeUpSection(icon: "hand.wave.fill", title: "Wake Screen", color: Color(hex: "F59E0B")) {
            VStack(spacing: 14) {
                // Preview
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(LinearGradient(colors: [Color(hex: "0F172A"), Color(hex: "1E293B")], startPoint: .top, endPoint: .bottom))
                    VStack(spacing: 12) {
                        Text("6:45 AM")
                            .font(.system(size: 36, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Text(greeting)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                        HStack(spacing: 16) {
                            if showSleepScore {
                                let score = store.sleepData.first.map { "Sleep \($0.score)" } ?? "Sleep"
                                Label(score, systemImage: "moon.stars.fill").foregroundColor(.steel)
                            }
                            if showWeather   { Label("Local weather", systemImage: "sun.max.fill").foregroundColor(Color(hex: "F59E0B")) }
                            if showWorkout   {
                                Label(store.todayWorkout?.name ?? "Rest day", systemImage: "dumbbell.fill").foregroundColor(.ember)
                            }
                        }
                        .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(20)
                }
                .frame(height: 140)

                // Greeting field
                TextField("Wake greeting…", text: $greeting)
                    .font(.system(size: 14)).foregroundColor(.textPrimary).tint(Color(hex: "F59E0B"))
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .background(Color.surfaceElevated).cornerRadius(12)

                // Toggles
                VStack(spacing: 2) {
                    WakeToggle(label: "Show sleep score", value: $showSleepScore, color: .steel)
                    WakeToggle(label: "Show weather",     value: $showWeather,    color: Color(hex: "F59E0B"))
                    WakeToggle(label: "Show today's workout", value: $showWorkout, color: .ember)
                }
            }
        }
        .onAppear {
            if greeting.isEmpty { greeting = defaultGreeting }
        }
    }
}

struct WakeToggle: View {
    let label: String
    @Binding var value: Bool
    let color: Color
    var body: some View {
        Toggle(isOn: $value) {
            Text(label).font(.system(size: 14, weight: .medium)).foregroundColor(.textPrimary)
        }
        .tint(color)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Color.surfaceElevated).cornerRadius(12)
    }
}

struct WakeUpSection<Content: View>: View {
    let icon: String
    let title: String
    let color: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(color.opacity(0.15)).frame(width: 36, height: 36)
                    Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundColor(color)
                }
                Text(title).font(.system(size: 16, weight: .bold)).foregroundColor(.textPrimary)
            }
            content()
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.06), radius: 14, y: 5)
    }
}

struct ChronotypeBadge: View {
    @EnvironmentObject var hkService: HealthKitSleepService
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: hkService.userProfile.chronotype.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.steel)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(hkService.userProfile.chronotype.displayName) Chronotype")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Text(hkService.userProfile.chronotype.tagline)
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textTertiary)
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}

struct AdaptiveSunriseCard: View {
    let config: AdaptiveSunriseConfig
    @Binding var enabled: Bool
    @Binding var duration: Int
    @Binding var colorTemp: Double

    private var displayColor: Color {
        Color(
            red: 1.0,
            green: 0.6 + colorTemp * 0.35,
            blue: 0.3 + colorTemp * 0.7
        ).opacity(0.9)
    }

    var body: some View {
        WakeUpSection(icon: "sunrise.fill", title: "Adaptive Sunrise", color: Color(hex: "F59E0B")) {
            VStack(spacing: 16) {
                Toggle(isOn: $enabled) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Gradual light increase")
                            .font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
                        Text(config.rationale)
                            .font(.system(size: 12)).foregroundColor(.textTertiary)
                    }
                }
                .tint(Color(hex: "F59E0B"))

                if enabled {
                    VStack(spacing: 14) {
                        HStack {
                            Text("Duration").font(.system(size: 13, weight: .semibold)).foregroundColor(.textSecondary)
                            Spacer()
                            HStack(spacing: 4) {
                                Text("\(duration) min")
                                    .font(.system(size: 14, weight: .bold)).foregroundColor(.textPrimary)
                                Stepper("", value: $duration, in: 5...60, step: 5)
                                    .labelsHidden().tint(Color(hex: "F59E0B"))
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Color Temperature").font(.system(size: 13, weight: .semibold)).foregroundColor(.textSecondary)
                                Spacer()
                                Text(colorTemp < 0.3 ? "2700K Warm" : colorTemp < 0.7 ? "3500K Neutral" : "5000K Cool")
                                    .font(.system(size: 12, weight: .semibold)).foregroundColor(displayColor)
                            }
                            ZStack(alignment: .bottom) {
                                LinearGradient(
                                    colors: [Color(hex: "FF8C42"), Color(hex: "FFD166"), Color(hex: "FEFAE0"), Color(hex: "C8E6FF")],
                                    startPoint: .leading, endPoint: .trailing
                                )
                                .frame(height: 24).cornerRadius(12)
                                Slider(value: $colorTemp)
                                    .tint(.clear)
                                    .padding(.horizontal, 2)
                            }
                        }

                        HStack(spacing: 8) {
                            ForEach(Array(stride(from: 0.1, through: 1.0, by: 0.18)), id: \.self) { t in
                                Circle()
                                    .fill(Color(
                                        red: 1.0,
                                        green: 0.4 + t * 0.55,
                                        blue: 0.1 + t * 0.85
                                    ))
                                    .frame(width: 8, height: 8)
                                    .frame(maxWidth: .infinity)
                                    .opacity(0.3 + t * Double(config.intensity))
                            }
                        }
                        .frame(height: 16)
                    }
                    .padding(12).background(Color(hex: "F59E0B").opacity(0.06)).cornerRadius(12)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                }
            }
        }
    }
}
