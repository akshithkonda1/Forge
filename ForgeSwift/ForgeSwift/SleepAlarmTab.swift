import SwiftUI
import UserNotifications
import ForgeCore

@MainActor
final class ForgeAlarmStore: ObservableObject {
    static let shared = ForgeAlarmStore()

    @Published var alarms: [ForgeAlarm]
    @Published var sunriseEnabled = true
    @Published var volumeRamp: VolumeRampCurve = .gradual
    @Published var sleeperDepth: SleeperDepth = .standard
    @Published var routine: [RoutineItem]
    @Published var delivery: SleepAlarmDelivery = .unknown

    private let alarmsKey = "forge.sleep.alarms.v1"
    private let sunriseKey = "forge.sleep.sunrise.enabled.v1"
    private let rampKey = "forge.sleep.volumeRamp.v1"
    private let depthKey = "forge.sleep.sleeperDepth.v1"
    private let routineKey = "forge.sleep.routine.v1"
    private let defaults = UserDefaults.standard

    private init() {
        if let data = defaults.data(forKey: alarmsKey),
           let saved = try? JSONDecoder().decode([ForgeAlarm].self, from: data) {
            alarms = saved
        } else {
            alarms = [
                ForgeAlarm(
                    label: "Weekdays",
                    time: Calendar.current.date(from: DateComponents(hour: 7, minute: 0)) ?? Date(),
                    days: [2, 3, 4, 5, 6],
                    isEnabled: true
                )
            ]
        }
        sunriseEnabled = defaults.object(forKey: sunriseKey) as? Bool ?? true
        if let raw = defaults.string(forKey: rampKey),
           let ramp = VolumeRampCurve(rawValue: raw) {
            volumeRamp = ramp
        }
        if let raw = defaults.string(forKey: depthKey),
           let depth = SleeperDepth(rawValue: raw) {
            sleeperDepth = depth
        }
        if let data = defaults.data(forKey: routineKey),
           let saved = try? JSONDecoder().decode([RoutineItem].self, from: data) {
            routine = saved
        } else {
            routine = RoutineItem.defaults
        }
        SleepAlarmScheduler.registerCategories()
        Task { await SleepAlarmScheduler.sync(alarms) }
    }

    func upsert(_ alarm: ForgeAlarm) {
        if let i = alarms.firstIndex(where: { $0.id == alarm.id }) {
            alarms[i] = alarm
        } else {
            alarms.append(alarm)
        }
        persistAndSchedule()
    }

    func setEnabled(id: UUID, enabled: Bool) {
        guard let i = alarms.firstIndex(where: { $0.id == id }) else { return }
        alarms[i].isEnabled = enabled
        persistAndSchedule()
    }

    func remove(at offsets: IndexSet) {
        alarms.remove(atOffsets: offsets)
        persistAndSchedule()
    }

    func setSunriseEnabled(_ on: Bool) {
        sunriseEnabled = on
        defaults.set(on, forKey: sunriseKey)
    }

    func setVolumeRamp(_ ramp: VolumeRampCurve) {
        volumeRamp = ramp
        defaults.set(ramp.rawValue, forKey: rampKey)
    }

    func setSleeperDepth(_ depth: SleeperDepth) {
        sleeperDepth = depth
        defaults.set(depth.rawValue, forKey: depthKey)
    }

    func setRoutine(_ items: [RoutineItem]) {
        routine = items
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: routineKey)
        }
    }

    var next: ForgeAlarm? { SleepWakeEngine.nextAlarm(in: alarms) }

    func alarm(id: UUID?) -> ForgeAlarm? {
        guard let id else { return nil }
        return alarms.first { $0.id == id }
    }

    func persistAndSchedule() {
        if let data = try? JSONEncoder().encode(alarms) {
            defaults.set(data, forKey: alarmsKey)
        }
        Task { await SleepAlarmScheduler.sync(alarms) }
    }
}

enum SleepAlarmScheduler {
    private static let center = UNUserNotificationCenter.current()

    static func registerCategories() {
        let snooze = UNNotificationAction(
            identifier: SleepWakeEngine.actionSnooze,
            title: "Snooze",
            options: []
        )
        let up = UNNotificationAction(
            identifier: SleepWakeEngine.actionUp,
            title: "I'm up",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: SleepWakeEngine.category,
            actions: [up, snooze],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        center.setNotificationCategories([category])
    }

    static func sync(_ alarms: [ForgeAlarm]) async {
        let health = await arm(alarms)
        await MainActor.run { ForgeAlarmStore.shared.delivery = health }
    }

    /// Schedules every enabled alarm, then fail-closes if iPhone cannot deliver.
    private static func arm(_ alarms: [ForgeAlarm]) async -> SleepAlarmDelivery {
        var authError: String?
        var authorization = await center.notificationSettings().authorizationStatus
        if authorization == .notDetermined || authorization == .provisional {
            do {
                _ = try await center.requestAuthorization(
                    options: SleepAlarmAppleAPI.authorizationOptions
                )
            } catch {
                authError = error.localizedDescription
                print("SleepWakeEngine: notification authorization failed: \(error.localizedDescription)")
            }
        }

        let afterAsk = await center.notificationSettings()
        authorization = afterAsk.authorizationStatus
        let timeSensitive = afterAsk.timeSensitiveSetting
        let expected = SleepAlarmScheduleMath.expectedPendingCount(in: alarms)

        let pending = await center.pendingNotificationRequests()
        let stale = pending.map(\.identifier).filter(SleepWakeEngine.isWakeNotification)
        center.removePendingNotificationRequests(withIdentifiers: stale)

        guard authorization == .authorized else {
            return SleepAlarmScheduleMath.delivery(
                authorization: authorization,
                timeSensitive: timeSensitive,
                expected: expected,
                pending: 0,
                addFailures: 0,
                authError: authError
            )
        }

        let windows: [UUID: Int] = await MainActor.run {
            Dictionary(uniqueKeysWithValues: alarms.map { alarm in
                (alarm.id, HealthKitSleepService.shared.adaptiveSmartWakeMinutes(base: alarm.smartWakeWindow, depth: ForgeAlarmStore.shared.sleeperDepth))
            })
        }

        var addFailures = 0
        for alarm in alarms where alarm.isEnabled {
            addFailures += await schedule(alarm, smartWindow: windows[alarm.id] ?? alarm.smartWakeWindow)
        }

        let remaining = await center.pendingNotificationRequests()
        let standing = remaining.map(\.identifier).filter(SleepAlarmScheduleMath.isStandingWakeNotification).count
        return SleepAlarmScheduleMath.delivery(
            authorization: authorization,
            timeSensitive: timeSensitive,
            expected: expected,
            pending: standing,
            addFailures: addFailures,
            authError: authError
        )
    }

    @discardableResult
    static func scheduleSnooze(alarm: ForgeAlarm) async -> Bool {
        let fire = Date().addingTimeInterval(TimeInterval(max(1, alarm.snoozeMinutes)) * 60)
        return await add(
            id: SleepWakeEngine.snoozeNotificationId(for: alarm.id),
            title: alarm.label,
            body: "Snooze is over. Get up.",
            date: fire,
            repeats: false,
            alarmID: alarm.id.uuidString,
            kind: "hard"
        )
    }

    static func scheduleFailsafe(alarm: ForgeAlarm) async {
        center.removePendingNotificationRequests(
            withIdentifiers: [SleepWakeEngine.failsafeNotificationId(for: alarm.id)]
        )
        let content = UNMutableNotificationContent()
        content.title = alarm.label
        content.body = "Still time to get up. The wake is still on."
        content.sound = SleepAlarmAppleAPI.notificationSound
        content.categoryIdentifier = SleepWakeEngine.category
        content.interruptionLevel = SleepAlarmAppleAPI.interruptionLevel
        content.userInfo = [
            "destination": "forge://wake",
            "alarmID": alarm.id.uuidString,
            "kind": "failsafe"
        ]
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: SleepAlarmAppleAPI.failsafePingSeconds,
            repeats: true
        )
        let request = UNNotificationRequest(
            identifier: SleepWakeEngine.failsafeNotificationId(for: alarm.id),
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }

    static func cancelFailsafe(alarmID: UUID) {
        center.removePendingNotificationRequests(
            withIdentifiers: [SleepWakeEngine.failsafeNotificationId(for: alarmID)]
        )
        center.removeDeliveredNotifications(
            withIdentifiers: [SleepWakeEngine.failsafeNotificationId(for: alarmID)]
        )
    }

    @discardableResult
    private static func schedule(_ alarm: ForgeAlarm, smartWindow: Int) async -> Int {
        let (hour, minute) = SleepWakeEngine.hourMinute(of: alarm.time)
        let days = alarm.days.isEmpty ? Array(1...7) : alarm.days
        var failures = 0
        for weekday in days {
            let hardOK = await addRepeating(
                id: SleepWakeEngine.hardNotificationId(for: alarm.id) + ".\(weekday)",
                weekday: weekday,
                hour: hour,
                minute: minute,
                title: alarm.label,
                body: "Get up. The day already started.",
                alarmID: alarm.id.uuidString,
                kind: "hard"
            )
            if !hardOK { failures += 1 }
            if alarm.isSmartWake {
                let smart = SleepWakeEngine.repeatingSmartClock(
                    weekday: weekday,
                    hour: hour,
                    minute: minute,
                    windowMinutes: smartWindow
                )
                let smartOK = await addRepeating(
                    id: SleepWakeEngine.smartNotificationId(for: alarm.id) + ".\(smart.weekday)",
                    weekday: smart.weekday,
                    hour: smart.hour,
                    minute: smart.minute,
                    title: "Smart wake · \(alarm.label)",
                    body: "If Apple has you in light sleep, get up now. Hard alarm still fires at the set time.",
                    alarmID: alarm.id.uuidString,
                    kind: "smart"
                )
                if !smartOK { failures += 1 }
            }
        }
        return failures
    }

    @discardableResult
    private static func addRepeating(
        id: String,
        weekday: Int,
        hour: Int,
        minute: Int,
        title: String,
        body: String,
        alarmID: String,
        kind: String
    ) async -> Bool {
        var comps = DateComponents()
        comps.weekday = weekday
        comps.hour = hour
        comps.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        return await add(id: id, title: title, body: body, trigger: trigger, alarmID: alarmID, kind: kind)
    }

    @discardableResult
    private static func add(
        id: String,
        title: String,
        body: String,
        date: Date,
        repeats: Bool,
        alarmID: String,
        kind: String
    ) async -> Bool {
        guard date > Date() else { return false }
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: repeats)
        return await add(id: id, title: title, body: body, trigger: trigger, alarmID: alarmID, kind: kind)
    }

    @discardableResult
    private static func add(
        id: String,
        title: String,
        body: String,
        trigger: UNNotificationTrigger,
        alarmID: String,
        kind: String
    ) async -> Bool {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = SleepAlarmAppleAPI.notificationSound
        content.categoryIdentifier = SleepWakeEngine.category
        content.interruptionLevel = SleepAlarmAppleAPI.interruptionLevel
        content.userInfo = [
            "destination": "forge://wake",
            "alarmID": alarmID,
            "kind": kind
        ]
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        do {
            try await center.add(request)
            return true
        } catch {
            print("SleepWakeEngine: failed to add \(id): \(error.localizedDescription)")
            return false
        }
    }

    /// React to a HealthKit-delivered stage. Not a live stream — Apple's
    /// sample is the event. One early fire per alarm per morning.
    @MainActor
    static func considerDeliveredSleep(
        stage: SleepStage,
        sampleEnd: Date,
        now: Date = Date()
    ) async {
        let alarms = ForgeAlarmStore.shared.alarms
        guard let alarm = SleepWakeEngine.nextAlarm(in: alarms, now: now), alarm.isSmartWake else { return }
        let window = HealthKitSleepService.shared.adaptiveSmartWakeMinutes(base: alarm.smartWakeWindow, depth: ForgeAlarmStore.shared.sleeperDepth)
        guard let hard = SleepWakeEngine.nextHardFire(alarm: alarm, now: now) else { return }
        let smart = SleepWakeEngine.smartWakeFire(hard: hard, windowMinutes: window)
        let decision = SmartWakeEarlyFire.decide(
            now: now,
            smartFire: smart,
            hardFire: hard,
            sampleEnd: sampleEnd,
            stage: stage
        )
        guard decision == .fireEarly else { return }
        let dayKey = WakeStruggleStore.dayKey(for: now)
        guard !SmartWakeEarlyFireStore.alreadyFired(alarmId: alarm.id.uuidString, dayKey: dayKey) else { return }
        SmartWakeEarlyFireStore.markFired(alarmId: alarm.id.uuidString, dayKey: dayKey)
        await addImmediate(
            id: SleepWakeEngine.liveNotificationId(for: alarm.id, dayKey: dayKey),
            title: "Smart wake · \(alarm.label)",
            body: "Apple just delivered light sleep. Get up now if you can — the hard alarm still stands.",
            alarmID: alarm.id.uuidString,
            kind: "smart-live"
        )
        AriaKnowledgeLedgerStore.file(AriaKnowledgeFact(
            category: .appleHealth,
            kind: "smart_wake_early",
            summary: "Smart wake fired early — Apple delivered \(stage.displayName.lowercased()) sleep in the window.",
            source: "sleep-live"
        ))
    }

    @MainActor
    static func considerWatchSleep(_ payload: WatchSleepSamplePayload, now: Date = Date()) async {
        guard let stage = payload.sleepStage else { return }
        await considerDeliveredSleep(stage: stage, sampleEnd: payload.end, now: now)
    }

    private static func addImmediate(
        id: String,
        title: String,
        body: String,
        alarmID: String,
        kind: String
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = SleepAlarmAppleAPI.notificationSound
        content.categoryIdentifier = SleepWakeEngine.category
        content.interruptionLevel = SleepAlarmAppleAPI.interruptionLevel
        content.userInfo = [
            "destination": "forge://wake",
            "alarmID": alarmID,
            "kind": kind
        ]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try? await center.add(request)
    }
}

private enum AlarmDayText {
    /// "Mon · Tue · Wed" for the screen.
    static func visible(_ days: [Int]) -> String {
        if days.isEmpty || Set(days).count >= 7 { return "Every day" }
        var names: [String] = []
        for day in days.sorted() {
            if let weekday = Weekday(rawValue: day) {
                names.append(String(weekday.full.prefix(3)))
            }
        }
        return names.joined(separator: " · ")
    }

    /// Full weekday names for VoiceOver, so "T" is never ambiguous.
    static func spoken(_ days: [Int]) -> String {
        if days.isEmpty || Set(days).count >= 7 { return "Every day" }
        var names: [String] = []
        for day in days.sorted() {
            if let weekday = Weekday(rawValue: day) {
                names.append(weekday.full)
            }
        }
        return names.joined(separator: ", ")
    }
}

struct WakeReliabilityBanner: View {
    let delivery: SleepAlarmDelivery

    private var iconName: String {
        delivery.isFailClosed ? "exclamationmark.triangle.fill" : "bell.badge.fill"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            HStack(alignment: .top, spacing: ForgeLayout.rowGap) {
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.warning)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                    Text(delivery.headline)
                        .font(HomeType.status)
                        .foregroundStyle(Color.textPrimary)
                        .forgeWrapping()
                    Text(delivery.cue)
                        .font(HomeType.body)
                        .foregroundStyle(Color.textSecondary)
                        .forgeWrapping()
                }
            }
            ForgeSecondaryButton(title: "Open Settings", icon: "gearshape.fill", accent: .warning) {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .accessibilityHint("Opens Settings so this wake can fire")
        }
        .forgeContentCard(tint: .warning)
        .accessibilityElement(children: .contain)
    }
}

struct AlarmTab: View {
    @ObservedObject private var store = ForgeAlarmStore.shared
    @State private var showEditor = false
    @State private var editingAlarm: ForgeAlarm? = nil

    private func startNewAlarm() {
        editingAlarm = ForgeAlarm()
        showEditor = true
    }

    private func startEditing(_ alarm: ForgeAlarm) {
        editingAlarm = alarm
        showEditor = true
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: ForgeLayout.sectionGap) {
                if store.delivery.needsAttention {
                    WakeReliabilityBanner(delivery: store.delivery)
                }

                nextBlock

                testWakeCard

                if !store.alarms.isEmpty {
                    alarmsCard
                }

                WakeUpTab()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .forgeScreenInsets(top: ForgeLayout.screenTop)
        }
        .onAppear {
            Task { await SleepAlarmScheduler.sync(store.alarms) }
        }
        .sheet(isPresented: $showEditor) {
            if let alarm = editingAlarm {
                AlarmEditorSheet(alarm: alarm) { updated in
                    store.upsert(updated)
                }
            }
        }
    }

    @ViewBuilder
    private var nextBlock: some View {
        if let next = store.next {
            NextAlarmHero(alarm: next)
        } else {
            ForgeEmptyStateCard(
                icon: "alarm.fill",
                title: "No wake set",
                message: "Add one — it will actually fire.",
                accent: .steel,
                cta: "Add a wake",
                action: { startNewAlarm() }
            )
        }
    }

    private var testWakeCard: some View {
        Button {
            ForgeHaptics.play(.press)
            SleepWakeStore.shared.ring(store.next ?? ForgeAlarm())
        } label: {
            HStack(spacing: ForgeLayout.rowGap) {
                ForgeIconWell(systemImage: "sun.max.fill", tint: .steel)
                VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                    Text("Test wake now")
                        .font(HomeType.status)
                        .foregroundStyle(Color.textPrimary)
                        .forgeWrapping()
                    Text("Sunrise, rising tone, backup if you sleep through. The real thing.")
                        .font(HomeType.body)
                        .foregroundStyle(Color.textTertiary)
                        .forgeWrapping()
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
            }
            .frame(minHeight: ForgeUX.minTap)
            .forgeContentCard(tint: .steel)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Test the wake-up screen now")
        .accessibilityHint("Rings the full wake screen with sound right away")
    }

    private var alarmsCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader(title: "Alarms") {
                ForgeTextLink(title: "New", accent: .steel) {
                    startNewAlarm()
                }
                .accessibilityHint("Adds an alarm")
            }
            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                ForEach(store.alarms) { alarm in
                    AlarmRow(
                        alarm: alarm,
                        onToggle: { store.setEnabled(id: alarm.id, enabled: $0) },
                        onEdit: { startEditing(alarm) }
                    )
                }
            }
        }
        .forgeContentCard(tint: .steel)
    }
}

struct NextAlarmHero: View {
    let alarm: ForgeAlarm
    @ObservedObject private var hk = HealthKitSleepService.shared
    @ObservedObject private var store = ForgeAlarmStore.shared

    private var timeString: String {
        alarm.time.formatted(date: .omitted, time: .shortened)
    }

    private var daysString: String {
        AlarmDayText.visible(alarm.days)
    }

    private var untilString: String {
        guard let fire = SleepWakeEngine.nextHardFire(alarm: alarm) else { return alarm.label }
        return "\(alarm.label) · \(SleepWakeEngine.countdownLabel(until: fire))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("Next", tint: .steel)
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text(timeString)
                    .font(HomeType.metric)
                    .foregroundStyle(Color.textPrimary)
                    .monospacedDigit()
                    .forgeSingleLine()
                    .contentTransition(.numericText())
                Text("\(untilString) · \(daysString)")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
            }
            if alarm.isSmartWake {
                let lead = hk.adaptiveSmartWakeMinutes(base: alarm.smartWakeWindow, depth: store.sleeperDepth)
                Text("Smart wake opens \(lead) min earlier tonight. Hard alarm still fires.")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textTertiary)
                    .forgeWrapping()
            }
        }
        .forgeContentCard(tint: .steel)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Next alarm \(alarm.label), \(timeString), \(daysString). \(untilString)")
    }
}

struct AlarmRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let alarm: ForgeAlarm
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void

    private var timeStr: String {
        alarm.time.formatted(date: .omitted, time: .shortened)
    }

    private var daysStr: String {
        AlarmDayText.visible(alarm.days)
    }

    private var daysSpoken: String {
        AlarmDayText.spoken(alarm.days)
    }

    private var timeColor: Color {
        alarm.isEnabled ? Color.textPrimary : Color.textTertiary
    }

    private var detailColor: Color {
        alarm.isEnabled ? Color.textSecondary : Color.textTertiary
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { alarm.isEnabled },
            set: { on in
                ForgeHaptics.play(.selection)
                onToggle(on)
            }
        )
    }

    var body: some View {
        HStack(spacing: ForgeLayout.rowGap) {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: ForgeLayout.labelValueGap) {
                    ForgeFlowLayout(spacing: ForgeLayout.rowGap, lineSpacing: ForgeLayout.pairGap) {
                        Text(timeStr)
                            .font(HomeType.metric)
                            .foregroundStyle(timeColor)
                            .monospacedDigit()
                            .forgeSingleLine()
                        if alarm.isSmartWake {
                            HudVibeChip(label: "Smart", energy: .steel)
                        }
                    }
                    Text("\(alarm.label) · \(daysStr)")
                        .font(HomeType.body)
                        .foregroundStyle(detailColor)
                        .forgeWrapping()
                }
                .frame(maxWidth: .infinity, minHeight: ForgeUX.minTap, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit \(alarm.label) alarm, \(timeStr), \(daysSpoken). \(alarm.isSmartWake ? "Smart wake on." : "") \(alarm.isEnabled ? "Enabled." : "Off.")")
            .accessibilityHint("Opens the alarm editor")
            Toggle("", isOn: enabledBinding)
                .tint(.steel)
                .labelsHidden()
                .accessibilityLabel("\(alarm.label) alarm, \(timeStr), \(daysSpoken). \(alarm.isEnabled ? "On" : "Off")")
        }
        .opacity(alarm.isEnabled ? 1 : 0.6)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: alarm.isEnabled)
    }
}

struct AlarmEditorSheet: View {
    @State private var alarm: ForgeAlarm
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var dayCircleSize: CGFloat = 36
    let onSave: (ForgeAlarm) -> Void
    @State private var selectedSoundCategory = "All"

    init(alarm: ForgeAlarm, onSave: @escaping (ForgeAlarm) -> Void) {
        _alarm = State(initialValue: alarm)
        self.onSave = onSave
    }

    var filteredSounds: [AlarmSoundOption] {
        if selectedSoundCategory == "All" { return AlarmSoundOption.allCases }
        return AlarmSoundOption.allCases.filter { $0.category == selectedSoundCategory }
    }

    private var soundCategoryChoices: [ForgeSegmentOption<String>] {
        ["All", "Ambient", "Nature", "Tones"].map { ForgeSegmentOption(value: $0, title: $0) }
    }

    private var smartWindowChoices: [ForgeSegmentOption<Int>] {
        var values = ForgeAlarmStore.shared.sleeperDepth.windowChoices
        if !values.contains(alarm.smartWakeWindow) {
            values.append(alarm.smartWakeWindow)
            values.sort()
        }
        return values.map { ForgeSegmentOption(value: $0, title: "\($0) min") }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: ForgeLayout.sectionGap) {
                        timeCard
                        repeatSection
                        labelCard
                        soundCard
                        snoozeCard
                        volumeCard
                        smartWakeCard
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .forgeScreenInsets(top: FDS.Spacing.lg)
                }
            }
            .navigationTitle("Edit Alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(alarm)
                        ForgeHaptics.play(.success)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.steel)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: Sections

    private var timeCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("ALARM TIME")
            DatePicker("Alarm time", selection: $alarm.time, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .tint(.steel)
        }
        .forgeContentCard()
    }

    /// Seven cells need the sheet inset, not a card inset, to stay 44 pt wide.
    private var repeatSection: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            ForgeCardHeader("REPEAT")
            if dynamicTypeSize.isAccessibilitySize {
                dayChips
            } else {
                dayCircles
            }
        }
    }

    private var dayCircles: some View {
        ForgeEqualColumnsLayout(columns: 7, spacing: ForgeLayout.pairGap) {
            ForEach(Weekday.allCases) { day in
                dayCircleButton(day)
            }
        }
    }

    private var dayChips: some View {
        ForgeFlowLayout(spacing: ForgeLayout.chipGap, lineSpacing: ForgeLayout.interactiveChipLineGap) {
            ForEach(Weekday.allCases) { day in
                ForgeChipButton(
                    label: day.full,
                    energy: .steel,
                    selected: alarm.days.contains(day.rawValue)
                ) {
                    toggleDay(day)
                }
            }
        }
    }

    private func toggleDay(_ day: Weekday) {
        if alarm.days.contains(day.rawValue) {
            alarm.days.removeAll { $0 == day.rawValue }
        } else {
            alarm.days.append(day.rawValue)
        }
    }

    private func dayCircleButton(_ day: Weekday) -> some View {
        let active = alarm.days.contains(day.rawValue)
        let diameter = min(ForgeLayout.scaledCap(dayCircleSize, base: 36, maxGrowth: 1.15), 40)
        let fill: Color = active ? Color.steel : Color.surfaceElevated
        let edge: Color = active ? Color.steel.opacity(0.4) : Color.white.opacity(0.12)
        let ink: Color = active ? Color.white : Color.textSecondary
        return Button {
            ForgeHaptics.play(.selection)
            toggleDay(day)
        } label: {
            Text(day.short)
                .font(HomeType.label)
                .foregroundStyle(ink)
                .hudInArcText()
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(fill))
                .overlay(Circle().stroke(edge, lineWidth: ForgeUX.hairline))
                .frame(maxWidth: .infinity, minHeight: ForgeUX.minTap)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.full)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private var labelCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("LABEL")
            TextField("Alarm label…", text: $alarm.label)
                .font(HomeType.body)
                .foregroundStyle(Color.textPrimary)
                .tint(.steel)
                .frame(maxWidth: .infinity, alignment: .leading)
                .forgeWell()
        }
        .forgeContentCard()
    }

    private var soundCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("WAKE SOUND")
            ForgeSegmentedControl(
                soundCategoryChoices,
                selection: $selectedSoundCategory,
                accent: .steel,
                bleed: ForgeLayout.cardPadding
            )
            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                ForEach(filteredSounds, id: \.self) { sound in
                    soundRow(sound)
                }
            }
        }
        .forgeContentCard()
    }

    private func soundRow(_ sound: AlarmSoundOption) -> some View {
        let selected = alarm.sound == sound
        let tint: Color = selected ? Color.steel : Color.textTertiary
        let ink: Color = selected ? Color.textPrimary : Color.textSecondary
        return Button {
            ForgeHaptics.play(.selection)
            alarm.sound = sound
        } label: {
            HStack(spacing: ForgeLayout.rowGap) {
                ForgeIconWell(systemImage: sound.icon, tint: tint)
                Text(sound.rawValue)
                    .font(HomeType.status)
                    .foregroundStyle(ink)
                    .lineLimit(2)
                Spacer(minLength: ForgeLayout.pairGap)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.steel)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: ForgeUX.minTap, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(sound.rawValue)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var snoozeCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("SNOOZE")
            ForgeAdaptiveStack(spacing: ForgeLayout.rowGap) {
                VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                    Text("Snooze Duration")
                        .font(HomeType.status)
                        .foregroundStyle(Color.textPrimary)
                        .forgeWrapping()
                    Text("\(alarm.snoozeMinutes) minutes")
                        .font(HomeType.body)
                        .foregroundStyle(Color.textTertiary)
                        .monospacedDigit()
                        .forgeWrapping()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Stepper("Snooze Duration", value: $alarm.snoozeMinutes, in: 1...30, step: 1)
                    .labelsHidden()
                    .accessibilityValue("\(alarm.snoozeMinutes) minutes")
            }
        }
        .forgeContentCard()
    }

    private var volumeCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("VOLUME")
            Toggle(isOn: $alarm.gradualVolume) {
                toggleLabel(
                    "Gradual Volume",
                    "Starts quiet, then a backup tone if you're still down."
                )
            }
            .tint(.steel)
        }
        .forgeContentCard()
    }

    private var smartWakeCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("SMART WAKE")
            Toggle(isOn: $alarm.isSmartWake) {
                toggleLabel(
                    "Smart Wake",
                    "Earlier nudge if you might already be light. Hard alarm still fires."
                )
            }
            .tint(.steel)
            if alarm.isSmartWake {
                smartWindowBlock
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }
        }
        .forgeContentCard()
    }

    private var smartWindowBlock: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            Text("Base window: \(alarm.smartWakeWindow) min. Tonight adapts from score, debt, and snooze history.")
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
            ForgeSegmentedControl(
                smartWindowChoices,
                selection: $alarm.smartWakeWindow,
                accent: .steel,
                bleed: ForgeLayout.cardPadding
            )
        }
    }

    private func toggleLabel(_ title: String, _ footnote: String) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
            Text(title)
                .font(HomeType.status)
                .foregroundStyle(Color.textPrimary)
                .forgeWrapping()
            Text(footnote)
                .font(HomeType.body)
                .foregroundStyle(Color.textTertiary)
                .forgeWrapping()
        }
    }
}
