import SwiftUI

// MARK: - Profile View (Tab Container)

struct ProfileView: View {
    @State private var subTab: SubTab = .progress

    enum SubTab: String, CaseIterable {
        case progress = "Progress"
        case settings = "Settings"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Sub-tab bar
            HStack(spacing: 0) {
                ForEach(SubTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.spring(response: 0.3)) { subTab = tab }
                    } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(subTab == tab ? .white : .textTertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(subTab == tab ? Color.forgeSurfaceElevated : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(Color.forgeSurface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16)
            .padding(.top, 48)

            // Content
            ScrollView {
                switch subTab {
                case .progress: ProgressContent()
                case .settings: SettingsContent()
                }
            }
            .padding(.bottom, 100)
        }
        .background(Color.forgeBackground)
    }
}

// MARK: - Progress Content

struct ProgressContent: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(spacing: 20) {
            Text("Progress")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            MonthlySummary()
            CalendarHeatmap()
            PersonalRecordsBoard()
            WorkoutHistoryList()

            CoachingBadge(
                message: "You train most consistently on Mon/Wed/Fri mornings. When you skip, it's usually Fridays after high-stress weeks. Consider a lighter Friday session as a fallback."
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }
}

// MARK: - Monthly Summary

struct MonthlySummary: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Accent bar
            Rectangle()
                .fill(LinearGradient.emberGradient)
                .frame(height: 2)

            SectionLabel(text: "This Month")
                .padding(.horizontal, 16)

            HStack(spacing: 8) {
                statPill("18", "Workouts")
                statPill("3", "New PRs")
                statPill("+22%", "Recovery")
            }
            .padding(.horizontal, 16)

            Text("Strong month. You've been consistent with your Mon/Wed/Fri schedule and hit 3 new personal records. Recovery consistency improved 22% — your sleep habits are paying off.")
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
                .lineSpacing(3)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .forgeBorderedCard()
    }

    private func statPill(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.forgeSurfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Calendar Heatmap

struct CalendarHeatmap: View {
    @Environment(AppStore.self) private var store

    private let dayLabels = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        let dateMap = buildDateMap()

        VStack(alignment: .leading, spacing: 12) {
            Text("February 2026")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)

            // Day headers
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(dayLabels.indices, id: \.self) { i in
                    Text(dayLabels[i])
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.textTertiary)
                        .frame(height: 20)
                }
            }

            // Calendar days
            let weeks = buildWeeks(dateMap: dateMap)
            ForEach(weeks.indices, id: \.self) { wi in
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                    ForEach(weeks[wi].indices, id: \.self) { ci in
                        let cell = weeks[wi][ci]
                        if let day = cell.day {
                            let isToday = cell.date == "2026-02-11"
                            RoundedRectangle(cornerRadius: 4)
                                .fill(heatColor(cell.level))
                                .aspectRatio(1, contentMode: .fit)
                                .overlay(
                                    Text("\(day)")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(cell.level > 0 ? .white.opacity(0.8) : .textTertiary.opacity(0.6))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(isToday ? Color.white.opacity(0.4) : .clear, lineWidth: 1)
                                )
                        } else {
                            Color.clear.aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
            }

            // Legend
            HStack(spacing: 12) {
                legendItem("None", Color.forgeSurfaceElevated)
                legendItem("Light", Color.ember.opacity(0.3))
                legendItem("Moderate", Color.ember.opacity(0.6))
                legendItem("Intense", Color.ember)
            }
        }
        .padding(16)
        .forgeBorderedCard()
    }

    private func legendItem(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 12, height: 12)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.textTertiary)
        }
    }

    private func heatColor(_ level: Int) -> Color {
        switch level {
        case 1: return .ember.opacity(0.3)
        case 2: return .ember.opacity(0.6)
        case 3: return .ember
        default: return Color.forgeSurfaceElevated
        }
    }

    private struct DayCell {
        var day: Int?
        var date: String
        var level: Int
    }

    private func buildDateMap() -> [String: Int] {
        var map: [String: Int] = [:]
        for w in store.workoutHistory {
            let level: Int
            switch w.intensity {
            case "max", "high": level = 3
            case "moderate": level = 2
            default: level = 1
            }
            map[w.date] = level
        }
        return map
    }

    private func buildWeeks(dateMap: [String: Int]) -> [[DayCell]] {
        let daysInMonth = 28
        var startDow = Calendar.current.component(.weekday, from: DateComponents(calendar: .current, year: 2026, month: 2, day: 1).date!) - 2
        if startDow < 0 { startDow = 6 }

        var allCells: [DayCell] = []
        for _ in 0..<startDow {
            allCells.append(DayCell(day: nil, date: "", level: 0))
        }
        for d in 1...daysInMonth {
            let dateStr = String(format: "2026-02-%02d", d)
            allCells.append(DayCell(day: d, date: dateStr, level: dateMap[dateStr] ?? 0))
        }
        while allCells.count % 7 != 0 {
            allCells.append(DayCell(day: nil, date: "", level: 0))
        }

        return stride(from: 0, to: allCells.count, by: 7).map { Array(allCells[$0..<min($0 + 7, allCells.count)]) }
    }
}

// MARK: - Personal Records

struct PersonalRecordsBoard: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "trophy.fill")
                    .foregroundColor(.ember)
                Text("Personal Records")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
            }

            ForEach(store.personalRecords) { pr in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pr.exercise)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        Text(formatDate(pr.date))
                            .font(.system(size: 11))
                            .foregroundColor(.textTertiary)
                    }

                    Spacer()

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(formatPRValue(pr.value, pr.unit))
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.ember)
                        Text(pr.unit)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.textSecondary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .forgeBorderedCard()
            }
        }
    }

    private func formatDate(_ dateStr: String) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        guard let date = fmt.date(from: dateStr) else { return dateStr }
        fmt.dateFormat = "MMM d, yyyy"
        return fmt.string(from: date)
    }

    private func formatPRValue(_ value: Double, _ unit: String) -> String {
        if unit == "min" {
            let min = Int(value)
            let sec = Int((value - Double(min)) * 100)
            return String(format: "%d:%02d", min, sec)
        }
        return value.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(value))" : String(format: "%.1f", value)
    }
}

// MARK: - Workout History List

struct WorkoutHistoryList: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Workouts")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)

            ForEach(store.workoutHistory) { w in
                HStack(spacing: 10) {
                    Circle()
                        .fill(intensityColor(w.intensity))
                        .frame(width: 8, height: 8)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(w.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)

                            Text(w.type.label)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(typeColor(w.type))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(typeColor(w.type).opacity(0.1))
                                .clipShape(Capsule())
                        }

                        HStack(spacing: 10) {
                            Text(formatDate(w.date))
                                .font(.system(size: 11))
                                .foregroundColor(.textTertiary)
                            Text("\(w.duration) min")
                                .font(.system(size: 11))
                                .foregroundColor(.textSecondary)
                            if w.volume > 0 {
                                Text(String(format: "%.1fk lbs", Double(w.volume) / 1000))
                                    .font(.system(size: 11))
                                    .foregroundColor(.textSecondary)
                            }
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .forgeBorderedCard()
            }
        }
    }

    private func formatDate(_ dateStr: String) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        guard let date = fmt.date(from: dateStr) else { return dateStr }
        fmt.dateFormat = "EEE, MMM d"
        return fmt.string(from: date)
    }

    private func typeColor(_ type: WorkoutType) -> Color {
        switch type {
        case .strength: return .ember
        case .hiit: return .forgeDanger
        case .cardio: return .steel
        case .yoga: return .forgeSuccess
        case .mobility: return Color(hex: "A855F7")
        default: return .textSecondary
        }
    }
}

// MARK: - Settings Content

struct SettingsContent: View {
    @Environment(AppStore.self) private var store
    @State private var workoutReminders = true
    @State private var aiInsights = true
    @State private var recoveryAlerts = true
    @State private var weeklySummary = false

    private var initials: String {
        store.userProfile.name.split(separator: " ").compactMap(\.first).map(String.init).prefix(2).joined().uppercased()
    }

    private let dayLabels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        VStack(spacing: 0) {
            Text("Settings")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 16)

            // Profile card
            VStack(spacing: 12) {
                Circle()
                    .fill(LinearGradient.emberGradient)
                    .frame(width: 72, height: 72)
                    .overlay(
                        Text(initials)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                    )

                HStack(spacing: 8) {
                    Text(store.userProfile.name)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    Text("Edit")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.ember)
                }

                HStack(spacing: 10) {
                    Text(store.userProfile.experienceLevel.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.ember)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.ember.opacity(0.15))
                        .clipShape(Capsule())

                    Text("Member since Jan 2026")
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                }
            }
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
            .forgeCard()
            .padding(.horizontal, 16)
            .padding(.top, 16)

            // AI Trainer
            settingsSection("AI Trainer") {
                settingsRow(icon: "person.fill", iconColor: .ember, label: "Coaching Style", value: store.userProfile.coachingStyle.label)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Training Goals")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                    HStack(spacing: 6) {
                        ForEach(store.userProfile.fitnessGoals) { goal in
                            Text(goal.label)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.ember)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.ember.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            // Devices
            settingsSection("Connected Devices") {
                ForEach(store.userProfile.connectedDevices, id: \.self) { device in
                    settingsRow(icon: "applewatch", iconColor: .steel, label: device, value: "Connected")
                }
            }

            // Notifications
            settingsSection("Notifications") {
                toggleRow("Workout Reminders", isOn: $workoutReminders)
                toggleRow("AI Insights", isOn: $aiInsights)
                toggleRow("Recovery Alerts", isOn: $recoveryAlerts)
                toggleRow("Weekly Summary", isOn: $weeklySummary)
            }

            // Log Out
            Button { } label: {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 16))
                    Text("Log Out")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.forgeDanger)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .forgeCard()
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 16)

            Spacer(minLength: 32)
        }
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundColor(.textTertiary)
                .padding(.horizontal, 16)
                .padding(.top, 24)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                content()
            }
            .forgeCard()
            .padding(.horizontal, 16)
        }
    }

    private func settingsRow(icon: String, iconColor: Color, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(iconColor)

            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)

            Spacer()

            Text(value)
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
                .lineLimit(1)

            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundColor(.textMuted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func toggleRow(_ label: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
        }
        .tint(.ember)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
