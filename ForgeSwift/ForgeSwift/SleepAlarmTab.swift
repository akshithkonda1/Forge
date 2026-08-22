import SwiftUI

struct AlarmTab: View {
    @State private var alarms: [ForgeAlarm] = [
        ForgeAlarm(label: "Wake Up", time: Calendar.current.date(from: DateComponents(hour: 6, minute: 45)) ?? Date(), days: [2,3,4,5,6], isEnabled: true),
        ForgeAlarm(label: "Weekend", time: Calendar.current.date(from: DateComponents(hour: 8, minute: 0)) ?? Date(), days: [1,7], sound: .forestBirds, isEnabled: false),
    ]
    @State private var showEditor = false
    @State private var editingAlarm: ForgeAlarm? = nil

    var nextAlarm: ForgeAlarm? {
        alarms.filter { $0.isEnabled }.first
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 28) {
                if let next = nextAlarm {
                    NextAlarmHero(alarm: next)
                }

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

                    ForEach($alarms) { $alarm in
                        AlarmRow(alarm: $alarm, onEdit: {
                            editingAlarm = alarm
                            showEditor = true
                        })
                    }
                    .onDelete { idx in alarms.remove(atOffsets: idx) }
                }

                WakeUpTab()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 120)
        }
        .sheet(isPresented: $showEditor) {
            if let alarm = editingAlarm {
                AlarmEditorSheet(alarm: alarm) { updated in
                    if let i = alarms.firstIndex(where: { $0.id == updated.id }) {
                        alarms[i] = updated
                    } else {
                        alarms.append(updated)
                    }
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
        let sorted = alarm.days.sorted()
        let names = sorted.compactMap { Weekday(rawValue: $0)?.short }
        return names.joined(separator: " · ")
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
            Text("\(alarm.label)  ·  \(daysString)")
                .font(.system(size: 14))
                .foregroundColor(.textSecondary)
            if alarm.isSmartWake {
                Text("Smart wake · \(alarm.smartWakeWindow) min")
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
    @Binding var alarm: ForgeAlarm
    let onEdit: () -> Void

    private var timeStr: String {
        let f = DateFormatter(); f.dateFormat = "h:mm a"
        return f.string(from: alarm.time)
    }
    private var daysStr: String {
        alarm.days.sorted().compactMap { Weekday(rawValue: $0)?.short }.joined(separator: " · ")
    }

    var body: some View {
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
                        if !alarm.days.isEmpty {
                            Circle().fill(Color.borderColor).frame(width: 3, height: 3)
                            Text(daysStr)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.textMuted)
                        }
                    }
                }
                Spacer()
                Toggle("", isOn: $alarm.isEnabled)
                    .tint(.ember)
                    .labelsHidden()
                    .onChange(of: alarm.isEnabled) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
            }
            .padding(.vertical, 12)
            .opacity(alarm.isEnabled ? 1 : 0.45)
            .animation(.easeInOut(duration: 0.2), value: alarm.isEnabled)
        }
        .buttonStyle(.plain)
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
