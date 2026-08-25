import SwiftUI
import UIKit
import ForgeCore

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
