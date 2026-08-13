import SwiftUI
import PhotosUI
import UIKit
import ForgeCore

// MARK: - Profile Tab (mirrors profile-tab.tsx)

struct ProfileTabView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        // Progress + Lifestyle live on bottom tabs; Profile is account + settings.
        SettingsPageView()
            .forgeScreenBackground(accent: .steel)
            .onAppear {
                // Legacy deep links: Progress / Lifestyle sub-tabs now map to root tabs.
                if let pending = store.pendingProfileSubTab {
                    switch pending.lowercased() {
                    case "progress":
                        store.activeTab = .progress
                    case "lifestyle":
                        store.activeTab = .lifestyle
                    default:
                        break
                    }
                    store.pendingProfileSubTab = nil
                }
            }
    }
}

// MARK: - Progress Page (mirrors progress-page.tsx)

struct ProgressPageView: View {
    @EnvironmentObject var store: AppStore
    @State private var showShareSheet = false
    @State private var selectedTimeRange: TimeRange = .month

    enum TimeRange: String, CaseIterable {
        case week = "Week"
        case month = "Month"
        case year = "Year"
    }

    // Skeletons only on first load — during pull-to-refresh existing content stays put.
    private var isInitialLoading: Bool {
        store.dataLoadState == .loading && store.workoutHistory.isEmpty && store.progressSummary == nil
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                ForgePageHeader(
                    title: "Progress",
                    subtitle: "History, PRs, streaks — your training story",
                    accent: Color(hex: "3B82F6")
                ) {
                    Button(action: { showShareSheet = true }) {
                        ZStack {
                            Circle()
                                .fill(Color.surfaceElevated)
                                .frame(width: 40, height: 40)
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.ember)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Share progress")
                }
                .padding(.top, 48)

                if isInitialLoading {
                    ForgeSkeletonBlock(height: 88, cornerRadius: 16)
                    ForgeSkeletonBlock(height: 160, cornerRadius: 16)
                    ForgeSkeletonBlock(height: 220, cornerRadius: 16)
                    ForgeSkeletonBlock(height: 160, cornerRadius: 16)
                } else if store.workoutHistory.isEmpty && store.progressSummary == nil && store.personalRecords.isEmpty {
                    ForgeEmptyStateCard(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "No sessions yet",
                        message: "Complete a workout and your history, PRs, and streaks will show up here.",
                        accent: .ember,
                        cta: "Start a session",
                        action: { store.openDestination(.workout) }
                    )
                } else {
                    TimeRangePicker(selection: $selectedTimeRange)
                    QuickStatsOverviewView(timeRange: selectedTimeRange)
                    MonthlySummaryView()
                    CalendarHeatmapView()
                    PersonalRecordsBoardView()
                    WorkoutHistoryListView()
                    BehavioralInsightView()
                    StreaksAndMilestonesView()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .forgeScreenBackground(accent: Color(hex: "3B82F6"))
        .refreshable {
            await store.loadDashboardFromAPI()
        }
        .sheet(isPresented: $showShareSheet) {
            ShareProgressView()
        }
    }
}

// MARK: - Monthly Summary (mirrors monthly-summary.tsx)

struct MonthlySummaryView: View {
    @EnvironmentObject var store: AppStore
    @State private var appeared = false

    private var monthLabel: String {
        Date().formatted(.dateTime.month(.wide))
    }

    private var workoutsCompleted: String {
        String(store.progressSummary?.workoutsCompleted ?? store.workoutHistory.count)
    }

    private var newPRs: String {
        String(store.progressSummary?.newPRCount ?? store.personalRecords.count)
    }

    private var recoveryDelta: String {
        guard let delta = store.progressSummary?.recoveryDelta else { return "—" }
        let sign = delta > 0 ? "+" : ""
        return "\(sign)\(Int(delta.rounded()))%"
    }

    private var summaryText: String {
        store.progressSummary?.summary
            ?? "Keep training consistently and Forge will surface your monthly progress here."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top gradient accent bar with shimmer
            ZStack {
                LinearGradient(colors: [.ember, .emberLight, .ember], startPoint: .leading, endPoint: .trailing)
                    .frame(height: 3)

                LinearGradient(colors: [.clear, .white.opacity(0.3), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(height: 3)
                    .offset(x: appeared ? 400 : -400)
                    .animation(.linear(duration: 2).repeatForever(autoreverses: false), value: appeared)
            }
            .clipShape(RoundedRectangle(cornerRadius: 1.5))

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("THIS MONTH")
                        .font(.system(size: 11, weight: .black))
                        .foregroundColor(.ember)
                        .tracking(2)

                    Spacer()

                    // Month indicator
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 10))
                        Text(monthLabel)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.textTertiary)
                }

                HStack(spacing: 10) {
                    StatPillCard(value: workoutsCompleted, label: "Workouts", appeared: appeared, delay: 0.1)
                    StatPillCard(value: newPRs, label: "New PRs", appeared: appeared, delay: 0.15)
                    StatPillCard(value: recoveryDelta, label: "Recovery", appeared: appeared, delay: 0.2)
                }

                Text(summaryText)
                    .font(.system(size: 14))
                    .foregroundColor(.textSecondary)
                    .lineSpacing(5)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 8)
                    .animation(.easeOut(duration: 0.5).delay(0.3), value: appeared)
            }
            .padding(20)
        }
        .background(Color.surface)
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.ember.opacity(0.15), lineWidth: 1))
        .shadow(color: Color.ember.opacity(0.08), radius: 20, y: 8)
        .onAppear { appeared = true }
    }
}

struct StatPillCard: View {
    let value: String
    let label: String
    var appeared: Bool = false
    var delay: Double = 0

    var body: some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundColor(.textPrimary)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.textSecondary)
                .fixedSize()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            ZStack {
                Color.surfaceElevated
                LinearGradient(
                    colors: [Color.ember.opacity(0.03), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        )
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.borderColor.opacity(0.5), lineWidth: 1))
        .scaleEffect(appeared ? 1 : 0.9)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(delay), value: appeared)
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

    private var displayMonth: Date {
        Date()
    }

    var monthTitle: String {
        ForgeDates.monthYearTitle(for: displayMonth)
    }

    var weeks: [[DayCell]] {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: displayMonth)
        guard let firstOfMonth = calendar.date(from: components),
              let dayRange = calendar.range(of: .day, in: .month, for: firstOfMonth) else {
            return []
        }

        var cells: [DayCell] = []
        let startOffset = ForgeDates.mondayBasedStartOffset(for: firstOfMonth, calendar: calendar)
        for index in 0..<startOffset {
            cells.append(DayCell(id: "lead-\(index)", day: nil, date: "", level: 0))
        }
        for day in dayRange {
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth) else { continue }
            let dateStr = ForgeDates.yyyyMMdd(from: date)
            cells.append(DayCell(id: dateStr, day: day, date: dateStr, level: dateMap[dateStr] ?? 0))
        }
        while cells.count % 7 != 0 {
            cells.append(DayCell(id: "trail-\(cells.count)", day: nil, date: "", level: 0))
        }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }
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
            Text(monthTitle)
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
    @State private var showAllPRs = false

    private static let collapsedCount = 3

    private var visibleRecords: [PersonalRecord] {
        showAllPRs ? store.personalRecords : Array(store.personalRecords.prefix(Self.collapsedCount))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "trophy.fill").font(.system(size: 18)).foregroundColor(.ember)
                Text("Personal Records").font(.system(size: 18, weight: .semibold)).foregroundColor(.textPrimary)
                Spacer()
                if store.personalRecords.count > Self.collapsedCount {
                    Button(action: { withAnimation(.spring()) { showAllPRs.toggle() } }) {
                        Text(showAllPRs ? "Show Less" : "View All (\(store.personalRecords.count))")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.ember)
                    }
                }
            }

            if store.personalRecords.isEmpty {
                ForgeEmptyState(
                    icon: "trophy",
                    title: "No records yet",
                    message: "Finish a few workouts and your personal bests will show up here."
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(visibleRecords.enumerated()), id: \.element.id) { idx, pr in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(pr.exercise)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.textPrimary)
                                Text(ForgeDates.displayDate(pr.date))
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
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(pr.exercise), \(pr.formattedValue) \(pr.unit), set \(ForgeDates.displayDate(pr.date))")
                    }
                }
            }
        }
        .onAppear { withAnimation { appear = true } }
    }
}

// MARK: - Workout History (mirrors workout-history-list.tsx)

struct WorkoutHistoryListView: View {
    @EnvironmentObject var store: AppStore
    @State private var searchText = ""
    @State private var selectedFilterType: WorkoutType? = nil
    @State private var showFilters = false
    @State private var showAllWorkouts = false
    @State private var selectedWorkout: WorkoutHistory?

    private static let collapsedCount = 6

    private var isFiltering: Bool {
        selectedFilterType != nil || !searchText.isEmpty
    }

    var filteredWorkouts: [WorkoutHistory] {
        var workouts = store.workoutHistory

        if let filterType = selectedFilterType {
            workouts = workouts.filter { $0.type == filterType }
        }

        if !searchText.isEmpty {
            workouts = workouts.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }

        return workouts
    }

    // Cap the list when browsing; searching or filtering always shows every match.
    private var visibleWorkouts: [WorkoutHistory] {
        if isFiltering || showAllWorkouts { return filteredWorkouts }
        return Array(filteredWorkouts.prefix(Self.collapsedCount))
    }

    private func shareText(for workout: WorkoutHistory) -> String {
        var parts = ["\(workout.name) — \(ForgeDates.displayWeekdayDate(workout.date))",
                     "\(workout.duration) min \(workout.type.label.lowercased())"]
        if workout.volume > 0 {
            parts.append(String(format: "%.1fk lbs total volume", Double(workout.volume) / 1000))
        }
        parts.append("Logged with Forge 🔥")
        return parts.joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Workouts")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Spacer()
                Button(action: { withAnimation(.spring()) { showFilters.toggle() } }) {
                    Image(systemName: showFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .font(.system(size: 20))
                        .foregroundColor(.ember)
                }
                .accessibilityLabel(showFilters ? "Hide workout filters" : "Show workout filters")
            }

            // Search and filter
            if showFilters {
                VStack(spacing: 12) {
                    // Search bar
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14))
                            .foregroundColor(.textTertiary)
                        TextField("Search workouts...", text: $searchText)
                            .font(.system(size: 14))
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.textTertiary)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color.surfaceElevated)
                    .cornerRadius(10)

                    // Type filters
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            FilterChip(title: "All", isSelected: selectedFilterType == nil) {
                                selectedFilterType = nil
                            }
                            ForEach(Array(WorkoutType.allCases), id: \.self) { (type: WorkoutType) in
                                FilterChip(title: type.label, isSelected: selectedFilterType == type) {
                                    selectedFilterType = type
                                }
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            VStack(spacing: 10) {
                ForEach(visibleWorkouts) { workout in
                    // Only the header row toggles expansion — the expanded section holds
                    // its own ShareLink, and nesting buttons would fire both on tap.
                    VStack(spacing: 0) {
                        Button(action: {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                selectedWorkout = selectedWorkout?.id == workout.id ? nil : workout
                            }
                        }) {
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
                                        Text(ForgeDates.displayWeekdayDate(workout.date))
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
                                Image(systemName: selectedWorkout?.id == workout.id ? "chevron.up.circle.fill" : "chevron.right.circle")
                                    .font(.system(size: 20))
                                    .foregroundColor(selectedWorkout?.id == workout.id ? .ember : .textTertiary)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        // Expanded details
                        if selectedWorkout?.id == workout.id {
                            VStack(spacing: 0) {
                                Divider().background(Color.borderColor)

                                VStack(alignment: .leading, spacing: 12) {
                                    HStack(spacing: 20) {
                                        StatBadge(label: "Duration", value: "\(workout.duration)", unit: "min")
                                        StatBadge(
                                            label: "Volume",
                                            value: workout.volume > 0 ? String(format: "%.1fk", Double(workout.volume) / 1000) : "—",
                                            unit: workout.volume > 0 ? "lbs" : ""
                                        )
                                        StatBadge(label: "Intensity", value: workout.intensity.label, unit: "")
                                    }

                                    ShareLink(item: shareText(for: workout)) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "square.and.arrow.up")
                                                .font(.system(size: 12))
                                            Text("Share Workout")
                                                .font(.system(size: 13, weight: .medium))
                                        }
                                        .foregroundColor(.ember)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(Color.ember.opacity(0.1))
                                        .cornerRadius(8)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .background(Color.surface)
                    .cornerRadius(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(selectedWorkout?.id == workout.id ? Color.ember : Color.borderColor,
                                   lineWidth: selectedWorkout?.id == workout.id ? 2 : 1)
                    )
                }
            }

            if !isFiltering && filteredWorkouts.count > Self.collapsedCount {
                Button(action: { withAnimation(.spring()) { showAllWorkouts.toggle() } }) {
                    Text(showAllWorkouts ? "Show Less" : "View All (\(filteredWorkouts.count))")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.ember)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.surface)
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.borderColor, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            if filteredWorkouts.isEmpty {
                if store.workoutHistory.isEmpty {
                    ForgeEmptyState(
                        icon: "figure.strengthtraining.traditional",
                        title: "No workouts yet",
                        message: "Your completed workouts will appear here."
                    )
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundColor(.textTertiary)
                        Text("No workouts match your search")
                            .font(.system(size: 14))
                            .foregroundColor(.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            }
        }
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isSelected ? .white : .textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? Color.ember : Color.surfaceElevated)
                .cornerRadius(100)
        }
        .buttonStyle(.plain)
    }
}

struct StatBadge: View {
    let label: String
    let value: String
    let unit: String

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.textPrimary)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 10))
                        .foregroundColor(.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.surfaceElevated)
        .cornerRadius(8)
    }
}

// MARK: - Behavioral Insight

struct BehavioralInsightView: View {
    @EnvironmentObject var store: AppStore

    private var insightTitle: String {
        store.primaryTrainingInsight?.title ?? "Pattern Insight"
    }

    private var insightBody: String {
        if let insight = store.primaryTrainingInsight {
            return "\(insight.observation) \(insight.recommendation)"
        }
        if let summary = store.progressSummary?.summary, !summary.isEmpty {
            return summary
        }
        return "Complete a few workouts and Forge will start surfacing training patterns here."
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 18))
                .foregroundColor(.ember)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 6) {
                Text(insightTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Text(insightBody)
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

private enum ForgeLegalConfig {
    static let privacyPolicyURLString = ""
    static var privacyPolicyURL: URL? { URL(string: privacyPolicyURLString) }
}

struct SettingsPageView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.openURL) private var openURL

    @State private var showDevicesSheet = false
    @State private var catalogRevision = 0
    @State private var showProfileEditor = false
    @State private var showCoachingStylePicker = false
    @State private var showTrainingThemePicker = false
    @State private var showPrivacyPolicyURLAlert = false
    @State private var showTermsSheet = false
    @State private var showMyChartPlaceholderSheet = false
    @State private var showDataPermissions = false
    @State private var showGoalsEditor = false
    @State private var showScheduleEditor = false
    @State private var showEquipmentPicker = false
    @State private var showWorkoutsEditor = false
    @State private var showBackendURL = false
    @State private var showShareSheet = false
    @State private var showAbout = false
    @State private var showLocalPrivacy = false
    @State private var confirmSignOut = false
    @State private var backendURLDraft = AriaService.shared.baseURL.absoluteString
    @State private var briefSettings: BriefNotificationSettings
    @ObservedObject private var weeklyReview = WeeklyAriaReviewStore.shared

    let dayLabels = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]

    init() {
        _briefSettings = State(initialValue: ForgePersistence.loadBriefNotificationSettings())
    }

    var scheduleDays: String {
        store.userProfile.weeklySchedule.map { dayLabels[$0] }.joined(separator: " / ")
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // World-class identity hero — avatar, signature stats, readiness, actions.
                ProfileHeroHeader(
                    onEdit: { showProfileEditor = true },
                    onShare: { showShareSheet = true }
                )
                .padding(.top, 8)
                .padding(.bottom, FDS.Spacing.sm)

                // Every primary surface in one place — guarantees no orphaned pages.
                sectionHeader("Explore Forge")
                ForgeExploreDestinationsGrid()
                    .padding(.bottom, FDS.Spacing.md)

                // AI Trainer
                sectionHeader("AI Trainer")
                SectionCard {
                    Button(action: { showCoachingStylePicker = true }) {
                        SettingsRow(icon: "person.fill", iconColor: .ember, label: "Coaching Style",
                                    trailingText: store.userProfile.coachingStyle.label, showChevron: true)
                    }
                    .buttonStyle(.plain)

                    Divider().background(Color.borderColor)

                    Button(action: { showTrainingThemePicker = true }) {
                        SettingsRow(
                            icon: store.userProfile.trainingTheme.icon,
                            iconColor: Color(hex: store.userProfile.trainingTheme.accentHex),
                            label: "Training Theme",
                            trailingText: store.userProfile.trainingTheme.label,
                            showChevron: true
                        )
                    }
                    .buttonStyle(.plain)

                    Divider().background(Color.borderColor)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(store.userProfile.coachingStyle.description)
                            .font(.system(size: 12))
                            .foregroundColor(.textTertiary)
                            .lineSpacing(2)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                        Text(store.userProfile.trainingTheme.tagline)
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: store.userProfile.trainingTheme.accentHex).opacity(0.9))
                            .lineSpacing(2)
                            .padding(.horizontal, 16).padding(.bottom, 10)
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
                    Color.clear.frame(width: 0, height: 0).hidden().id(catalogRevision)
                    if store.userProfile.connectedDevices.isEmpty {
                        HStack(spacing: 10) {
                            Image(systemName: "link.badge.plus")
                                .font(.system(size: 16))
                                .foregroundColor(.textTertiary)
                            Text("No devices yet. Browse the library — LARQ, Oura, Garmin, Watch and more.")
                                .font(.system(size: 14))
                                .foregroundColor(.textSecondary)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                    } else {
                        ForEach(Array(HealthDeviceCatalog.migrateStoredIDs(store.userProfile.connectedDevices).enumerated()), id: \.element) { idx, raw in
                            if idx > 0 { Divider().background(Color.borderColor) }
                            let device = HealthDeviceCatalog.device(matching: raw)
                            Button { showDevicesSheet = true } label: {
                                SettingsRow(
                                    icon: device?.symbolName ?? "sensor.tag.radiowaves.forward",
                                    iconColor: .steel,
                                    label: device?.name ?? raw,
                                    showChevron: true
                                ) {
                                    if let device {
                                        DeviceProductImage(device: device, size: 28, cornerRadius: 6)
                                    }
                                    HStack(spacing: 5) {
                                        Circle().fill(Color.success).frame(width: 8, height: 8)
                                        Text(device?.writesToAppleHealth == true ? "Health" : "iOS")
                                            .font(.system(size: 12))
                                            .foregroundColor(.textSecondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Divider().background(Color.borderColor)
                    Button { showDevicesSheet = true } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle().stroke(Color.borderLight, style: StrokeStyle(lineWidth: 1, dash: [4])).frame(width: 32, height: 32)
                                Image(systemName: "plus").font(.system(size: 13)).foregroundColor(.textTertiary)
                            }
                            Text("Browse compatible devices")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.ember)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // Account
                sectionHeader("Account")
                SectionCard {
                    SettingsRow(
                        icon: "person.crop.circle.fill",
                        iconColor: .ember,
                        label: store.authEmail.isEmpty ? "Signed in" : store.authEmail,
                        trailingText: store.authProvider.isEmpty ? "Session" : store.authProvider.capitalized
                    )
                    Divider().background(Color.borderColor)
                    SettingsRow(
                        icon: "checkmark.shield.fill",
                        iconColor: .success,
                        label: "Session",
                        trailingText: store.isAuthenticated ? "Active" : "None"
                    )
                }

                // Health
                sectionHeader("Apple Health")
                SectionCard {
                    SettingsRow(
                        icon: "heart.text.square.fill",
                        iconColor: store.healthKitLive ? .success : .warning,
                        label: "HealthKit",
                        trailingText: store.healthKitLive ? "Connected" : "Offline"
                    )
                    Divider().background(Color.borderColor)
                    Button {
                        Task {
                            await store.reconnectHealthKit()
                            FDS.notificationHaptic(store.healthKitLive ? .success : .warning)
                        }
                    } label: {
                        SettingsRow(
                            icon: "arrow.triangle.2.circlepath",
                            iconColor: .ember,
                            label: store.healthKitLive ? "Resync HealthKit" : "Reconnect HealthKit",
                            trailingText: "Now",
                            showChevron: true
                        )
                    }
                    .buttonStyle(.plain)
                    Divider().background(Color.borderColor)
                    SettingsRow(
                        icon: "calendar.badge.clock",
                        iconColor: .steel,
                        label: "Cycle quiet sync",
                        trailingText: "Weekly"
                    )
                }

                // Cycle privacy (Home opens the full Cycle surface)
                sectionHeader("Cycle privacy")
                SectionCard {
                    SettingsRow(
                        icon: "lock.shield.fill",
                        iconColor: Color(hex: "22C55E"),
                        label: "Coaching-only data",
                        trailingText: MenstrualHealthStore.shared.settings.enabled ? "On" : "Off"
                    )
                    Divider().background(Color.borderColor)
                    SettingsRow(
                        icon: "chart.line.uptrend.xyaxis",
                        iconColor: .ember,
                        label: "Prediction accuracy",
                        trailingText: {
                            if let mae = MenstrualHealthStore.shared.accuracyReport.maeDays {
                                return String(format: "MAE %.1fd", mae)
                            }
                            return "Learning"
                        }()
                    )
                    Divider().background(Color.borderColor)
                    SettingsRow(icon: "scope", iconColor: Color(hex: "A855F7"), label: "High-accuracy mode") {
                        ForgeToggle(isOn: Binding(
                            get: { MenstrualHealthStore.shared.settings.highAccuracyMode },
                            set: { v in MenstrualHealthStore.shared.updateSettings { $0.highAccuracyMode = v } }
                        ))
                    }
                    Divider().background(Color.borderColor)
                    SettingsRow(icon: "eye.fill", iconColor: .ember, label: "Share cycle with ARIA") {
                        ForgeToggle(isOn: Binding(
                            get: { MenstrualHealthStore.shared.settings.shareWithAria },
                            set: { v in MenstrualHealthStore.shared.updateSettings { $0.shareWithAria = v } }
                        ))
                    }
                    Divider().background(Color.borderColor)
                    Button {
                        store.openCycleHealth(pane: "me")
                    } label: {
                        SettingsRow(
                            icon: "house.fill",
                            iconColor: Color(hex: "EF4444"),
                            label: "Open Cycle Health",
                            trailingText: "Home",
                            showChevron: true
                        )
                    }
                    .buttonStyle(.plain)
                }

                // Data & Privacy
                sectionHeader("Data & Privacy")
                SectionCard {
                    Button { showDataPermissions = true } label: {
                        SettingsRow(icon: "lock.shield.fill", iconColor: .steel, label: "ARIA Data Permissions",
                                    trailingText: "Manage", showChevron: true)
                    }
                    .buttonStyle(.plain)
                }

                // Focus / quiet
                sectionHeader("Focus")
                SectionCard {
                    SettingsRow(icon: "moon.fill", iconColor: .steel, label: "Quiet mode") {
                        ForgeToggle(isOn: Binding(
                            get: { store.quietMode },
                            set: { store.setQuietMode($0) }
                        ))
                    }
                }

                // Workout Preferences
                sectionHeader("Workout Preferences")
                SectionCard {
                    Button { showGoalsEditor = true } label: {
                        SettingsRow(
                            icon: "target",
                            iconColor: .ember,
                            label: "Training Goals",
                            trailingText: "\(store.userProfile.fitnessGoals.count)",
                            showChevron: true
                        )
                    }
                    .buttonStyle(.plain)
                    Divider().background(Color.borderColor)
                    Button { showWorkoutsEditor = true } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Preferred Types").font(.system(size: 14, weight: .medium)).foregroundColor(.textPrimary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.textMuted)
                            }
                            if store.userProfile.preferredWorkouts.isEmpty {
                                Text("Tap to choose the sessions you actually do.")
                                    .font(.system(size: 12))
                                    .foregroundColor(.textTertiary)
                            } else {
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
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    Divider().background(Color.borderColor)
                    Button { showScheduleEditor = true } label: {
                        SettingsRow(icon: "dumbbell.fill", iconColor: .ember, label: "Training Schedule",
                                    trailingText: scheduleDays.isEmpty ? "Set days" : scheduleDays, showChevron: true)
                    }
                    .buttonStyle(.plain)
                    Divider().background(Color.borderColor)
                    Button { showEquipmentPicker = true } label: {
                        SettingsRow(
                            icon: store.userProfile.trainingEquipment.icon,
                            iconColor: .steel,
                            label: "Equipment",
                            trailingText: store.userProfile.trainingEquipment.rawValue,
                            showChevron: true
                        )
                    }
                    .buttonStyle(.plain)
                }

                // Notifications
                sectionHeader("Notifications")
                SectionCard {
                    SettingsRow(icon: "bell.fill", iconColor: .ember, label: "Workout Reminders") {
                        ForgeToggle(isOn: notificationBinding(\.workoutReminders))
                    }
                    Divider().background(Color.borderColor)
                    SettingsRow(icon: "bell.fill", iconColor: .steel, label: "ARIA Proactive Briefs") {
                        ForgeToggle(isOn: Binding(
                            get: { store.briefNotificationsEnabled },
                            set: { store.setBriefNotificationsEnabled($0) }
                        ))
                    }
                    if store.briefNotificationsEnabled {
                        Divider().background(Color.borderColor)
                        briefTimeRow(
                            icon: "sunrise.fill",
                            iconColor: Color(hex: "F59E0B"),
                            label: "Morning brief",
                            hour: $briefSettings.morningHour,
                            minute: $briefSettings.morningMinute
                        )
                        Divider().background(Color.borderColor)
                        briefTimeRow(
                            icon: "sunset.fill",
                            iconColor: Color(hex: "6366F1"),
                            label: "Evening brief",
                            hour: $briefSettings.eveningHour,
                            minute: $briefSettings.eveningMinute
                        )
                    }
                    Divider().background(Color.borderColor)
                    Button {
                        weeklyReview.showSheet = true
                    } label: {
                        SettingsRow(
                            icon: "calendar.badge.clock",
                            iconColor: .ember,
                            label: "Weekly ARIA evaluation",
                            trailingText: weeklyReview.isDue ? "Due" : "Done",
                            showChevron: true
                        )
                    }
                    .buttonStyle(.plain)
                    Divider().background(Color.borderColor)
                    SettingsRow(icon: "bell.fill", iconColor: .success, label: "Recovery Alerts") {
                        ForgeToggle(isOn: notificationBinding(\.recoveryAlerts))
                    }
                    Divider().background(Color.borderColor)
                    SettingsRow(icon: "bell.fill", iconColor: .textSecondary, label: "Weekly Summary") {
                        ForgeToggle(isOn: notificationBinding(\.weeklySummary))
                    }
                    Divider().background(Color.borderColor)
                    SettingsRow(icon: "drop.fill", iconColor: Color(hex: "38BDF8"), label: "Lifestyle Reminders") {
                        ForgeToggle(isOn: notificationBinding(\.lifestyleReminders))
                    }
                }

                // Clinical Integrations
                sectionHeader("Clinical Integrations")
                Button {
                    Task {
                        try? await HealthKitManager.shared.requestClinicalRecordsAuthorization()
                    }
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color.ember.opacity(0.14))
                                .frame(width: 42, height: 42)
                            Image(systemName: "cross.case.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.ember)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Clinical records")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.textPrimary)
                            Text("Read labs and meds already in Apple Health. Nothing is uploaded.")
                                .font(.system(size: 12))
                                .foregroundColor(.textSecondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.textMuted)
                    }
                    .padding(16)
                    .background(Color.surface)
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.borderColor, lineWidth: 1))
                }
                .buttonStyle(.plain)

                // More
                sectionHeader("More")
                SectionCard {
                    Button { showDataPermissions = true } label: {
                        SettingsRow(icon: "lock.shield.fill", iconColor: .textSecondary, label: "Data & Privacy",
                                    trailingText: "HealthKit + ARIA", showChevron: true)
                    }
                    .buttonStyle(.plain)
                    Divider().background(Color.borderColor)
                    Button {
                        if let privacyPolicyURL = ForgeLegalConfig.privacyPolicyURL {
                            openURL(privacyPolicyURL)
                        } else {
                            showLocalPrivacy = true
                        }
                    } label: {
                        SettingsRow(icon: "doc.text.fill", iconColor: .textSecondary, label: "Privacy Policy",
                                    trailingText: ForgeLegalConfig.privacyPolicyURL == nil ? "Required" : nil,
                                    showChevron: ForgeLegalConfig.privacyPolicyURL != nil)
                    }
                    .buttonStyle(.plain)
                    Divider().background(Color.borderColor)
                    Button { showTermsSheet = true } label: {
                        SettingsRow(icon: "doc.plaintext.fill", iconColor: .textSecondary, label: "Terms & Conditions",
                                    trailingText: "Local-first", showChevron: true)
                    }
                    .buttonStyle(.plain)
                    Divider().background(Color.borderColor)
                    SettingsRow(icon: "creditcard.fill", iconColor: .textSecondary, label: "Subscription",
                                trailingText: "Coming soon")
                    Divider().background(Color.borderColor)
                    // Was a flat label showing an address you couldn't tap. Now it opens
                    // a pre-addressed mail draft with the diagnostics a support reply needs.
                    Button {
                        openSupportEmail()
                    } label: {
                        SettingsRow(icon: "questionmark.circle.fill", iconColor: .textSecondary,
                                    label: "Help & Support", trailingText: "Email us", showChevron: true)
                    }
                    .buttonStyle(.plain)
                    Divider().background(Color.borderColor)
                    Button { showAbout = true } label: {
                        SettingsRow(icon: "info.circle.fill", iconColor: .textSecondary, label: "About Forge",
                                    trailingText: ForgeAppInfo.shortVersion, showChevron: true)
                    }
                    .buttonStyle(.plain)
                    Divider().background(Color.borderColor)
                    Button { showBackendURL = true } label: {
                        SettingsRow(
                            icon: "server.rack",
                            iconColor: .steel,
                            label: "ARIA backend URL",
                            trailingText: "Bedrock",
                            showChevron: true
                        )
                    }
                    .buttonStyle(.plain)
                }

                // Log Out
                Button {
                    confirmSignOut = true
                } label: {
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
        .sheet(isPresented: $showProfileEditor) {
            ProfileEditorView()
        }
        .sheet(isPresented: $showShareSheet) {
            ShareProgressView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showCoachingStylePicker) {
            CoachingStylePickerView()
        }
        .sheet(isPresented: $showTrainingThemePicker) {
            TrainingThemePickerView()
        }
        .sheet(isPresented: $showDevicesSheet) {
            ConnectedDevicesLibraryView()
                .environmentObject(store)
        }
        .onReceive(NotificationCenter.default.publisher(for: .healthDeviceCatalogDidChange)) { _ in
            catalogRevision += 1
        }
        .sheet(isPresented: $showLocalPrivacy) {
            NavigationStack {
                ScrollView {
                    Text("Forge keeps HealthKit data on this device. ARIA only receives what you allow under Data Permissions. Wearables on the Devices list write to Apple Health through their own iOS apps — Forge reads that ledger, it does not scrape vendor accounts.")
                        .font(.system(size: 15))
                        .foregroundColor(.textSecondary)
                        .padding(20)
                }
                .background(Color.background)
                .navigationTitle("Privacy")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showLocalPrivacy = false }
                    }
                }
            }
        }
        .sheet(isPresented: $showTermsSheet) {
            ForgeTermsAndConditionsView()
        }
        .sheet(isPresented: $showAbout) {
            ForgeAboutView()
        }
        .sheet(isPresented: $showMyChartPlaceholderSheet) {
            MyChartNativeAPIPlaceholderView()
        }
        .sheet(isPresented: $showDataPermissions) {
            DataPermissionsView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showGoalsEditor) {
            FitnessGoalsEditorView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showScheduleEditor) {
            TrainingScheduleEditorView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showEquipmentPicker) {
            EquipmentPickerView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showWorkoutsEditor) {
            PreferredWorkoutsEditorView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showBackendURL) {
            NavigationStack {
                Form {
                    Section("Backend (Bedrock path)") {
                        TextField("https://…", text: $backendURLDraft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    }
                    Section {
                        Button("Save") {
                            AriaService.shared.setBaseURL(backendURLDraft)
                            showBackendURL = false
                        }
                    }
                }
                .navigationTitle("ARIA backend")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { showBackendURL = false }
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
        .alert("Privacy Policy Required", isPresented: $showPrivacyPolicyURLAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Add Forge's production privacy policy URL before enabling clinical health records in release builds.")
        }
        .confirmationDialog("Log out of Forge?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Log Out", role: .destructive) { store.signOut() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You'll need to sign in again. Health data stays on this iPhone.")
        }
        .onChange(of: briefSettings) { _, updated in
            ForgePersistence.saveBriefNotificationSettings(updated)
            store.updateBriefNotificationSchedule(
                morningHour: updated.morningHour,
                morningMinute: updated.morningMinute,
                eveningHour: updated.eveningHour,
                eveningMinute: updated.eveningMinute
            )
        }
        .onAppear { weeklyReview.refreshDue() }
    }

    /// Opens the user's mail client with a support draft already addressed and stamped
    /// with build info, so a bug report arrives with the context we'd otherwise ask for.
    private func openSupportEmail() {
        let subject = "Forge support request"
        let body = """


        ---
        App: Forge \(ForgeAppInfo.fullVersion)
        Device: \(UIDevice.current.model) · iOS \(UIDevice.current.systemVersion)
        """
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = ForgeAppInfo.supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        if let url = components.url {
            openURL(url)
        }
    }

    private func notificationBinding(_ keyPath: WritableKeyPath<AppNotificationSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { store.notificationSettings[keyPath: keyPath] },
            set: { newValue in
                var settings = store.notificationSettings
                settings[keyPath: keyPath] = newValue
                store.updateNotificationSettings(settings)
            }
        )
    }

    private func briefTimeRow(
        icon: String,
        iconColor: Color,
        label: String,
        hour: Binding<Int>,
        minute: Binding<Int>
    ) -> some View {
        SettingsRow(icon: icon, iconColor: iconColor, label: label) {
            DatePicker(
                label,
                selection: Binding(
                    get: { Self.clockDate(hour: hour.wrappedValue, minute: minute.wrappedValue) },
                    set: { date in
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                        hour.wrappedValue = min(23, max(0, parts.hour ?? 0))
                        minute.wrappedValue = min(59, max(0, parts.minute ?? 0))
                    }
                ),
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .tint(.ember)
            .accessibilityLabel(label)
        }
    }

    /// Fixed calendar day so DST cannot flip 6:00 into 5:00 when the picker
    /// is bound to "today".
    private static func clockDate(hour: Int, minute: Int) -> Date {
        var parts = DateComponents()
        parts.calendar = Calendar.current
        parts.year = 2026
        parts.month = 1
        parts.day = 15
        parts.hour = min(23, max(0, hour))
        parts.minute = min(59, max(0, minute))
        return parts.date ?? Date()
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

// MARK: - Profile Hero Header

/// The identity anchor for the Profile tab: avatar, name, coaching identity,
/// a signature lifetime-stat band, today's readiness, and quick actions.
/// Replaces the old profile card that was buried beneath the Settings title.
struct ProfileHeroHeader: View {
    @EnvironmentObject var store: AppStore
    var onEdit: () -> Void
    var onShare: () -> Void

    @State private var appeared = false
    @State private var glow = false

    private var profile: UserProfile { store.userProfile }
    private var totalWorkouts: Int { store.workoutHistory.count }
    private var totalPRs: Int { store.personalRecords.count }
    private var totalVolume: Int { store.workoutHistory.reduce(0) { $0 + $1.volume } }

    private var volumeCompact: String {
        let v = Double(totalVolume)
        if v >= 1_000_000 { return String(format: "%.1fM", v / 1_000_000) }
        if v >= 1_000 { return String(format: "%.0fk", v / 1_000) }
        return String(totalVolume)
    }

    private var displayName: String {
        let trimmed = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Your Profile" : trimmed
    }

    private var readinessWord: String {
        switch store.readiness.overall {
        case 85...:   return "Primed"
        case 70..<85: return "Ready"
        case 55..<70: return "Steady"
        default:      return "Recover"
        }
    }

    private var trend: AppStore.ReadinessTrend { store.readinessTrend }

    private var trendSymbol: String {
        switch trend {
        case .improving: return "arrow.up.right"
        case .declining: return "arrow.down.right"
        case .stable:    return "equal"
        }
    }

    private var trendLabel: String {
        switch trend {
        case .improving: return "Trending up"
        case .declining: return "Easing off"
        case .stable:    return "Holding"
        }
    }

    private var trendColor: Color {
        switch trend {
        case .improving: return .success
        case .declining: return .danger
        case .stable:    return .textSecondary
        }
    }

    var body: some View {
        VStack(spacing: FDS.Spacing.lg) {
            identity
            statBand
            readinessStrip
            actions
        }
        .frame(maxWidth: .infinity)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 14)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { appeared = true }
            if !UIAccessibility.isReduceMotionEnabled {
                withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                    glow = true
                }
            }
        }
    }

    // MARK: Avatar + name + identity chips

    private var identity: some View {
        VStack(spacing: FDS.Spacing.md) {
            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [Color.ember.opacity(glow ? 0.34 : 0.16), .clear],
                        center: .center, startRadius: 6, endRadius: 92))
                    .frame(width: 188, height: 188)
                    .blur(radius: 14)

                Button(action: { FDS.haptic(.light); onEdit() }) {
                    ZStack(alignment: .bottomTrailing) {
                        ProfileAvatarView(
                            fileName: profile.avatarFileName,
                            initials: profile.initials,
                            size: 92
                        )
                        ZStack {
                            Circle().fill(Color.background).frame(width: 30, height: 30)
                            Circle().fill(Color.ember).frame(width: 26, height: 26)
                            Image(systemName: profile.avatarFileName == nil ? "camera.fill" : "pencil")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .offset(x: 3, y: 3)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(profile.avatarFileName == nil ? "Add profile photo" : "Edit profile")
            }
            .frame(height: 108)

            VStack(spacing: FDS.Spacing.sm) {
                Text(displayName)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                HStack(spacing: FDS.Spacing.sm) {
                    identityChip(text: profile.experienceLevel.label, icon: "chart.bar.fill", color: .ember)
                    identityChip(text: profile.coachingStyle.label, icon: profile.coachingStyle.icon, color: profile.coachingStyle.color)
                }
            }
        }
    }

    private func identityChip(text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold))
            Text(text).font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundColor(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(color.opacity(0.12)))
        .overlay(Capsule().stroke(color.opacity(0.25), lineWidth: 1))
    }

    // MARK: Signature stat band

    private var statBand: some View {
        HStack(spacing: 0) {
            heroStat(value: "\(store.currentStreak)", label: "Day streak", icon: "flame.fill", tint: .warning)
            statDivider
            heroStat(value: "\(totalWorkouts)", label: "Workouts", icon: "figure.strengthtraining.traditional", tint: .ember)
            statDivider
            heroStat(value: "\(totalPRs)", label: "PRs", icon: "trophy.fill", tint: .steel)
            statDivider
            heroStat(value: volumeCompact, label: "Lbs lifted", icon: "scalemass.fill", tint: .success)
        }
        .padding(.vertical, FDS.Spacing.lg)
        .forgeCard()
    }

    private var statDivider: some View {
        Rectangle().fill(Color.borderColor).frame(width: 1, height: 34)
    }

    private func heroStat(value: String, label: String, icon: String, tint: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundColor(tint)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }

    // MARK: Readiness strip

    private var readinessStrip: some View {
        HStack(spacing: FDS.Spacing.md) {
            ZStack {
                Circle().stroke(Color.borderColor, lineWidth: 5).frame(width: 46, height: 46)
                Circle()
                    .trim(from: 0, to: max(0.02, CGFloat(store.readiness.overall) / 100))
                    .stroke(LinearGradient.emberGradient, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 46, height: 46)
                Text("\(store.readiness.overall)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Readiness today")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.textTertiary)
                Text(readinessWord)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.textPrimary)
            }

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: trendSymbol).font(.system(size: 10, weight: .bold))
                Text(trendLabel).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            }
            .foregroundColor(trendColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(trendColor.opacity(0.12)))
        }
        .padding(FDS.Spacing.lg)
        .forgeCard(accent: .ember)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Readiness today \(store.readiness.overall) out of 100, \(readinessWord), \(trendLabel)")
    }

    // MARK: Quick actions

    private var actions: some View {
        HStack(spacing: FDS.Spacing.md) {
            Button(action: { FDS.haptic(.light); onEdit() }) {
                actionLabel(icon: "square.and.pencil", text: "Edit profile", filled: true)
            }
            .buttonStyle(.plain)

            Button(action: { FDS.haptic(.light); onShare() }) {
                actionLabel(icon: "square.and.arrow.up", text: "Share", filled: false)
            }
            .buttonStyle(.plain)
        }
    }

    private func actionLabel(icon: String, text: String, filled: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold))
            Text(text).font(.system(size: 14, weight: .semibold))
        }
        .foregroundColor(filled ? .white : .ember)
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .background {
            if filled {
                Capsule().fill(LinearGradient.emberGradient)
            } else {
                Capsule().fill(Color.ember.opacity(0.12))
                    .overlay(Capsule().stroke(Color.ember.opacity(0.3), lineWidth: 1))
            }
        }
    }
}

// MARK: - App info

/// Single source of truth for build metadata. "v1.0" used to be typed into the settings
/// row by hand, so it stayed at 1.0 no matter what shipped.
enum ForgeAppInfo {
    static let supportEmail = "support@forge.health"

    static var shortVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return "v" + (version ?? "1.0")
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    static var fullVersion: String { "\(shortVersion) (\(buildNumber))" }
}

struct ForgeAboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Forge")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(.textPrimary)
                        Text(ForgeAppInfo.fullVersion)
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundColor(.textTertiary)
                    }

                    Text("Training, recovery, cycle health, and lifestyle coaching that runs on your own data. ARIA reasons over what you allow it to see, and nothing more.")
                        .font(.system(size: 14))
                        .foregroundColor(.textSecondary)

                    aboutRow("lock.shield.fill", "Local-first", "Your profile, cycle logs, and photos live on this device. Cycle data is coaching-only and is never sold.")
                    aboutRow("heart.text.square.fill", "HealthKit", "Read and write is scoped to what you approve in the Health app, and can be revoked there at any time.")
                    aboutRow("sparkles", "ARIA", "Coaching, not clinical care. Verify health decisions with a qualified professional.")

                    VStack(alignment: .leading, spacing: 4) {
                        Text("SUPPORT")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(1.2)
                            .foregroundColor(.textTertiary)
                        Text(ForgeAppInfo.supportEmail)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.ember)
                            .textSelection(.enabled)
                    }
                    .padding(.top, 4)
                }
                .padding(20)
            }
            .background(Color.background.ignoresSafeArea())
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundColor(.ember)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func aboutRow(_ icon: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundColor(.ember)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Text(body)
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct ForgeTermsAndConditionsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Forge is built around local-first health and lifestyle data. You and only you have access to your personal data. Forge never sees, sells, rents, or shares your data in any way whatsoever.")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.textPrimary)
                        .lineSpacing(3)

                    VStack(alignment: .leading, spacing: 12) {
                        legalPoint("Your Apple Health, clinical, cycle, sexual health, workout, sleep, nutrition, and lifestyle data stays under your control.")
                        legalPoint("Forge uses HealthKit permissions only for features you enable and only through Apple's permission system.")
                        legalPoint("Clinical records from providers or apps such as MyChart remain read-only through Apple Health unless a future native connection is explicitly added and authorized by you.")
                        legalPoint("Forge does not sell personal information, health information, clinical records, or lifestyle data.")
                        legalPoint("You can revoke Health permissions at any time in the iOS Settings app or Apple Health.")
                    }
                }
                .padding(20)
            }
            .background(Color.background.ignoresSafeArea())
            .navigationTitle("Terms & Conditions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func legalPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 15))
                .foregroundColor(.success)
                .padding(.top, 2)
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(.textSecondary)
                .lineSpacing(2)
        }
    }
}

struct MyChartNativeAPIPlaceholderView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "cross.case.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.ember)

                Text("MyChart Native API")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.textPrimary)

                Text("This is a filler destination for a future native MyChart connection. Until the API credentials, patient authorization flow, and provider scope are added, Forge reads clinical records through Apple Health as read-only data from connected sources.")
                    .font(.system(size: 15))
                    .foregroundColor(.textSecondary)
                    .lineSpacing(3)

                SettingsRow(icon: "heart.text.square.fill", iconColor: .textSecondary, label: "Current clinical path", trailingText: "Apple Health")
                    .background(Color.surface)
                    .cornerRadius(14)

                SettingsRow(icon: "key.fill", iconColor: .textSecondary, label: "Native API status", trailingText: "Filler")
                    .background(Color.surface)
                    .cornerRadius(14)

                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.background.ignoresSafeArea())
            .navigationTitle("MyChart")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Settings Persistence

struct AppNotificationSettings: Codable, Equatable {
    var workoutReminders: Bool = true
    var recoveryAlerts: Bool = true
    var weeklySummary: Bool = true
    var lifestyleReminders: Bool = true
}

struct BriefNotificationSettings: Codable, Equatable {
    var morningHour: Int = 6
    var morningMinute: Int = 0
    var eveningHour: Int = 18
    var eveningMinute: Int = 0
}

struct ProgressSummary: Equatable {
    var workoutsCompleted: Int
    var newPRCount: Int
    var recoveryDelta: Double
    var summary: String
}

struct TrainingInsight: Equatable {
    var title: String
    var observation: String
    var recommendation: String
}

enum DataLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed
}

enum ForgeDates {
    private static let isoFormatter = ISO8601DateFormatter()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE, MMM d")
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter
    }()

    static func parse(_ value: String) -> Date? {
        isoFormatter.date(from: value) ?? dayFormatter.date(from: value)
    }

    static func yyyyMMdd(from date: Date) -> String {
        dayFormatter.string(from: date)
    }

    static func displayDate(_ value: String) -> String {
        guard let date = parse(value) else { return value }
        return displayFormatter.string(from: date)
    }

    static func displayWeekdayDate(_ value: String) -> String {
        guard let date = parse(value) else { return value }
        return weekdayFormatter.string(from: date)
    }

    static func monthYearTitle(for date: Date) -> String {
        monthFormatter.string(from: date)
    }

    static func mondayBasedStartOffset(for date: Date, calendar: Calendar = .current) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return (weekday + 5) % 7
    }
}

enum ForgePersistence {
    private static let notificationSettingsKey = "forge.notificationSettings"
    private static let briefNotificationSettingsKey = "forge.briefNotificationSettings"
    private static let briefNotificationsEnabledKey = "forge.briefNotificationsEnabled"
    private static let nutritionPreferencesKey = "forge.nutritionPreferences"

    static func loadNotificationSettings() -> AppNotificationSettings {
        load(AppNotificationSettings.self, forKey: notificationSettingsKey) ?? AppNotificationSettings()
    }

    static func saveNotificationSettings(_ settings: AppNotificationSettings) {
        save(settings, forKey: notificationSettingsKey)
    }

    static func loadBriefNotificationSettings() -> BriefNotificationSettings {
        var settings = load(BriefNotificationSettings.self, forKey: briefNotificationSettingsKey)
            ?? BriefNotificationSettings()
        // One-time move off the old 8:00 / 20:00 factory defaults that the
        // broken stepper UI also displayed as stacked digits.
        let migratedKey = "forge.brief.defaults.6am6pm"
        if !UserDefaults.standard.bool(forKey: migratedKey) {
            if settings.morningHour == 8, settings.morningMinute == 0,
               settings.eveningHour == 20, settings.eveningMinute == 0 {
                settings.morningHour = 6
                settings.eveningHour = 18
            }
            UserDefaults.standard.set(true, forKey: migratedKey)
            saveBriefNotificationSettings(settings)
        }
        return settings
    }

    static func saveBriefNotificationSettings(_ settings: BriefNotificationSettings) {
        save(settings, forKey: briefNotificationSettingsKey)
    }

    static func loadBriefNotificationsEnabled() -> Bool {
        guard UserDefaults.standard.object(forKey: briefNotificationsEnabledKey) != nil else { return true }
        return UserDefaults.standard.bool(forKey: briefNotificationsEnabledKey)
    }

    static func saveBriefNotificationsEnabled(_ isEnabled: Bool) {
        UserDefaults.standard.set(isEnabled, forKey: briefNotificationsEnabledKey)
    }

    static func loadNutritionPreferences() -> NutritionPreferences {
        load(NutritionPreferences.self, forKey: nutritionPreferencesKey) ?? NutritionPreferences()
    }

    static func saveNutritionPreferences(_ preferences: NutritionPreferences) {
        save(preferences, forKey: nutritionPreferencesKey)
    }

    private static func load<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func save<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

extension AppStore {
    var lifestyleTargets: LifestyleTargets {
        LifestyleTargets.resolve(profile: userProfile, overrides: nutritionPreferences)
    }

    var dataLoadState: DataLoadState {
        .loaded
    }

    var progressSummary: ProgressSummary? {
        guard !workoutHistory.isEmpty || !personalRecords.isEmpty else { return nil }

        let calendar = Calendar.current
        let now = Date()
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? now
        let monthlyWorkouts = workoutHistory.filter { workout in
            guard let date = ForgeDates.parse(workout.date) else { return false }
            return date >= monthStart && date <= now
        }
        let monthlyRecords = personalRecords.filter { record in
            guard let date = ForgeDates.parse(record.date) else { return false }
            return date >= monthStart && date <= now
        }
        let recoveryDelta = Double(readiness.recoveryScore - readiness.sleepQuality)
        let summary = "You completed \(monthlyWorkouts.count) workouts this month with \(monthlyRecords.count) new PRs. Recovery is \(readiness.recoveryScore >= readiness.sleepQuality ? "trending up" : "asking for more attention")."

        return ProgressSummary(
            workoutsCompleted: monthlyWorkouts.count,
            newPRCount: monthlyRecords.count,
            recoveryDelta: recoveryDelta,
            summary: summary
        )
    }

    var primaryTrainingInsight: TrainingInsight? {
        guard !workoutHistory.isEmpty else { return nil }

        switch readinessTrend {
        case .improving:
            return TrainingInsight(
                title: "Recovery Trend Improving",
                observation: "Your readiness is running above your recent sleep-score baseline.",
                recommendation: "This is a good window for progressive overload if soreness is manageable."
            )
        case .declining:
            return TrainingInsight(
                title: "Recovery Needs Attention",
                observation: "Your readiness is trailing your recent sleep-score baseline.",
                recommendation: "Keep intensity controlled and prioritize sleep before the next hard session."
            )
        case .stable:
            return TrainingInsight(
                title: "Consistency Pattern",
                observation: "Your training and recovery signals are holding steady.",
                recommendation: "Maintain the current rhythm and look for small weekly volume increases."
            )
        }
    }

    func updateNotificationSettings(_ settings: AppNotificationSettings) {
        notificationSettings = settings   // didSet persists + reschedules
    }

    func setBriefNotificationsEnabled(_ isEnabled: Bool) {
        briefNotificationsEnabled = isEnabled   // didSet persists + reschedules
    }

    func updateBriefNotificationSchedule(
        morningHour: Int,
        morningMinute: Int,
        eveningHour: Int,
        eveningMinute: Int
    ) {
        let settings = BriefNotificationSettings(
            morningHour: morningHour,
            morningMinute: morningMinute,
            eveningHour: eveningHour,
            eveningMinute: eveningMinute
        )
        ForgePersistence.saveBriefNotificationSettings(settings)
        objectWillChange.send()
        Task { await resyncNotifications() }
    }

    func updateNutritionPreferences(_ preferences: NutritionPreferences) {
        nutritionPreferences = preferences   // didSet persists
    }

    func resyncNotifications() async {
        await ForgeNotificationScheduler.sync(
            settings: notificationSettings,
            briefEnabled: briefNotificationsEnabled,
            brief: ForgePersistence.loadBriefNotificationSettings()
        )
    }

    func loadDashboardFromAPI() async {
        await Task.yield()
        objectWillChange.send()
    }

    func signOut() {
        isAuthenticated = false
        isOnboarded = false
        authProvider = ""
        authEmail = ""
        UserDefaults.standard.set(false, forKey: "forge.auth.session.v1")
        UserDefaults.standard.removeObject(forKey: "forge.auth.provider.v1")
        UserDefaults.standard.removeObject(forKey: "forge.auth.email.v1")
        activeTab = .home
        onboardingStep = 0
    }

    /// Force HealthKit reconnect from Settings / Home offline pill.
    func reconnectHealthKit() async {
        do {
            try await HealthKitManager.shared.requestAuthorization()
            healthKitLive = await HealthKitManager.shared.checkAuthorizationStatus()
            if healthKitLive {
                await refreshDailyData()
            }
        } catch {
            healthKitLive = false
        }
        objectWillChange.send()
    }
}

// MARK: - Shared Profile Helpers

struct ForgeSkeletonBlock: View {
    var height: CGFloat
    var cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.surfaceElevated)
            .overlay(
                LinearGradient(
                    colors: [.clear, .white.opacity(0.08), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .redacted(reason: .placeholder)
            .accessibilityHidden(true)
    }
}

struct ForgeEmptyState: View {
    var icon: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .medium))
                .foregroundColor(.textTertiary)
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 16)
        .background(Color.surface)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.borderColor, lineWidth: 1))
    }
}

struct ConnectedDevicesSheet: View {
    var body: some View {
        ConnectedDevicesLibraryView()
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

struct SettingsRow<Trailing: View>: View {
    private let icon: String?
    private let iconColor: Color?
    private let label: String
    private let trailingText: String?
    private let showChevron: Bool
    private let trailing: Trailing

    init(
        icon: String? = nil,
        iconColor: Color? = nil,
        label: String,
        trailingText: String? = nil,
        showChevron: Bool = false,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.label = label
        self.trailingText = trailingText
        self.showChevron = showChevron
        self.trailing = trailing()
    }

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
            trailing
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

extension SettingsRow where Trailing == EmptyView {
    init(
        icon: String? = nil,
        iconColor: Color? = nil,
        label: String,
        trailingText: String? = nil,
        showChevron: Bool = false
    ) {
        self.init(
            icon: icon,
            iconColor: iconColor,
            label: label,
            trailingText: trailingText,
            showChevron: showChevron
        ) { EmptyView() }
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
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

// MARK: - New Interactive Components

struct TimeRangePicker: View {
    @Binding var selection: ProgressPageView.TimeRange
    @Namespace private var pickerAnimation

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ProgressPageView.TimeRange.allCases, id: \.self) { range in
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        selection = range
                    }
                    UISelectionFeedbackGenerator().selectionChanged()
                }) {
                    ZStack {
                        if selection == range {
                            Capsule()
                                .fill(Color.ember)
                                .matchedGeometryEffect(id: "picker", in: pickerAnimation)
                                .shadow(color: Color.ember.opacity(0.3), radius: 8, y: 2)
                        }

                        Text(range.rawValue)
                            .font(.system(size: 13, weight: selection == range ? .semibold : .medium))
                            .foregroundColor(selection == range ? .white : .textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.surface)
        .cornerRadius(100)
        .overlay(Capsule().stroke(Color.borderColor.opacity(0.5), lineWidth: 1))
    }
}

struct QuickStatsOverviewView: View {
    @EnvironmentObject var store: AppStore
    let timeRange: ProgressPageView.TimeRange
    @State private var appear = false

    private var filteredWorkouts: [WorkoutHistory] {
        let days: Int
        switch timeRange {
        case .week: days = 7
        case .month: days = 30
        case .year: days = 365
        }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return store.workoutHistory.filter { workout in
            guard let date = ForgeDates.parse(workout.date) else { return false }
            return date >= cutoff
        }
    }

    private var workoutCountText: String {
        if let completed = store.progressSummary?.workoutsCompleted, timeRange == .month {
            return String(completed)
        }
        return String(filteredWorkouts.count)
    }

    private var caloriesText: String {
        let calories = filteredWorkouts.reduce(0) { $0 + ($1.duration * 5) }
        if calories >= 1000 {
            return String(format: "%.1fk", Double(calories) / 1000.0)
        }
        return String(calories)
    }

    private var avgDurationText: String {
        guard !filteredWorkouts.isEmpty else { return "—" }
        let avg = filteredWorkouts.reduce(0) { $0 + $1.duration } / filteredWorkouts.count
        return String(avg)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.ember)
                Text("OVERVIEW")
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(.textTertiary)
                    .tracking(2)
                Spacer()
            }
            .padding(.bottom, 14)

            HStack(spacing: 12) {
                QuickStatCard(icon: "figure.strengthtraining.traditional", value: workoutCountText, label: "Workouts", trend: nil, trendUp: true, appeared: appear, delay: 0.1)
                QuickStatCard(icon: "flame.fill", value: caloriesText, label: "Calories", trend: nil, trendUp: true, appeared: appear, delay: 0.15)
                QuickStatCard(icon: "timer", value: avgDurationText, label: "Avg Min", trend: nil, trendUp: true, appeared: appear, delay: 0.2)
            }
        }
        .onAppear {
            withAnimation { appear = true }
        }
    }
}

struct QuickStatCard: View {
    let icon: String
    let value: String
    let label: String
    let trend: String?
    let trendUp: Bool
    var appeared: Bool = false
    var delay: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(.ember)
                Spacer()
                if let trend, !trend.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: trendUp ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 9, weight: .bold))
                        Text(trend)
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(trendUp ? .success : .ember)
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background((trendUp ? Color.success : Color.ember).opacity(0.12))
                    .cornerRadius(6)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundColor(.textPrimary)

                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            ZStack {
                Color.surface
                LinearGradient(
                    colors: [Color.ember.opacity(0.02), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.borderColor.opacity(0.5), lineWidth: 1))
        .scaleEffect(appeared ? 1 : 0.9)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(delay), value: appeared)
    }
}

struct StreaksAndMilestonesView: View {
    @EnvironmentObject var store: AppStore
    @State private var appear = false

    // Longest run of consecutive workout days in the loaded history.
    private var longestStreak: Int {
        let calendar = Calendar.current
        let days = Set(store.workoutHistory.compactMap { workout in
            ForgeDates.parse(workout.date).map { calendar.startOfDay(for: $0) }
        })
        var longest = 0
        for day in days {
            // Only walk forward from the first day of each run.
            if let previous = calendar.date(byAdding: .day, value: -1, to: day), days.contains(previous) { continue }
            var length = 1
            var cursor = day
            while let next = calendar.date(byAdding: .day, value: 1, to: cursor), days.contains(next) {
                length += 1
                cursor = next
            }
            longest = max(longest, length)
        }
        return max(longest, store.currentStreak)
    }

    private var streakMessage: String {
        let current = store.currentStreak
        let best = longestStreak
        if current == 0 {
            return "Complete a workout today to start a new streak."
        }
        if current >= best {
            return "This is your longest streak yet — keep it going!"
        }
        let remaining = best - current + 1
        return "\(remaining) more \(remaining == 1 ? "day" : "days") to beat your \(best)-day record."
    }

    private func nextTarget(above value: Int, ladder: [Int]) -> Int {
        ladder.first { value < $0 } ?? ladder[ladder.count - 1]
    }

    private func compact(_ value: Int) -> String {
        value >= 1000 ? String(format: "%.1fk", Double(value) / 1000) : String(value)
    }

    var body: some View {
        let workoutCount = store.workoutHistory.count
        let workoutTarget = nextTarget(above: workoutCount, ladder: [10, 25, 50, 100, 250, 500])
        let totalVolume = store.workoutHistory.reduce(0) { $0 + $1.volume }
        let volumeTarget = nextTarget(above: totalVolume, ladder: [50_000, 100_000, 250_000, 500_000, 1_000_000])
        let prCount = store.personalRecords.count
        let prTarget = nextTarget(above: prCount, ladder: [3, 5, 10, 25, 50])
        let streakTarget = nextTarget(above: longestStreak, ladder: [7, 14, 30, 60, 90])

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.warning)
                Text("Streaks & Milestones")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.textPrimary)
            }

            VStack(spacing: 12) {
                // Current streak
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [.warning, .ember], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 50, height: 50)
                        VStack(spacing: 0) {
                            Text("\(store.currentStreak)")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                            Text(store.currentStreak == 1 ? "day" : "days")
                                .font(.system(size: 8))
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current Streak")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.textPrimary)
                        Text(streakMessage)
                            .font(.system(size: 12))
                            .foregroundColor(.textSecondary)
                            .lineLimit(2)
                    }
                    Spacer()
                }
                .padding(14)
                .background(Color.surface)
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.warning.opacity(0.3), lineWidth: 2))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Current streak: \(store.currentStreak) days. \(streakMessage)")

                // Milestones grid — next goal scales with actual progress
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    MilestoneCard(
                        icon: "trophy.fill",
                        title: "\(workoutTarget) Workouts",
                        subtitle: "\(workoutCount)/\(workoutTarget)",
                        progress: min(1, Double(workoutCount) / Double(workoutTarget)),
                        color: .ember
                    )
                    MilestoneCard(
                        icon: "scalemass.fill",
                        title: "\(compact(volumeTarget)) lbs Lifted",
                        subtitle: "\(compact(totalVolume))/\(compact(volumeTarget))",
                        progress: min(1, Double(totalVolume) / Double(volumeTarget)),
                        color: .warning
                    )
                    MilestoneCard(
                        icon: "figure.strengthtraining.traditional",
                        title: "\(prTarget) Personal Records",
                        subtitle: "\(prCount)/\(prTarget)",
                        progress: min(1, Double(prCount) / Double(prTarget)),
                        color: .steel
                    )
                    MilestoneCard(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "\(streakTarget)-Day Streak",
                        subtitle: "Best: \(longestStreak)",
                        progress: min(1, Double(longestStreak) / Double(streakTarget)),
                        color: .success
                    )
                }
            }
        }
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : 15)
        .onAppear { withAnimation(.easeOut(duration: 0.5).delay(0.2)) { appear = true } }
    }
}

struct MilestoneCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let progress: Double
    let color: Color
    @State private var animatedProgress: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(color)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(color)
            }

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.textPrimary)

            Text(subtitle)
                .font(.system(size: 11))
                .foregroundColor(.textSecondary)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.borderColor)
                        .frame(height: 5)
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * animatedProgress, height: 5)
                }
            }
            .frame(height: 5)
        }
        .padding(12)
        .background(Color.surface)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.borderColor, lineWidth: 1))
        .onAppear {
            withAnimation(.easeOut(duration: 1.0).delay(0.3)) {
                animatedProgress = CGFloat(progress)
            }
        }
    }
}

struct ShareProgressView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var store: AppStore
    @State private var copied = false

    private var summaryText: String {
        var lines = ["My Forge progress 🔥"]
        let workouts = store.progressSummary?.workoutsCompleted ?? store.workoutHistory.count
        if workouts > 0 {
            lines.append("• \(workouts) workouts this month")
        }
        if store.currentStreak > 0 {
            lines.append("• \(store.currentStreak)-day streak")
        }
        for pr in store.personalRecords.prefix(3) {
            lines.append("• \(pr.exercise) PR: \(pr.formattedValue) \(pr.unit)")
        }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.up.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.ember)

                    Text("Share Your Progress")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.textPrimary)

                    Text("Show off your achievements and inspire others!")
                        .font(.system(size: 14))
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)

                // Preview of what gets shared
                Text(summaryText)
                    .font(.system(size: 14))
                    .foregroundColor(.textSecondary)
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color.surface)
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.borderColor, lineWidth: 1))
                    .padding(.horizontal)

                VStack(spacing: 12) {
                    ShareLink(item: summaryText) {
                        ShareOptionRow(icon: "square.and.arrow.up", title: "Share", subtitle: "Send your stats anywhere")
                    }
                    .buttonStyle(.plain)

                    Button {
                        UIPasteboard.general.string = summaryText
                        withAnimation { copied = true }
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    } label: {
                        ShareOptionRow(
                            icon: copied ? "checkmark" : "doc.on.doc",
                            title: copied ? "Copied!" : "Copy to Clipboard",
                            subtitle: "Paste your stats anywhere"
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)

                Spacer()
            }
            .background(Color.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.ember)
                }
            }
        }
    }
}

struct ShareOptionRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.ember.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(.ember)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundColor(.textTertiary)
        }
        .padding(16)
        .background(Color.surface)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.borderColor, lineWidth: 1))
    }
}
// MARK: - Profile Editor View

struct ProfileEditorView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var store: AppStore

    @State private var name = ""
    @State private var age = ""
    @State private var weight = ""
    @State private var heightFeet = ""
    @State private var heightInches = ""
    @State private var experience: ExperienceLevel = .beginner
    @State private var gender: Gender = .preferNotToSay
    @State private var biologicalSex: BiologicalSex?

    @State private var photoItem: PhotosPickerItem?
    @State private var pendingPhoto: UIImage?
    @State private var removePhoto = false
    @State private var showCamera = false
    @State private var isLoadingPhoto = false
    @State private var errorMessage: String?

    private static let lbsPerKg = 2.20462
    private static let cmPerInch = 2.54

    private var currentAvatarFileName: String? {
        removePhoto ? nil : store.userProfile.avatarFileName
    }

    private var hasPhoto: Bool {
        pendingPhoto != nil || (!removePhoto && store.userProfile.avatarFileName != nil)
    }

    // MARK: Save

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Your name can't be empty."
            return
        }

        // Empty means "leave it alone"; a filled field with junk in it is an error the
        // user should see rather than have silently dropped, which is what the old
        // `Int(age)` optional-chain did.
        let ageText = age.trimmingCharacters(in: .whitespaces)
        var newAge: Int?
        if !ageText.isEmpty {
            guard let parsed = Int(ageText), (13...120).contains(parsed) else {
                errorMessage = "Enter an age between 13 and 120."
                return
            }
            newAge = parsed
        }

        let weightText = weight.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        var newWeightKg: Double?
        if !weightText.isEmpty {
            guard let lbs = Double(weightText), (50...800).contains(lbs) else {
                errorMessage = "Enter a weight between 50 and 800 lbs."
                return
            }
            newWeightKg = lbs / Self.lbsPerKg
        }

        var newHeightCm: Double?
        let feetText = heightFeet.trimmingCharacters(in: .whitespaces)
        let inchesText = heightInches.trimmingCharacters(in: .whitespaces)
        if !feetText.isEmpty || !inchesText.isEmpty {
            let feet = Int(feetText) ?? 0
            let inches = Int(inchesText) ?? 0
            let totalInches = Double(feet * 12 + inches)
            guard (36...96).contains(totalInches) else {
                errorMessage = "Enter a height between 3'0\" and 8'0\"."
                return
            }
            newHeightCm = totalInches * Self.cmPerInch
        }

        if let pendingPhoto {
            guard store.setProfilePhoto(pendingPhoto) else {
                errorMessage = "Couldn't save that photo. Try a different image."
                return
            }
        } else if removePhoto {
            store.removeProfilePhoto()
        }

        store.updateProfile(
            name: trimmedName == store.userProfile.name ? nil : trimmedName,
            experienceLevel: experience == store.userProfile.experienceLevel ? nil : experience,
            age: newAge,
            weightKg: newWeightKg,
            heightCm: newHeightCm,
            gender: gender == store.userProfile.gender ? nil : gender,
            biologicalSex: biologicalSex == store.userProfile.biologicalSex ? nil : biologicalSex
        )
        FDS.notificationHaptic(.success)
        dismiss()
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    avatarEditor
                    identityFields
                    bodyFields
                    trainingFields
                    saveButton
                }
                .padding()
            }
            .background(Color.background.ignoresSafeArea())
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.textSecondary)
                }
            }
            .onAppear(perform: loadCurrentValues)
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                loadPickedPhoto(item)
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraCaptureView { image in
                    pendingPhoto = image
                    removePhoto = false
                }
                .ignoresSafeArea()
            }
            .alert("Check that", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func loadCurrentValues() {
        let profile = store.userProfile
        name = profile.name
        age = profile.age.map(String.init) ?? ""
        weight = profile.weight.map { String(Int(($0 * Self.lbsPerKg).rounded())) } ?? ""
        if let cm = profile.height {
            let totalInches = Int((cm / Self.cmPerInch).rounded())
            heightFeet = String(totalInches / 12)
            heightInches = String(totalInches % 12)
        }
        experience = profile.experienceLevel
        gender = profile.gender
        biologicalSex = profile.biologicalSex
    }

    private func loadPickedPhoto(_ item: PhotosPickerItem) {
        isLoadingPhoto = true
        Task {
            defer { isLoadingPhoto = false }
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                errorMessage = "Couldn't read that image."
                return
            }
            pendingPhoto = image
            removePhoto = false
            FDS.haptic(.light)
        }
    }

    // MARK: Sections

    private var avatarEditor: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let pendingPhoto {
                        Image(uiImage: pendingPhoto)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 110, height: 110)
                            .clipShape(Circle())
                    } else {
                        ProfileAvatarView(
                            fileName: currentAvatarFileName,
                            initials: store.userProfile.initials,
                            size: 110,
                            showsRing: false
                        )
                    }
                }
                .overlay(Circle().stroke(Color.ember.opacity(0.4), lineWidth: 2))

                if isLoadingPhoto {
                    ProgressView()
                        .tint(.white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.ember))
                } else {
                    ZStack {
                        Circle().fill(Color.background).frame(width: 36, height: 36)
                        Circle().fill(Color.ember).frame(width: 32, height: 32)
                        Image(systemName: "camera.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                    }
                    .offset(x: 2, y: 2)
                }
            }
            .accessibilityHidden(true)

            HStack(spacing: 10) {
                // The picker is its own control rather than a dialog action, because
                // PhotosPicker must be present in the hierarchy to present its sheet.
                PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                    Label(hasPhoto ? "Change photo" : "Add photo", systemImage: "photo.on.rectangle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.ember)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Color.ember.opacity(0.12))
                        .cornerRadius(100)
                }

                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        showCamera = true
                    } label: {
                        Label("Camera", systemImage: "camera")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.textSecondary)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(Color.surfaceElevated)
                            .cornerRadius(100)
                    }
                    .buttonStyle(.plain)
                }

                if hasPhoto {
                    Button {
                        pendingPhoto = nil
                        photoItem = nil
                        removePhoto = true
                        FDS.haptic(.light)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.danger)
                            .padding(9)
                            .background(Color.danger.opacity(0.12))
                            .cornerRadius(100)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove profile photo")
                }
            }

            if removePhoto && pendingPhoto == nil {
                Text("Photo will be removed when you save.")
                    .font(.system(size: 11))
                    .foregroundColor(.textTertiary)
            }
        }
        .padding(.top, 12)
    }

    private var identityFields: some View {
        VStack(spacing: 16) {
            ProfileFieldRow(label: "Name", placeholder: "Your name", text: $name)

            ProfilePickerRow(label: "Gender") {
                Picker("Gender", selection: $gender) {
                    ForEach(Gender.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .tint(.ember)
            }

            // Cycle health keys off biological sex, so it has to be editable after
            // onboarding rather than locked in forever at first launch.
            ProfilePickerRow(
                label: "Biological sex",
                footnote: "Used to configure cycle health features. Stays on your device."
            ) {
                Picker("Biological sex", selection: $biologicalSex) {
                    Text("Not set").tag(BiologicalSex?.none)
                    ForEach(BiologicalSex.allCases) { option in
                        Text(option.label).tag(BiologicalSex?.some(option))
                    }
                }
                .pickerStyle(.menu)
                .tint(.ember)
            }
        }
    }

    private var bodyFields: some View {
        VStack(spacing: 16) {
            ProfileFieldRow(label: "Age", placeholder: "Age", text: $age, keyboardType: .numberPad)
            ProfileFieldRow(label: "Weight (lbs)", placeholder: "Weight", text: $weight, keyboardType: .decimalPad)

            VStack(alignment: .leading, spacing: 8) {
                Text("Height")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.textSecondary)
                HStack(spacing: 10) {
                    heightField(placeholder: "5", text: $heightFeet, unit: "ft")
                    heightField(placeholder: "10", text: $heightInches, unit: "in")
                }
            }
        }
    }

    private func heightField(placeholder: String, text: Binding<String>, unit: String) -> some View {
        HStack(spacing: 6) {
            TextField(placeholder, text: text)
                .font(.system(size: 15))
                .keyboardType(.numberPad)
            Text(unit)
                .font(.system(size: 13))
                .foregroundColor(.textTertiary)
        }
        .padding(14)
        .background(Color.surface)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.borderColor, lineWidth: 1))
        .accessibilityLabel("Height in \(unit == "ft" ? "feet" : "inches")")
    }

    private var trainingFields: some View {
        ProfilePickerRow(label: "Experience level", footnote: experience.description) {
            Picker("Experience", selection: $experience) {
                ForEach(ExperienceLevel.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.menu)
            .tint(.ember)
        }
    }

    private var saveButton: some View {
        Button(action: save) {
            Text("Save Changes")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.ember)
                .cornerRadius(14)
        }
        .buttonStyle(.plain)
        .padding(.top, 12)
    }
}

// MARK: - Editor helpers

struct ProfilePickerRow<Content: View>: View {
    let label: String
    var footnote: String?
    @ViewBuilder var content: Content

    init(label: String, footnote: String? = nil, @ViewBuilder content: () -> Content) {
        self.label = label
        self.footnote = footnote
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.textSecondary)
                Spacer()
                content
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.surface)
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.borderColor, lineWidth: 1))

            if let footnote {
                Text(footnote)
                    .font(.system(size: 11))
                    .foregroundColor(.textTertiary)
                    .padding(.horizontal, 2)
            }
        }
    }
}

/// Minimal camera capture. `PhotosPicker` covers the library; this covers "take one now",
/// which the old editor's dead camera button implied but never delivered.
struct CameraCaptureView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.allowsEditing = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraCaptureView

        init(_ parent: CameraCaptureView) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
            if let image { parent.onCapture(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

struct ProfileFieldRow: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.textSecondary)

            TextField(placeholder, text: $text)
                .font(.system(size: 15))
                .padding(14)
                .background(Color.surface)
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.borderColor, lineWidth: 1))
                .keyboardType(keyboardType)
        }
    }
}

// MARK: - Coaching Style Picker View

struct CoachingStylePickerView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var store: AppStore
    @State private var selectedStyle: CoachingStyle = .balanced

    private func save() {
        if selectedStyle != store.userProfile.coachingStyle {
            store.updateProfile(coachingStyle: selectedStyle)
        }
        dismiss()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text("Choose how Forge AI interacts with you during workouts and provides feedback.")
                        .font(.system(size: 14))
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .padding(.top, 8)

                    VStack(spacing: 12) {
                        ForEach(CoachingStyle.allCases, id: \.self) { style in
                            Button(action: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    selectedStyle = style
                                }
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: style.icon)
                                        .font(.system(size: 18))
                                        .foregroundColor(style.color)
                                        .frame(width: 28)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(style.label)
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.textPrimary)
                                        Text(style.description)
                                            .font(.system(size: 13))
                                            .foregroundColor(.textSecondary)
                                            .lineLimit(3)
                                    }
                                    Spacer()

                                    ZStack {
                                        Circle()
                                            .stroke(selectedStyle == style ? Color.ember : Color.borderColor, lineWidth: 2)
                                            .frame(width: 24, height: 24)
                                        if selectedStyle == style {
                                            Circle()
                                                .fill(Color.ember)
                                                .frame(width: 14, height: 14)
                                        }
                                    }
                                }
                                .padding(16)
                                .background(Color.surface)
                                .cornerRadius(14)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(selectedStyle == style ? Color.ember : Color.borderColor, lineWidth: selectedStyle == style ? 2 : 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)

                    Button(action: save) {
                        Text("Save Selection")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.ember)
                            .cornerRadius(14)
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)
                }
                .padding(.bottom, 32)
            }
            .background(Color.background.ignoresSafeArea())
            .navigationTitle("Coaching Style")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.textSecondary)
                }
            }
            .onAppear { selectedStyle = store.userProfile.coachingStyle }
        }
    }
}

// MARK: - ARIA Data Permissions

/// Per-domain control over what ARIA may use, plus a one-tap body-model sync
/// that calls POST /ai/observe and shows the fused result.
struct DataPermissionsView: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject private var permissions = DataPermissionsStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var snapshot: BodySnapshot?
    @State private var restricted: [String] = []
    @State private var isSyncing = false
    @State private var syncError: String?

    private let labels: [String: (String, String)] = [
        "sleep": ("Sleep", "moon.fill"),
        "readiness": ("Readiness & HRV", "bolt.heart.fill"),
        "activity": ("Activity", "figure.walk"),
        "training": ("Training", "dumbbell.fill"),
        "chronotype": ("Sleep Timing", "clock.fill"),
        "body": ("Body Metrics", "scalemass.fill"),
        "nutrition": ("Nutrition", "fork.knife"),
        "profile": ("Goals & Profile", "person.fill"),
        "progress": ("Progress", "chart.line.uptrend.xyaxis"),
        "lifestyle": ("Lifestyle & Patterns", "sparkles"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("ARIA only reasons over the data you allow. Turn a domain off and it's redacted before ARIA ever sees it — never used, never inferred.")
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)
                        .padding(.top, 4)

                    VStack(spacing: 0) {
                        ForEach(Array(DataPermissionsStore.domains.enumerated()), id: \.element) { index, domain in
                            if index > 0 { Divider().background(Color.borderColor) }
                            Toggle(isOn: allowBinding(for: domain)) {
                                HStack(spacing: 12) {
                                    Image(systemName: labels[domain]?.1 ?? "circle.fill")
                                        .font(.system(size: 15))
                                        .foregroundColor(.ember)
                                        .frame(width: 24)
                                    Text(labels[domain]?.0 ?? domain.capitalized)
                                        .font(.system(size: 15))
                                        .foregroundColor(.textPrimary)
                                }
                            }
                            .tint(.ember)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                    }
                    .background(Color.surface)
                    .cornerRadius(16)

                    syncSection
                }
                .padding(16)
            }
            .background(Color.background.ignoresSafeArea())
            .navigationTitle("Data Permissions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundColor(.ember)
                }
            }
        }
    }

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                Task { await sync() }
            } label: {
                HStack(spacing: 8) {
                    if isSyncing { ProgressView().tint(.white) }
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text(isSyncing ? "Syncing body model…" : "Sync body model")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(LinearGradient.emberGradient)
                .cornerRadius(14)
            }
            .disabled(isSyncing)

            if let syncError {
                Text(syncError).font(.system(size: 12)).foregroundColor(.danger)
            }

            if let snapshot {
                snapshotCard(snapshot)
            }
        }
    }

    private func snapshotCard(_ snap: BodySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Body Model")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.textPrimary)
            Text("\(snap.observationCount) signals · \(Int(snap.confidence * 100))% confidence")
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)

            ForEach(snap.derived.values.sorted { $0.name < $1.name }) { estimate in
                if let value = estimate.value {
                    HStack {
                        Text(estimate.name.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.system(size: 13))
                            .foregroundColor(.textSecondary)
                        Spacer()
                        Text("\(value, specifier: "%.0f") · \(estimate.state)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.textPrimary)
                    }
                }
            }

            if !restricted.isEmpty {
                Text("Off: \(restricted.joined(separator: ", "))")
                    .font(.system(size: 11))
                    .foregroundColor(.textTertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface)
        .cornerRadius(16)
    }

    private func allowBinding(for domain: String) -> Binding<Bool> {
        Binding(
            get: { permissions.isAllowed(domain) },
            set: { permissions.setAllowed($0, for: domain) }
        )
    }

    private func sync() async {
        isSyncing = true
        syncError = nil
        defer { isSyncing = false }
        do {
            let response = try await AriaService.shared.observe(store: store)
            snapshot = response.snapshot
            restricted = response.restrictedDomains ?? []
        } catch {
            syncError = "Couldn't reach ARIA — showing local state only."
        }
    }
}

