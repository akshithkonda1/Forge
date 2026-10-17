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

    private var hasNoProgressData: Bool {
        store.workoutHistory.isEmpty && store.progressSummary == nil && store.personalRecords.isEmpty
    }

    private var hasFailedWithoutData: Bool {
        store.dataLoadState == .failed && hasNoProgressData
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            ForgeScreenStack {
                ForgePageHeader(
                    title: "Progress",
                    subtitle: "History, PRs, streaks — your training story",
                    accent: Color.steel
                ) {
                    askAriaButton
                    ForgeIconButton(
                        systemImage: "square.and.arrow.up",
                        accent: Color.steel,
                        accessibilityLabel: "Share progress"
                    ) {
                        showShareSheet = true
                    }
                }

                StatsMosaicCard()

                pageContent
            }
        }
        .forgeScreenBackground(accent: Color.steel)
        .refreshable {
            await store.loadDashboardFromAPI()
        }
        .sheet(isPresented: $showShareSheet) {
            ShareProgressView()
        }
    }

    /// The ARIA mark is 28 pt (the still pose) inside a 44 pt tap area.
    private var askAriaButton: some View {
        Button {
            store.openChat(with: "Walk me through my progress, PRs, and what to train next.", voice: false)
        } label: {
            ARIAIdentityMark(state: .idle, mood: .energized, size: 28, amplitude: 0.24)
                .frame(width: ForgeUX.minTap, height: ForgeUX.minTap)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ask ARIA about progress")
    }

    @ViewBuilder
    private var pageContent: some View {
        if isInitialLoading {
            loadingContent
        } else if hasFailedWithoutData {
            ForgeErrorState(
                title: "Couldn’t load your progress",
                message: "Pull down to refresh, or try again now."
            ) {
                Task { await store.loadDashboardFromAPI() }
            }
        } else if hasNoProgressData {
            ForgeEmptyStateCard(
                icon: "chart.line.uptrend.xyaxis",
                title: "No sessions yet",
                message: "Complete a workout and your history, PRs, and streaks will show up here.",
                accent: .ember,
                cta: "Ask ARIA to write a session",
                action: { store.openChat(with: HomeInsightFlow.todayPlanPrompt, voice: false) }
            )
        } else {
            loadedContent
        }
    }

    private var loadingContent: some View {
        VStack(spacing: ForgeLayout.sectionGap) {
            ForgeSkeletonBlock(height: 88, cornerRadius: FDS.Radius.xl)
            ForgeSkeletonBlock(height: 160, cornerRadius: FDS.Radius.xl)
            ForgeSkeletonBlock(height: 220, cornerRadius: FDS.Radius.xl)
            ForgeSkeletonBlock(height: 160, cornerRadius: FDS.Radius.xl)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading your progress")
    }

    @ViewBuilder
    private var loadedContent: some View {
        MonthlySummaryView()
        TimeRangePicker(selection: $selectedTimeRange)
        QuickStatsOverviewView(timeRange: selectedTimeRange)
        CalendarHeatmapView()
        PersonalRecordsBoardView()
        WorkoutHistoryListView()
        StreaksAndMilestonesView()
        BehavioralInsightView()
    }
}

struct MonthlySummaryView: View {
    @EnvironmentObject var store: AppStore

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
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("This month", meta: monthLabel, tint: .ember)

            ForgeStatGrid(columns: 3) {
                StatPillCard(value: workoutsCompleted, label: "Workouts")
                StatPillCard(value: newPRs, label: "New PRs")
                StatPillCard(value: recoveryDelta, label: "Readiness")
            }

            Text(summaryText)
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
        }
        .forgeContentCard(tint: .ember)
    }
}

/// A stat cell in the Home well. Callers lay the cells out in `ForgeStatGrid`.
/// `appeared` and `delay` are kept for source compatibility; the entrance
/// cascade they drove was retired.
struct StatPillCard: View {
    let value: String
    let label: String
    var appeared: Bool = false
    var delay: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.labelValueGap) {
            Text(value)
                .font(FDS.TypeScale.Dynamic.headline)
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
                .forgeSingleLine()
                .contentTransition(.numericText())
            Text(label)
                .font(HomeType.micro)
                .foregroundStyle(Color.textTertiary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .forgeWell()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }
}

struct CalendarHeatmapView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dynamicTypeSize) private var typeSize

    private static let gridGap: CGFloat = 6
    private static let dayLabels = ["M", "T", "W", "T", "F", "S", "S"]

    // Build date->intensity map from workout history. In-app finishes store a
    // full ISO-8601 instant, so keys are normalised to the calendar day and a
    // multi-session day keeps its highest intensity.
    var dateMap: [String: Int] {
        var m: [String: Int] = [:]
        for w in store.workoutHistory {
            let level: Int
            switch w.intensity {
            case .max, .high:     level = 3
            case .moderate:       level = 2
            case .low:            level = 1
            }
            let key: String
            if let parsed = WorkoutHistoryWindow.parseDate(w.date) {
                key = ForgeDates.yyyyMMdd(from: parsed)
            } else {
                key = w.date
            }
            m[key] = max(m[key] ?? 0, level)
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

        let levels = dateMap
        var cells: [DayCell] = []
        let startOffset = ForgeDates.mondayBasedStartOffset(for: firstOfMonth, calendar: calendar)
        for index in 0..<startOffset {
            cells.append(DayCell(id: "lead-\(index)", day: nil, date: "", level: 0))
        }
        for day in dayRange {
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth) else { continue }
            let dateStr = ForgeDates.yyyyMMdd(from: date)
            cells.append(DayCell(id: dateStr, day: day, date: dateStr, level: levels[dateStr] ?? 0))
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
        default: return Color.white.opacity(0.05)
        }
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Self.gridGap), count: 7)
    }

    private static func sessionName(for level: Int) -> String {
        switch level {
        case 1: return "Light session"
        case 2: return "Moderate session"
        case 3: return "Intense session"
        default: return "No session"
        }
    }

    private static func legendName(for level: Int) -> String {
        switch level {
        case 1: return "Light"
        case 2: return "Moderate"
        case 3: return "Intense"
        default: return "None"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("Consistency", meta: monthTitle, tint: .ember)

            LazyVGrid(columns: gridColumns, spacing: Self.gridGap) {
                ForEach(0..<7, id: \.self) { index in
                    Text(Self.dayLabels[index])
                        .font(HomeType.micro)
                        .foregroundStyle(Color.textTertiary)
                        .frame(maxWidth: .infinity, minHeight: 20)
                        .accessibilityHidden(true)
                }
                ForEach(weeks.flatMap { $0 }) { cell in
                    dayCellView(cell)
                }
            }

            legend
        }
        .forgeContentCard(tint: .ember)
    }

    @ViewBuilder
    private func dayCellView(_ cell: DayCell) -> some View {
        if let day = cell.day {
            let today = ForgeDates.yyyyMMdd(from: Date())
            let isToday = cell.date == today
            let isFuture = cell.date > today
            let spoken = ForgeDates.displayDate(cell.date)
            let status = isFuture ? "Upcoming" : Self.sessionName(for: cell.level)
            RoundedRectangle(cornerRadius: FDS.Radius.xs, style: .continuous)
                .fill(heatColor(cell.level))
                .aspectRatio(1, contentMode: .fit)
                .overlay { dayNumber(day, level: cell.level) }
                .overlay {
                    if isToday {
                        RoundedRectangle(cornerRadius: FDS.Radius.xs, style: .continuous)
                            .stroke(Color.ember, lineWidth: 1.5)
                    }
                }
                .opacity(isFuture ? 0.4 : 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(spoken), \(status)\(isToday ? ", today" : "")")
        } else {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func dayNumber(_ day: Int, level: Int) -> some View {
        if !typeSize.isAccessibilitySize {
            Text("\(day)")
                .font(HomeType.micro)
                .foregroundStyle(level > 0 ? Color.white.opacity(0.9) : Color.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    private var legend: some View {
        ForgeFlowLayout(spacing: ForgeLayout.rowGap, lineSpacing: ForgeLayout.chipGap) {
            ForEach(0..<4, id: \.self) { level in
                HStack(spacing: FDS.Spacing.xs) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(heatColor(level))
                        .frame(width: 12, height: 12)
                        .accessibilityHidden(true)
                    Text(Self.legendName(for: level))
                        .font(HomeType.micro)
                        .foregroundStyle(Color.textTertiary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

struct PersonalRecordsBoardView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showAllPRs = false

    private static let collapsedCount = 3

    private var visibleRecords: [PersonalRecord] {
        showAllPRs ? store.personalRecords : Array(store.personalRecords.prefix(Self.collapsedCount))
    }

    private func toggleShowAll() {
        if reduceMotion {
            showAllPRs.toggle()
        } else {
            withForgeMotion(ForgeMotion.smooth) { showAllPRs.toggle() }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            header

            if store.personalRecords.isEmpty {
                ForgeEmptyNote(
                    title: "No records yet",
                    message: "Finish a few workouts and your personal bests will show up here.",
                    systemImage: "trophy",
                    tint: .amber
                )
            } else {
                VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                    ForEach(visibleRecords) { pr in
                        recordRow(pr)
                    }
                }

                if store.personalRecords.count > Self.collapsedCount {
                    ForgeTextLink(
                        title: showAllPRs ? "Show Less" : "View All (\(store.personalRecords.count))",
                        accent: .amber,
                        expanded: showAllPRs
                    ) {
                        toggleShowAll()
                    }
                }
            }
        }
        .forgeContentCard(accent: .amber)
    }

    @ViewBuilder
    private var header: some View {
        if store.personalRecords.isEmpty {
            ForgeCardHeader("Personal Records", tint: .amber)
        } else {
            ForgeCardHeader("Personal Records", meta: "\(store.personalRecords.count) total", tint: .amber)
        }
    }

    private func recordRow(_ pr: PersonalRecord) -> some View {
        ForgeAdaptiveStack(spacing: FDS.Spacing.sm, alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: ForgeLayout.labelValueGap) {
                Text(pr.exercise)
                    .font(HomeType.status)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                Text(ForgeDates.displayDate(pr.date))
                    .font(HomeType.micro)
                    .foregroundStyle(Color.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(pr.formattedValue)
                    .font(HomeType.metric)
                    .foregroundStyle(Color.textPrimary)
                    .forgeSingleLine()
                    .contentTransition(.numericText())
                Text(pr.unit)
                    .font(HomeType.label)
                    .foregroundStyle(Color.amber)
                    .lineLimit(1)
            }
            .layoutPriority(1)
        }
        .padding(.vertical, ForgeLayout.rowVerticalPadding)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(pr.exercise), \(pr.formattedValue) \(pr.unit), set \(ForgeDates.displayDate(pr.date))")
    }
}

struct BehavioralInsightView: View {
    @EnvironmentObject var store: AppStore

    private var insightTitle: String {
        store.primaryTrainingInsight?.title ?? "Pattern Insight"
    }

    private var insightBody: String {
        if let remote = store.remoteProgressReview, !remote.isEmpty {
            return remote
        }
        if let insight = store.primaryTrainingInsight {
            return "\(insight.observation) \(insight.recommendation)"
        }
        if let summary = store.progressSummary?.summary, !summary.isEmpty {
            return summary
        }
        return "Complete a few workouts and Forge will start surfacing training patterns here."
    }

    var body: some View {
        Button {
            store.openChat(with: "Review my last 30 days. One win, one risk, one recommendation.", voice: false)
        } label: {
            HStack(alignment: .top, spacing: ForgeLayout.rowGap) {
                ForgeIconWell(systemImage: "chart.line.uptrend.xyaxis", tint: .aurora)

                VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                    Text(insightTitle)
                        .font(HomeType.status)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(2)
                    Text(insightBody)
                        .font(HomeType.body)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.leading)
                        .forgeWrapping()
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textMuted)
                    .frame(height: ForgeLayout.iconWell)
                    .accessibilityHidden(true)
            }
            .forgeContentCard(tint: .aurora)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(insightTitle). \(insightBody)")
        .accessibilityHint("Opens ARIA")
        .task { store.shareProgressInsightIfNeeded() }
    }
}
