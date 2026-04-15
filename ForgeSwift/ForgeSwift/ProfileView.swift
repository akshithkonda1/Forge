import SwiftUI

// MARK: - Profile Tab (mirrors profile-tab.tsx)

struct ProfileTabView: View {
    @State private var subTab: SubTab = .progress

    enum SubTab: String, CaseIterable { case progress = "Progress"; case settings = "Settings" }

    var body: some View {
        VStack(spacing: 0) {
            // Sticky sub-tab bar
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(SubTab.allCases, id: \.self) { tab in
                        Button(action: { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { subTab = tab } }) {
                            ZStack {
                                if subTab == tab {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.surfaceElevated)
                                }
                                Text(tab.rawValue)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(subTab == tab ? .textPrimary : .textTertiary)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                        }
                    }
                }
                .padding(4)
                .background(Color.surface)
                .cornerRadius(12)
            }
            .padding(.horizontal, 16)
            .padding(.top, 60)
            .padding(.bottom, 8)
            .background(Color.background.opacity(0.9))

            // Content
            if subTab == .progress {
                ProgressPageView()
            } else {
                SettingsPageView()
            }
        }
        .background(Color.background.ignoresSafeArea())
    }
}

// MARK: - Progress Page (mirrors progress-page.tsx)

struct ProgressPageView: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                Text("Progress")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.textPrimary)
                    .padding(.top, 16)

                MonthlySummaryView()
                CalendarHeatmapView()
                PersonalRecordsBoardView()
                WorkoutHistoryListView()
                BehavioralInsightView()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
    }
}

// MARK: - Monthly Summary (mirrors monthly-summary.tsx)

struct MonthlySummaryView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top gradient accent bar
            LinearGradient(colors: [.ember, .emberLight, .ember], startPoint: .leading, endPoint: .trailing)
                .frame(height: 2)

            VStack(alignment: .leading, spacing: 16) {
                Text("THIS MONTH")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textTertiary)
                    .tracking(1.2)

                HStack(spacing: 10) {
                    StatPillCard(value: "18", label: "Workouts")
                    StatPillCard(value: "3",  label: "New PRs")
                    StatPillCard(value: "+22%", label: "Recovery")
                }

                Text("Strong month. You've been consistent with your Mon/Wed/Fri schedule and hit 3 new personal records. Recovery consistency improved 22% — your sleep habits are paying off.")
                    .font(.system(size: 14))
                    .foregroundColor(.textSecondary)
                    .lineSpacing(3)
            }
            .padding(20)
        }
        .background(Color.surface)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.borderColor, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct StatPillCard: View {
    let value: String
    let label: String
    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 20, weight: .bold)).foregroundColor(.textPrimary)
            Text(label).font(.system(size: 11)).foregroundColor(.textSecondary).fixedSize()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.surfaceElevated)
        .cornerRadius(12)
    }
}

// MARK: - Calendar Heatmap (mirrors calendar-heatmap.tsx)

struct CalendarHeatmapView: View {
    @EnvironmentObject var store: AppStore

    // Build date->intensity map from workout history
    var dateMap: [String: Int] {
        var m: [String: Int] = [:]
        for w in store.workoutHistory {
            switch w.intensity {
            case .max, .high:     m[w.date] = 3
            case .moderate:       m[w.date] = 2
            case .low:            m[w.date] = 1
            }
        }
        return m
    }

    struct DayCell: Identifiable {
        var id: String
        var day: Int?
        var date: String
        var level: Int
    }

    var weeks: [[DayCell]] {
        // February 2026 — first day is Sunday (index 0), Mon-based layout
        // Feb 1 2026 is Sunday → start offset = 6 (Mon=0)
        var cells: [DayCell] = []
        let startOffset = 6 // Feb 1 2026 is Sunday
        for _ in 0..<startOffset { cells.append(DayCell(id: UUID().uuidString, day: nil, date: "", level: 0)) }
        for d in 1...28 {
            let dateStr = String(format: "2026-02-%02d", d)
            cells.append(DayCell(id: dateStr, day: d, date: dateStr, level: dateMap[dateStr] ?? 0))
        }
        while cells.count % 7 != 0 { cells.append(DayCell(id: UUID().uuidString, day: nil, date: "", level: 0)) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0+7, cells.count)]) }
    }

    func heatColor(_ level: Int) -> Color {
        switch level {
        case 1: return Color.ember.opacity(0.3)
        case 2: return Color.ember.opacity(0.6)
        case 3: return Color.ember
        default: return Color.surfaceElevated
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("February 2026")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.textPrimary)

            // Day labels
            let dayLabels = ["M","T","W","T","F","S","S"]
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(Array(dayLabels.enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.textTertiary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 20)
                }
            }

            // Calendar cells
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                    ForEach(week) { cell in
                        if let day = cell.day {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(heatColor(cell.level))
                                .aspectRatio(1, contentMode: .fit)
                                .overlay(
                                    Text("\(day)")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(cell.level > 0 ? .white.opacity(0.85) : Color.textTertiary.opacity(0.6))
                                )
                        } else {
                            Color.clear.aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
            }

            // Legend
            HStack(spacing: 12) {
                ForEach([("None", Color.surfaceElevated), ("Light", Color.ember.opacity(0.3)), ("Moderate", Color.ember.opacity(0.6)), ("Intense", Color.ember)], id: \.0) { label, color in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 12, height: 12)
                        Text(label).font(.system(size: 10)).foregroundColor(.textTertiary)
                    }
                }
            }
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.borderColor, lineWidth: 1))
    }
}

// MARK: - Personal Records (mirrors personal-records.tsx)

struct PersonalRecordsBoardView: View {
    @EnvironmentObject var store: AppStore
    @State private var appear = false

    func formatDate(_ str: String) -> String {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        guard let d = fmt.date(from: str) else { return str }
        let out = DateFormatter(); out.dateFormat = "MMM d, yyyy"
        return out.string(from: d)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "trophy.fill").font(.system(size: 18)).foregroundColor(.ember)
                Text("Personal Records").font(.system(size: 18, weight: .semibold)).foregroundColor(.textPrimary)
            }

            VStack(spacing: 10) {
                ForEach(Array(store.personalRecords.enumerated()), id: \.element.id) { idx, pr in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(pr.exercise)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.textPrimary)
                            Text(formatDate(pr.date))
                                .font(.system(size: 11))
                                .foregroundColor(.textTertiary)
                        }
                        Spacer()
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(pr.formattedValue)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.ember)
                            Text(pr.unit)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.textSecondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.surface)
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.borderColor, lineWidth: 1))
                    .opacity(appear ? 1 : 0)
                    .offset(x: appear ? 0 : -12)
                    .animation(.easeOut(duration: 0.35).delay(Double(idx) * 0.07), value: appear)
                }
            }
        }
        .onAppear { withAnimation { appear = true } }
    }
}

// MARK: - Workout History (mirrors workout-history-list.tsx)

struct WorkoutHistoryListView: View {
    @EnvironmentObject var store: AppStore

    func formatDate(_ str: String) -> String {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        guard let d = fmt.date(from: str) else { return str }
        let out = DateFormatter(); out.dateFormat = "EEE, MMM d"
        return out.string(from: d)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Workouts")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.textPrimary)

            VStack(spacing: 10) {
                ForEach(store.workoutHistory) { workout in
                    HStack(spacing: 12) {
                        // Intensity dot
                        Circle()
                            .fill(workout.intensity.color)
                            .frame(width: 10, height: 10)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(workout.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.textPrimary)
                                    .lineLimit(1)
                                Text(workout.type.label)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(workout.type.color)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(workout.type.color.opacity(0.12))
                                    .cornerRadius(100)
                            }
                            HStack(spacing: 10) {
                                Text(formatDate(workout.date))
                                    .font(.system(size: 11)).foregroundColor(.textTertiary)
                                Text("\(workout.duration) min")
                                    .font(.system(size: 11)).foregroundColor(.textSecondary)
                                if workout.volume > 0 {
                                    Text(String(format: "%.1fk lbs", Double(workout.volume) / 1000))
                                        .font(.system(size: 11)).foregroundColor(.textSecondary)
                                }
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .background(Color.surface)
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.borderColor, lineWidth: 1))
                }
            }
        }
    }
}

// MARK: - Behavioral Insight

struct BehavioralInsightView: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 18))
                .foregroundColor(.ember)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 6) {
                Text("Pattern Insight")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Text("Your best workouts happen on Mondays — likely from weekend rest. Your consistency drops on Fridays after high-stress work weeks. Consider keeping Friday sessions shorter and more flexible.")
                    .font(.system(size: 13))
                    .foregroundColor(.textSecondary)
                    .lineSpacing(3)
            }
        }
        .padding(16)
        .background(Color.surface)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.borderColor, lineWidth: 1))
    }
}

// MARK: - Settings Page (mirrors settings-page.tsx)

struct SettingsPageView: View {
    @EnvironmentObject var store: AppStore

    @State private var workoutReminders = true
    @State private var aiInsights = true
    @State private var recoveryAlerts = true
    @State private var weeklySummary = false

    let dayLabels = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]

    var scheduleDays: String {
        store.userProfile.weeklySchedule.map { dayLabels[$0] }.joined(separator: " / ")
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Settings")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.textPrimary)
                    .padding(.bottom, 24)
                    .padding(.top, 16)

                // Profile card
                profileCard

                // AI Trainer
                sectionHeader("AI Trainer")
                SectionCard {
                    SettingsRow(icon: "person.fill", iconColor: .ember, label: "Coaching Style",
                                trailingText: store.userProfile.coachingStyle.label)
                    Divider().background(Color.borderColor)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(store.userProfile.coachingStyle.description)
                            .font(.system(size: 12))
                            .foregroundColor(.textTertiary)
                            .lineSpacing(2)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                        Divider().background(Color.borderColor)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Training Goals")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.textPrimary)
                            FlowLayout(spacing: 8) {
                                ForEach(store.userProfile.fitnessGoals) { goal in
                                    Text(goal.label)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.ember)
                                        .padding(.horizontal, 12).padding(.vertical, 5)
                                        .background(Color.ember.opacity(0.12))
                                        .cornerRadius(100)
                                }
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                    }
                }

                // Connected Devices
                sectionHeader("Connected Devices")
                SectionCard {
                    ForEach(Array(store.userProfile.connectedDevices.enumerated()), id: \.element) { idx, device in
                        if idx > 0 { Divider().background(Color.borderColor) }
                        SettingsRow(icon: "applewatch", iconColor: .steel, label: device,
                                    trailing: AnyView(
                                        HStack(spacing: 5) {
                                            Circle().fill(Color.success).frame(width: 8, height: 8)
                                            Text("Connected").font(.system(size: 12)).foregroundColor(.textSecondary)
                                        }
                                    ))
                    }
                    Divider().background(Color.borderColor)
                    Button(action: {}) {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle().stroke(Color.borderLight, style: StrokeStyle(lineWidth: 1, dash: [4])).frame(width: 32, height: 32)
                                Image(systemName: "plus").font(.system(size: 13)).foregroundColor(.textTertiary)
                            }
                            Text("Add Device").font(.system(size: 14, weight: .medium)).foregroundColor(.ember)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // Workout Preferences
                sectionHeader("Workout Preferences")
                SectionCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Preferred Types").font(.system(size: 14, weight: .medium)).foregroundColor(.textPrimary)
                        FlowLayout(spacing: 8) {
                            ForEach(store.userProfile.preferredWorkouts) { type in
                                Text(type.label)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.textSecondary)
                                    .padding(.horizontal, 12).padding(.vertical, 5)
                                    .background(Color.surfaceElevated)
                                    .cornerRadius(100)
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    Divider().background(Color.borderColor)
                    SettingsRow(icon: "dumbbell.fill", iconColor: .ember, label: "Training Schedule", trailingText: scheduleDays)
                    Divider().background(Color.borderColor)
                    SettingsRow(icon: nil, iconColor: nil, label: "Equipment", trailingText: "Commercial Gym")
                }

                // Notifications
                sectionHeader("Notifications")
                SectionCard {
                    SettingsRow(icon: "bell.fill", iconColor: .ember, label: "Workout Reminders",
                                trailing: AnyView(ForgeToggle(isOn: $workoutReminders)))
                    Divider().background(Color.borderColor)
                    SettingsRow(icon: "bell.fill", iconColor: .steel, label: "AI Insights",
                                trailing: AnyView(ForgeToggle(isOn: $aiInsights)))
                    Divider().background(Color.borderColor)
                    SettingsRow(icon: "bell.fill", iconColor: .success, label: "Recovery Alerts",
                                trailing: AnyView(ForgeToggle(isOn: $recoveryAlerts)))
                    Divider().background(Color.borderColor)
                    SettingsRow(icon: "bell.fill", iconColor: .textSecondary, label: "Weekly Summary",
                                trailing: AnyView(ForgeToggle(isOn: $weeklySummary)))
                }

                // More
                sectionHeader("More")
                SectionCard {
                    SettingsRow(icon: "lock.shield.fill", iconColor: .textSecondary, label: "Data & Privacy", showChevron: true)
                    Divider().background(Color.borderColor)
                    SettingsRow(icon: "creditcard.fill", iconColor: .textSecondary, label: "Subscription", showChevron: true)
                    Divider().background(Color.borderColor)
                    SettingsRow(icon: "questionmark.circle.fill", iconColor: .textSecondary, label: "Help & Support", showChevron: true)
                    Divider().background(Color.borderColor)
                    SettingsRow(icon: "info.circle.fill", iconColor: .textSecondary, label: "About Forge", showChevron: true)
                }

                // Log Out
                Button(action: {}) {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.portrait.and.arrow.right").font(.system(size: 16))
                        Text("Log Out").font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.danger)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.surface)
                    .cornerRadius(14)
                }
                .padding(.top, 24)
                .padding(.bottom, 32)
            }
            .padding(.horizontal, 16)
        }
    }

    var profileCard: some View {
        VStack(spacing: 16) {
            // Avatar
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.ember, .emberLight], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 80, height: 80)
                Text(store.userProfile.initials)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
            }

            // Name + Edit
            HStack(spacing: 8) {
                Text(store.userProfile.name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.textPrimary)
                Button("Edit") {}
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.ember)
            }

            // Experience + member since
            HStack(spacing: 12) {
                Text(store.userProfile.experienceLevel.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.ember)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Color.ember.opacity(0.12))
                    .cornerRadius(100)
                Text("Member since Jan 2026")
                    .font(.system(size: 12))
                    .foregroundColor(.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color.surface)
        .cornerRadius(14)
        .padding(.bottom, 8)
    }

    func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.textTertiary)
            .tracking(1)
            .padding(.top, 24)
            .padding(.bottom, 8)
    }
}

// MARK: - Settings sub-components

struct SectionCard<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(spacing: 0) { content() }
            .background(Color.surface)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.borderColor, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct SettingsRow: View {
    var icon: String?
    var iconColor: Color?
    var label: String
    var trailingText: String? = nil
    var trailing: AnyView? = nil
    var showChevron: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(iconColor ?? .textSecondary)
                    .frame(width: 20)
            }
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.textPrimary)
            Spacer()
            if let t = trailingText {
                Text(t)
                    .font(.system(size: 13))
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 160, alignment: .trailing)
            }
            if let t = trailing { t }
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.textMuted)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct ForgeToggle: View {
    @Binding var isOn: Bool
    var body: some View {
        Button(action: { withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { isOn.toggle() } }) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? Color.ember : Color.borderLight)
                    .frame(width: 48, height: 28)
                Circle()
                    .fill(Color.white)
                    .frame(width: 22, height: 22)
                    .shadow(color: .black.opacity(0.2), radius: 2)
                    .padding(3)
            }
        }
        .buttonStyle(.plain)
    }
}
