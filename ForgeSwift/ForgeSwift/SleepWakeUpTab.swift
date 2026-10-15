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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var clockSize: CGFloat = 48
    private let player = SleepWakePlayer.shared

    private var alarm: ForgeAlarm { wake.current ?? ForgeAlarm() }

    private func progress(at date: Date) -> Double {
        min(1, date.timeIntervalSince(wake.startedAt) / 24)
    }

    private var morningPrompt: String {
        SleepWakeCoach.morningPrompt(
            sleepScore: SleepData.lastNight(in: store.sleepData)?.score,
            lastNightHours: SleepData.lastNight(in: store.sleepData)?.totalHours
        )
    }

    var body: some View {
        TimelineView(.periodic(
            from: .now,
            by: Date().timeIntervalSince(wake.startedAt) < 24 ? 1 : 60
        )) { context in
            let now = context.date
            let progress = progress(at: now)
            ZStack {
                sunrise(progress: progress)
                VStack(spacing: 0) {
                    GeometryReader { geo in
                        ScrollView(showsIndicators: false) {
                            upperContent(progress: progress, date: now)
                                .frame(maxWidth: .infinity, minHeight: geo.size.height)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                    }
                    controls
                }
            }
            .interactiveDismissDisabled()
            .onAppear {
                SleepWakePlayer.shared.ensurePlaying(for: alarm)
            }
        }
    }

    // MARK: Upper content (scrolls when space runs out)

    private func upperContent(progress: Double, date: Date) -> some View {
        VStack(spacing: FDS.Spacing.xl) {
            VStack(spacing: FDS.Spacing.sm) {
                clockRing(progress: progress, date: date)
                Text(alarm.label)
                    .font(FDS.TypeScale.Dynamic.headline)
                    .foregroundColor(.white.opacity(0.82))
                    .multilineTextAlignment(.center)
                statusLines
            }
            routineRows
        }
        .padding(.horizontal, FDS.Spacing.xl)
        .padding(.vertical, FDS.Spacing.lg)
    }

    private func clockRing(progress: Double, date: Date) -> some View {
        ZStack {
            SleepWakeHudRing(progress: progress)
            Text(date.formatted(date: .omitted, time: .shortened))
                .font(.system(
                    size: ForgeLayout.scaledCap(clockSize, base: 48, maxGrowth: 1.3),
                    weight: .semibold,
                    design: .rounded
                ))
                .foregroundColor(.white)
                .monospacedDigit()
                .hudInArcText()
                .contentTransition(.numericText())
                .padding(.horizontal, FDS.Spacing.xl)
        }
    }

    @ViewBuilder
    private var statusLines: some View {
        if player.stage != .primary {
            Text(player.stage == .insistent
                 ? "Backup tone + pulse. Hold I'm up."
                 : "Backup tone. Still time to get up.")
                .font(HomeType.body)
                .foregroundColor(.white.opacity(0.88))
                .multilineTextAlignment(.center)
                .forgeWrapping()
        }
        if player.fault.isFailClosed {
            Text(player.fault.coachLine)
                .font(HomeType.body)
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .forgeWrapping()
                .padding(.top, FDS.Spacing.xs)
        }
        if !WakeScreenPreferences.greeting.isEmpty {
            Text(WakeScreenPreferences.greeting)
                .font(HomeType.body)
                .foregroundColor(.white.opacity(0.88))
                .multilineTextAlignment(.center)
                .forgeWrapping()
        }
        if WakeScreenPreferences.showSleepScore {
            Text(morningPrompt)
                .font(HomeType.body)
                .foregroundColor(.white.opacity(0.84))
                .multilineTextAlignment(.center)
                .forgeWrapping()
                .padding(.top, FDS.Spacing.sm)
        }
        if WakeScreenPreferences.showWorkout, let name = store.todayWorkout?.name {
            Text(name)
                .font(HomeType.label)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .forgeWrapping()
        }
    }

    private var routineRows: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.sm) {
            ForEach(alarms.routine.filter(\.isEnabled).prefix(3)) { item in
                routineRow(item)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func routineRow(_ item: RoutineItem) -> some View {
        let done = doneRoutine.contains(item.id)
        return Button {
            FDS.haptic(.select)
            if done { doneRoutine.remove(item.id) }
            else { doneRoutine.insert(item.id) }
        } label: {
            HStack(spacing: FDS.Spacing.md) {
                Image(systemName: done ? "checkmark.circle.fill" : item.icon)
                    .foregroundColor(done ? .white : .white.opacity(0.78))
                    .accessibilityHidden(true)
                Text(item.name)
                    .font(HomeType.status)
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .layoutPriority(1)
                Spacer(minLength: FDS.Spacing.xs)
                Text("\(item.duration) min")
                    .font(HomeType.label)
                    .monospacedDigit()
                    .foregroundColor(.white.opacity(0.78))
                    .lineLimit(1)
            }
            .padding(.horizontal, FDS.Spacing.lg)
            .padding(.vertical, FDS.Spacing.md)
            .frame(minHeight: ForgeUX.minTap)
            .background(Color.white.opacity(done ? 0.22 : 0.10))
            .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.name), \(item.duration) minutes")
        .accessibilityAddTraits(done ? .isSelected : [])
    }

    // MARK: Controls (always visible)

    private var controls: some View {
        VStack(spacing: FDS.Spacing.md) {
            HoldToWakeButton { wake.dismiss() }
            snoozeControl
            askAriaButton
        }
        .padding(.horizontal, FDS.Spacing.xl)
        .padding(.top, FDS.Spacing.sm)
        .padding(.bottom, FDS.Spacing.lg)
    }

    @ViewBuilder
    private var snoozeControl: some View {
        if wake.remainingSnoozes > 0 {
            Button {
                wake.snooze()
            } label: {
                Text("Snooze \(alarm.snoozeMinutes) min · \(wake.remainingSnoozes) left")
                    .font(HomeType.status)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Capsule().fill(Color.white.opacity(0.10)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Snooze. \(wake.remainingSnoozes) remaining.")
        } else {
            Text("No snoozes left. Get up.")
                .font(HomeType.body)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .forgeWrapping()
        }
    }

    private var askAriaButton: some View {
        Button {
            let prompt = morningPrompt
            wake.dismiss()
            store.openChat(with: prompt, voice: false)
        } label: {
            HStack(spacing: FDS.Spacing.sm) {
                ARIAIdentityMark(state: .idle, mood: .energized, size: 16, amplitude: 0.22)
                Text("Ask ARIA to start the morning")
                    .font(HomeType.label)
                    .multilineTextAlignment(.leading)
            }
            .foregroundColor(.white.opacity(0.9))
            .frame(minHeight: ForgeUX.minTap)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sunrise(progress: Double) -> some View {
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
                colors: [HudChrome.plate.opacity(0.18 + 0.35 * t), .clear],
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
        .animation(reduceMotion ? nil : Animation.easeInOut(duration: 1.0), value: t)
    }
}

struct SleepWakeHudRing: View {
    var progress: Double
    @ScaledMetric(relativeTo: .largeTitle) private var ringSize: CGFloat = 220

    var body: some View {
        let side = ForgeLayout.scaledCap(ringSize, base: 220, maxGrowth: 1.15)
        Canvas { context, size in
            let s = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outer = s / 2 - 2
            let plate = HudChrome.plate
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
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

struct HoldToWakeButton: View {
    let action: () -> Void
    @State private var progress: CGFloat = 0
    @State private var holdTask: Task<Void, Never>?

    var body: some View {
        Text(progress > 0.05 ? "Keep holding" : "Hold — I'm up")
            .font(FDS.TypeScale.Dynamic.headline)
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, FDS.Spacing.lg)
            .padding(.vertical, FDS.Spacing.md)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(Capsule().fill(Color.white.opacity(0.14)))
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule()
                        .fill(Color.white.opacity(0.32))
                        .frame(width: geo.size.width * progress)
                }
            }
            .clipShape(Capsule())
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in beginHold() }
                    .onEnded { _ in cancelHold() }
            )
            .accessibilityLabel("Hold to dismiss. I'm up.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }

    private func beginHold() {
        guard holdTask == nil else { return }
        withAnimation(.linear(duration: 1.2)) { progress = 1 }
        holdTask = Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            FDS.haptic(.success)
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
            sleepScore: SleepData.lastNight(in: appStore.sleepData)?.score,
            lastNightHours: SleepData.lastNight(in: appStore.sleepData)?.totalHours,
            smartWindowMinutes: store.next.map {
                hkService.adaptiveSmartWakeMinutes(base: $0.smartWakeWindow, depth: store.sleeperDepth)
            }
        )
    }

    var body: some View {
        VStack(spacing: ForgeLayout.sectionGap) {
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

/// The Wake tab's hero: the next alarm time, the cue and the one Ask ARIA entry point.
struct NextWakePlanCard: View {
    let coach: SleepWakeCoach
    @EnvironmentObject private var store: AppStore

    private var smartHardLine: String? {
        guard let smart = coach.smartFire, let hard = coach.hardFire else { return nil }
        let smartText = smart.formatted(date: .omitted, time: .shortened)
        let hardText = hard.formatted(date: .omitted, time: .shortened)
        return "Smart \(smartText)  ·  Hard \(hardText)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.heroGap) {
            ForgeCardHeader(title: "This wake", tint: .steel) {
                if coach.smartFire != nil {
                    HudVibeChip(label: "Smart wake", energy: .steel)
                }
            }
            leadBlock
            Text(coach.cue)
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
            if let line = smartHardLine {
                Text(line)
                    .font(HomeType.label)
                    .foregroundStyle(Color.textTertiary)
                    .forgeWrapping()
            }
            askAriaButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .hudPlate(energy: .steel)
        .accessibilityElement(children: .contain)
    }

    private var leadBlock: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
            if let hard = coach.hardFire {
                Text(hard.formatted(date: .omitted, time: .shortened))
                    .font(HomeType.heroScore)
                    .foregroundStyle(Color.textPrimary)
                    .forgeSingleLine()
                    .contentTransition(.numericText())
                Text(coach.headline)
                    .font(HomeType.status)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
            } else {
                Text(coach.headline)
                    .font(HomeType.sessionTitle)
                    .foregroundStyle(Color.textPrimary)
                    .forgeWrapping()
            }
        }
    }

    private var askAriaButton: some View {
        Button {
            FDS.haptic(.press)
            store.openChat(with: coach.ariaPrompt, voice: false)
        } label: {
            HStack(spacing: FDS.Spacing.sm) {
                ARIAIdentityMark(state: .idle, mood: .energized, size: 16, amplitude: 0.22)
                Text("Ask ARIA about this morning")
                    .font(HomeType.label)
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: FDS.Spacing.xs)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: ForgeUX.minTap - 2 * ForgeLayout.tilePadding, alignment: .leading)
            .forgeWell()
        }
        .buttonStyle(ForgePressStyle())
    }
}

struct SleeperDepthCard: View {
    @Binding var depth: SleeperDepth

    private var depthOptions: [ForgeSegmentOption<SleeperDepth>] {
        SleeperDepth.allCases.map { ForgeSegmentOption(value: $0, title: $0.title) }
    }

    var body: some View {
        WakeUpSection(icon: "bed.double.fill", title: "How you sleep", color: .steel) {
            VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
                Text("Deep and super-deep sleepers get a longer Smart Wake lead and a slower volume climb. Lifestyle coaching — iPhone cannot read live stage.")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
                ForgeSegmentedControl(
                    depthOptions,
                    selection: $depth,
                    accent: .steel,
                    bleed: ForgeLayout.cardPadding
                )
            }
        }
    }
}

struct SmartWakeCard: View {
    @Binding var enabled: Bool
    @Binding var windowMinutes: Int
    var adaptedMinutes: Int
    var windowChoices: [Int] = [15, 30, 45]

    @State private var showDetail = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var leadOptions: [ForgeSegmentOption<Int>] {
        windowChoices.map { ForgeSegmentOption(value: $0, title: "\($0) min") }
    }

    private var detailText: String {
        "iPhone cannot stream live stage. Tonight's lead is \(adaptedMinutes) min from last night's score, debt, and how heavy you sleep — your pick is the base. The hard alarm still stands."
    }

    var body: some View {
        WakeUpSection(icon: "waveform.path.ecg", title: "Smart Wake", color: .steel) {
            VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
                Toggle(isOn: $enabled) {
                    Text("Earlier nudge, then the hard alarm")
                        .font(HomeType.status)
                        .foregroundStyle(Color.textPrimary)
                }
                .tint(.steel)
                .frame(minHeight: ForgeUX.minTap)

                explanation

                if enabled {
                    leadWindow
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                }
            }
        }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
            Text("When Apple delivers a sample in the window, Forge can nudge earlier if you're in light or core sleep.")
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
            if showDetail {
                Text(detailText)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
                    .transition(.opacity)
            }
            ForgeTextLink(title: "How Smart Wake works", accent: .steel, expanded: showDetail) {
                withAnimation(reduceMotion ? nil : FDS.Spring.standard) { showDetail.toggle() }
            }
        }
    }

    private var leadWindow: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            Text("Lead window")
                .font(HomeType.label)
                .foregroundStyle(Color.textSecondary)
            ForgeSegmentedControl(
                leadOptions,
                selection: $windowMinutes,
                accent: .steel,
                bleed: ForgeLayout.cardPadding + ForgeLayout.tilePadding
            )
            leadTimeline
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeWell()
    }

    private var leadTimeline: some View {
        let maxWindow = CGFloat(max(1, windowChoices.last ?? 45))
        let fraction = min(1, CGFloat(windowMinutes) / maxWindow)
        return HStack(spacing: FDS.Spacing.sm) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(LinearGradient(
                            colors: [Color.steel.opacity(0.3), Color.steel],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 8)
            VStack(spacing: ForgeLayout.labelValueGap) {
                Image(systemName: "alarm.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.steel)
                Text("Alarm")
                    .font(HomeType.micro)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Smart Wake starts \(windowMinutes) minutes before the alarm")
    }
}

struct VolumeRampCard: View {
    @Binding var curve: VolumeRampCurve

    var body: some View {
        WakeUpSection(icon: "speaker.wave.3.fill", title: "Volume Ramp", color: .steel) {
            VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
                VStack(spacing: ForgeLayout.tileGap) {
                    ForEach(VolumeRampCurve.allCases, id: \.self) { option in
                        rampRow(option)
                    }
                }

                Text(WakeStruggleStore.isRepeatStruggler()
                     ? "Mornings have been sticky, so this wake starts loud and a backup tone takes over sooner."
                     : "Volume climbs, then a backup tone if you're still down.")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()

                VolumeRampPreview(curve: curve)
            }
        }
    }

    private func rampRow(_ option: VolumeRampCurve) -> some View {
        let selected = curve == option
        return Button {
            curve = option
            FDS.haptic(.select)
        } label: {
            HStack(spacing: ForgeLayout.rowGap) {
                ForgeIconWell(
                    systemImage: option.icon,
                    tint: selected ? Color.steel : Color.textTertiary
                )
                VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                    Text(option.rawValue)
                        .font(HomeType.status)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(2)
                    Text(option.description)
                        .font(HomeType.body)
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(2)
                }
                .layoutPriority(1)
                Spacer(minLength: FDS.Spacing.xs)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.steel)
                        .accessibilityHidden(true)
                }
            }
            .forgeWell()
            .overlay(selectionStroke(selected))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(option.rawValue), \(option.description)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func selectionStroke(_ selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: ForgeLayout.innerRadius, style: .continuous)
            .strokeBorder(selected ? Color.steel.opacity(0.4) : Color.clear, lineWidth: 1)
    }
}

struct VolumeRampPreview: View {
    let curve: VolumeRampCurve
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func height(for x: CGFloat) -> CGFloat {
        CGFloat(SleepVolumeRamp.gain(
            elapsed: TimeInterval(x) * curve.rampSeconds,
            seconds: curve.rampSeconds
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.sm) {
            Text("Volume preview")
                .font(HomeType.micro)
                .foregroundStyle(Color.textTertiary)
            GeometryReader { geo in
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(0..<80, id: \.self) { i in
                        let x = CGFloat(i) / 79
                        let h = height(for: x)
                        Rectangle()
                            .fill(Color.steel.opacity(0.3 + h * 0.5))
                            .frame(width: geo.size.width / 80, height: geo.size.height * h)
                    }
                }
                .animation(reduceMotion ? nil : Animation.easeInOut(duration: 0.4), value: curve)
            }
            .frame(height: 44)
            .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.xs, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeWell()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Volume preview, \(curve.rawValue). \(curve.description)")
    }
}

struct MorningRoutineCard: View {
    @Binding var items: [RoutineItem]
    @State private var editMode = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var totalMinutes: Int { items.filter { $0.isEnabled }.reduce(0) { $0 + $1.duration } }

    private var motion: Animation? { reduceMotion ? nil : FDS.Spring.standard }

    var body: some View {
        WakeUpSection(icon: "checklist", title: "Morning Routine", color: .steel) {
            VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
                summaryRow

                VStack(spacing: ForgeLayout.rowGap) {
                    ForEach($items) { $item in
                        routineRow($item)
                    }
                    .onMove { from, to in items.move(fromOffsets: from, toOffset: to) }
                }
                .animation(motion, value: items.map { $0.id })
            }
        }
    }

    private var summaryRow: some View {
        HStack(spacing: FDS.Spacing.md) {
            Text("Total: \(totalMinutes) min")
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .monospacedDigit()
                .contentTransition(.numericText())
            Spacer(minLength: FDS.Spacing.sm)
            Button {
                FDS.haptic(.press)
                withAnimation(motion) { editMode.toggle() }
            } label: {
                Text(editMode ? "Done" : "Edit")
                    .font(HomeType.label)
                    .foregroundStyle(Color.steel)
                    .frame(minWidth: ForgeUX.minTap, minHeight: ForgeUX.minTap)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func routineRow(_ item: Binding<RoutineItem>) -> some View {
        let enabled = item.wrappedValue.isEnabled
        return VStack(alignment: .leading, spacing: ForgeLayout.tileGap) {
            Toggle(isOn: item.isEnabled) {
                HStack(spacing: ForgeLayout.rowGap) {
                    ForgeIconWell(
                        systemImage: item.wrappedValue.icon,
                        tint: enabled ? Color.steel : Color.textMuted
                    )
                    VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                        Text(item.wrappedValue.name)
                            .font(HomeType.status)
                            .foregroundStyle(enabled ? Color.textPrimary : Color.textTertiary)
                            .lineLimit(2)
                        Text("\(item.wrappedValue.duration) min")
                            .font(HomeType.micro)
                            .foregroundStyle(Color.textTertiary)
                            .monospacedDigit()
                    }
                }
            }
            .tint(.steel)

            if editMode {
                Stepper(value: item.duration, in: 1...60, step: 1) {
                    Text("Duration")
                        .font(HomeType.body)
                        .foregroundStyle(Color.textSecondary)
                }
                .tint(.steel)
                .accessibilityLabel("\(item.wrappedValue.name) duration")
                .accessibilityValue("\(item.wrappedValue.duration) minutes")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeWell()
        .animation(motion, value: enabled)
    }
}

struct WakeGreetingCard: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var alarms = ForgeAlarmStore.shared

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

    private var previewTime: String {
        let time = alarms.next?.time ?? ForgeAlarm().time
        return time.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        WakeUpSection(icon: "hand.wave.fill", title: "Wake Screen", color: .steel) {
            VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
                preview

                TextField("Wake greeting…", text: $greeting)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textPrimary)
                    .tint(Color.steel)
                    .accessibilityLabel("Wake greeting")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .forgeWell()

                VStack(spacing: 0) {
                    WakeToggle(label: "Show sleep score", value: $showSleepScore, color: .steel)
                    WakeToggle(label: "Show weather", value: $showWeather, color: .steel)
                    WakeToggle(label: "Show today's workout", value: $showWorkout, color: .steel)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .forgeWell()
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

    private var preview: some View {
        VStack(spacing: FDS.Spacing.md) {
            Text(previewTime)
                .font(HomeType.heroScore)
                .foregroundStyle(Color.white)
                .forgeSingleLine()
            Text(greeting)
                .font(HomeType.body)
                .foregroundStyle(Color.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .forgeWrapping()
            ForgeFlowLayout(spacing: FDS.Spacing.sm, lineSpacing: ForgeLayout.chipGap, alignment: .center) {
                if showSleepScore {
                    Label(sleepScoreText, systemImage: "moon.stars.fill")
                        .foregroundStyle(Color.steel)
                }
                if showWeather {
                    Label("Local weather", systemImage: "sun.max.fill")
                        .foregroundStyle(Color.amber)
                }
                if showWorkout {
                    Label(store.todayWorkout?.name ?? "Rest day", systemImage: "dumbbell.fill")
                        .foregroundStyle(Color.ember)
                }
            }
            .font(HomeType.micro)
        }
        .padding(FDS.Spacing.lg)
        .frame(maxWidth: .infinity, minHeight: 140)
        .background(
            RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous)
                .fill(Color.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: ForgeUX.hairline)
        )
        .accessibilityElement(children: .combine)
    }

    private var sleepScoreText: String {
        SleepData.lastNight(in: store.sleepData).map { "Sleep \($0.score)" } ?? "Sleep"
    }
}

struct WakeToggle: View {
    let label: String
    @Binding var value: Bool
    let color: Color
    var body: some View {
        Toggle(isOn: $value) {
            Text(label)
                .font(HomeType.status)
                .foregroundStyle(Color.textPrimary)
        }
        .tint(color)
        .frame(minHeight: ForgeUX.minTap)
    }
}

struct WakeUpSection<Content: View>: View {
    let icon: String
    let title: String
    let color: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader(title)
            content()
        }
        .forgeContentCard(tint: .steel)
    }
}

struct ChronotypeBadge: View {
    @EnvironmentObject var hkService: HealthKitSleepService
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: ForgeLayout.rowGap) {
                Image(systemName: hkService.userProfile.chronotype.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.steel)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                    Text("\(hkService.userProfile.chronotype.displayName) Chronotype")
                        .font(HomeType.status)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(2)
                    Text(hkService.userProfile.chronotype.tagline)
                        .font(HomeType.body)
                        .foregroundStyle(Color.textTertiary)
                        .forgeWrapping()
                }
                .layoutPriority(1)
                Spacer(minLength: FDS.Spacing.xs)
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, ForgeLayout.rowVerticalPadding)
            .frame(minHeight: ForgeUX.minTap)
            .contentShape(Rectangle())
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

    private var temperatureLabel: String {
        colorTemp < 0.3 ? "2700K Warm" : colorTemp < 0.7 ? "3500K Neutral" : "5000K Cool"
    }

    private var temperatureGradient: LinearGradient {
        LinearGradient(
            colors: SleepHud.sunriseRamp,
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    var body: some View {
        WakeUpSection(icon: "sunrise.fill", title: "Adaptive Sunrise", color: .steel) {
            VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
                Toggle(isOn: $enabled) {
                    Text("Gradual light increase")
                        .font(HomeType.status)
                        .foregroundStyle(Color.textPrimary)
                }
                .tint(.steel)
                .frame(minHeight: ForgeUX.minTap)

                Text(config.rationale)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()

                if enabled {
                    sunriseControls
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                }
            }
        }
    }

    private var sunriseControls: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            Stepper(value: $duration, in: 5...60, step: 5) {
                HStack(spacing: FDS.Spacing.sm) {
                    Text("Duration")
                        .font(HomeType.body)
                        .foregroundStyle(Color.textSecondary)
                    Spacer(minLength: FDS.Spacing.xs)
                    Text("\(duration) min")
                        .font(HomeType.status)
                        .foregroundStyle(Color.textPrimary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            .tint(.steel)
            .accessibilityLabel("Duration")
            .accessibilityValue("\(duration) minutes")

            temperatureBlock
            intensityDots
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeWell()
    }

    private var temperatureBlock: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            ForgeAdaptiveStack(spacing: ForgeLayout.pairGap, alignment: .firstTextBaseline) {
                Text("Color Temperature")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(temperatureLabel)
                    .font(HomeType.label)
                    .foregroundStyle(displayColor)
            }
            ZStack(alignment: .bottom) {
                temperatureGradient
                    .frame(height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
                Slider(value: $colorTemp)
                    .tint(.clear)
                    .padding(.horizontal, 2)
                    .accessibilityLabel("Color temperature")
                    .accessibilityValue(temperatureLabel)
            }
        }
    }

    private var intensityDots: some View {
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
        .accessibilityHidden(true)
    }
}
