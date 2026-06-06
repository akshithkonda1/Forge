import SwiftUI

// MARK: - Profile Tab (mirrors profile-tab.tsx)

struct ProfileTabView: View {
    @State private var subTab: SubTab = .progress
    @Namespace private var tabAnimation

    enum SubTab: String, CaseIterable { 
        case progress = "Progress"
        case lifestyle = "Lifestyle"
        case settings = "Settings"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Enhanced sticky sub-tab bar with matched geometry effect
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(SubTab.allCases, id: \.self) { tab in
                        Button(action: { 
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { 
                                subTab = tab 
                            }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }) {
                            ZStack {
                                if subTab == tab {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.ember)
                                        .matchedGeometryEffect(id: "tab", in: tabAnimation)
                                        .shadow(color: Color.ember.opacity(0.3), radius: 8, y: 2)
                                }
                                Text(tab.rawValue)
                                    .font(.system(size: 14, weight: subTab == tab ? .semibold : .medium))
                                    .foregroundColor(subTab == tab ? .white : .textTertiary)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(Color.surface)
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.borderColor.opacity(0.5), lineWidth: 1))
            }
            .padding(.horizontal, 16)
            .padding(.top, 60)
            .padding(.bottom, 8)
            .background(
                ZStack {
                    Color.background.opacity(0.95)
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [Color.clear, Color.borderColor.opacity(0.1)],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                        .frame(height: 1)
                        .offset(y: 50)
                }
            )

            // Content with transitions
            Group {
                switch subTab {
                case .progress:
                    ProgressPageView()
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                case .lifestyle:
                    LifestyleView()
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                case .settings:
                    SettingsPageView()
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                }
            }
            .id(subTab)
        }
        .background(Color.background.ignoresSafeArea())
    }
}

// MARK: - Progress Page (mirrors progress-page.tsx)

struct ProgressPageView: View {
    @EnvironmentObject var store: AppStore
    @State private var isRefreshing = false
    @State private var showShareSheet = false
    @State private var selectedTimeRange: TimeRange = .month
    
    enum TimeRange: String, CaseIterable {
        case week = "Week"
        case month = "Month"
        case year = "Year"
    }
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                // Header with action buttons
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Progress")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.textPrimary)
                        Text("Track your fitness journey")
                            .font(.system(size: 13))
                            .foregroundColor(.textSecondary)
                    }
                    Spacer()
                    
                    // Share progress button
                    Button(action: { showShareSheet = true }) {
                        ZStack {
                            Circle()
                                .fill(Color.surface)
                                .frame(width: 40, height: 40)
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 16))
                                .foregroundColor(.ember)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 16)
                
                if store.dataLoadState == .loading {
                    ForgeSkeletonBlock(height: 88, cornerRadius: 16)
                    ForgeSkeletonBlock(height: 160, cornerRadius: 16)
                    ForgeSkeletonBlock(height: 220, cornerRadius: 16)
                }

                // Time range selector
                TimeRangePicker(selection: $selectedTimeRange)
                
                // Quick Stats Overview
                QuickStatsOverviewView(timeRange: selectedTimeRange)

                MonthlySummaryView()
                CalendarHeatmapView()
                PersonalRecordsBoardView()
                WorkoutHistoryListView()
                BehavioralInsightView()
                
                // Streaks & Milestones
                StreaksAndMilestonesView()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .refreshable {
            await refreshData()
        }
        .sheet(isPresented: $showShareSheet) {
            ShareProgressView()
        }
    }
    
    func refreshData() async {
        isRefreshing = true
        await store.loadDashboardFromAPI()
        isRefreshing = false
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
    @State private var selectedPR: PersonalRecord?
    @State private var showAllPRs = false

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
                Spacer()
                Button(action: { withAnimation(.spring()) { showAllPRs.toggle() } }) {
                    Text(showAllPRs ? "Show Less" : "View All")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.ember)
                }
            }

            VStack(spacing: 10) {
                ForEach(Array(store.personalRecords.prefix(showAllPRs ? 10 : 3).enumerated()), id: \.element.id) { idx, pr in
                    Button(action: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            selectedPR = selectedPR?.id == pr.id ? nil : pr
                        }
                    }) {
                        VStack(spacing: 0) {
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
                                Image(systemName: selectedPR?.id == pr.id ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.textTertiary)
                                    .padding(.leading, 8)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            
                            // Expandable details
                            if selectedPR?.id == pr.id {
                                VStack(alignment: .leading, spacing: 10) {
                                    Divider().background(Color.borderColor)
                                    
                                    HStack(spacing: 20) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Previous PR")
                                                .font(.system(size: 11))
                                                .foregroundColor(.textTertiary)
                                            Text("245 \(pr.unit)")
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(.textSecondary)
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Improvement")
                                                .font(.system(size: 11))
                                                .foregroundColor(.textTertiary)
                                            HStack(spacing: 4) {
                                                Image(systemName: "arrow.up.right")
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.success)
                                                Text("+10 \(pr.unit)")
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundColor(.success)
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 12)
                                }
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .background(Color.surface)
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(selectedPR?.id == pr.id ? Color.ember : Color.borderColor, lineWidth: selectedPR?.id == pr.id ? 2 : 1)
                        )
                        .shadow(color: selectedPR?.id == pr.id ? Color.ember.opacity(0.2) : .clear, radius: 8)
                    }
                    .buttonStyle(.plain)
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
    @State private var searchText = ""
    @State private var selectedFilterType: WorkoutType? = nil
    @State private var showFilters = false
    @State private var selectedWorkout: WorkoutHistory?

    func formatDate(_ str: String) -> String {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        guard let d = fmt.date(from: str) else { return str }
        let out = DateFormatter(); out.dateFormat = "EEE, MMM d"
        return out.string(from: d)
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
                ForEach(filteredWorkouts) { workout in
                    Button(action: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            selectedWorkout = selectedWorkout?.id == workout.id ? nil : workout
                        }
                    }) {
                        VStack(spacing: 0) {
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
                                Image(systemName: selectedWorkout?.id == workout.id ? "chevron.up.circle.fill" : "chevron.right.circle")
                                    .font(.system(size: 20))
                                    .foregroundColor(selectedWorkout?.id == workout.id ? .ember : .textTertiary)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 14)
                            
                            // Expanded details
                            if selectedWorkout?.id == workout.id {
                                VStack(spacing: 0) {
                                    Divider().background(Color.borderColor)
                                    
                                    VStack(alignment: .leading, spacing: 12) {
                                        HStack(spacing: 20) {
                                            StatBadge(label: "Volume", value: "\(Int(workout.volume / 1000))k", unit: "lbs")
                                            StatBadge(label: "Sets", value: "24", unit: "")
                                            StatBadge(label: "Reps", value: "186", unit: "")
                                        }
                                        
                                        HStack {
                                            Button(action: {}) {
                                                HStack(spacing: 6) {
                                                    Image(systemName: "arrow.clockwise")
                                                        .font(.system(size: 12))
                                                    Text("Repeat Workout")
                                                        .font(.system(size: 13, weight: .medium))
                                                }
                                                .foregroundColor(.ember)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 10)
                                                .background(Color.ember.opacity(0.1))
                                                .cornerRadius(8)
                                            }
                                            
                                            Button(action: {}) {
                                                HStack(spacing: 6) {
                                                    Image(systemName: "square.and.arrow.up")
                                                        .font(.system(size: 12))
                                                    Text("Share")
                                                        .font(.system(size: 13, weight: .medium))
                                                }
                                                .foregroundColor(.steel)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 10)
                                                .background(Color.steel.opacity(0.1))
                                                .cornerRadius(8)
                                            }
                                        }
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
                    .buttonStyle(.plain)
                }
            }
            
            if filteredWorkouts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(.textTertiary)
                    Text("No workouts found")
                        .font(.system(size: 14))
                        .foregroundColor(.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
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

struct SettingsPageView: View {
    @EnvironmentObject var store: AppStore

    @State private var showDevicesSheet = false
    @State private var workoutReminders = true
    @State private var aiInsights = true
    @State private var recoveryAlerts = true
    @State private var weeklySummary = false
    @State private var showProfileEditor = false
    @State private var showCoachingStylePicker = false

    let dayLabels = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]

    var scheduleDays: String {
        store.userProfile.weeklySchedule.map { dayLabels[$0] }.joined(separator: " / ")
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Settings")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.textPrimary)
                        Text("Customize your experience")
                            .font(.system(size: 13))
                            .foregroundColor(.textSecondary)
                    }
                    Spacer()
                }
                .padding(.bottom, 24)
                .padding(.top, 16)

                // Enhanced profile card
                profileCard

                // AI Trainer
                sectionHeader("AI Trainer")
                SectionCard {
                    Button(action: { showCoachingStylePicker = true }) {
                        SettingsRow(icon: "person.fill", iconColor: .ember, label: "Coaching Style",
                                    trailingText: store.userProfile.coachingStyle.label, showChevron: true)
                    }
                    .buttonStyle(.plain)
                    
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
                    if store.userProfile.connectedDevices.isEmpty {
                        HStack(spacing: 10) {
                            Image(systemName: "link.badge.plus")
                                .font(.system(size: 16))
                                .foregroundColor(.textTertiary)
                            Text("No devices connected yet")
                                .font(.system(size: 14))
                                .foregroundColor(.textSecondary)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        Divider().background(Color.borderColor)
                    }
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
                    Button { showDevicesSheet = true } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle().stroke(Color.borderLight, style: StrokeStyle(lineWidth: 1, dash: [4])).frame(width: 32, height: 32)
                                Image(systemName: "plus").font(.system(size: 13)).foregroundColor(.textTertiary)
                            }
                            Text("Add or Manage Devices")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.ember)
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
                    Button(action: {}) {
                        SettingsRow(icon: "lock.shield.fill", iconColor: .textSecondary, label: "Data & Privacy", showChevron: true)
                    }
                    .buttonStyle(.plain)
                    
                    Divider().background(Color.borderColor)
                    
                    Button(action: {}) {
                        SettingsRow(icon: "creditcard.fill", iconColor: .textSecondary, label: "Subscription", showChevron: true)
                    }
                    .buttonStyle(.plain)
                    
                    Divider().background(Color.borderColor)
                    
                    Button(action: {}) {
                        SettingsRow(icon: "questionmark.circle.fill", iconColor: .textSecondary, label: "Help & Support", showChevron: true)
                    }
                    .buttonStyle(.plain)
                    
                    Divider().background(Color.borderColor)
                    
                    Button(action: {}) {
                        SettingsRow(icon: "info.circle.fill", iconColor: .textSecondary, label: "About Forge", showChevron: true)
                    }
                    .buttonStyle(.plain)
                }

                // Log Out
                Button {
                    store.signOut()
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
        .sheet(isPresented: $showCoachingStylePicker) {
            CoachingStylePickerView()
        }
        .sheet(isPresented: $showDevicesSheet) {
            ConnectedDevicesSheet()
                .environmentObject(store)
        }
    }

    var profileCard: some View {
        Button(action: { showProfileEditor = true }) {
            VStack(spacing: 16) {
                // Avatar with edit indicator
                ZStack(alignment: .bottomTrailing) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [.ember, .emberLight], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 80, height: 80)
                        Text(store.userProfile.initials)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    ZStack {
                        Circle()
                            .fill(Color.background)
                            .frame(width: 26, height: 26)
                        Circle()
                            .fill(Color.ember)
                            .frame(width: 24, height: 24)
                        Image(systemName: "pencil")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }

                // Name + Edit
                VStack(spacing: 6) {
                    Text(store.userProfile.name)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.textPrimary)
                    
                    Text("Tap to edit profile")
                        .font(.system(size: 12))
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
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.borderColor, lineWidth: 1))
            .padding(.bottom, 8)
        }
        .buttonStyle(.plain)
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
    let timeRange: ProgressPageView.TimeRange
    @State private var appear = false
    
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
                QuickStatCard(icon: "figure.strengthtraining.traditional", value: "24", label: "Workouts", trend: "+12%", trendUp: true, appeared: appear, delay: 0.1)
                QuickStatCard(icon: "flame.fill", value: "18.5k", label: "Calories", trend: "+8%", trendUp: true, appeared: appear, delay: 0.15)
                QuickStatCard(icon: "timer", value: "42", label: "Avg Time", trend: "-5m", trendUp: false, appeared: appear, delay: 0.2)
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
    let trend: String
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
    @State private var appear = false
    
    var body: some View {
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
                            Text("7")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                            Text("days")
                                .font(.system(size: 8))
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current Streak")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.textPrimary)
                        Text("Keep it up! 3 more days to beat your record.")
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
                
                // Milestones grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    MilestoneCard(icon: "trophy.fill", title: "100 Workouts", subtitle: "82/100", progress: 0.82, color: .ember)
                    MilestoneCard(icon: "flame.fill", title: "50k Calories", subtitle: "38.5k/50k", progress: 0.77, color: .warning)
                    MilestoneCard(icon: "figure.strengthtraining.traditional", title: "1000 Sets", subtitle: "743/1000", progress: 0.74, color: .steel)
                    MilestoneCard(icon: "chart.line.uptrend.xyaxis", title: "90 Day Streak", subtitle: "Best: 10", progress: 0.11, color: .success)
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
    
    var body: some View {
        NavigationView {
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
                
                VStack(spacing: 12) {
                    ShareOptionButton(icon: "photo.fill", title: "Share as Image", subtitle: "Create a shareable graphic")
                    ShareOptionButton(icon: "text.quote", title: "Share as Text", subtitle: "Copy stats to clipboard")
                    ShareOptionButton(icon: "link", title: "Share Link", subtitle: "Share your profile")
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

struct ShareOptionButton: View {
    let icon: String
    let title: String
    let subtitle: String
    
    var body: some View {
        Button(action: {}) {
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
        .buttonStyle(.plain)
    }
}
// MARK: - Profile Editor View

struct ProfileEditorView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var store: AppStore
    @State private var name = ""
    @State private var age = ""
    @State private var weight = ""
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Avatar editor
                    VStack(spacing: 12) {
                        ZStack(alignment: .bottomTrailing) {
                            Circle()
                                .fill(LinearGradient(colors: [.ember, .emberLight], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 100, height: 100)
                                .overlay(
                                    Text(store.userProfile.initials)
                                        .font(.system(size: 36, weight: .bold))
                                        .foregroundColor(.white)
                                )
                            
                            Button(action: {}) {
                                ZStack {
                                    Circle()
                                        .fill(Color.ember)
                                        .frame(width: 32, height: 32)
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        
                        Text("Change Photo")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.ember)
                    }
                    .padding(.top, 20)
                    
                    // Form fields
                    VStack(spacing: 16) {
                        ProfileFieldRow(label: "Name", placeholder: store.userProfile.name, text: $name)
                        ProfileFieldRow(label: "Age", placeholder: "28", text: $age, keyboardType: .numberPad)
                        ProfileFieldRow(label: "Weight", placeholder: "175 lbs", text: $weight)
                    }
                    
                    // Save button
                    Button(action: { dismiss() }) {
                        Text("Save Changes")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.ember)
                            .cornerRadius(14)
                    }
                    .padding(.top, 12)
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
    @State private var selectedStyle: CoachingStyle = .pushHard
    
    var body: some View {
        NavigationView {
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
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
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
                    
                    Button(action: { dismiss() }) {
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
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.ember)
                }
            }
        }
    }
}

