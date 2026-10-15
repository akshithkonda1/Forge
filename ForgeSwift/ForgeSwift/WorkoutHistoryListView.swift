import SwiftUI
import ForgeCore

struct WorkoutHistoryListView: View {
    @EnvironmentObject var store: AppStore
    @State private var searchText = ""
    @State private var selectedFilterType: WorkoutType? = nil
    @State private var showFilters = false
    @State private var showAllWorkouts = false
    @State private var selectedWorkout: WorkoutHistory?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let collapsedCount = 6

    private struct WeekGroup: Identifiable {
        let id: String
        let title: String
        let workouts: [WorkoutHistory]
    }

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

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            headerRow

            if showFilters {
                filterPanel
                    .transition(expandTransition)
            }

            if filteredWorkouts.isEmpty {
                emptyContent
            } else {
                weekList
            }

            if !isFiltering && filteredWorkouts.count > Self.collapsedCount {
                ForgeTextLink(
                    title: showAllWorkouts ? "Show Less" : "View All (\(filteredWorkouts.count))",
                    accent: .ember,
                    expanded: showAllWorkouts
                ) {
                    withAnimation(motion) { showAllWorkouts.toggle() }
                }
            }
        }
        .forgeContentCard()
    }

    // MARK: - Motion

    private var motion: Animation? { reduceMotion ? nil : FDS.Spring.standard }

    private var expandTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97, anchor: .top))
    }

    // MARK: - Header and filters

    private var headerRow: some View {
        HStack(alignment: .center, spacing: FDS.Spacing.sm) {
            Text("Recent Workouts")
                .forgeSectionLabel(tint: .textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(ForgeLayout.labelMinScale)
                .accessibilityAddTraits(.isHeader)
            if !filteredWorkouts.isEmpty {
                ForgeCardMeta(text: "\(filteredWorkouts.count)")
            }
            Spacer(minLength: FDS.Spacing.sm)
            ForgeIconButton(
                systemImage: showFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle",
                accent: .ember,
                accessibilityLabel: showFilters ? "Hide workout filters" : "Show workout filters",
                tinted: showFilters || isFiltering
            ) {
                withAnimation(motion) { showFilters.toggle() }
            }
        }
    }

    private var filterPanel: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            searchField
            ForgeFlowLayout(lineSpacing: ForgeLayout.interactiveChipLineGap) {
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

    private var searchField: some View {
        HStack(spacing: ForgeLayout.rowGap) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .accessibilityHidden(true)
            TextField("Search workouts...", text: $searchText)
                .font(HomeType.body)
                .foregroundStyle(Color.textPrimary)
                .submitLabel(.search)
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.textTertiary)
                        .forgeTapOutset(vertical: 14, horizontal: 14)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .forgeWell()
    }

    // MARK: - Empty states

    @ViewBuilder
    private var emptyContent: some View {
        if store.workoutHistory.isEmpty {
            ForgeEmptyNote(
                title: "No workouts yet",
                message: "Your completed workouts will appear here.",
                systemImage: "figure.strengthtraining.traditional",
                tint: .ember
            )
        } else {
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                ForgeEmptyNote(
                    title: "No workouts match your search",
                    systemImage: "magnifyingglass"
                )
                ForgeTextLink(title: "Clear filters", accent: .ember) {
                    searchText = ""
                    selectedFilterType = nil
                }
            }
        }
    }

    // MARK: - Week grouping

    private var weekGroups: [WeekGroup] {
        let calendar = Calendar.current
        let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start
        var order: [String] = []
        var titles: [String: String] = [:]
        var buckets: [String: [WorkoutHistory]] = [:]
        for workout in visibleWorkouts {
            let bucket = weekBucket(for: workout, calendar: calendar, thisWeekStart: thisWeekStart)
            if buckets[bucket.key] == nil {
                order.append(bucket.key)
                titles[bucket.key] = bucket.title
            }
            buckets[bucket.key, default: []].append(workout)
        }
        return order.map { key in
            WeekGroup(id: key, title: titles[key] ?? key, workouts: buckets[key] ?? [])
        }
    }

    private func weekBucket(
        for workout: WorkoutHistory,
        calendar: Calendar,
        thisWeekStart: Date?
    ) -> (key: String, title: String) {
        guard let date = WorkoutHistoryWindow.parseDate(workout.date),
              let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start else {
            return ("earlier", "Earlier")
        }
        let key = "\(Int(start.timeIntervalSince1970))"
        if let thisWeekStart {
            if calendar.isDate(start, inSameDayAs: thisWeekStart) {
                return (key, "This week")
            }
            if let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart),
               calendar.isDate(start, inSameDayAs: lastWeekStart) {
                return (key, "Last week")
            }
        }
        let label = start.formatted(.dateTime.month(.abbreviated).day())
        return (key, "Week of \(label)")
    }

    private var weekList: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForEach(weekGroups) { group in
                VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                    ForgeSectionHeader(title: group.title)
                    ForEach(group.workouts) { workout in
                        workoutRow(workout)
                    }
                }
            }
        }
    }

    // MARK: - Row

    private func workoutRow(_ workout: WorkoutHistory) -> some View {
        let isOpen = selectedWorkout?.id == workout.id
        // Only the header row toggles expansion. The expanded section holds
        // its own ShareLink, and nesting buttons would fire both on tap.
        return VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            Button(action: {
                withAnimation(motion) {
                    selectedWorkout = isOpen ? nil : workout
                }
            }) {
                rowHeader(workout, isOpen: isOpen)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(rowAccessibilityLabel(workout))
            .accessibilityValue(isOpen ? "Expanded" : "Collapsed")
            .accessibilityHint(isOpen ? "Hides workout details" : "Shows workout details")

            if isOpen {
                expandedDetails(workout)
                    .transition(expandTransition)
            }
        }
    }

    private func rowHeader(_ workout: WorkoutHistory, isOpen: Bool) -> some View {
        HStack(spacing: ForgeLayout.rowGap) {
            ForgeIconWell(systemImage: icon(for: workout.type), tint: tint(for: workout.type))
            VStack(alignment: .leading, spacing: ForgeLayout.labelValueGap) {
                Text(workout.name)
                    .font(HomeType.status)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                Text(rowSubtitle(workout))
                    .font(HomeType.body)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(2)
            }
            .layoutPriority(1)
            Spacer(minLength: FDS.Spacing.xs)
            Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textMuted)
                .accessibilityHidden(true)
        }
        .padding(.vertical, ForgeLayout.rowVerticalPadding)
        .frame(minHeight: ForgeUX.minTap)
        .contentShape(Rectangle())
    }

    private func rowSubtitle(_ workout: WorkoutHistory) -> String {
        var parts = [ForgeDates.displayWeekdayDate(workout.date), "\(workout.duration) min"]
        if workout.volume > 0 {
            parts.append(String(format: "%.1fk lbs", Double(workout.volume) / 1000))
        }
        return parts.joined(separator: " · ")
    }

    private func rowAccessibilityLabel(_ workout: WorkoutHistory) -> String {
        "\(workout.name), \(workout.type.label), \(rowSubtitle(workout)), \(workout.intensity.label) intensity"
    }

    private func expandedDetails(_ workout: WorkoutHistory) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeStatGrid(columns: 3) {
                StatBadge(label: "Duration", value: "\(workout.duration)", unit: "min")
                StatBadge(
                    label: "Volume",
                    value: workout.volume > 0 ? String(format: "%.1fk", Double(workout.volume) / 1000) : "—",
                    unit: workout.volume > 0 ? "lbs" : ""
                )
                StatBadge(label: "Intensity", value: workout.intensity.label, unit: "")
            }

            ShareLink(item: shareText(for: workout)) {
                shareLabel
            }
            .buttonStyle(.plain)
        }
    }

    private var shareLabel: some View {
        HStack(spacing: FDS.Spacing.sm) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: ForgeUX.icon, weight: .semibold))
            Text("Share Workout")
                .font(HomeType.label)
                .lineLimit(1)
                .minimumScaleFactor(ForgeLayout.labelMinScale)
        }
        .foregroundStyle(Color.ember)
        .frame(maxWidth: .infinity)
        .frame(minHeight: ForgeUX.minTap)
        .padding(.horizontal, FDS.Spacing.lg)
        .background(Color.ember.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous)
                .stroke(Color.ember.opacity(0.28), lineWidth: ForgeUX.hairline)
        )
    }

    // MARK: - Type presentation

    private func icon(for type: WorkoutType) -> String {
        switch type {
        case .strength: return "dumbbell.fill"
        case .cardio: return "figure.run"
        case .hiit: return "bolt.heart.fill"
        case .yoga: return "figure.yoga"
        case .mobility: return "figure.flexibility"
        case .sportSpecific: return "sportscourt.fill"
        }
    }

    private func tint(for type: WorkoutType) -> Color {
        switch type {
        case .strength: return .ember
        case .cardio: return .steel
        case .hiit: return .amber
        case .yoga: return .vitality
        case .mobility: return .aurora
        case .sportSpecific: return .textSecondary
        }
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        ForgeChipButton(label: title, energy: .ember, selected: isSelected, action: action)
    }
}

struct StatBadge: View {
    let label: String
    let value: String
    let unit: String

    var body: some View {
        ForgeStatTile(
            label: label,
            value: value,
            unit: unit.isEmpty ? nil : unit,
            energy: .ember
        )
    }
}
