import SwiftUI
import ForgeCore

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
        UIApplication.shared.isIdleTimerDisabled = true
        SleepWindDownPlayer.shared.stop(deactivateSession: false)
        SleepWakePlayer.shared.start(for: alarm)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        Task { await SleepAlarmScheduler.scheduleFailsafe(alarm: alarm) }
    }

    func ringFromNotification(alarmID: UUID?) {
        let alarm = ForgeAlarmStore.shared.alarm(id: alarmID)
            ?? ForgeAlarmStore.shared.next
            ?? ForgeAlarm()
        ring(alarm)
    }

    func dismiss() {
        WakeStruggleStore.record(snoozes: snoozeCount, on: startedAt)
        isRinging = false
        if let id = current?.id {
            SleepAlarmScheduler.cancelFailsafe(alarmID: id)
        }
        current = nil
        UIApplication.shared.isIdleTimerDisabled = false
        SleepWakePlayer.shared.stop()
    }

    func snooze() {
        guard let alarm = current, SleepWakeEngine.canSnooze(count: snoozeCount) else { return }
        snoozeCount += 1
        isRinging = false
        SleepAlarmScheduler.cancelFailsafe(alarmID: alarm.id)
        UIApplication.shared.isIdleTimerDisabled = false
        SleepWakePlayer.shared.stop()
        Task {
            let scheduled = await SleepAlarmScheduler.scheduleSnooze(alarm: alarm)
            if !scheduled {
                await MainActor.run { self.ring(alarm) }
            }
        }
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
        SleepAlarmScheduler.cancelFailsafe(alarmID: alarm.id)
        UIApplication.shared.isIdleTimerDisabled = false
        SleepWakePlayer.shared.stop()
        let scheduled = await SleepAlarmScheduler.scheduleSnooze(alarm: alarm)
        if !scheduled {
            await MainActor.run { ring(alarm) }
        }
    }
}

enum WakeScreenPreferences {
    private static let greetingKey = "forge.wake.greeting"
    private static let weatherKey = "forge.wake.showWeather"
    private static let workoutKey = "forge.wake.showWorkout"
    private static let sleepKey = "forge.wake.showSleepScore"

    static var greeting: String {
        get { UserDefaults.standard.string(forKey: greetingKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: greetingKey) }
    }

    static var showWeather: Bool {
        get { UserDefaults.standard.object(forKey: weatherKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: weatherKey) }
    }

    static var showWorkout: Bool {
        get { UserDefaults.standard.object(forKey: workoutKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: workoutKey) }
    }

    static var showSleepScore: Bool {
        get { UserDefaults.standard.object(forKey: sleepKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: sleepKey) }
    }
}

struct SleepWakeScreen: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var wake = SleepWakeStore.shared
    @ObservedObject private var alarms = ForgeAlarmStore.shared
    @State private var doneRoutine: Set<UUID> = []
    @State private var tick = Date()
    private let player = SleepWakePlayer.shared

    private var alarm: ForgeAlarm { wake.current ?? ForgeAlarm() }

    private var progress: Double {
        min(1, Date().timeIntervalSince(wake.startedAt) / 24)
    }

    private var clock: String {
        tick.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        @Bindable var player = player
        ZStack {
            sunrise
            VStack(spacing: FDS.Spacing.xl) {
                Spacer()
                VStack(spacing: FDS.Spacing.sm) {
                    ZStack {
                        SleepWakeHudRing(progress: progress)
                        Text(clock)
                            .font(.system(size: 64, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .monospacedDigit()
                    }
                    Text(alarm.label)
                        .font(FDS.TypeScale.Dynamic.headline)
                        .foregroundColor(.white.opacity(0.72))
                    if player.stage != .primary {
                        Text(player.stage == .insistent
                             ? "Backup tone + pulse. Hold I'm up."
                             : "Backup tone. Still time to get up.")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.82))
                    }
                    if player.fault.isFailClosed {
                        Text(player.fault.coachLine)
                            .font(FDS.TypeScale.Dynamic.caption)
                            .foregroundColor(.white.opacity(0.88))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, FDS.Spacing.xl)
                            .padding(.top, FDS.Spacing.xs)
                    }
                    if !WakeScreenPreferences.greeting.isEmpty {
                        Text(WakeScreenPreferences.greeting)
                            .font(FDS.TypeScale.Dynamic.body)
                            .foregroundColor(.white.opacity(0.82))
                    }
                    if WakeScreenPreferences.showSleepScore {
                        Text(SleepWakeCoach.morningPrompt(
                            sleepScore: store.sleepData.first?.score,
                            lastNightHours: store.sleepData.first?.totalHours
                        ))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.78))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, FDS.Spacing.xl)
                        .padding(.top, FDS.Spacing.sm)
                    }
                    if WakeScreenPreferences.showWorkout, let name = store.todayWorkout?.name {
                        Text(name)
                            .font(FDS.TypeScale.Dynamic.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }

                VStack(alignment: .leading, spacing: FDS.Spacing.sm) {
                    ForEach(alarms.routine.filter(\.isEnabled).prefix(3)) { item in
                        Button {
                            if doneRoutine.contains(item.id) { doneRoutine.remove(item.id) }
                            else { doneRoutine.insert(item.id) }
                        } label: {
                            HStack(spacing: FDS.Spacing.md) {
                                Image(systemName: doneRoutine.contains(item.id) ? "checkmark.circle.fill" : item.icon)
                                    .foregroundColor(doneRoutine.contains(item.id) ? .white : .white.opacity(0.7))
                                Text(item.name)
                                    .font(FDS.TypeScale.Dynamic.body.weight(.semibold))
                                    .foregroundColor(.white)
                                Spacer()
                                Text("\(item.duration) min")
                                    .font(FDS.TypeScale.Dynamic.caption)
                                    .foregroundColor(.white.opacity(0.55))
                            }
                            .padding(.horizontal, FDS.Spacing.lg)
                            .padding(.vertical, FDS.Spacing.md)
                            .background(Color.white.opacity(doneRoutine.contains(item.id) ? 0.22 : 0.10))
                            .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, FDS.Spacing.xl)

                HoldToWakeButton { wake.dismiss() }

                if wake.remainingSnoozes > 0 {
                    Button {
                        wake.snooze()
                    } label: {
                        Text("Snooze \(alarm.snoozeMinutes) min · \(wake.remainingSnoozes) left")
                            .font(FDS.TypeScale.Dynamic.body.weight(.semibold))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Snooze. \(wake.remainingSnoozes) remaining.")
                } else {
                    Text("No snoozes left. Get up.")
                        .font(FDS.TypeScale.Dynamic.caption)
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
                    HStack(spacing: FDS.Spacing.sm) {
                        ARIAIdentityMark(state: .idle, mood: .energized, size: 16, amplitude: 0.22)
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
                    Color(red: 0.03, green: 0.05, blue: 0.10),
                    Color(red: 0.08 + 0.12 * t, green: 0.16 + 0.18 * t, blue: 0.28 + 0.22 * t),
                    Color(red: 0.98, green: 0.55 + 0.2 * t, blue: 0.22 + 0.18 * t)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [Color(hex: SleepHud.plateHex).opacity(0.18 + 0.35 * t), .clear],
                center: UnitPoint(x: 0.5, y: 0.22),
                startRadius: 8,
                endRadius: 220
            )
            RadialGradient(
                colors: [Color.ember.opacity(0.12 + 0.45 * t), .clear],
                center: UnitPoint(x: 0.5, y: 0.78),
                startRadius: 10,
                endRadius: 280
            )
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 1.0), value: t)
    }
}

struct SleepWakeHudRing: View {
    var progress: Double

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outer = s / 2 - 2
            let plate = Color(hex: SleepHud.plateHex)
            for i in 0..<SleepHud.tickCount {
                let major = i.isMultiple(of: 6)
                let angle = Double(i) / Double(SleepHud.tickCount) * .pi * 2 - .pi / 2
                let inner = outer - (major ? 10 : 5)
                var path = Path()
                path.move(to: CGPoint(
                    x: center.x + CGFloat(cos(angle)) * inner,
                    y: center.y + CGFloat(sin(angle)) * inner
                ))
                path.addLine(to: CGPoint(
                    x: center.x + CGFloat(cos(angle)) * outer,
                    y: center.y + CGFloat(sin(angle)) * outer
                ))
                context.stroke(
                    path,
                    with: .color(major ? plate.opacity(0.85) : plate.opacity(0.28)),
                    lineWidth: major ? 1.6 : 0.8
                )
            }
            var arc = Path()
            arc.addArc(
                center: center,
                radius: outer - 16,
                startAngle: .degrees(-90),
                endAngle: .degrees(-90 + 360 * min(1, max(0, progress))),
                clockwise: false
            )
            context.stroke(arc, with: .color(Color.ember.opacity(0.9)), lineWidth: 3)
        }
        .frame(width: 220, height: 220)
        .accessibilityHidden(true)
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
                .font(FDS.TypeScale.Dynamic.headline)
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
            lastNightHours: appStore.sleepData.first?.totalHours,
            smartWindowMinutes: store.next.map {
                hkService.adaptiveSmartWakeMinutes(base: $0.smartWakeWindow, depth: store.sleeperDepth)
            }
        )
    }

    var body: some View {
        VStack(spacing: FDS.Spacing.lg) {
            NextWakePlanCard(coach: coach)

            SleeperDepthCard(
                depth: Binding(
                    get: { store.sleeperDepth },
                    set: { store.setSleeperDepth($0) }
                )
            )

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
                        get: { store.next?.smartWakeWindow ?? store.sleeperDepth.defaultWindow },
                        set: { mins in
                            guard var next = store.next else { return }
                            next.smartWakeWindow = mins
                            store.upsert(next)
                        }
                    ),
                    adaptedMinutes: store.next.map {
                        hkService.adaptiveSmartWakeMinutes(base: $0.smartWakeWindow, depth: store.sleeperDepth)
                    } ?? store.sleeperDepth.defaultWindow,
                    windowChoices: store.sleeperDepth.windowChoices
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
            .onChange(of: sunriseDuration) { _, value in
                hkService.applySunriseOverrides(durationMinutes: value, colorTemp: colorTemp)
            }
            .onChange(of: colorTemp) { _, value in
                hkService.applySunriseOverrides(durationMinutes: sunriseDuration, colorTemp: value)
            }

            WakeGreetingCard()

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
        WakeUpSection(icon: "sun.horizon.fill", title: "This wake", color: Color.amber) {
            VStack(alignment: .leading, spacing: FDS.Spacing.md) {
                Text(coach.headline)
                    .font(FDS.TypeScale.Dynamic.metric)
                    .foregroundColor(.textPrimary)
                Text(coach.cue)
                    .font(.system(size: 13))
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let smart = coach.smartFire, let hard = coach.hardFire {
                    Text("Smart \(smart.formatted(date: .omitted, time: .shortened))  ·  Hard \(hard.formatted(date: .omitted, time: .shortened))")
                        .font(FDS.TypeScale.Dynamic.caption)
                        .foregroundColor(.textTertiary)
                }
                Button {
                    store.openChat(with: coach.ariaPrompt, voice: false)
                } label: {
                    HStack(spacing: FDS.Spacing.sm) {
                        ARIAIdentityMark(state: .idle, mood: .energized, size: 16, amplitude: 0.22)
                        Text("Ask ARIA about this morning")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.ember)
                    .padding(FDS.Spacing.md)
                    .background(Color.ember.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct SleeperDepthCard: View {
    @Binding var depth: SleeperDepth

    var body: some View {
        WakeUpSection(icon: "bed.double.fill", title: "How you sleep", color: Color(hex: SleepHud.plateHex)) {
            VStack(alignment: .leading, spacing: FDS.Spacing.md) {
                Text("Deep and super-deep sleepers get a longer Smart Wake lead and a slower volume climb. Lifestyle coaching — iPhone cannot read live stage.")
                    .font(.system(size: 12))
                    .foregroundColor(.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: FDS.Spacing.sm) {
                    ForEach(SleeperDepth.allCases, id: \.self) { option in
                        Button {
                            depth = option
                            UISelectionFeedbackGenerator().selectionChanged()
                        } label: {
                            Text(option.title)
                                .font(FDS.TypeScale.Dynamic.caption)
                                .foregroundColor(depth == option ? .white : .textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, FDS.Spacing.md)
                                .background(depth == option ? Color(hex: SleepHud.plateHex) : Color.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct SmartWakeCard: View {
    @Binding var enabled: Bool
    @Binding var windowMinutes: Int
    var adaptedMinutes: Int
    var windowChoices: [Int] = [15, 30, 45]

    var body: some View {
        VStack(spacing: 0) {
            WakeUpSection(icon: "waveform.path.ecg", title: "Smart Wake", color: .steel) {
                VStack(spacing: FDS.Spacing.lg) {
                    Toggle(isOn: $enabled) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Earlier nudge, then the hard alarm")
                                .font(FDS.TypeScale.Dynamic.body.weight(.semibold)).foregroundColor(.textPrimary)
                            Text("When Apple delivers a sample in the window, Forge can nudge earlier if you're in light or core sleep. iPhone cannot stream live stage. Tonight's lead is \(adaptedMinutes) min from last night's score, debt, and how heavy you sleep — your pick is the base. The hard alarm still stands.")
                                .font(.system(size: 12)).foregroundColor(.textTertiary).lineSpacing(3)
                        }
                    }
                    .tint(.steel)

                    if enabled {
                        VStack(alignment: .leading, spacing: FDS.Spacing.md) {
                            Text("Lead window")
                                .font(FDS.TypeScale.Dynamic.caption).foregroundColor(.textSecondary)
                            HStack(spacing: FDS.Spacing.md) {
                                ForEach(windowChoices, id: \.self) { mins in
                                    Button {
                                        windowMinutes = mins
                                        UISelectionFeedbackGenerator().selectionChanged()
                                    } label: {
                                        VStack(spacing: FDS.Spacing.xs) {
                                            Text("\(mins)")
                                                .font(FDS.TypeScale.Dynamic.metric)
                                                .foregroundColor(windowMinutes == mins ? .white : .textPrimary)
                                            Text("min")
                                                .font(FDS.TypeScale.Dynamic.micro)
                                                .foregroundColor(windowMinutes == mins ? .white.opacity(0.7) : .textTertiary)
                                        }
                                        .frame(maxWidth: .infinity).padding(.vertical, FDS.Spacing.md)
                                        .background(windowMinutes == mins ? Color.steel : Color.surfaceElevated)
                                        .cornerRadius(FDS.Radius.md)
                                        .shadow(color: windowMinutes == mins ? Color.steel.opacity(0.35) : .clear, radius: 8, y: 4)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            // Visual representation
                            HStack(spacing: 0) {
                                Spacer()
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: FDS.Radius.xs).fill(Color.borderColor.opacity(0.3)).frame(height: 8)
                                    RoundedRectangle(cornerRadius: FDS.Radius.xs)
                                        .fill(LinearGradient(colors: [Color.steel.opacity(0.3), Color.steel], startPoint: .leading, endPoint: .trailing))
                                        .frame(width: CGFloat(windowMinutes) / CGFloat(windowChoices.last ?? 45) * 200, height: 8)
                                }
                                .frame(width: 200)
                                VStack(alignment: .trailing, spacing: 2) {
                                    Image(systemName: "alarm.fill").font(.system(size: 12)).foregroundColor(.ember)
                                    Text("Alarm").font(FDS.TypeScale.Dynamic.micro).foregroundColor(.textMuted)
                                }
                                .padding(.leading, FDS.Spacing.sm)
                            }
                            .padding(.top, FDS.Spacing.xs)
                        }
                        .padding(FDS.Spacing.md).background(Color.steel.opacity(0.06)).cornerRadius(FDS.Radius.md)
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                    }
                }
            }
        }
    }
}

struct VolumeRampCard: View {
    @Binding var curve: VolumeRampCurve

    var body: some View {
        WakeUpSection(icon: "speaker.wave.3.fill", title: "Volume Ramp", color: .ember) {
            VStack(spacing: FDS.Spacing.md) {
                ForEach(VolumeRampCurve.allCases, id: \.self) { option in
                    Button {
                        curve = option
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        HStack(spacing: FDS.Spacing.lg) {
                            ZStack {
                                Circle().fill(curve == option ? Color.ember.opacity(0.15) : Color.surfaceElevated)
                                    .frame(width: 38, height: 38)
                                Image(systemName: option.icon)
                                    .font(.system(size: 15))
                                    .foregroundColor(curve == option ? .ember : .textTertiary)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(option.rawValue).font(FDS.TypeScale.Dynamic.body.weight(.semibold)).foregroundColor(.textPrimary)
                                Text(option.description).font(.system(size: 12)).foregroundColor(.textTertiary)
                            }
                            Spacer()
                            if curve == option {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 18)).foregroundColor(.ember)
                            }
                        }
                        .padding(.horizontal, FDS.Spacing.lg).padding(.vertical, FDS.Spacing.md)
                        .background(curve == option ? Color.ember.opacity(0.07) : Color.surfaceElevated)
                        .cornerRadius(FDS.Radius.md)
                        .overlay(RoundedRectangle(cornerRadius: FDS.Radius.md).stroke(curve == option ? Color.ember.opacity(0.4) : Color.borderColor.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }

                Text(WakeStruggleStore.isRepeatStruggler()
                     ? "Mornings have been sticky, so this wake starts loud and a backup tone takes over sooner."
                     : "Volume climbs, then a backup tone if you're still down.")
                    .font(.system(size: 12))
                    .foregroundColor(.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                VolumeRampPreview(curve: curve)
            }
        }
    }
}

struct VolumeRampPreview: View {
    let curve: VolumeRampCurve

    private func height(for x: CGFloat) -> CGFloat {
        CGFloat(SleepVolumeRamp.gain(
            elapsed: TimeInterval(x) * curve.rampSeconds,
            seconds: curve.rampSeconds
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.sm) {
            Text("Volume preview")
                .font(FDS.TypeScale.Dynamic.micro).foregroundColor(.textMuted)
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
            .cornerRadius(FDS.Radius.xs)
        }
        .padding(FDS.Spacing.md).forgeInsetTile(radius: FDS.Radius.md)
    }
}

struct MorningRoutineCard: View {
    @Binding var items: [RoutineItem]
    @State private var editMode = false

    var totalMinutes: Int { items.filter { $0.isEnabled }.reduce(0) { $0 + $1.duration } }

    var body: some View {
        WakeUpSection(icon: "checklist", title: "Morning Routine", color: .success) {
            VStack(spacing: FDS.Spacing.md) {
                HStack {
                    Text("Total: \(totalMinutes) min")
                        .font(FDS.TypeScale.Dynamic.caption).foregroundColor(.textSecondary)
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { editMode.toggle() }
                    } label: {
                        Text(editMode ? "Done" : "Edit")
                            .font(FDS.TypeScale.Dynamic.caption).foregroundColor(.success)
                    }
                }

                ForEach($items) { $item in
                    HStack(spacing: FDS.Spacing.md) {
                        // Drag handle (visible in edit mode)
                        if editMode {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 14)).foregroundColor(.textMuted)
                        }

                        Toggle(isOn: $item.isEnabled) {
                            HStack(spacing: FDS.Spacing.md) {
                                ZStack {
                                    Circle().fill(item.isEnabled ? Color.success.opacity(0.15) : Color.surfaceElevated)
                                        .frame(width: 36, height: 36)
                                    Image(systemName: item.icon)
                                        .font(.system(size: 14))
                                        .foregroundColor(item.isEnabled ? .success : .textMuted)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(FDS.TypeScale.Dynamic.body)
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
                    .padding(.horizontal, FDS.Spacing.md).padding(.vertical, FDS.Spacing.md)
                    .forgeInsetTile(radius: FDS.Radius.md)
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

    @State private var greeting = WakeScreenPreferences.greeting
    @State private var showWeather = WakeScreenPreferences.showWeather
    @State private var showWorkout = WakeScreenPreferences.showWorkout
    @State private var showSleepScore = WakeScreenPreferences.showSleepScore

    private var firstName: String {
        store.userProfile.name.components(separatedBy: " ").first ?? ""
    }

    /// The greeting this person would write for themselves, not the one the
    /// demo shipped with. It used to read "Good morning, Akshith" for everybody.
    private var defaultGreeting: String {
        firstName.isEmpty ? "Good morning 🌅" : "Good morning, \(firstName) 🌅"
    }

    var body: some View {
        WakeUpSection(icon: "hand.wave.fill", title: "Wake Screen", color: Color.amber) {
            VStack(spacing: FDS.Spacing.lg) {
                // Preview
                ZStack {
                    RoundedRectangle(cornerRadius: FDS.Radius.lg)
                        .fill(LinearGradient(colors: [Color(hex: "0F172A"), Color(hex: "1E293B")], startPoint: .top, endPoint: .bottom))
                    VStack(spacing: FDS.Spacing.md) {
                        Text("6:45 AM")
                            .font(.system(size: 36, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Text(greeting)
                            .font(FDS.TypeScale.Dynamic.caption)
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                        HStack(spacing: FDS.Spacing.lg) {
                            if showSleepScore {
                                let score = store.sleepData.first.map { "Sleep \($0.score)" } ?? "Sleep"
                                Label(score, systemImage: "moon.stars.fill").foregroundColor(.steel)
                            }
                            if showWeather   { Label("Local weather", systemImage: "sun.max.fill").foregroundColor(Color.amber) }
                            if showWorkout   {
                                Label(store.todayWorkout?.name ?? "Rest day", systemImage: "dumbbell.fill").foregroundColor(.ember)
                            }
                        }
                        .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(FDS.Spacing.lg)
                }
                .frame(height: 140)

                // Greeting field
                TextField("Wake greeting…", text: $greeting)
                    .font(.system(size: 14)).foregroundColor(.textPrimary).tint(Color.amber)
                    .padding(.horizontal, FDS.Spacing.lg).padding(.vertical, FDS.Spacing.md)
                    .forgeInsetTile(radius: FDS.Radius.md)

                // Toggles
                VStack(spacing: 2) {
                    WakeToggle(label: "Show sleep score", value: $showSleepScore, color: .steel)
                    WakeToggle(label: "Show weather",     value: $showWeather,    color: Color.amber)
                    WakeToggle(label: "Show today's workout", value: $showWorkout, color: .ember)
                }
            }
        }
        .onAppear {
            if greeting.isEmpty { greeting = defaultGreeting }
        }
        .onChange(of: greeting) { _, value in WakeScreenPreferences.greeting = value }
        .onChange(of: showWeather) { _, value in WakeScreenPreferences.showWeather = value }
        .onChange(of: showWorkout) { _, value in WakeScreenPreferences.showWorkout = value }
        .onChange(of: showSleepScore) { _, value in WakeScreenPreferences.showSleepScore = value }
    }
}

struct WakeToggle: View {
    let label: String
    @Binding var value: Bool
    let color: Color
    var body: some View {
        Toggle(isOn: $value) {
            Text(label).font(FDS.TypeScale.Dynamic.body).foregroundColor(.textPrimary)
        }
        .tint(color)
        .padding(.horizontal, FDS.Spacing.lg).padding(.vertical, FDS.Spacing.md)
        .forgeInsetTile(radius: FDS.Radius.md)
    }
}

struct WakeUpSection<Content: View>: View {
    let icon: String
    let title: String
    let color: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.lg) {
            HStack(spacing: FDS.Spacing.md) {
                ZStack {
                    Circle().fill(color.opacity(0.15)).frame(width: 36, height: 36)
                    Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundColor(color)
                }
                Text(title).font(FDS.TypeScale.Dynamic.headline).foregroundColor(.textPrimary)
            }
            content()
        }
        .padding(FDS.Spacing.lg)
        .forgeGlassCard(cornerRadius: FDS.Radius.xl, accent: .aurora)
    }
}

struct ChronotypeBadge: View {
    @EnvironmentObject var hkService: HealthKitSleepService
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: FDS.Spacing.md) {
                Image(systemName: hkService.userProfile.chronotype.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.steel)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(hkService.userProfile.chronotype.displayName) Chronotype")
                        .font(FDS.TypeScale.Dynamic.caption)
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
            .padding(.vertical, FDS.Spacing.md)
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
        WakeUpSection(icon: "sunrise.fill", title: "Adaptive Sunrise", color: Color.amber) {
            VStack(spacing: FDS.Spacing.lg) {
                Toggle(isOn: $enabled) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Gradual light increase")
                            .font(FDS.TypeScale.Dynamic.body.weight(.semibold)).foregroundColor(.textPrimary)
                        Text(config.rationale)
                            .font(.system(size: 12)).foregroundColor(.textTertiary)
                    }
                }
                .tint(Color.amber)

                if enabled {
                    VStack(spacing: FDS.Spacing.lg) {
                        HStack {
                            Text("Duration").font(FDS.TypeScale.Dynamic.caption).foregroundColor(.textSecondary)
                            Spacer()
                            HStack(spacing: FDS.Spacing.xs) {
                                Text("\(duration) min")
                                    .font(FDS.TypeScale.Dynamic.body.weight(.semibold)).foregroundColor(.textPrimary)
                                Stepper("", value: $duration, in: 5...60, step: 5)
                                    .labelsHidden().tint(Color.amber)
                            }
                        }

                        VStack(alignment: .leading, spacing: FDS.Spacing.md) {
                            HStack {
                                Text("Color Temperature").font(FDS.TypeScale.Dynamic.caption).foregroundColor(.textSecondary)
                                Spacer()
                                Text(colorTemp < 0.3 ? "2700K Warm" : colorTemp < 0.7 ? "3500K Neutral" : "5000K Cool")
                                    .font(FDS.TypeScale.Dynamic.caption).foregroundColor(displayColor)
                            }
                            ZStack(alignment: .bottom) {
                                LinearGradient(
                                    colors: [Color(hex: "FF8C42"), Color(hex: "FFD166"), Color(hex: "FEFAE0"), Color(hex: "C8E6FF")],
                                    startPoint: .leading, endPoint: .trailing
                                )
                                .frame(height: 24).cornerRadius(FDS.Radius.md)
                                Slider(value: $colorTemp)
                                    .tint(.clear)
                                    .padding(.horizontal, 2)
                            }
                        }

                        HStack(spacing: FDS.Spacing.sm) {
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
                    .padding(FDS.Spacing.md).background(Color.amber.opacity(0.06)).cornerRadius(FDS.Radius.md)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                }
            }
        }
    }
}
