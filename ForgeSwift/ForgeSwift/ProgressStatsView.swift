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

        return StatsMosaic.snapshot(
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
            )
        )
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TODAY’S MOSAIC")
                        .font(FDS.TypeScale.Dynamic.micro)
                        .foregroundColor(HudChrome.plate)
                        .tracking(1.6)
                    Text(
                        snap.closing
                            ? "\(snap.dayPercent)% · one track left"
                            : "\(snap.dayPercent)% · \(snap.doneCount)/5 tracks"
                    )
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundColor(.textPrimary)
                }
                Spacer()
                Button("Log") { showManual = true }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.ember)
                    .accessibilityLabel("Log today’s stats manually")
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(snap.tiles) { tile in
                    Button {
                        store.openChat(with: tile.ariaPrompt, voice: false)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(tile.track.title.uppercased())
                                    .font(FDS.TypeScale.Dynamic.micro)
                                    .foregroundColor(HudChrome.plate)
                                    .tracking(1.1)
                                Spacer()
                                Circle()
                                    .fill(
                                        tile.almostThere
                                            ? HudChrome.plate
                                            : (tile.source == .empty ? HudChrome.miss.opacity(0.35) : Color.ember)
                                    )
                                    .frame(width: 6, height: 6)
                            }
                            Text(tile.headline)
                                .font(FDS.TypeScale.Dynamic.metric)
                                .foregroundColor(.textPrimary)
                            Text(tile.almostThere ? "Almost there · \(tile.detail)" : tile.detail)
                                .font(FDS.TypeScale.Dynamic.micro)
                                .foregroundColor(tile.almostThere ? HudChrome.plate : .textTertiary)
                            ProgressView(value: tile.progress)
                                .tint(tile.almostThere ? HudChrome.plate : (tile.source == .empty ? HudChrome.miss : HudChrome.plate))
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.surfaceElevated.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: FDS.Radius.md)
                                .stroke(
                                    (tile.almostThere ? HudChrome.plate : HudChrome.miss)
                                        .opacity(tile.source == .empty ? 0.16 : (tile.almostThere ? 0.50 : 0.32)),
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(tile.track.title), \(tile.headline), \(tile.detail)")
                    .accessibilityHint("Ask ARIA about this track")
                }
            }

            Button {
                store.openChat(with: snap.mosaicLine, voice: false)
            } label: {
                Text("Ask ARIA about this picture")
                    .font(FDS.TypeScale.Dynamic.body.weight(.semibold))
                    .foregroundColor(.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.ember.opacity(0.16))
                    .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: FDS.Radius.md)
                            .stroke(HudChrome.plate.opacity(0.28), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ask ARIA about today’s mosaic")
        }
        .padding(16)
        .background(Color.surface.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FDS.Radius.lg)
                .stroke(HudChrome.plate.opacity(0.22), lineWidth: 1)
        )
        .sheet(isPresented: $showManual) {
            StatsManualEntrySheet()
                .environmentObject(store)
        }
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
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)
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
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
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
                    .font(FDS.TypeScale.Dynamic.micro)
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
                            .font(FDS.TypeScale.Dynamic.micro)
                    }
                    .foregroundColor(trendUp ? .success : .ember)
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background((trendUp ? Color.success : Color.ember).opacity(0.12))
                    .cornerRadius(6)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(FDS.TypeScale.Dynamic.metric)
                    .foregroundColor(.textPrimary)

                Text(label)
                    .font(FDS.TypeScale.Dynamic.micro)
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
        .overlay(RoundedRectangle(cornerRadius: FDS.Radius.md).stroke(Color.borderColor.opacity(0.5), lineWidth: 1))
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
        let workoutCount = store.workoutHistory.count
        let workoutTarget = nextTarget(above: workoutCount, ladder: [10, 25, 50, 100, 250, 500])
        let totalVolume = store.workoutHistory.reduce(0) { $0 + $1.volume }
        let volumeTarget = nextTarget(above: totalVolume, ladder: [50_000, 100_000, 250_000, 500_000, 1_000_000])
        let prCount = store.personalRecords.count
        let prTarget = nextTarget(above: prCount, ladder: [3, 5, 10, 25, 50])
        let streakTarget = nextTarget(above: longestStreak, ladder: [7, 14, 30, 60, 90])

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.ember)
                Text("Your training")
                    .font(FDS.TypeScale.Dynamic.headline)
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
                                .font(FDS.TypeScale.Dynamic.headline)
                                .foregroundColor(.white)
                            Text(store.currentStreak == 1 ? "day" : "days")
                                .font(.system(size: 8))
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Days in a row")
                            .font(FDS.TypeScale.Dynamic.body.weight(.semibold))
                            .foregroundColor(.textPrimary)
                        Text(streakMessage)
                            .font(.system(size: 12))
                            .foregroundColor(.textSecondary)
                            .lineLimit(2)
                    }
                    Spacer()
                }
                .padding(14)
                .forgeGlassCard(cornerRadius: FDS.Radius.md, accent: .warning)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Days trained in a row: \(store.currentStreak). \(streakMessage)")

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
                        title: "\(streakTarget) days in a row",
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(color)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(FDS.TypeScale.Dynamic.micro)
                    .foregroundColor(color)
            }

            Text(title)
                .font(FDS.TypeScale.Dynamic.caption)
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
        .forgeGlassCard(cornerRadius: FDS.Radius.md, accent: Color.steel)
        .onAppear {
            if reduceMotion {
                animatedProgress = CGFloat(progress)
            } else {
                withAnimation(.easeOut(duration: 1.0).delay(0.3)) {
                    animatedProgress = CGFloat(progress)
                }
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
                        .font(FDS.TypeScale.Dynamic.title)
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
                    .forgeGlassCard(cornerRadius: FDS.Radius.md, accent: Color.steel)
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

                    ShareLink(item: store.exportUserDataJSON()) {
                        ShareOptionRow(
                            icon: "doc.text.fill",
                            title: "Export JSON",
                            subtitle: "Workouts, PRs, and today's metrics"
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
                    .font(FDS.TypeScale.Dynamic.body.weight(.semibold))
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
        .forgeGlassCard(cornerRadius: FDS.Radius.md, accent: Color.steel)
    }
}
