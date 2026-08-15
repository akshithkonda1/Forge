import SwiftUI
import Charts

// MARK: - Models

enum Weekday: Int, CaseIterable, Codable, Identifiable {
    case sun = 1, mon, tue, wed, thu, fri, sat
    var id: Int { rawValue }
    var short: String { ["S","M","T","W","T","F","S"][rawValue - 1] }
    var full: String  { ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"][rawValue - 1] }
}

enum AlarmSoundOption: String, CaseIterable, Codable {
    case gentleRise  = "Gentle Rise"
    case forestBirds = "Forest Birds"
    case oceanWaves  = "Ocean Waves"
    case windChimes  = "Wind Chimes"
    case tibetanBell = "Tibetan Bell"
    case sunriseGlow = "Sunrise Glow"
    case rainDrop    = "Rain Drop"
    case softPiano   = "Soft Piano"

    var icon: String {
        switch self {
        case .gentleRise:  return "sunrise.fill"
        case .forestBirds: return "bird.fill"
        case .oceanWaves:  return "water.waves"
        case .windChimes:  return "wind"
        case .tibetanBell: return "bell.fill"
        case .sunriseGlow: return "sun.max.fill"
        case .rainDrop:    return "cloud.drizzle.fill"
        case .softPiano:   return "music.note"
        }
    }

    var category: String {
        switch self {
        case .gentleRise, .sunriseGlow:                return "Ambient"
        case .forestBirds, .oceanWaves, .rainDrop:     return "Nature"
        case .windChimes, .tibetanBell, .softPiano:    return "Tones"
        }
    }
}

struct ForgeAlarm: Identifiable, Codable {
    var id: UUID = UUID()
    var label: String = "Wake Up"
    var time: Date = Calendar.current.date(from: DateComponents(hour: 7, minute: 0)) ?? Date()
    var days: [Int] = [2, 3, 4, 5, 6]          // Mon–Fri
    var sound: AlarmSoundOption = .gentleRise
    var snoozeMinutes: Int = 9
    var isSmartWake: Bool = true
    var smartWakeWindow: Int = 30               // minutes before alarm
    var isEnabled: Bool = true
    var gradualVolume: Bool = true
}

struct SleepSoundItem: Identifiable {
    let id: UUID = UUID()
    let name: String
    let icon: String
    let color: Color
    let category: SleepSoundCategory
}

enum SleepSoundCategory: String, CaseIterable {
    case nature  = "Nature"
    case noise   = "Noise"
    case ambient = "Ambient"
    case focus   = "Focus"
}

let allSleepSounds: [SleepSoundItem] = [
    SleepSoundItem(name: "Rain",          icon: "cloud.rain.fill",          color: .steel,              category: .nature),
    SleepSoundItem(name: "Ocean",         icon: "water.waves",               color: Color(hex: "0EA5E9"), category: .nature),
    SleepSoundItem(name: "Forest",        icon: "tree.fill",                 color: .success,            category: .nature),
    SleepSoundItem(name: "Thunder",       icon: "cloud.bolt.rain.fill",      color: Color(hex: "6366F1"), category: .nature),
    SleepSoundItem(name: "White Noise",   icon: "waveform",                  color: .textTertiary,       category: .noise),
    SleepSoundItem(name: "Brown Noise",   icon: "waveform.path",             color: Color(hex: "92400E"), category: .noise),
    SleepSoundItem(name: "Pink Noise",    icon: "waveform.path.ecg",         color: Color(hex: "EC4899"), category: .noise),
    SleepSoundItem(name: "Fan",           icon: "fan.fill",                  color: .textSecondary,      category: .noise),
    SleepSoundItem(name: "Fireplace",     icon: "flame.fill",                color: .ember,              category: .ambient),
    SleepSoundItem(name: "Café",          icon: "cup.and.saucer.fill",       color: Color(hex: "92400E"), category: .ambient),
    SleepSoundItem(name: "Tibetan Bowl",  icon: "bell.fill",                 color: Color(hex: "A78BFA"), category: .ambient),
    SleepSoundItem(name: "Wind Chimes",   icon: "wind",                      color: Color(hex: "38BDF8"), category: .ambient),
    SleepSoundItem(name: "Lo-Fi",         icon: "music.note",                color: Color(hex: "F472B6"), category: .focus),
    SleepSoundItem(name: "Binaural",      icon: "headphones",                color: Color(hex: "818CF8"), category: .focus),
    SleepSoundItem(name: "432 Hz",        icon: "tuningfork",                color: .success,            category: .focus),
    SleepSoundItem(name: "Deep Focus",    icon: "brain.fill",                color: Color(hex: "7C3AED"), category: .focus),
]

// MARK: - Sleep Tab Enum

enum SleepTab: Int, CaseIterable {
    case day, night, alarms
    var title: String {
        switch self {
        case .day: return "Day"
        case .night: return "Night"
        case .alarms: return "Alarms"
        }
    }
}

// MARK: - Root SleepView

struct SleepView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var hkService = HealthKitSleepService.shared
    @State private var selectedTab: SleepTab = .day
    @State private var showAIChat = false
    @State private var showSleepPersonalization = false

    var body: some View {
        ZStack(alignment: .top) {
            SleepBackground().ignoresSafeArea()

            VStack(spacing: 0) {
                SleepHeaderView(
                    selectedTab: selectedTab,
                    onAskAria: { showAIChat = true },
                    onPersonalize: { showSleepPersonalization = true },
                    onTabSelect: { selectedTab = $0 }
                )

                TabView(selection: $selectedTab) {
                    SleepDayTab()
                        .environmentObject(hkService)
                        .tag(SleepTab.day)

                    SleepNightTab(
                        showPersonalization: $showSleepPersonalization
                    )
                    .environmentObject(hkService)
                    .tag(SleepTab.night)

                    AlarmTab()
                        .environmentObject(hkService)
                        .tag(SleepTab.alarms)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.22), value: selectedTab)
            }
        }
        .sheet(isPresented: $showAIChat) {
            AISleepChatView()
                .environmentObject(store)
                .environmentObject(hkService)
        }
        .sheet(isPresented: $showSleepPersonalization) {
            SleepPersonalizationSheet()
                .environmentObject(hkService)
                .environmentObject(store)
        }
        .task {
            if await hkService.requestAuthorization() {
                let hkSleep = await hkService.fetchRecentSleepData(days: 14)
                store.mergeSleepDataLocally(hkSleep)
            }
            let debt = hkService.computeSleepDebt(from: store.sleepData)
            let recentScore = store.sleepData.first?.score
            _ = hkService.computeAdaptiveSunrise(
                debt: debt,
                recentScore: recentScore,
                profile: hkService.userProfile
            )
        }
    }
}

// MARK: - Sleep Background

struct SleepBackground: View {
    var body: some View {
        ZStack {
            Color.background
            RadialGradient(
                colors: [Color(hex: "1E1B4B").opacity(0.35), .clear],
                center: UnitPoint(x: 0.5, y: 0.0),
                startRadius: 20,
                endRadius: 420
            )
            RadialGradient(
                colors: [Color.ember.opacity(0.05), .clear],
                center: UnitPoint(x: 0.15, y: 0.22),
                startRadius: 10,
                endRadius: 280
            )
        }
    }
}

// MARK: - Sleep Header

struct SleepHeaderView: View {
    let selectedTab: SleepTab
    let onAskAria: () -> Void
    let onPersonalize: () -> Void
    let onTabSelect: (SleepTab) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("Sleep")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Spacer()
                Button(action: onPersonalize) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.textSecondary)
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("Sleep preferences")
                Button(action: onAskAria) {
                    Text("Ask ARIA")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())
                }
                .accessibilityLabel("Ask ARIA about sleep")
            }

            HStack(spacing: 0) {
                ForEach(SleepTab.allCases, id: \.self) { tab in
                    Button {
                        onTabSelect(tab)
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        VStack(spacing: 8) {
                            Text(tab.title)
                                .font(.system(size: 14, weight: selectedTab == tab ? .semibold : .medium))
                                .foregroundColor(selectedTab == tab ? .textPrimary : .textTertiary)
                            Rectangle()
                                .fill(selectedTab == tab ? Color.textPrimary : Color.clear)
                                .frame(height: 1.5)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 56)
        .padding(.bottom, 8)
    }
}

// MARK: - Day

struct SleepDayTab: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 32) {
                EnergyScheduleCard()
                SleepLastNightStrip()
                SleepWeekRhythm()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 120)
        }
    }
}

// MARK: - Night

struct SleepNightTab: View {
    @EnvironmentObject var store: AppStore
    @Binding var showPersonalization: Bool
    @State private var showSounds = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                SleepLastNightDetail()
                SleepWeekRhythm()
                ChronotypeBadge(onTap: { showPersonalization = true })
                Button { showSounds = true } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Sounds")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.textPrimary)
                            Text("Rain, noise, or a timer for wind-down.")
                                .font(.system(size: 13))
                                .foregroundColor(.textTertiary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.textMuted)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 120)
        }
        .sheet(isPresented: $showSounds) {
            NavigationStack {
                SleepSoundsTab()
                    .navigationTitle("Sounds")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showSounds = false }
                        }
                    }
            }
        }
    }
}

struct SleepLastNightStrip: View {
    @EnvironmentObject var store: AppStore

    private var night: SleepData? { store.sleepData.first }

    var body: some View {
        if let night {
            VStack(alignment: .leading, spacing: 12) {
                Text("Last night")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.textTertiary)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(EnergySchedule.durationLabel(night.totalHours))
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(.textPrimary)
                        .monospacedDigit()
                    Text("asleep")
                        .font(.system(size: 15))
                        .foregroundColor(.textSecondary)
                    Spacer()
                    Text("Deep \(night.deepMinutes)m  ·  REM \(night.remMinutes)m")
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                        .monospacedDigit()
                }
                SleepStageHairline(night: night)
            }
        }
    }
}

struct SleepLastNightDetail: View {
    @EnvironmentObject var store: AppStore

    private var night: SleepData? { store.sleepData.first }

    var body: some View {
        if let night {
            VStack(alignment: .leading, spacing: 14) {
                Text("Last night")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.textTertiary)
                Text(EnergySchedule.durationLabel(night.totalHours))
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundColor(.textPrimary)
                    .monospacedDigit()
                SleepStageHairline(night: night)
                HStack(spacing: 0) {
                    nightStat("Deep", "\(night.deepMinutes)m")
                    nightStat("REM", "\(night.remMinutes)m")
                    nightStat("Light", "\(night.lightMinutes)m")
                    nightStat("Awake", "\(night.awakeMinutes)m")
                }
                .padding(.top, 6)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("No night on file")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Text("Connect Apple Health and last night will land here.")
                    .font(.system(size: 14))
                    .foregroundColor(.textSecondary)
            }
        }
    }

    private func nightStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.textPrimary)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SleepStageHairline: View {
    let night: SleepData

    private var parts: [(Color, Int)] {
        [
            (Color.danger.opacity(0.7), night.awakeMinutes),
            (Color(hex: "475569"), night.lightMinutes),
            (Color.steel, night.deepMinutes),
            (Color.aurora, night.remMinutes),
        ]
    }

    private var total: Int { max(1, parts.reduce(0) { $0 + $1.1 }) }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    Capsule()
                        .fill(part.0)
                        .frame(width: max(3, geo.size.width * CGFloat(part.1) / CGFloat(total)))
                }
            }
        }
        .frame(height: 6)
    }
}

struct SleepWeekRhythm: View {
    @EnvironmentObject var store: AppStore

    private var nights: [SleepData] {
        Array(store.sleepData.prefix(7).reversed())
    }

    private var need: Double {
        EnergySchedule.make(from: store.sleepData)?.needHours ?? 8
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This week")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.textTertiary)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(nights) { night in
                    VStack(spacing: 6) {
                        Capsule()
                            .fill(night.totalHours >= need - 0.4 ? Color.ember.opacity(0.85) : Color.white.opacity(0.16))
                            .frame(height: max(8, CGFloat(night.totalHours / 10) * 72))
                        Text(weekday(night.date))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 96, alignment: .bottom)
        }
    }

    private func weekday(_ value: String) -> String {
        let parse = DateFormatter()
        parse.dateFormat = "yyyy-MM-dd"
        guard let date = parse.date(from: value) else { return "" }
        let out = DateFormatter()
        out.setLocalizedDateFormatFromTemplate("EEEEE")
        return out.string(from: date)
    }
}

// MARK: - Sleep Score Hero Card (upgraded from ring-only to full card)

struct SleepScoreHeroCard: View {
    @EnvironmentObject var store: AppStore
    @State private var progress: CGFloat = 0
    @State private var appeared = false

    var latest: SleepData { store.sleepData[0] }
    var score: Int { min(100, max(0, latest.score)) }
    var totalHrs: String {
        let h = Int(latest.totalHours); let m = Int((latest.totalHours - Double(h)) * 60)
        return "\(h)h \(m)m"
    }

    var scoreLabel: String {
        switch score { case 85...: return "Excellent"; case 70..<85: return "Good"; case 55..<70: return "Fair"; default: return "Poor" }
    }
    var scoreColor: Color {
        switch score { case 85...: return .success; case 70..<85: return .steel; case 55..<70: return .warning; default: return .danger }
    }

    let size: CGFloat = 168
    let stroke: CGFloat = 13

    var body: some View {
        VStack(spacing: 20) {
            // Ring
            ZStack {
                // Track
                Circle()
                    .stroke(Color.borderColor.opacity(0.5), style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                    .frame(width: size, height: size)

                // Glow
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(scoreColor.opacity(0.3), style: StrokeStyle(lineWidth: stroke + 6, lineCap: .round))
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(-90))
                    .blur(radius: 8)

                // Main arc
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        LinearGradient(colors: [scoreColor, scoreColor.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: stroke, lineCap: .round)
                    )
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(-90))
                    .shadow(color: scoreColor.opacity(0.5), radius: 12)
                    .animation(.spring(response: 1.4, dampingFraction: 0.7).delay(0.3), value: progress)

                // Tip dot
                if progress > 0.02 {
                    Circle()
                        .fill(scoreColor)
                        .frame(width: stroke * 0.85, height: stroke * 0.85)
                        .shadow(color: scoreColor, radius: 4)
                        .offset(y: -size / 2)
                        .rotationEffect(.degrees(-90 + Double(progress) * 360))
                }

                // Center
                VStack(spacing: 5) {
                    Text("\(score)")
                        .font(.system(size: 46, weight: .black, design: .rounded))
                        .foregroundColor(.textPrimary)
                        .scaleEffect(appeared ? 1 : 0.7)
                        .animation(.spring(response: 0.55, dampingFraction: 0.7).delay(0.25), value: appeared)
                    Text(scoreLabel)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(scoreColor)
                        .tracking(0.5)
                        .opacity(appeared ? 1 : 0)
                        .animation(.easeOut(duration: 0.3).delay(0.45), value: appeared)
                }
            }
            .frame(width: size, height: size)

            // Stats row
            HStack(spacing: 0) {
                ScoreStatPill(value: totalHrs, label: "Total")
                Divider().frame(height: 32).background(Color.borderColor)
                ScoreStatPill(value: "\(latest.deepMinutes)m", label: "Deep")
                Divider().frame(height: 32).background(Color.borderColor)
                ScoreStatPill(value: "\(latest.remMinutes)m", label: "REM")
                Divider().frame(height: 32).background(Color.borderColor)
                ScoreStatPill(value: "\(latest.awakeMinutes)m", label: "Awake")
            }
            .padding(.horizontal, 8)
        }
        .padding(24)
        .background(
            ZStack {
                Color.surface
                RadialGradient(colors: [scoreColor.opacity(0.07), .clear], center: .center, startRadius: 40, endRadius: 200)
            }
        )
        .cornerRadius(24)
        .shadow(color: .black.opacity(0.07), radius: 20, y: 8)
        .onAppear {
            appeared = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                progress = CGFloat(score) / 100
            }
        }
    }
}

struct ScoreStatPill: View {
    let value: String; let label: String
    var body: some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 16, weight: .bold)).foregroundColor(.textPrimary)
            Text(label).font(.system(size: 11, weight: .medium)).foregroundColor(.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Alarm Tab

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

// MARK: - Next Alarm Hero

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

// MARK: - Alarm Row

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

// MARK: - Alarm Editor Sheet

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

private struct EditorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 10, weight: .black))
                .foregroundColor(.textTertiary)
                .tracking(2.5)
            content()
        }
    }
}

// MARK: - Sleep Sounds Tab

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

// MARK: - Now Playing Bar

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

// MARK: - Sound Mixer Panel

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

// MARK: - Sound Card

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

// MARK: - Wake Up Tab

struct WakeUpTab: View {
    @EnvironmentObject private var hkService: HealthKitSleepService
    @State private var smartWakeEnabled = true
    @State private var smartWakeWindow  = 30
    @State private var sunriseEnabled   = true
    @State private var sunriseDuration  = 20          // minutes
    @State private var colorTemp        = 0.5         // 0=warm, 1=cool
    @State private var volumeRamp: VolumeRampCurve    = .gradual
    @State private var morningRoutine: [RoutineItem]  = RoutineItem.defaults

    var body: some View {
        VStack(spacing: 20) {
            SmartWakeCard(
                enabled: $smartWakeEnabled,
                windowMinutes: $smartWakeWindow
            )

            AdaptiveSunriseCard(
                config: hkService.currentSunriseConfig,
                enabled: $sunriseEnabled,
                duration: $sunriseDuration,
                colorTemp: $colorTemp
            )

            VolumeRampCard(curve: $volumeRamp)

            MorningRoutineCard(items: $morningRoutine)

            WakeGreetingCard()
        }
        .onAppear {
            let config = hkService.currentSunriseConfig
            sunriseDuration = config.durationMinutes
            colorTemp = config.colorTemp
            smartWakeWindow = hkService.computeSmartAlarmWindow(
                baseWindow: smartWakeWindow,
                recentScore: nil,
                debt: 0,
                chronotype: hkService.userProfile.chronotype
            )
        }
    }
}

// MARK: - Smart Wake Card

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

// MARK: - Sunrise Simulation Card

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

// MARK: - Volume Ramp Card

enum VolumeRampCurve: String, CaseIterable {
    case instant  = "Instant"
    case gentle   = "Gentle"
    case gradual  = "Gradual"

    var description: String {
        switch self {
        case .instant: return "Full volume immediately"
        case .gentle:  return "Ramps up over 15 seconds"
        case .gradual: return "Slowly increases over 60 seconds"
        }
    }
    var icon: String {
        switch self {
        case .instant: return "bolt.fill"
        case .gentle:  return "chart.line.uptrend.xyaxis"
        case .gradual: return "waveform.path"
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

// MARK: - Morning Routine Card

struct RoutineItem: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var icon: String
    var duration: Int        // minutes
    var isEnabled: Bool = true

    static var defaults: [RoutineItem] {[
        RoutineItem(name: "Drink Water",       icon: "drop.fill",            duration: 1),
        RoutineItem(name: "Morning Sunlight",  icon: "sun.max.fill",         duration: 10),
        RoutineItem(name: "Stretch / Mobility",icon: "figure.cooldown",      duration: 10),
        RoutineItem(name: "Cold Shower",       icon: "thermometer.snowflake", duration: 3),
        RoutineItem(name: "Journaling",        icon: "pencil.and.outline",   duration: 5),
        RoutineItem(name: "Meditation",        icon: "brain.fill",           duration: 5),
    ]}
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

// MARK: - Wake Greeting Card

struct WakeGreetingCard: View {
    @State private var greeting = "Good morning, Akshith 🌅"
    @State private var showWeather = true
    @State private var showWorkout = true
    @State private var showSleepScore = true

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
                            if showSleepScore { Label("Sleep 82", systemImage: "moon.stars.fill").foregroundColor(.steel) }
                            if showWeather   { Label("72°F", systemImage: "sun.max.fill").foregroundColor(Color(hex: "F59E0B")) }
                            if showWorkout   { Label("Upper Body", systemImage: "dumbbell.fill").foregroundColor(.ember) }
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

// MARK: - Wake Up Section Container

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

// MARK: - Existing Components (all bugs fixed)

struct SleepStreakCard: View {
    let streak: Int
    @Binding var showDetail: Bool
    @State private var appeared = false

    var body: some View {
        Button { showDetail = true } label: {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color.ember, Color.ember.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 58, height: 58)
                        .shadow(color: Color.ember.opacity(0.45), radius: 10, y: 4)
                    Image(systemName: "flame.fill").font(.system(size: 26)).foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(streak)").font(.system(size: 28, weight: .black, design: .rounded)).foregroundColor(.textPrimary)
                        Text("Day Streak").font(.system(size: 16, weight: .medium)).foregroundColor(.textSecondary)
                    }
                    Text(streak >= 7 ? "🔥 On fire!" : "Keep it going!")
                        .font(.system(size: 13)).foregroundColor(.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundColor(.textMuted)
            }
            .padding(18)
            .background(Color.surface)
            .cornerRadius(20)
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.ember.opacity(0.2), lineWidth: 1))
            .shadow(color: .black.opacity(0.05), radius: 12, y: 4)
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.96)
        }
        .buttonStyle(.plain)
        .onAppear { withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) { appeared = true } }
    }
}

struct AISleepPredictionCard: View {
    @State private var appear = false
    @State private var showDetail = false

    var body: some View {
        Button { showDetail = true } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(Color.steel.opacity(0.15)).frame(width: 34, height: 34)
                        Image(systemName: "sparkles").font(.system(size: 14)).foregroundColor(.steel)
                    }
                    Text("AI Sleep Prediction").font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(.textMuted)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Optimal Bedtime Tonight")
                        .font(.system(size: 12)).foregroundColor(.textSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("10:15 PM")
                            .font(.system(size: 26, weight: .bold, design: .rounded)).foregroundColor(.steel)
                        Text("for peak recovery")
                            .font(.system(size: 13)).foregroundColor(.textTertiary)
                    }
                }
                Text("Based on workout intensity and your 7-day sleep pattern")
                    .font(.system(size: 12)).foregroundColor(.textMuted).lineLimit(2)
            }
            .padding(18)
            .background(Color.surface)
            .cornerRadius(20)
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.steel.opacity(0.25), lineWidth: 1))
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 10)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) { AISleepPredictionDetailView() }
        .onAppear { withAnimation(.easeOut(duration: 0.4).delay(0.1), { appear = true }) }
    }
}

struct SleepTimelineView: View {
    @EnvironmentObject var store: AppStore
    @State private var appeared = false

    struct Stage: Identifiable {
        let id: String; let label: String; let minutes: Int; let color: Color
    }

    var latest: SleepData { store.sleepData[0] }
    var stages: [Stage] {[
        Stage(id: "awake", label: "Awake", minutes: latest.awakeMinutes, color: .danger),
        Stage(id: "light", label: "Light",  minutes: latest.lightMinutes, color: Color.borderColor),
        Stage(id: "deep",  label: "Deep",   minutes: latest.deepMinutes,  color: .steel),
        Stage(id: "rem",   label: "REM",    minutes: latest.remMinutes,   color: Color(hex: "A78BFA")),
    ]}
    var total: Int { stages.reduce(0) { $0 + $1.minutes } }

    func fmt(_ m: Int) -> String { m >= 60 ? "\(m/60)h \(m%60)m" : "\(m)m" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sleep Stages").font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary)

            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(Array(stages.enumerated()), id: \.element.id) { i, stage in
                        let w = total > 0 ? CGFloat(stage.minutes) / CGFloat(total) * geo.size.width : 0
                        Rectangle().fill(stage.color)
                            .frame(width: appeared ? w : 0, height: 36)
                            .shadow(color: stage.id == "deep" ? stage.color.opacity(0.4) : .clear, radius: 6)
                            .animation(.easeOut(duration: 0.8).delay(Double(i) * 0.1), value: appeared)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .frame(height: 36)

            FlowLayout(spacing: 12) {
                ForEach(stages) { s in
                    HStack(spacing: 6) {
                        Circle().fill(s.color).frame(width: 9, height: 9)
                        Text(s.label).font(.system(size: 12)).foregroundColor(.textSecondary)
                        Text(fmt(s.minutes)).font(.system(size: 12, weight: .semibold)).foregroundColor(.textPrimary)
                    }
                }
            }
        }
        .padding(18)
        .background(Color.surface)
        .cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.borderColor.opacity(0.5), lineWidth: 1))
        // Fixed: withAnimation requires value: parameter
        .onAppear { withAnimation(.easeOut(duration: 0.6)) { appeared = true } }
    }
}

struct SleepBreakdownView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var hkService: HealthKitSleepService

    var latest: SleepData { store.sleepData[0] }
    var efficiency: Double {
        let t = latest.totalHours * 60
        return t > 0 ? ((t - Double(latest.awakeMinutes)) / t) * 100 : 0
    }
    func fmt(_ m: Int) -> String { m >= 60 ? "\(m/60)hr \(m%60)min" : "\(m)min" }

    struct Card { let label: String; let value: String; let progress: Double?; let color: Color; let subtitle: String }

    var cards: [Card] {
        let deepGoal = hkService.userProfile.chronotype.deepSleepGoalMinutes
        let remGoal = hkService.userProfile.chronotype.remSleepGoalMinutes
        let dp = Double(latest.deepMinutes) / Double(deepGoal) * 100
        let rp = Double(latest.remMinutes) / Double(remGoal) * 100
        return [
            Card(label: "Deep Sleep",      value: fmt(latest.deepMinutes), progress: dp, color: dp >= 100 ? .success : .steel, subtitle: "\(Int(dp))% of \(deepGoal) min goal"),
            Card(label: "REM Sleep",       value: fmt(latest.remMinutes),  progress: rp, color: rp >= 100 ? .success : .steel, subtitle: "\(Int(rp))% of \(remGoal) min goal"),
            Card(label: "Sleep Efficiency",value: "\(Int(efficiency))%",   progress: efficiency, color: efficiency >= 85 ? .success : efficiency >= 75 ? .warning : .danger, subtitle: efficiency >= 85 ? "Excellent" : "Needs work"),
            Card(label: "Time Awake",      value: "\(latest.awakeMinutes)m", progress: nil, color: .danger, subtitle: latest.awakeMinutes <= 15 ? "Great" : "High"),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Breakdown").font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(Array(cards.enumerated()), id: \.offset) { i, card in
                    SleepBreakdownCard(item: card, index: i)
                }
            }
        }
    }
}

struct SleepBreakdownCard: View {
    let item: SleepBreakdownView.Card
    let index: Int
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.label).font(.system(size: 12, weight: .medium)).foregroundColor(.textSecondary)
            Text(item.value).font(.system(size: 18, weight: .bold)).foregroundColor(.textPrimary)
            if let p = item.progress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.borderColor.opacity(0.4)).frame(height: 5)
                        Capsule().fill(item.color)
                            .frame(width: appeared ? geo.size.width * CGFloat(min(p, 100)) / 100 : 0, height: 5)
                            .animation(.spring(response: 1.0, dampingFraction: 0.7).delay(0.2 + Double(index) * 0.08), value: appeared)
                    }
                }
                .frame(height: 5)
            }
            Text(item.subtitle).font(.system(size: 10)).foregroundColor(.textTertiary)
        }
        .padding(14)
        .background(Color.surface)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(item.color.opacity(0.2), lineWidth: 1))
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .onAppear { withAnimation(.easeOut(duration: 0.4).delay(Double(index) * 0.08)) { appeared = true } }
    }
}

struct AISleepInsightView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var hkService: HealthKitSleepService

    var insight: String {
        let d = store.sleepData[0]
        let s = "\(d.deepMinutes >= 60 ? "\(d.deepMinutes/60)hr " : "")\(d.deepMinutes % 60)min"
        if d.score >= 85 { return "Excellent recovery. \(s) of deep sleep has fully topped up muscle repair. You're primed for a heavy session today." }
        else if d.score >= 70 { return "Good sleep — \(s) deep sleep. HRV reflects adequate recovery. Cut screens 45 min before bed to push this score higher." }
        else { return "Only \(s) of deep sleep last night. Recovery is below target. Consider a lighter session and an earlier bedtime tonight." }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color.steel.opacity(0.12)).frame(width: 38, height: 38)
                Image(systemName: "moon.stars.fill").font(.system(size: 16)).foregroundColor(.steel)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("AI Sleep Insight")
                    .font(.system(size: 12, weight: .bold)).foregroundColor(.steel).tracking(0.5)
                Text(hkService.chronotypeInsightPrefix() + insight)
                    .font(.system(size: 14)).foregroundColor(.textPrimary).lineSpacing(5)
            }
        }
        .padding(18)
        .background(Color.surface)
        .cornerRadius(20)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3).fill(Color.steel).frame(width: 3).padding(.vertical, 12)
        }
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }
}

struct RecoveryTrendsView: View {
    @EnvironmentObject var store: AppStore

    private let mockHRV: [Double] = [44, 46, 52, 48, 41, 55, 50]
    private let mockRHR: [Double] = [62, 60, 58, 61, 64, 57, 59]

    struct Pt: Identifiable { var id = UUID(); var day: String; var value: Double; var series: String }

    func dayAbbr(_ s: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: s) else { return "" }
        let df = DateFormatter(); df.dateFormat = "EEE"; return df.string(from: d)
    }

    var scorePoints: [Pt] { store.sleepData.prefix(7).reversed().enumerated().map { Pt(day: dayAbbr($1.date), value: Double($1.score), series: "Score") }}
    var hrvPoints:   [Pt] { store.sleepData.prefix(7).reversed().enumerated().map { i, d in Pt(day: dayAbbr(d.date), value: mockHRV[i % mockHRV.count], series: "HRV") }}
    var rhrPoints:   [Pt] { store.sleepData.prefix(7).reversed().enumerated().map { i, d in Pt(day: dayAbbr(d.date), value: mockRHR[i % mockRHR.count], series: "RHR") }}

    var body: some View {
        VStack(spacing: 16) {
            ChartCard(title: "Recovery Trend") {
                Chart {
                    ForEach(scorePoints) { p in
                        AreaMark(x: .value("Day", p.day), y: .value("Score", p.value)).foregroundStyle(Color.steel.opacity(0.2))
                        LineMark(x: .value("Day", p.day), y: .value("Score", p.value)).foregroundStyle(Color.steel).lineStyle(StrokeStyle(lineWidth: 2.5))
                        PointMark(x: .value("Day", p.day), y: .value("Score", p.value)).foregroundStyle(Color.steel).symbolSize(44)
                    }
                }
                .chartYScale(domain: 40...100)
                .chartXAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(Color.textTertiary) } }
                .chartYAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(Color.textTertiary); AxisGridLine().foregroundStyle(Color.borderColor.opacity(0.4)) } }
                .frame(height: 150)
            }

            ChartCard(title: "HRV & Resting HR") {
                Chart {
                    ForEach(hrvPoints) { p in LineMark(x: .value("Day", p.day), y: .value("HRV", p.value)).foregroundStyle(Color.steel).lineStyle(StrokeStyle(lineWidth: 2.5)); PointMark(x: .value("Day", p.day), y: .value("HRV", p.value)).foregroundStyle(Color.steel).symbolSize(38) }
                    ForEach(rhrPoints) { p in LineMark(x: .value("Day", p.day), y: .value("RHR", p.value)).foregroundStyle(Color.ember).lineStyle(StrokeStyle(lineWidth: 2.5)); PointMark(x: .value("Day", p.day), y: .value("RHR", p.value)).foregroundStyle(Color.ember).symbolSize(38) }
                }
                .chartXAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(Color.textTertiary) } }
                .chartYAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(Color.textTertiary); AxisGridLine().foregroundStyle(Color.borderColor.opacity(0.4)) } }
                .frame(height: 150)
                HStack(spacing: 16) {
                    Label { Text("HRV (ms)").font(.system(size: 11)).foregroundColor(.textSecondary) } icon: { Circle().fill(Color.steel).frame(width: 8, height: 8) }
                    Label { Text("Resting HR").font(.system(size: 11)).foregroundColor(.textSecondary) } icon: { Circle().fill(Color.ember).frame(width: 8, height: 8) }
                }
            }
        }
    }
}

private struct ChartCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
            content()
        }
        .padding(16).background(Color.surface).cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.borderColor.opacity(0.4), lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
    }
}

struct SleepWeeklyComparisonChart: View {
    @EnvironmentObject var store: AppStore
    @State private var appeared = false

    struct DayData: Identifiable { let id = UUID(); let day: String; let hours: Double; let score: Int }

    var weekData: [DayData] {
        store.sleepData.prefix(7).reversed().map { s in
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            guard let d = f.date(from: s.date) else { return DayData(day: "", hours: s.totalHours, score: s.score) }
            let df = DateFormatter(); df.dateFormat = "EEE"
            return DayData(day: df.string(from: d), hours: s.totalHours, score: s.score)
        }
    }

    var body: some View {
        ChartCard(title: "Weekly Sleep Duration") {
            Chart {
                ForEach(weekData) { d in
                    BarMark(x: .value("Day", d.day), y: .value("Hours", appeared ? d.hours : 0))
                        .foregroundStyle(d.score >= 75 ? Color.steel : Color.warning)
                        .cornerRadius(6)
                }
            }
            .chartYScale(domain: 0...10)
            .chartXAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(Color.textTertiary) } }
            .chartYAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(Color.textTertiary); AxisGridLine().foregroundStyle(Color.borderColor.opacity(0.4)) } }
            .frame(height: 170)
            .animation(.easeOut(duration: 0.8).delay(0.2), value: appeared)
            HStack {
                Label { Text("Good (≥75)").font(.system(size: 11)).foregroundColor(.textSecondary) } icon: { Circle().fill(Color.steel).frame(width: 8, height: 8) }
                Spacer()
                Label { Text("Below target").font(.system(size: 11)).foregroundColor(.textSecondary) } icon: { Circle().fill(Color.warning).frame(width: 8, height: 8) }
            }
        }
        .onAppear { withAnimation(.easeOut(duration: 0.5)) { appeared = true } }
    }
}

struct AISleepEnvironmentView: View {
    @State private var appeared = false
    private struct Metric: Identifiable { let id = UUID(); let icon: String; let label: String; let value: String; let status: String; let color: Color }
    private let metrics: [Metric] = [
        Metric(icon: "thermometer.medium",   label: "Temperature", value: "68°F", status: "Optimal",  color: .success),
        Metric(icon: "drop.fill",            label: "Humidity",    value: "45%",  status: "Good",     color: .success),
        Metric(icon: "moon.fill",            label: "Light Level", value: "Dark", status: "Perfect",  color: .success),
        Metric(icon: "speaker.wave.2.fill",  label: "Noise",       value: "32 dB", status: "Quiet",  color: .success),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "house.fill").font(.system(size: 14)).foregroundColor(.steel)
                Text("Sleep Environment").font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(Array(metrics.enumerated()), id: \.element.id) { i, m in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: m.icon).font(.system(size: 12)).foregroundColor(.steel)
                            Text(m.label).font(.system(size: 11)).foregroundColor(.textSecondary)
                        }
                        Text(m.value).font(.system(size: 17, weight: .bold)).foregroundColor(.textPrimary)
                        Text(m.status).font(.system(size: 10, weight: .semibold)).foregroundColor(m.color)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12).background(Color.surfaceElevated).cornerRadius(12)
                    .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 10)
                    .animation(.easeOut(duration: 0.3).delay(Double(i) * 0.08), value: appeared)
                }
            }
        }
        .padding(18).background(Color.surface).cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.borderColor.opacity(0.4), lineWidth: 1))
        .onAppear { withAnimation(.easeOut(duration: 0.5)) { appeared = true } }
    }
}

struct AIPersonalizedGoalsView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var hkService: HealthKitSleepService
    @State private var appeared = false

    var goals: [AdaptiveSleepGoal] {
        hkService.computeAdaptiveGoals(from: store.sleepData)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "target").font(.system(size: 14)).foregroundColor(.ember)
                Text("Sleep Goals").font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
            }
            VStack(spacing: 10) {
                ForEach(Array(goals.enumerated()), id: \.element.id) { i, g in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: g.icon).font(.system(size: 12)).foregroundColor(.steel)
                            Text(g.title).font(.system(size: 13, weight: .medium)).foregroundColor(.textPrimary)
                            Spacer()
                            Text(String(format: "%.1f / %.1f %@", g.current, g.target, g.unit))
                                .font(.system(size: 13, weight: .semibold)).foregroundColor(.textSecondary)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.borderColor.opacity(0.4)).frame(height: 6)
                                Capsule()
                                    .fill(g.current >= g.target ? Color.success : Color.steel)
                                    .frame(width: appeared ? geo.size.width * CGFloat(min(g.current / g.target, 1.0)) : 0, height: 6)
                                    .animation(.spring(response: 1.0, dampingFraction: 0.7).delay(0.3 + Double(i) * 0.1), value: appeared)
                            }
                        }
                        .frame(height: 6)
                    }
                    .padding(12).background(Color.surfaceElevated).cornerRadius(12)
                    .opacity(appeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.3).delay(Double(i) * 0.1), value: appeared)
                }
            }
        }
        .padding(18).background(Color.surface).cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.borderColor.opacity(0.4), lineWidth: 1))
        .onAppear { withAnimation(.easeOut(duration: 0.5)) { appeared = true } }
    }
}

struct AISmartRecommendationsView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var hkService: HealthKitSleepService
    @State private var appeared = false

    var recs: [SleepRecommendation] {
        hkService.chronotypeRecommendations(debt: hkService.computeSleepDebt(from: store.sleepData))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Smart Recommendations").font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
            VStack(spacing: 10) {
                ForEach(Array(recs.enumerated()), id: \.element.id) { i, rec in
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            Circle().fill(Color.steel.opacity(0.12)).frame(width: 38, height: 38)
                            Image(systemName: rec.icon).font(.system(size: 14)).foregroundColor(.steel)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(rec.title).font(.system(size: 13, weight: .semibold)).foregroundColor(.textPrimary)
                                Spacer()
                                Text(rec.priority)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(rec.priority == "High" ? .ember : .warning)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background((rec.priority == "High" ? Color.ember : Color.warning).opacity(0.12))
                                    .cornerRadius(6)
                            }
                            Text(rec.description).font(.system(size: 12)).foregroundColor(.textSecondary).lineLimit(2)
                        }
                    }
                    .padding(12).background(Color.surfaceElevated).cornerRadius(12)
                    .opacity(appeared ? 1 : 0).offset(x: appeared ? 0 : -10)
                    .animation(.easeOut(duration: 0.3).delay(Double(i) * 0.08), value: appeared)
                }
            }
        }
        .padding(18).background(Color.surface).cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.borderColor.opacity(0.4), lineWidth: 1))
        .onAppear { withAnimation(.easeOut(duration: 0.5)) { appeared = true } }
    }
}

struct SleepAchievementsView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var hkService: HealthKitSleepService
    @State private var appeared = false

    var achievements: [SleepAchievementState] {
        hkService.computeAchievements(from: store.sleepData)
    }

    private func achievementColor(_ name: String, unlocked: Bool) -> Color {
        guard unlocked else { return .textMuted }
        switch name {
        case "ember": return .ember
        case "steel": return .steel
        case "success": return .success
        default: return .steel
        }
    }

    private func achievementIcon(_ id: String) -> String {
        switch id {
        case "perfect-week": return "star.fill"
        case "deep-sleeper": return "moon.stars.fill"
        case "consistency": return "clock.fill"
        default: return "star.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Achievements").font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(achievements.enumerated()), id: \.element.id) { i, a in
                        let color = achievementColor(a.colorName, unlocked: a.unlocked)
                        VStack(spacing: 10) {
                            ZStack {
                                Circle().fill(a.unlocked ? color.opacity(0.15) : Color.borderColor.opacity(0.25)).frame(width: 58, height: 58)
                                Image(systemName: achievementIcon(a.id)).font(.system(size: 24)).foregroundColor(a.unlocked ? color : .textMuted)
                            }
                            VStack(spacing: 3) {
                                Text(a.title).font(.system(size: 12, weight: .bold)).foregroundColor(.textPrimary)
                                Text(a.description).font(.system(size: 10)).foregroundColor(.textSecondary).multilineTextAlignment(.center)
                            }
                        }
                        .frame(width: 110)
                        .padding(.vertical, 14)
                        .background(Color.surfaceElevated)
                        .cornerRadius(16)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(a.unlocked ? color.opacity(0.3) : Color.borderColor.opacity(0.3), lineWidth: 1))
                        .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 10)
                        .animation(.easeOut(duration: 0.3).delay(Double(i) * 0.08), value: appeared)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(18).background(Color.surface).cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.borderColor.opacity(0.4), lineWidth: 1))
        .onAppear { withAnimation(.easeOut(duration: 0.5)) { appeared = true } }
    }
}

struct SleepDebtTrackerView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var hkService: HealthKitSleepService
    @State private var appeared = false

    var debt: Double {
        hkService.computeSleepDebt(from: store.sleepData)
    }
    // Thresholds match EnergyScheduleCard's, deliberately. The two cards render
    // the same number and disagreeing about whether it is bad would be worse
    // than either of them being slightly off.
    var debtColor: Color { debt >= 8 ? .alert : debt >= 2 ? .amber : .vitality }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sleep Debt").font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%.1f", debt)).font(.system(size: 32, weight: .bold, design: .rounded)).foregroundColor(debtColor)
                        Text("hours").font(.system(size: 14)).foregroundColor(.textSecondary)
                    }
                    Text("Last 14 nights").font(.system(size: 12)).foregroundColor(.textTertiary)
                }
                Spacer()
                Text(debt >= 8 ? "Prioritize recovery" : debt >= 2 ? "Add 30 min tonight" : "On track! 🎉")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(debtColor)
                    .multilineTextAlignment(.trailing)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.borderColor.opacity(0.3)).frame(height: 8)
                    Capsule().fill(debtColor)
                        .frame(width: appeared ? geo.size.width * CGFloat(min(debt / 14, 1.0)) : 0, height: 8)
                        .animation(.spring(response: 1.0, dampingFraction: 0.7).delay(0.2), value: appeared)
                }
            }
            .frame(height: 8)
        }
        .padding(18).background(Color.surface).cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.borderColor.opacity(0.4), lineWidth: 1))
        .onAppear { withAnimation(.easeOut(duration: 0.5)) { appeared = true } }
    }
}

struct SleepQuickActionsBar: View {
    @State private var appeared = false
    let onAITap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            QuickActionButton(icon: "moon.fill",                  title: "Tips",   color: .steel,   action: {})
            QuickActionButton(icon: "bell.badge.fill",            title: "Alarm",  color: .ember,   action: {})
            QuickActionButton(icon: "brain.head.profile",         title: "ARIA",   color: .steel,   action: onAITap)
            QuickActionButton(icon: "chart.line.uptrend.xyaxis",  title: "Trends", color: Color(hex: "6366F1"), action: {})
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Color.surface)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.1), radius: 14, y: 5)
        .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 20)
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.3)) { appeared = true } }
    }
}

struct QuickActionButton: View {
    let icon: String; let title: String; let color: Color; let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle().fill(color.opacity(0.14)).frame(width: 44, height: 44)
                    Image(systemName: icon).font(.system(size: 18, weight: .medium)).foregroundColor(color)
                }
                Text(title).font(.system(size: 11, weight: .medium)).foregroundColor(.textPrimary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Streak Detail Sheet (fixed: NavigationView → NavigationStack)

struct SleepStreakDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let streak: Int

    private let milestones: [(days: Int, title: String, icon: String)] = [
        (7,   "Week Warrior",  "flame.fill"),
        (30,  "Month Master",  "moon.stars.fill"),
        (100, "Century Club",  "crown.fill"),
        (365, "Year Legend",   "trophy.fill"),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 28) {
                        // Hero
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(LinearGradient(colors: [Color.ember, Color.ember.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 100, height: 100)
                                    .shadow(color: Color.ember.opacity(0.45), radius: 20, y: 8)
                                Image(systemName: "flame.fill").font(.system(size: 46)).foregroundColor(.white)
                            }
                            Text("\(streak) Days").font(.system(size: 36, weight: .black, design: .rounded)).foregroundColor(.textPrimary)
                            Text("Current Sleep Streak").font(.system(size: 16)).foregroundColor(.textSecondary)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 28)

                        // Milestones
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Milestones").font(.system(size: 18, weight: .bold)).foregroundColor(.textPrimary)
                            VStack(spacing: 10) {
                                ForEach(milestones, id: \.days) { m in
                                    HStack(spacing: 14) {
                                        ZStack {
                                            Circle().fill(streak >= m.days ? Color.ember.opacity(0.15) : Color.surfaceElevated).frame(width: 42, height: 42)
                                            Image(systemName: streak >= m.days ? "checkmark" : m.icon)
                                                .font(.system(size: 16)).foregroundColor(streak >= m.days ? .ember : .textMuted)
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(m.title).font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
                                            Text("\(m.days) days").font(.system(size: 12)).foregroundColor(.textSecondary)
                                        }
                                        Spacer()
                                        if streak < m.days {
                                            Text("\(m.days - streak) to go")
                                                .font(.system(size: 12, weight: .semibold)).foregroundColor(.steel)
                                                .padding(.horizontal, 10).padding(.vertical, 5)
                                                .background(Color.steel.opacity(0.1)).cornerRadius(8)
                                        }
                                    }
                                    .padding(14).background(Color.surface).cornerRadius(14)
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(streak >= m.days ? Color.ember.opacity(0.3) : Color.borderColor.opacity(0.4), lineWidth: 1))
                                }
                            }
                        }
                        .padding(20).background(Color.surface).cornerRadius(20)

                        // Benefits
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Streak Benefits").font(.system(size: 18, weight: .bold)).foregroundColor(.textPrimary)
                            VStack(spacing: 10) {
                                ForEach([("heart.fill", "Improved cardiovascular health"), ("brain.head.profile", "Enhanced cognitive function"), ("figure.run", "Better athletic performance"), ("face.smiling.fill", "Elevated mood & energy")], id: \.0) { icon, text in
                                    HStack(spacing: 12) {
                                        Image(systemName: icon).font(.system(size: 14)).foregroundColor(.steel).frame(width: 20)
                                        Text(text).font(.system(size: 13)).foregroundColor(.textPrimary)
                                    }
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    .background(Color.surfaceElevated).cornerRadius(12)
                                }
                            }
                        }
                        .padding(20).background(Color.surface).cornerRadius(20)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Sleep Streak")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundColor(.ember).fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - AI Sleep Chat (fixed: NavigationView → NavigationStack)

struct AISleepChatView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var hkService: HealthKitSleepService
    @State private var input = ""

    private var ariaContext: String {
        hkService.buildARIAContext(sleepData: store.sleepData, store: store)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()
                VStack {
                    ScrollView {
                        VStack(spacing: 16) {
                            Text("Ask me anything about your sleep patterns, recovery, or how to optimize your rest for better performance.")
                                .font(.system(size: 14)).foregroundColor(.textSecondary).multilineTextAlignment(.center).lineSpacing(5).padding(.horizontal, 24).padding(.top, 16)
                            if !store.sleepData.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("ARIA Context (ready for backend)")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.steel)
                                        .tracking(0.5)
                                    Text(ariaContext)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.textTertiary)
                                        .lineSpacing(4)
                                }
                                .padding(14)
                                .background(Color.surface)
                                .cornerRadius(12)
                                .padding(.horizontal, 16)
                            }
                        }
                    }
                    Spacer()
                    HStack(spacing: 12) {
                        TextField("Ask about your sleep…", text: $input)
                            .font(.system(size: 15)).foregroundColor(.textPrimary).tint(.steel)
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            .background(Color.surfaceElevated).cornerRadius(14)
                        Button {} label: {
                            Circle().fill(Color.steel).frame(width: 44, height: 44)
                                .overlay(Image(systemName: "arrow.up").font(.system(size: 16, weight: .bold)).foregroundColor(.white))
                                .shadow(color: Color.steel.opacity(0.35), radius: 8, y: 3)
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 20)
                }
            }
            .navigationTitle("Sleep AI — ARIA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundColor(.steel).fontWeight(.semibold)
                }
            }
        }
    }
}

struct AISleepPredictionDetailView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Tonight's Recommendation").font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("10:15 PM").font(.system(size: 40, weight: .black, design: .rounded)).foregroundColor(.steel)
                                Text("bedtime").font(.system(size: 16)).foregroundColor(.textSecondary)
                            }
                            Text("Wake at 6:15 AM for 8 hours of sleep").font(.system(size: 14)).foregroundColor(.textSecondary)
                        }
                        .padding(20).background(Color.surface).cornerRadius(20)

                        VStack(alignment: .leading, spacing: 14) {
                            Text("Why This Time?").font(.system(size: 16, weight: .bold)).foregroundColor(.textPrimary)
                            VStack(spacing: 10) {
                                ForEach([("figure.strengthtraining.traditional", "Heavy workout tomorrow — need optimal recovery"),
                                         ("chart.line.uptrend.xyaxis", "Your 90-min sleep cycles align best with 10 PM"),
                                         ("heart.fill", "HRV trends show earlier sleep improves your recovery by 18%")], id: \.0) { icon, text in
                                    HStack(spacing: 12) {
                                        Image(systemName: icon).font(.system(size: 14)).foregroundColor(.steel).frame(width: 20)
                                        Text(text).font(.system(size: 13)).foregroundColor(.textPrimary)
                                    }
                                    .padding(14).background(Color.surfaceElevated).cornerRadius(12)
                                }
                            }
                        }
                        .padding(20).background(Color.surface).cornerRadius(20)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Sleep Prediction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundColor(.steel).fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Chronotype Badge

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

// MARK: - Adaptive Sunrise Card

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

// MARK: - Sleep Personalization Sheet

struct SleepPersonalizationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var hkService: HealthKitSleepService
    @EnvironmentObject var store: AppStore
    @State private var draft = UserSleepProfile()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Your chronotype shapes scoring, goals, sunrise, and smart wake.")
                            .font(.system(size: 14))
                            .foregroundColor(.textSecondary)
                            .lineSpacing(4)

                        VStack(spacing: 10) {
                            ForEach(Chronotype.allCases) { type in
                                Button {
                                    draft.chronotype = type
                                    UISelectionFeedbackGenerator().selectionChanged()
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: type.icon)
                                            .font(.system(size: 18))
                                            .foregroundColor(draft.chronotype == type ? .white : .steel)
                                            .frame(width: 40, height: 40)
                                            .background(draft.chronotype == type ? Color.steel : Color.surfaceElevated)
                                            .cornerRadius(12)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(type.displayName)
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundColor(.textPrimary)
                                            Text(type.tagline)
                                                .font(.system(size: 12))
                                                .foregroundColor(.textTertiary)
                                        }
                                        Spacer()
                                        if draft.chronotype == type {
                                            Image(systemName: "checkmark.circle.fill").foregroundColor(.steel)
                                        }
                                    }
                                    .padding(14)
                                    .background(Color.surface)
                                    .cornerRadius(14)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(draft.chronotype == type ? Color.steel.opacity(0.5) : Color.borderColor.opacity(0.4), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Coaching personality")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.textSecondary)
                            TextField("e.g. direct, encouraging, data-focused", text: $draft.personality)
                                .padding(12)
                                .background(Color.surfaceElevated)
                                .cornerRadius(12)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Lifestyle notes")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.textSecondary)
                            TextEditor(text: $draft.notes)
                                .frame(minHeight: 90)
                                .padding(8)
                                .background(Color.surfaceElevated)
                                .cornerRadius(12)
                                .scrollContentBackground(.hidden)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Sleep Profile")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { draft = hkService.userProfile }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        hkService.updateProfile(draft)
                        if !store.sleepData.isEmpty {
                            Task {
                                let rescored = await hkService.fetchRecentSleepData(days: 14)
                                store.mergeSleepDataLocally(rescored)
                            }
                        }
                        dismiss()
                    }
                    .foregroundColor(.steel)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        FlowResult(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews, spacing: spacing).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (i, sv) in subviews.enumerated() {
            sv.place(at: CGPoint(x: bounds.minX + result.positions[i].x, y: bounds.minY + result.positions[i].y), proposal: .unspecified)
        }
    }
    struct FlowResult {
        var size: CGSize = .zero; var positions: [CGPoint] = []
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0; var y: CGFloat = 0; var lineH: CGFloat = 0
            for sv in subviews {
                let sz = sv.sizeThatFits(.unspecified)
                if x + sz.width > maxWidth && x > 0 { x = 0; y += lineH + spacing; lineH = 0 }
                positions.append(CGPoint(x: x, y: y))
                lineH = max(lineH, sz.height); x += sz.width + spacing
            }
            size = CGSize(width: maxWidth, height: y + lineH)
        }
    }
}
