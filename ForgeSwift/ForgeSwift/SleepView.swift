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
    SleepSoundItem(name: "Thunder",       icon: "cloud.bolt.rain.fill",      color: Color.indigo, category: .nature),
    SleepSoundItem(name: "White Noise",   icon: "waveform",                  color: .textTertiary,       category: .noise),
    SleepSoundItem(name: "Brown Noise",   icon: "waveform.path",             color: Color(hex: "92400E"), category: .noise),
    SleepSoundItem(name: "Pink Noise",    icon: "waveform.path.ecg",         color: Color(hex: "EC4899"), category: .noise),
    SleepSoundItem(name: "Fan",           icon: "fan.fill",                  color: .textSecondary,      category: .noise),
    SleepSoundItem(name: "Fireplace",     icon: "flame.fill",                color: .ember,              category: .ambient),
    SleepSoundItem(name: "Café",          icon: "cup.and.saucer.fill",       color: Color(hex: "92400E"), category: .ambient),
    SleepSoundItem(name: "Tibetan Bowl",  icon: "bell.fill",                 color: Color(hex: "A78BFA"), category: .ambient),
    SleepSoundItem(name: "Wind Chimes",   icon: "wind",                      color: Color.sky, category: .ambient),
    SleepSoundItem(name: "Lo-Fi",         icon: "music.note",                color: Color(hex: "F472B6"), category: .focus),
    SleepSoundItem(name: "Binaural",      icon: "headphones",                color: Color(hex: "818CF8"), category: .focus),
    SleepSoundItem(name: "432 Hz",        icon: "tuningfork",                color: .success,            category: .focus),
    SleepSoundItem(name: "Deep Focus",    icon: "brain.fill",                color: Color(hex: "7C3AED"), category: .focus),
]

// MARK: - Sleep Tab Enum

enum SleepTab: Int, CaseIterable {
    case overview, alarm, sounds, wakeUp
    var title: String {
        switch self { case .overview: return "Sleep"; case .alarm: return "Alarm"; case .sounds: return "Sounds"; case .wakeUp: return "Wake Up" }
    }
    var icon: String {
        switch self { case .overview: return "moon.stars.fill"; case .alarm: return "alarm.fill"; case .sounds: return "waveform"; case .wakeUp: return "sunrise.fill" }
    }
}

// MARK: - Root SleepView

struct SleepView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var hkService = HealthKitSleepService.shared
    @State private var selectedTab: SleepTab = .overview
    @State private var showAIChat = false
    @State private var showStreakDetail = false
    @State private var showSleepPersonalization = false
    @Namespace private var tabNS

    var currentStreak: Int {
        var s = 0
        for sleep in store.sleepData { if sleep.score >= 75 { s += 1 } else { break } }
        return s
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Background — deep midnight blue for sleep context
            SleepBackground(tab: selectedTab).ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                SleepHeaderView(
                    selectedTab: selectedTab,
                    showAIChat: $showAIChat,
                    namespace: tabNS,
                    onTabSelect: { selectedTab = $0 }
                )

                // Content
                TabView(selection: $selectedTab) {
                    SleepOverviewTab(
                        streak: currentStreak,
                        showStreakDetail: $showStreakDetail,
                        showAIChat: $showAIChat,
                        showPersonalization: $showSleepPersonalization
                    )
                    .environmentObject(hkService)
                    .tag(SleepTab.overview)

                    AlarmTab()
                        .tag(SleepTab.alarm)

                    SleepSoundsTab()
                        .tag(SleepTab.sounds)

                    WakeUpTab()
                        .environmentObject(hkService)
                        .tag(SleepTab.wakeUp)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.spring(response: 0.42, dampingFraction: 0.82), value: selectedTab)
            }
        }
        .sheet(isPresented: $showAIChat) {
            AISleepChatView()
                .environmentObject(store)
                .environmentObject(hkService)
        }
        .sheet(isPresented: $showStreakDetail) {
            SleepStreakDetailView(streak: currentStreak)
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
    let tab: SleepTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = false

    private var accent: Color {
        switch tab {
        case .overview: return Color(hex: "334155")
        case .alarm:    return Color.ember
        case .sounds:   return Color.steel
        case .wakeUp:   return Color.amber
        }
    }

    var body: some View {
        ZStack {
            Color.background
            RadialGradient(
                colors: [accent.opacity(phase ? 0.09 : 0.04), .clear],
                center: .top, startRadius: 0, endRadius: 500
            )
        }
        .onAppear {
            if !reduceMotion { withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) { phase = true } }
        }
        .animation(.easeInOut(duration: 1.0), value: tab)
    }
}

// MARK: - Sleep Header

struct SleepHeaderView: View {
    let selectedTab: SleepTab
    @Binding var showAIChat: Bool
    let namespace: Namespace.ID
    let onTabSelect: (SleepTab) -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            // Title row
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SLEEP")
                        .font(.forgeDynamic(size: 11, weight: .black))
                        .foregroundColor(.textTertiary)
                        .tracking(3)
                    Text(selectedTab.title)
                        .font(.forgeDynamic(size: 30, weight: .bold))
                        .foregroundColor(.textPrimary)
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedTab)
                }
                Spacer()
                Button {
                    showAIChat = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [Color.steel, Color.steel.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 46, height: 46)
                            .shadow(color: Color.steel.opacity(0.4), radius: 10, y: 4)
                        Image(systemName: "brain.head.profile")
                            .font(.forgeDynamic(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 60)
            .padding(.bottom, 16)

            // Tab pills with matchedGeometryEffect
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(SleepTab.allCases, id: \.self) { tab in
                        Button {
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.75)) { onTabSelect(tab) }
                            UISelectionFeedbackGenerator().selectionChanged()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: tab.icon).font(.forgeDynamic(size: 11, weight: .semibold))
                                Text(tab.title).font(.forgeDynamic(size: 13, weight: .semibold))
                            }
                            .foregroundColor(selectedTab == tab ? .white : .textTertiary)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background {
                                if selectedTab == tab {
                                    Capsule()
                                        .fill(tabColor(tab))
                                        .matchedGeometryEffect(id: "sleepPill", in: namespace)
                                        .shadow(color: tabColor(tab).opacity(0.5), radius: 10, y: 3)
                                } else {
                                    Capsule().fill(Color.surface.opacity(0.6))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 2)
            }
            .padding(.bottom, 12)
        }
    }

    private func tabColor(_ tab: SleepTab) -> Color {
        switch tab {
        case .overview: return Color.steel
        case .alarm:    return Color.ember
        case .sounds:   return Color.indigo
        case .wakeUp:   return Color.amber
        }
    }
}

// MARK: - Overview Tab

struct SleepOverviewTab: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var hkService: HealthKitSleepService
    let streak: Int
    @Binding var showStreakDetail: Bool
    @Binding var showAIChat: Bool
    @Binding var showPersonalization: Bool

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 22) {
                ChronotypeBadge(onTap: { showPersonalization = true })

                // Hero score ring
                SleepScoreHeroCard()

                // Streak
                SleepStreakCard(streak: streak, showDetail: $showStreakDetail)

                // AI Insight (now integrated — was defined but never shown)
                AISleepInsightView()

                // AI Prediction
                AISleepPredictionCard()

                // Sleep stages timeline
                SleepTimelineView()

                // Breakdown grid
                SleepBreakdownView()

                // Recovery trends (now integrated — was defined but never shown)
                RecoveryTrendsView()

                // Weekly chart
                SleepWeeklyComparisonChart()

                // Environment (now integrated — was defined but never shown)
                AISleepEnvironmentView()

                // Personalized goals (now integrated)
                AIPersonalizedGoalsView()

                // Smart recommendations (now integrated)
                AISmartRecommendationsView()

                // Achievements
                SleepAchievementsView()

                // Debt tracker
                SleepDebtTrackerView()

                // Quick actions
                SleepQuickActionsBar(onAITap: { showAIChat = true })
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 120)
        }
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
                        .font(.forgeDynamic(size: 46, weight: .black, design: .rounded))
                        .foregroundColor(.textPrimary)
                        .scaleEffect(appeared ? 1 : 0.7)
                        .animation(.spring(response: 0.55, dampingFraction: 0.7).delay(0.25), value: appeared)
                    Text(scoreLabel)
                        .font(.forgeDynamic(size: 13, weight: .bold))
                        .foregroundColor(scoreColor)
                        .tracking(0.5)
                        .opacity(appeared ? 1 : 0)
                        .animation(.easeOut(duration: 0.3).delay(0.45), value: appeared)
                }
            }
            .frame(width: size, height: size)
            // The ring + centered numbers are decorative layers around one
            // fact; without this VoiceOver reads "82", "Good" as two
            // disconnected stops instead of one sleep-score readout.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Sleep score")
            .accessibilityValue("\(score) out of 100, \(scoreLabel)")

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
            Text(value).font(.forgeDynamic(size: 16, weight: .bold)).foregroundColor(.textPrimary)
            Text(label).font(.forgeDynamic(size: 11, weight: .medium)).foregroundColor(.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
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
            VStack(spacing: 20) {
                // Hero: next alarm display
                if let next = nextAlarm {
                    NextAlarmHero(alarm: next)
                }

                // Alarm list
                VStack(spacing: 14) {
                    HStack {
                        Text("ALARMS")
                            .font(.forgeDynamic(size: 10, weight: .black))
                            .foregroundColor(.textTertiary)
                            .tracking(2.5)
                        Spacer()
                        Button {
                            editingAlarm = ForgeAlarm()
                            showEditor = true
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "plus").font(.forgeDynamic(size: 12, weight: .bold))
                                Text("New").font(.forgeDynamic(size: 13, weight: .semibold))
                            }
                            .foregroundColor(.ember)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color.ember.opacity(0.12))
                            .cornerRadius(8)
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
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 100)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

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
        VStack(spacing: 0) {
            // Glowing time display
            ZStack {
                // Ambient glow
                Ellipse()
                    .fill(RadialGradient(colors: [Color.ember.opacity(0.2), .clear], center: .center, startRadius: 0, endRadius: 120))
                    .frame(width: 280, height: 120)
                    .blur(radius: 20)
                    .scaleEffect(pulse ? 1.1 : 1.0)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(timeString)
                        .font(.forgeDynamic(size: 72, weight: .black, design: .rounded))
                        .foregroundStyle(LinearGradient(
                            colors: [.textPrimary, Color.ember.opacity(0.9)],
                            startPoint: .top, endPoint: .bottom
                        ))
                    Text(ampm)
                        .font(.forgeDynamic(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.ember)
                        .offset(y: -8)
                }
            }
            .padding(.bottom, 8)

            // Label + days
            VStack(spacing: 6) {
                Text(alarm.label)
                    .font(.forgeDynamic(size: 18, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Text(daysString)
                    .font(.forgeDynamic(size: 13, weight: .medium))
                    .foregroundColor(.textTertiary)
            }
            .padding(.bottom, 20)

            // Smart wake badge
            if alarm.isSmartWake {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.path.ecg").font(.forgeDynamic(size: 12))
                    Text("Smart Wake · \(alarm.smartWakeWindow) min window")
                        .font(.forgeDynamic(size: 12, weight: .semibold))
                }
                .foregroundColor(.steel)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color.steel.opacity(0.12))
                .cornerRadius(20)
                .overlay(Capsule().stroke(Color.steel.opacity(0.3), lineWidth: 1))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 24)
        .background(Color.surface)
        .cornerRadius(28)
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(
            LinearGradient(colors: [Color.ember.opacity(0.3), Color.ember.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing),
            lineWidth: 1
        ))
        .shadow(color: Color.ember.opacity(0.12), radius: 24, y: 8)
        .onAppear {
            if !reduceMotion { withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) { pulse = true } }
        }
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
                        .font(.forgeDynamic(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(alarm.isEnabled ? .textPrimary : .textTertiary)
                    HStack(spacing: 8) {
                        Text(alarm.label)
                            .font(.forgeDynamic(size: 13, weight: .medium))
                            .foregroundColor(alarm.isEnabled ? .textSecondary : .textMuted)
                        if !alarm.days.isEmpty {
                            Circle().fill(Color.borderColor).frame(width: 3, height: 3)
                            Text(daysStr)
                                .font(.forgeDynamic(size: 12, weight: .medium))
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
            .padding(.horizontal, 18).padding(.vertical, 16)
            .background(Color.surface)
            .cornerRadius(18)
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(
                alarm.isEnabled ? Color.ember.opacity(0.25) : Color.borderColor.opacity(0.4),
                lineWidth: 1
            ))
            .opacity(alarm.isEnabled ? 1 : 0.55)
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
                                .font(.forgeDynamic(size: 10, weight: .black))
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
                                            .font(.forgeDynamic(size: 13, weight: .bold))
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
                                .font(.forgeDynamic(size: 15))
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
                                                    .font(.forgeDynamic(size: 12, weight: .semibold))
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
                                                    .font(.forgeDynamic(size: 16))
                                                    .foregroundColor(alarm.sound == sound ? .ember : .textTertiary)
                                                    .frame(width: 24)
                                                Text(sound.rawValue)
                                                    .font(.forgeDynamic(size: 13, weight: .medium))
                                                    .foregroundColor(alarm.sound == sound ? .textPrimary : .textSecondary)
                                                    .lineLimit(1)
                                                Spacer()
                                                if alarm.sound == sound {
                                                    Image(systemName: "checkmark")
                                                        .font(.forgeDynamic(size: 11, weight: .bold))
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
                                        .font(.forgeDynamic(size: 14, weight: .medium))
                                        .foregroundColor(.textPrimary)
                                    Text("\(alarm.snoozeMinutes) minutes")
                                        .font(.forgeDynamic(size: 12))
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
                                        .font(.forgeDynamic(size: 14, weight: .medium))
                                        .foregroundColor(.textPrimary)
                                    Text("Slowly increases over 30 seconds")
                                        .font(.forgeDynamic(size: 12))
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
                                            .font(.forgeDynamic(size: 14, weight: .medium))
                                            .foregroundColor(.textPrimary)
                                        Text("Wake during lightest sleep phase")
                                            .font(.forgeDynamic(size: 12))
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
                                            .font(.forgeDynamic(size: 12, weight: .medium))
                                            .foregroundColor(.textSecondary)
                                        HStack(spacing: 8) {
                                            ForEach([15, 30, 45], id: \.self) { mins in
                                                Button {
                                                    alarm.smartWakeWindow = mins
                                                    UISelectionFeedbackGenerator().selectionChanged()
                                                } label: {
                                                    Text("\(mins) min")
                                                        .font(.forgeDynamic(size: 13, weight: .semibold))
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
                    .font(.forgeDynamic(size: 15, weight: .semibold))
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
                .font(.forgeDynamic(size: 10, weight: .black))
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
                                        .font(.forgeDynamic(size: 13, weight: .semibold))
                                        .foregroundColor(sleepTimer == mins ? .white : .textTertiary)
                                        .padding(.horizontal, 14).padding(.vertical, 8)
                                        .background(sleepTimer == mins ? Color.indigo : Color.surface)
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
                                    .font(.forgeDynamic(size: 13, weight: .semibold))
                                    .foregroundColor(selectedCategory == nil ? .white : .textTertiary)
                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                    .background(selectedCategory == nil ? Color.indigo : Color.surface)
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
                                        .font(.forgeDynamic(size: 13, weight: .semibold))
                                        .foregroundColor(selectedCategory == cat ? .white : .textTertiary)
                                        .padding(.horizontal, 14).padding(.vertical, 8)
                                        .background(selectedCategory == cat ? Color.indigo : Color.surface)
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
                        Image(systemName: "info.circle").font(.forgeDynamic(size: 12))
                        Text("Mix up to 3 sounds at once")
                            .font(.forgeDynamic(size: 12, weight: .medium))
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
                        Image(systemName: item.sound.icon).font(.forgeDynamic(size: 13)).foregroundColor(item.sound.color)
                    }
                    .overlay(Circle().stroke(Color.background, lineWidth: 2))
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(sounds.map { $0.sound.name }.joined(separator: " · "))
                    .font(.forgeDynamic(size: 13, weight: .semibold))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)

                // Animated waveform indicator
                SoundWaveformBadge()
            }

            Spacer()

            Button(action: onMixerTap) {
                Image(systemName: "slider.horizontal.3").font(.forgeDynamic(size: 14)).foregroundColor(Color.indigo)
                    .frame(width: 36, height: 36).background(Color.indigo.opacity(0.12)).clipShape(Circle())
            }
            Button(action: onStop) {
                Image(systemName: "stop.fill").font(.forgeDynamic(size: 14)).foregroundColor(.textTertiary)
                    .frame(width: 36, height: 36).background(Color.surfaceElevated).clipShape(Circle())
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Color.surface)
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.indigo.opacity(0.3), lineWidth: 1))
        .shadow(color: Color.indigo.opacity(0.1), radius: 12, y: 4)
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
                        .fill(Color.indigo.opacity(0.7))
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
                .font(.forgeDynamic(size: 10, weight: .black))
                .foregroundColor(.textTertiary)
                .tracking(2.5)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(Array(activeSounds.enumerated()), id: \.offset) { index, item in
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(item.sound.color.opacity(0.18)).frame(width: 36, height: 36)
                        Image(systemName: item.sound.icon).font(.forgeDynamic(size: 14)).foregroundColor(item.sound.color)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.sound.name).font(.forgeDynamic(size: 13, weight: .semibold)).foregroundColor(.textPrimary)
                        Slider(value: $activeSounds[index].volume, in: 0...1)
                            .tint(item.sound.color)
                    }
                    Button {
                        withAnimation { 
                            _ = activeSounds.remove(at: index)
                        }
                    } label: {
                        Image(systemName: "xmark").font(.forgeDynamic(size: 11, weight: .bold)).foregroundColor(.textMuted)
                            .frame(width: 28, height: 28).background(Color.surfaceElevated).clipShape(Circle())
                    }
                    .accessibilityLabel("Remove sound")
                }
            }
        }
        .padding(16)
        .background(Color.surface)
        .cornerRadius(16)
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.indigo.opacity(0.25), lineWidth: 1)
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
                            .font(.forgeDynamic(size: 22, weight: .medium))
                            .foregroundColor(sound.color)
                    }
                }

                VStack(spacing: 3) {
                    Text(sound.name)
                        .font(.forgeDynamic(size: 13, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Text(sound.category.rawValue)
                        .font(.forgeDynamic(size: 10, weight: .medium))
                        .foregroundColor(sound.color.opacity(0.8))
                }

                if isActive {
                    Text("Playing")
                        .font(.forgeDynamic(size: 10, weight: .bold))
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
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                // Smart Wake
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

                // Volume Ramp
                VolumeRampCard(curve: $volumeRamp)

                // Morning Routine
                MorningRoutineCard(items: $morningRoutine)

                // Wake Word / Greeting
                WakeGreetingCard()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 100)
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
                                .font(.forgeDynamic(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
                            Text("Detects your sleep cycle and wakes you at the optimal moment")
                                .font(.forgeDynamic(size: 12)).foregroundColor(.textTertiary).lineSpacing(3)
                        }
                    }
                    .tint(.steel)

                    if enabled {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Detection window")
                                .font(.forgeDynamic(size: 12, weight: .semibold)).foregroundColor(.textSecondary)
                            HStack(spacing: 10) {
                                ForEach([15, 30, 45], id: \.self) { mins in
                                    Button {
                                        windowMinutes = mins
                                        UISelectionFeedbackGenerator().selectionChanged()
                                    } label: {
                                        VStack(spacing: 4) {
                                            Text("\(mins)")
                                                .font(.forgeDynamic(size: 20, weight: .bold, design: .rounded))
                                                .foregroundColor(windowMinutes == mins ? .white : .textPrimary)
                                            Text("min")
                                                .font(.forgeDynamic(size: 11, weight: .medium))
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
                                    Image(systemName: "alarm.fill").font(.forgeDynamic(size: 12)).foregroundColor(.ember)
                                    Text("Alarm").font(.forgeDynamic(size: 9, weight: .medium)).foregroundColor(.textMuted)
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
        WakeUpSection(icon: "sunrise.fill", title: "Sunrise Simulation", color: Color.amber) {
            VStack(spacing: 16) {
                Toggle(isOn: $enabled) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Gradual light increase")
                            .font(.forgeDynamic(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
                        Text("Mimics a natural sunrise to gently bring you out of sleep")
                            .font(.forgeDynamic(size: 12)).foregroundColor(.textTertiary)
                    }
                }
                .tint(Color.amber)

                if enabled {
                    VStack(spacing: 14) {
                        // Duration
                        HStack {
                            Text("Duration").font(.forgeDynamic(size: 13, weight: .semibold)).foregroundColor(.textSecondary)
                            Spacer()
                            HStack(spacing: 4) {
                                Text("\(duration) min")
                                    .font(.forgeDynamic(size: 14, weight: .bold)).foregroundColor(.textPrimary)
                                Stepper("", value: $duration, in: 5...60, step: 5)
                                    .labelsHidden().tint(Color.amber)
                            }
                        }

                        // Color temperature
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Color Temperature").font(.forgeDynamic(size: 13, weight: .semibold)).foregroundColor(.textSecondary)
                                Spacer()
                                Text(colorTemp < 0.3 ? "2700K Warm" : colorTemp < 0.7 ? "3500K Neutral" : "5000K Cool")
                                    .font(.forgeDynamic(size: 12, weight: .semibold)).foregroundColor(displayColor)
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
                            Text("Start").font(.forgeDynamic(size: 9, weight: .medium)).foregroundColor(.textMuted)
                        }
                        .overlay(alignment: .trailing) {
                            Text("Full").font(.forgeDynamic(size: 9, weight: .medium)).foregroundColor(.textMuted)
                        }
                    }
                    .padding(12).background(Color.amber.opacity(0.06)).cornerRadius(12)
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
                                    .font(.forgeDynamic(size: 15))
                                    .foregroundColor(curve == option ? .ember : .textTertiary)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(option.rawValue).font(.forgeDynamic(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
                                Text(option.description).font(.forgeDynamic(size: 12)).foregroundColor(.textTertiary)
                            }
                            Spacer()
                            if curve == option {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.forgeDynamic(size: 18)).foregroundColor(.ember)
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
                .font(.forgeDynamic(size: 11, weight: .medium)).foregroundColor(.textMuted)
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
                        .font(.forgeDynamic(size: 12, weight: .semibold)).foregroundColor(.textSecondary)
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { editMode.toggle() }
                    } label: {
                        Text(editMode ? "Done" : "Edit")
                            .font(.forgeDynamic(size: 13, weight: .semibold)).foregroundColor(.success)
                    }
                }

                ForEach($items) { $item in
                    HStack(spacing: 12) {
                        // Drag handle (visible in edit mode)
                        if editMode {
                            Image(systemName: "line.3.horizontal")
                                .font(.forgeDynamic(size: 14)).foregroundColor(.textMuted)
                        }

                        Toggle(isOn: $item.isEnabled) {
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle().fill(item.isEnabled ? Color.success.opacity(0.15) : Color.surfaceElevated)
                                        .frame(width: 36, height: 36)
                                    Image(systemName: item.icon)
                                        .font(.forgeDynamic(size: 14))
                                        .foregroundColor(item.isEnabled ? .success : .textMuted)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(.forgeDynamic(size: 14, weight: .medium))
                                        .foregroundColor(item.isEnabled ? .textPrimary : .textTertiary)
                                    Text("\(item.duration) min")
                                        .font(.forgeDynamic(size: 11))
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
        WakeUpSection(icon: "hand.wave.fill", title: "Wake Screen", color: Color.amber) {
            VStack(spacing: 14) {
                // Preview
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(LinearGradient(colors: [Color(hex: "0F172A"), Color(hex: "1E293B")], startPoint: .top, endPoint: .bottom))
                    VStack(spacing: 12) {
                        Text("6:45 AM")
                            .font(.forgeDynamic(size: 36, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Text(greeting)
                            .font(.forgeDynamic(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                        HStack(spacing: 16) {
                            if showSleepScore { Label("Sleep 82", systemImage: "moon.stars.fill").foregroundColor(.steel) }
                            if showWeather   { Label("72°F", systemImage: "sun.max.fill").foregroundColor(Color.amber) }
                            if showWorkout   { Label("Upper Body", systemImage: "dumbbell.fill").foregroundColor(.ember) }
                        }
                        .font(.forgeDynamic(size: 11, weight: .semibold))
                    }
                    .padding(20)
                }
                .frame(height: 140)

                // Greeting field
                TextField("Wake greeting…", text: $greeting)
                    .font(.forgeDynamic(size: 14)).foregroundColor(.textPrimary).tint(Color.amber)
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .background(Color.surfaceElevated).cornerRadius(12)

                // Toggles
                VStack(spacing: 2) {
                    WakeToggle(label: "Show sleep score", value: $showSleepScore, color: .steel)
                    WakeToggle(label: "Show weather",     value: $showWeather,    color: Color.amber)
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
            Text(label).font(.forgeDynamic(size: 14, weight: .medium)).foregroundColor(.textPrimary)
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
                    Image(systemName: icon).font(.forgeDynamic(size: 15, weight: .semibold)).foregroundColor(color)
                }
                Text(title).font(.forgeDynamic(size: 16, weight: .bold)).foregroundColor(.textPrimary)
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
                    Image(systemName: "flame.fill").font(.forgeDynamic(size: 26)).foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(streak)").font(.forgeDynamic(size: 28, weight: .black, design: .rounded)).foregroundColor(.textPrimary)
                        Text("Day Streak").font(.forgeDynamic(size: 16, weight: .medium)).foregroundColor(.textSecondary)
                    }
                    Text(streak >= 7 ? "🔥 On fire!" : "Keep it going!")
                        .font(.forgeDynamic(size: 13)).foregroundColor(.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.forgeDynamic(size: 13, weight: .semibold)).foregroundColor(.textMuted)
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
                        Image(systemName: "sparkles").font(.forgeDynamic(size: 14)).foregroundColor(.steel)
                    }
                    Text("AI Sleep Prediction").font(.forgeDynamic(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.forgeDynamic(size: 12)).foregroundColor(.textMuted)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Optimal Bedtime Tonight")
                        .font(.forgeDynamic(size: 12)).foregroundColor(.textSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("10:15 PM")
                            .font(.forgeDynamic(size: 26, weight: .bold, design: .rounded)).foregroundColor(.steel)
                        Text("for peak recovery")
                            .font(.forgeDynamic(size: 13)).foregroundColor(.textTertiary)
                    }
                }
                Text("Based on workout intensity and your 7-day sleep pattern")
                    .font(.forgeDynamic(size: 12)).foregroundColor(.textMuted).lineLimit(2)
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
