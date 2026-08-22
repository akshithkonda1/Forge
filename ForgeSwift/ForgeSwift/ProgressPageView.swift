import SwiftUI
import ForgeCore

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
