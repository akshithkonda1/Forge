import SwiftUI
import UIKit
import ForgeCore

/// Manual overlay for the Progress mosaic. Same day only — Health stays the
/// ingest path; this is the honest write when the watch was off.
enum StatsManualLog {
    static let storageKey = "forge.stats.manual.v1"

    struct Entry: Codable, Equatable {
        var dayKey: String
        var sleepHours: Double?
        var waterGlasses: Double?
        var steps: Int?
        var habitsDone: Int?
    }

    static func dayKey(now: Date = Date(), calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func load(defaults: UserDefaults = .standard, now: Date = Date()) -> Entry {
        let key = dayKey(now: now)
        guard let data = defaults.data(forKey: storageKey),
              let entry = try? JSONDecoder().decode(Entry.self, from: data),
              entry.dayKey == key else {
            return Entry(dayKey: key)
        }
        return entry
    }

    static func save(_ entry: Entry, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(entry) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

struct StatsMosaicCard: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject private var health = HealthKitManager.shared
    @State private var showManual = false
    @Environment(\.dynamicTypeSize) private var typeSize

    private var mosaic: StatsMosaic.Snapshot {
        let manual = StatsManualLog.load()
        let sleepHours: Double?
        let sleepManual: Bool
        if let logged = manual.sleepHours {
            sleepHours = logged
            sleepManual = true
        } else if store.dailyMetrics.totalSleep > 0 {
            sleepHours = Double(store.dailyMetrics.totalSleep) / 60
            sleepManual = false
        } else if let hours = health.todayStats?.sleepHours, hours > 0 {
            sleepHours = hours
            sleepManual = false
        } else {
            sleepHours = nil
            sleepManual = false
        }

        let water: Double?
        let waterManual: Bool
        if let logged = manual.waterGlasses {
            water = logged
            waterManual = true
        } else if let glasses = health.todayStats?.water, glasses > 0 {
            water = glasses
            waterManual = false
        } else {
            water = nil
            waterManual = false
        }

        let steps: Int?
        let stepsManual: Bool
        if let logged = manual.steps {
            steps = logged
            stepsManual = true
        } else if store.dailyMetrics.steps > 0 {
            steps = store.dailyMetrics.steps
            stepsManual = false
        } else if let healthSteps = health.todayStats?.steps, healthSteps > 0 {
            steps = healthSteps
            stepsManual = false
        } else {
            steps = nil
            stepsManual = false
        }

        let today: String = {
            let f = DateFormatter()
            f.calendar = Calendar.current
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: Date())
        }()
        let contribution = HobbyFit.dayContribution(
            hobbies: store.userProfile.lifestyleProfile.hobbies,
            todayISO: today
        )
        let input = HobbyFit.applyToMosaic(
            StatsMosaic.Input(
                sleepHours: sleepHours,
                sleepManual: sleepManual,
                workoutsThisWeek: workoutsThisWeek,
                workoutGoal: 3,
                waterGlasses: water,
                waterManual: waterManual,
                steps: steps,
                stepsManual: stepsManual,
                habitsDone: manual.habitsDone ?? 0,
                habitsGoal: 3
            ),
            contribution: contribution
        )
        let live = StatsMosaic.snapshot(input)
        return ForgeTutorial.mosaic(for: store.mosaicTutorial, live: live)
    }

    private var workoutsThisWeek: Int {
        let calendar = Calendar.current
        let start = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
        return store.workoutHistory.filter { workout in
            guard let date = ForgeDates.parse(workout.date) else { return false }
            return date >= start
        }.count
    }


    var body: some View {
        let snap = mosaic
        VStack(alignment: .leading, spacing: ForgeLayout.heroGap) {
            mosaicHeader(snap)
            mosaicTiles(snap.tiles)
            ForgeSecondaryButton(title: "Ask ARIA about this picture", accent: .ember) {
                if store.mosaicTutorial.isComplete {
                    store.openChat(with: snap.mosaicLine, voice: false)
                } else {
                    store.recordTutorial(.askedAria)
                }
            }
            .accessibilityLabel("Ask ARIA about today’s mosaic")
        }
        .forgePlate(energy: ForgeProgressChrome.plate)
        .accessibilityElement(children: .contain)
        .sheet(isPresented: $showManual) {
            StatsManualEntrySheet()
                .environmentObject(store)
        }
    }

    private func mosaicHeader(_ snap: StatsMosaic.Snapshot) -> some View {
        let headline = snap.closing
            ? "\(snap.dayPercent)% · one track left"
            : "\(snap.dayPercent)% · \(snap.doneCount)/5 tracks"
        return ForgeAdaptiveStack(spacing: FDS.Spacing.sm, alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text("TODAY’S MOSAIC")
                    .forgeSectionLabel(tint: ForgeProgressChrome.plate)
                    .accessibilityAddTraits(.isHeader)
                Text(headline)
                    .font(HomeType.sessionTitle)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ForgeTextLink(title: "Log", accent: .ember) {
                showManual = true
            }
            .accessibilityLabel("Log today’s stats manually")
        }
    }

    @ViewBuilder
    private func mosaicTiles(_ tiles: [StatsMosaic.Tile]) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: ForgeLayout.tileGap) {
                ForEach(tiles) { tile in
                    mosaicTile(tile)
                }
            }
        } else {
            Grid(horizontalSpacing: ForgeLayout.tileGap, verticalSpacing: ForgeLayout.tileGap) {
                ForEach(Array(stride(from: 0, to: tiles.count, by: 2)), id: \.self) { start in
                    GridRow {
                        mosaicTile(tiles[start])
                            .gridCellColumns(start + 1 < tiles.count ? 1 : 2)
                        if start + 1 < tiles.count {
                            mosaicTile(tiles[start + 1])
                        }
                    }
                }
            }
        }
    }

    private func tileDotColor(_ tile: StatsMosaic.Tile) -> Color {
        if tile.almostThere { return ForgeProgressChrome.plate }
        return tile.source == .empty ? ForgeProgressChrome.miss.opacity(0.35) : Color.ember
    }

    private func tileBarTint(_ tile: StatsMosaic.Tile) -> Color {
        if !tile.almostThere && tile.source == .empty { return ForgeProgressChrome.miss }
        return ForgeProgressChrome.plate
    }

    /// Normal tiles keep the well's own white edge; only almost-there and
    /// empty tiles add a colored one.
    private func tileEdge(_ tile: StatsMosaic.Tile) -> Color {
        if tile.almostThere { return ForgeProgressChrome.plate.opacity(0.50) }
        if tile.source == .empty { return ForgeProgressChrome.miss.opacity(0.16) }
        return Color.clear
    }

    private func mosaicTile(_ tile: StatsMosaic.Tile) -> some View {
        Button {
            store.recordTutorial(.focusedTile)
            store.recordTutorial(.expandedTile)
            store.openChat(with: tile.ariaPrompt, voice: false)
        } label: {
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                HStack(alignment: .firstTextBaseline, spacing: FDS.Spacing.xs) {
                    Text(tile.track.title)
                        .font(HomeType.micro)
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Circle()
                        .fill(tileDotColor(tile))
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
                Text(tile.headline)
                    .font(HomeType.metric)
                    .foregroundStyle(Color.textPrimary)
                    .forgeSingleLine()
                    .contentTransition(.numericText())
                Text(tile.almostThere ? "Almost there · \(tile.detail)" : tile.detail)
                    .font(HomeType.micro)
                    .foregroundStyle(tile.almostThere ? ForgeProgressChrome.plate : Color.textTertiary)
                    .lineLimit(2)
                Spacer(minLength: FDS.Spacing.xs)
                ForgeProgressBar(fraction: tile.progress, tint: tileBarTint(tile), height: 5)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .forgeWell()
            .overlay(
                RoundedRectangle(cornerRadius: ForgeLayout.innerRadius, style: .continuous)
                    .stroke(tileEdge(tile), lineWidth: ForgeUX.stroke)
            )
        }
        .buttonStyle(ForgePressStyle())
        .accessibilityLabel("\(tile.track.title), \(tile.headline), \(tile.detail)")
        .accessibilityValue("\(Int((tile.progress * 100).rounded())) percent")
        .accessibilityHint("Ask ARIA about this track")
    }
}

struct StatsManualEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entry = StatsManualLog.load()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Apple Health is the ingest path. Log here only when the day is missing — lifestyle numbers, not a clinical chart.")
                        .font(HomeType.body)
                        .foregroundStyle(Color.textSecondary)
                        .forgeWrapping()
                }
                Section("Sleep (hours)") {
                    TextField("7.5", value: $entry.sleepHours, format: .number)
                        .keyboardType(.decimalPad)
                }
                Section("Water (glasses)") {
                    TextField("8", value: $entry.waterGlasses, format: .number)
                        .keyboardType(.decimalPad)
                }
                Section("Steps") {
                    TextField("8000", value: $entry.steps, format: .number)
                        .keyboardType(.numberPad)
                }
                Section("Habits marked") {
                    Stepper(value: Binding(
                        get: { entry.habitsDone ?? 0 },
                        set: { entry.habitsDone = $0 }
                    ), in: 0...3) {
                        Text("\(entry.habitsDone ?? 0) of 3")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.background.ignoresSafeArea())
            .navigationTitle("Log today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var next = entry
                        next.dayKey = StatsManualLog.dayKey()
                        StatsManualLog.save(next)
                        ForgeHaptics.play(.success)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }
}

struct QuickStatsOverviewView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let timeRange: ProgressPageView.TimeRange

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
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("Overview", meta: timeRange.rawValue, tint: .ember)

            ForgeStatGrid(columns: 3) {
                QuickStatCard(icon: "figure.strengthtraining.traditional", value: workoutCountText, label: "Workouts", trend: nil, trendUp: true)
                QuickStatCard(icon: "flame.fill", value: caloriesText, label: "Calories", trend: nil, trendUp: true)
                QuickStatCard(icon: "timer", value: avgDurationText, label: "Avg Min", trend: nil, trendUp: true)
            }
        }
        .forgeContentCard(tint: .ember)
        .animation(reduceMotion ? nil : ForgeMotion.smooth, value: timeRange)
    }
}

/// A stat cell in the Home well. Callers place the cells in one card via
/// `ForgeStatGrid`. `appeared` and `delay` are kept for source compatibility;
/// the entrance cascade they drove was retired.
struct QuickStatCard: View {
    let icon: String
    let value: String
    let label: String
    let trend: String?
    let trendUp: Bool
    var appeared: Bool = false
    var delay: Double = 0

    private var trendTint: Color {
        trendUp ? Color.vitality : ForgeProgressChrome.miss
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.sm) {
            HStack(alignment: .top, spacing: FDS.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.ember)
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                if let trend, !trend.isEmpty {
                    trendChip(trend)
                }
            }

            VStack(alignment: .leading, spacing: ForgeLayout.labelValueGap) {
                Text(value)
                    .font(HomeType.metric)
                    .foregroundStyle(Color.textPrimary)
                    .forgeSingleLine()
                    .contentTransition(.numericText())
                Text(label)
                    .font(HomeType.micro)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .forgeWell()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spokenLabel)
    }

    private var spokenLabel: String {
        guard let trend, !trend.isEmpty else { return "\(label) \(value)" }
        return "\(label) \(value), \(trend)"
    }

    private func trendChip(_ trend: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: trendUp ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 9, weight: .bold))
                .accessibilityHidden(true)
            Text(trend)
                .font(HomeType.micro)
                .lineLimit(1)
        }
        .foregroundStyle(trendTint)
        .padding(.horizontal, FDS.Spacing.sm)
        .padding(.vertical, FDS.Spacing.xs)
        .background(Capsule().fill(trendTint.opacity(0.12)))
        .overlay(Capsule().stroke(trendTint.opacity(0.28), lineWidth: ForgeUX.hairline))
    }
}

struct StreaksAndMilestonesView: View {
    @EnvironmentObject var store: AppStore

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
            return "No session logged today. That’s fine — the stretch stays open."
        }
        if current >= best {
            return "Longest stretch so far. A fact, not a record to defend."
        }
        return "Longest stretch: \(best) days. Consecutive days are a note, not a ladder."
    }

    private func nextTarget(above value: Int, ladder: [Int]) -> Int {
        ladder.first { value < $0 } ?? ladder[ladder.count - 1]
    }

    private func compact(_ value: Int) -> String {
        value >= 1000 ? String(format: "%.1fk", Double(value) / 1000) : String(value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("Your training", tint: .ember)

            streakRow

            Divider().background(Color.white.opacity(0.08))

            milestoneRows
        }
        .forgeContentCard(tint: .ember)
    }

    private var streakCount: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text("\(store.currentStreak)")
                .font(HomeType.metric)
                .foregroundStyle(Color.textPrimary)
                .forgeSingleLine()
                .contentTransition(.numericText())
            Text(store.currentStreak == 1 ? "day" : "days")
                .font(HomeType.micro)
                .foregroundStyle(Color.textTertiary)
                .lineLimit(1)
        }
        .layoutPriority(1)
    }

    private var streakRow: some View {
        ForgeAdaptiveStack(spacing: ForgeLayout.rowGap, alignment: .top) {
            HStack(alignment: .top, spacing: ForgeLayout.rowGap) {
                ForgeIconWell(systemImage: "flame.fill", tint: .ember)
                VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                    Text("Days in a row")
                        .font(HomeType.status)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(2)
                    Text(streakMessage)
                        .font(HomeType.body)
                        .foregroundStyle(Color.textSecondary)
                        .forgeWrapping()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            streakCount
        }
        .padding(.vertical, ForgeLayout.rowVerticalPadding)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Days trained in a row: \(store.currentStreak). \(streakMessage)")
    }

    // Milestones — next goal scales with actual progress
    private var milestoneRows: some View {
        let workoutCount = store.workoutHistory.count
        let workoutTarget = nextTarget(above: workoutCount, ladder: [10, 25, 50, 100, 250, 500])
        let totalVolume = store.workoutHistory.reduce(0) { $0 + $1.volume }
        let volumeTarget = nextTarget(above: totalVolume, ladder: [50_000, 100_000, 250_000, 500_000, 1_000_000])
        let prCount = store.personalRecords.count
        let prTarget = nextTarget(above: prCount, ladder: [3, 5, 10, 25, 50])
        let streakTarget = nextTarget(above: longestStreak, ladder: [7, 14, 30, 60, 90])

        return VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
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
                color: .ember
            )
            MilestoneCard(
                icon: "figure.strengthtraining.traditional",
                title: "\(prTarget) Personal Records",
                subtitle: "\(prCount)/\(prTarget)",
                progress: min(1, Double(prCount) / Double(prTarget)),
                color: .amber
            )
            MilestoneCard(
                icon: "chart.line.uptrend.xyaxis",
                title: "\(streakTarget) days in a row",
                subtitle: "Best: \(longestStreak)",
                progress: min(1, Double(longestStreak) / Double(streakTarget)),
                color: .ember
            )
        }
    }
}

/// One milestone as a compact row: label, count, progress bar. It sits inside
/// the shared "Your training" card, so it carries no chrome of its own.
struct MilestoneCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let progress: Double
    let color: Color
    @State private var animatedProgress: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
            ForgeAdaptiveStack(spacing: FDS.Spacing.sm, alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: FDS.Spacing.sm) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(color)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(HomeType.status)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(subtitle)
                    .font(HomeType.label)
                    .foregroundStyle(Color.textSecondary)
                    .monospacedDigit()
                    .forgeSingleLine()
                    .layoutPriority(1)
            }
            ForgeProgressBar(fraction: animatedProgress, tint: color, height: 5)
                .padding(.vertical, FDS.Spacing.xs)
        }
        .padding(.vertical, ForgeLayout.rowVerticalPadding)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(subtitle)")
        .accessibilityValue("\(Int((min(1, max(0, progress)) * 100).rounded())) percent")
        .onAppear {
            if reduceMotion {
                animatedProgress = progress
            } else {
                withAnimation(ForgeMotion.sweep.delay(0.12)) {
                    animatedProgress = progress
                }
            }
        }
    }
}

struct ShareProgressView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: ForgeLayout.sectionGap) {
                    shareIntro

                    // Preview of what gets shared
                    Text(summaryText)
                        .font(HomeType.body)
                        .foregroundStyle(Color.textSecondary)
                        .forgeWrapping()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .forgeContentCard(tint: .ember)

                    shareOptions
                }
                .forgeScreenInsets(top: ForgeLayout.groupBreak)
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
        .presentationDragIndicator(.visible)
    }

    private var shareIntro: some View {
        VStack(spacing: ForgeLayout.blockGap) {
            ForgeIconWell(systemImage: "square.and.arrow.up", tint: .ember, diameter: 56)

            VStack(spacing: ForgeLayout.pairGap) {
                Text("Share Your Progress")
                    .font(ForgeType.title)
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)
                    .forgeWrapping()
                    .accessibilityAddTraits(.isHeader)

                Text("Show off your achievements and inspire others!")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .forgeWrapping()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var shareOptions: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            ShareLink(item: summaryText) {
                ShareOptionRow(icon: "square.and.arrow.up", title: "Share", subtitle: "Send your stats anywhere")
            }
            .buttonStyle(.plain)

            Button {
                UIPasteboard.general.string = summaryText
                if reduceMotion {
                    copied = true
                } else {
                    withForgeMotion(ForgeMotion.smooth) { copied = true }
                }
                ForgeHaptics.play(.success)
            } label: {
                ShareOptionRow(
                    icon: copied ? "checkmark" : "doc.on.doc",
                    title: copied ? "Copied!" : "Copy to Clipboard",
                    subtitle: "Paste your stats anywhere"
                )
            }
            .buttonStyle(.plain)

            ShareLink(item: store.exportUserDataJSON()) {
                ShareOptionRow(
                    icon: "doc.text.fill",
                    title: "Export JSON",
                    subtitle: "Workouts, PRs, and today's metrics"
                )
            }
            .buttonStyle(.plain)
        }
        .forgeContentCard()
    }
}

/// Agenda-row anatomy for the share options. The rows live together in one
/// card, so a row carries no chrome of its own.
struct ShareOptionRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        ForgeListRow(
            icon: icon,
            iconColor: .ember,
            title: title,
            subtitle: subtitle,
            showChevron: true
        )
    }
}
