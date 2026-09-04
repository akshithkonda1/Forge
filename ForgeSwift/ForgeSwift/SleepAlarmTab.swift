import SwiftUI
import UserNotifications

@MainActor
final class ForgeAlarmStore: ObservableObject {
    static let shared = ForgeAlarmStore()

    @Published var alarms: [ForgeAlarm]
    @Published var sunriseEnabled = true
    @Published var volumeRamp: VolumeRampCurve = .gradual
    @Published var routine: [RoutineItem]

    private let alarmsKey = "forge.sleep.alarms.v1"
    private let sunriseKey = "forge.sleep.sunrise.enabled.v1"
    private let rampKey = "forge.sleep.volumeRamp.v1"
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
        do { try await center.requestAuthorization(options: [.alert, .sound, .badge]) } catch {}
        let pending = await center.pendingNotificationRequests()
        let stale = pending.map(\.identifier).filter(SleepWakeEngine.isWakeNotification)
        center.removePendingNotificationRequests(withIdentifiers: stale)

        for alarm in alarms where alarm.isEnabled {
            await schedule(alarm)
        }
    }

    static func scheduleSnooze(alarm: ForgeAlarm) async {
        let fire = Date().addingTimeInterval(TimeInterval(max(1, alarm.snoozeMinutes)) * 60)
        await add(
            id: SleepWakeEngine.snoozeNotificationId(for: alarm.id),
            title: alarm.label,
            body: "Snooze is over. Get up.",
            date: fire,
            repeats: false,
            alarmID: alarm.id.uuidString,
            kind: "hard"
        )
    }

    private static func schedule(_ alarm: ForgeAlarm) async {
        let (hour, minute) = SleepWakeEngine.hourMinute(of: alarm.time)
        let days = alarm.days.isEmpty ? Array(1...7) : alarm.days
        for weekday in days {
            await addRepeating(
                id: SleepWakeEngine.hardNotificationId(for: alarm.id) + ".\(weekday)",
                weekday: weekday,
                hour: hour,
                minute: minute,
                title: alarm.label,
                body: "Get up. The day already started.",
                alarmID: alarm.id.uuidString,
                kind: "hard"
            )
            if alarm.isSmartWake {
                let smart = SleepWakeEngine.repeatingSmartClock(
                    weekday: weekday,
                    hour: hour,
                    minute: minute,
                    windowMinutes: alarm.smartWakeWindow
                )
                await addRepeating(
                    id: SleepWakeEngine.smartNotificationId(for: alarm.id) + ".\(smart.weekday)",
                    weekday: smart.weekday,
                    hour: smart.hour,
                    minute: smart.minute,
                    title: "Smart wake · \(alarm.label)",
                    body: "If you're already light, get up now. Hard alarm still fires at the set time.",
                    alarmID: alarm.id.uuidString,
                    kind: "smart"
                )
            }
        }
    }

    private static func addRepeating(
        id: String,
        weekday: Int,
        hour: Int,
        minute: Int,
        title: String,
        body: String,
        alarmID: String,
        kind: String
    ) async {
        var comps = DateComponents()
        comps.weekday = weekday
        comps.hour = hour
        comps.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        await add(id: id, title: title, body: body, trigger: trigger, alarmID: alarmID, kind: kind)
    }

    private static func add(
        id: String,
        title: String,
        body: String,
        date: Date,
        repeats: Bool,
        alarmID: String,
        kind: String
    ) async {
        guard date > Date() else { return }
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: repeats)
        await add(id: id, title: title, body: body, trigger: trigger, alarmID: alarmID, kind: kind)
    }

    private static func add(
        id: String,
        title: String,
        body: String,
        trigger: UNNotificationTrigger,
        alarmID: String,
        kind: String
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = SleepWakeEngine.category
        content.interruptionLevel = .timeSensitive
        content.userInfo = [
            "destination": "forge://wake",
            "alarmID": alarmID,
            "kind": kind
        ]
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try? await center.add(request)
    }
}

struct AlarmTab: View {
    @ObservedObject private var store = ForgeAlarmStore.shared
    @State private var showEditor = false
    @State private var editingAlarm: ForgeAlarm? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 28) {
                if let next = store.next {
                    NextAlarmHero(alarm: next)
                } else {
                    Text("No wake set. Add one — it will actually fire.")
                        .font(.system(size: 14))
                        .foregroundColor(.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }

                Button {
                    SleepWakeStore.shared.ring(store.next ?? ForgeAlarm())
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "sun.max.fill")
                            .foregroundStyle(Color(hex: "F59E0B"))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Test wake now")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundColor(.textPrimary)
                            Text("Sunrise, rising tone, hold to dismiss. The real thing.")
                                .font(.system(size: 12))
                                .foregroundColor(.textTertiary)
                        }
                        Spacer()
                    }
                    .padding(16)
                    .background(Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color(hex: "F59E0B").opacity(0.35), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Test the wake-up screen now")

                VStack(spacing: 12) {
                    HStack {
                        Text("Alarms")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.textTertiary)
                        Spacer()
                        Button {
                            editingAlarm = ForgeAlarm()
                            showEditor = true
                        } label: {
                            Text("New")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.ember)
                        }
                    }

                    ForEach(store.alarms) { alarm in
                        AlarmRow(
                            alarm: alarm,
                            onToggle: { store.setEnabled(id: alarm.id, enabled: $0) },
                            onEdit: {
                                editingAlarm = alarm
                                showEditor = true
                            }
                        )
                    }
                }

                WakeUpTab()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 120)
        }
        .sheet(isPresented: $showEditor) {
            if let alarm = editingAlarm {
                AlarmEditorSheet(alarm: alarm) { updated in
                    store.upsert(updated)
                }
            }
        }
    }
}

struct NextAlarmHero: View {
    let alarm: ForgeAlarm

    private var timeString: String {
        let f = DateFormatter(); f.dateFormat = "h:mm"
        return f.string(from: alarm.time)
    }
    private var ampm: String {
        let f = DateFormatter(); f.dateFormat = "a"
        return f.string(from: alarm.time)
    }
    private var daysString: String {
        if alarm.days.isEmpty { return "Every day" }
        let names = alarm.days.sorted().compactMap { Weekday(rawValue: $0)?.short }
        return names.joined(separator: " · ")
    }

    private var untilString: String {
        guard let fire = SleepWakeEngine.nextHardFire(alarm: alarm) else { return alarm.label }
        return "\(alarm.label)  ·  \(SleepWakeEngine.countdownLabel(until: fire))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Next")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(timeString)
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundColor(.textPrimary)
                    .monospacedDigit()
                Text(ampm)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.textSecondary)
            }
            Text("\(untilString)  ·  \(daysString)")
                .font(.system(size: 14))
                .foregroundColor(.textSecondary)
            if alarm.isSmartWake {
                Text("Smart wake opens \(alarm.smartWakeWindow) min earlier. Hard alarm still fires.")
                    .font(.system(size: 12))
                    .foregroundColor(.textTertiary)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }
}

struct AlarmRow: View {
    let alarm: ForgeAlarm
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void

    private var timeStr: String {
        let f = DateFormatter(); f.dateFormat = "h:mm a"
        return f.string(from: alarm.time)
    }
    private var daysStr: String {
        if alarm.days.isEmpty { return "Every day" }
        return alarm.days.sorted().compactMap { Weekday(rawValue: $0)?.short }.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 16) {
            Button(action: onEdit) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(timeStr)
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(alarm.isEnabled ? .textPrimary : .textTertiary)
                            .monospacedDigit()
                        HStack(spacing: 8) {
                            Text(alarm.label)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(alarm.isEnabled ? .textSecondary : .textMuted)
                            Circle().fill(Color.borderColor).frame(width: 3, height: 3)
                            Text(daysStr)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.textMuted)
                            if alarm.isSmartWake {
                                Text("Smart")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.steel)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.steel.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            Toggle("", isOn: Binding(get: { alarm.isEnabled }, set: { on in
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onToggle(on)
            }))
            .tint(.ember)
            .labelsHidden()
        }
        .padding(.vertical, 12)
        .opacity(alarm.isEnabled ? 1 : 0.45)
        .animation(.easeInOut(duration: 0.2), value: alarm.isEnabled)
    }
}

struct AlarmEditorSheet: View {
    @State private var alarm: ForgeAlarm
    @Environment(\.dismiss) private var dismiss
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

    var body: some View {
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Giant time picker
                        VStack(spacing: 4) {
                            Text("ALARM TIME")
                                .font(.system(size: 10, weight: .black))
                                .foregroundColor(.textTertiary)
                                .tracking(2.5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)

                            DatePicker("", selection: $alarm.time, displayedComponents: .hourAndMinute)
                                .datePickerStyle(.wheel)
                                .labelsHidden()
                                .frame(maxWidth: .infinity)
                                .tint(.ember)
                        }
                        .padding(16)
                        .background(Color.surface)
                        .cornerRadius(20)

                        // Day selector
                        EditorSection(title: "REPEAT") {
                            HStack(spacing: 8) {
                                ForEach(Weekday.allCases) { day in
                                    let active = alarm.days.contains(day.rawValue)
                                    Button {
                                        UISelectionFeedbackGenerator().selectionChanged()
                                        if active { alarm.days.removeAll { $0 == day.rawValue } }
                                        else { alarm.days.append(day.rawValue) }
                                    } label: {
                                        Text(day.short)
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(active ? .white : .textTertiary)
                                            .frame(width: 38, height: 38)
                                            .background(active ? Color.ember : Color.surfaceElevated)
                                            .clipShape(Circle())
                                            .overlay(Circle().stroke(active ? Color.ember.opacity(0.4) : Color.borderColor.opacity(0.4), lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                    .frame(maxWidth: .infinity)
                                }
                            }
                        }

                        // Label
                        EditorSection(title: "LABEL") {
                            TextField("Alarm label…", text: $alarm.label)
                                .font(.system(size: 15))
                                .foregroundColor(.textPrimary)
                                .tint(.ember)
                                .padding(.horizontal, 14).padding(.vertical, 12)
                                .background(Color.surfaceElevated)
                                .cornerRadius(12)
                        }

                        // Sound
                        EditorSection(title: "WAKE SOUND") {
                            VStack(spacing: 12) {
                                // Category filter
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(["All", "Ambient", "Nature", "Tones"], id: \.self) { cat in
                                            Button { selectedSoundCategory = cat } label: {
                                                Text(cat)
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .foregroundColor(selectedSoundCategory == cat ? .white : .textTertiary)
                                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                                    .background(selectedSoundCategory == cat ? Color.ember : Color.surfaceElevated)
                                                    .cornerRadius(20)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }

                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                    ForEach(filteredSounds, id: \.self) { sound in
                                        Button {
                                            alarm.sound = sound
                                            UISelectionFeedbackGenerator().selectionChanged()
                                        } label: {
                                            HStack(spacing: 10) {
                                                Image(systemName: sound.icon)
                                                    .font(.system(size: 16))
                                                    .foregroundColor(alarm.sound == sound ? .ember : .textTertiary)
                                                    .frame(width: 24)
                                                Text(sound.rawValue)
                                                    .font(.system(size: 13, weight: .medium))
                                                    .foregroundColor(alarm.sound == sound ? .textPrimary : .textSecondary)
                                                    .lineLimit(1)
                                                Spacer()
                                                if alarm.sound == sound {
                                                    Image(systemName: "checkmark")
                                                        .font(.system(size: 11, weight: .bold))
                                                        .foregroundColor(.ember)
                                                }
                                            }
                                            .padding(.horizontal, 12).padding(.vertical, 10)
                                            .background(alarm.sound == sound ? Color.ember.opacity(0.1) : Color.surfaceElevated)
                                            .cornerRadius(12)
                                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(alarm.sound == sound ? Color.ember.opacity(0.4) : Color.borderColor.opacity(0.3), lineWidth: 1))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }

                        // Snooze
                        EditorSection(title: "SNOOZE") {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Snooze Duration")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.textPrimary)
                                    Text("\(alarm.snoozeMinutes) minutes")
                                        .font(.system(size: 12))
                                        .foregroundColor(.textTertiary)
                                }
                                Spacer()
                                Stepper("", value: $alarm.snoozeMinutes, in: 1...30, step: 1)
                                    .labelsHidden()
                                    .tint(.ember)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .background(Color.surfaceElevated)
                            .cornerRadius(12)
                        }

                        // Gradual volume
                        EditorSection(title: "VOLUME") {
                            Toggle(isOn: $alarm.gradualVolume) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Gradual Volume")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.textPrimary)
                                    Text("Slowly increases over 30 seconds")
                                        .font(.system(size: 12))
                                        .foregroundColor(.textTertiary)
                                }
                            }
                            .tint(.ember)
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .background(Color.surfaceElevated)
                            .cornerRadius(12)
                        }

                        // Smart wake
                        EditorSection(title: "SMART WAKE") {
                            VStack(spacing: 12) {
                                Toggle(isOn: $alarm.isSmartWake) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Smart Wake")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.textPrimary)
                                        Text("Wake during lightest sleep phase")
                                            .font(.system(size: 12))
                                            .foregroundColor(.textTertiary)
                                    }
                                }
                                .tint(.steel)
                                .padding(.horizontal, 14).padding(.vertical, 12)
                                .background(Color.surfaceElevated)
                                .cornerRadius(12)

                                if alarm.isSmartWake {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("Wake window: up to \(alarm.smartWakeWindow) min before alarm")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.textSecondary)
                                        HStack(spacing: 8) {
                                            ForEach([15, 30, 45], id: \.self) { mins in
                                                Button {
                                                    alarm.smartWakeWindow = mins
                                                    UISelectionFeedbackGenerator().selectionChanged()
                                                } label: {
                                                    Text("\(mins) min")
                                                        .font(.system(size: 13, weight: .semibold))
                                                        .foregroundColor(alarm.smartWakeWindow == mins ? .white : .textTertiary)
                                                        .frame(maxWidth: .infinity)
                                                        .padding(.vertical, 10)
                                                        .background(alarm.smartWakeWindow == mins ? Color.steel : Color.surfaceElevated)
                                                        .cornerRadius(10)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 14).padding(.vertical, 12)
                                    .background(Color.steel.opacity(0.07))
                                    .cornerRadius(12)
                                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                                }
                            }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Edit Alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(alarm)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.ember)
                }
            }
        }
    }
}
