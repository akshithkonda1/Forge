import SwiftUI
import ForgeCore

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
