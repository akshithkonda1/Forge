import SwiftUI
import UIKit
import Charts

// MARK: - Wellbeing View

struct WellbeingView: View {
    @ObservedObject var vm: LifestyleViewModel

    var body: some View {
        VStack(spacing: 20) {
            DailyHabitsCard()
            MindfulnessCard(vm: vm)
            MindfulTrendCard(trend: vm.mindfulTrend)
            StressManagementCard(stats: vm.healthStats)
            SleepOptimizationCard(stats: vm.healthStats, metrics: vm.metrics)
        }
    }
}

// MARK: - Mindful Minutes Trend (Swift Charts)

struct MindfulTrendCard: View {
    let trend: [MindfulDay]

    private var total: Int { Int(trend.reduce(0) { $0 + $1.minutes }) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .font(.forgeDynamic(size: 16)).foregroundColor(Color.violet)
                    Text("Mindful Minutes").font(.forgeDynamic(size: 18, weight: .bold)).foregroundColor(.textPrimary)
                }
                Spacer()
                Text("\(total) min this week")
                    .font(.forgeDynamic(size: 12, weight: .semibold)).foregroundColor(.textTertiary)
            }

            if trend.isEmpty || trend.allSatisfy({ $0.minutes == 0 }) {
                Text("No mindful sessions logged this week. Even 5 minutes a day supports recovery.")
                    .font(.forgeDynamic(size: 13)).foregroundColor(.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                Chart(trend) { day in
                    BarMark(
                        x: .value("Day", day.date, unit: .day),
                        y: .value("Minutes", day.minutes)
                    )
                    .foregroundStyle(Color.violet.gradient)
                    .cornerRadius(4)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.narrow)).font(.forgeDynamic(size: 9))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine()
                        AxisValueLabel().font(.forgeDynamic(size: 9))
                    }
                }
                .frame(height: 120)
            }
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.05), radius: 14, y: 5)
    }
}

// MARK: - QOL Trend (Swift Charts)

struct QOLTrendCard: View {
    let history: [QOLDay]

    private var recent: [QOLDay] { Array(history.suffix(30)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.forgeDynamic(size: 16)).foregroundColor(.ember)
                    Text("Quality of Life Trend")
                        .font(.forgeDynamic(size: 18, weight: .bold)).foregroundColor(.textPrimary)
                }
                Spacer()
                if let last = recent.last {
                    Text("\(last.score)/100")
                        .font(.forgeDynamic(size: 12, weight: .semibold)).foregroundColor(.ember)
                }
            }

            if recent.count < 2 {
                Text("Your QOL trend appears after a couple of days of tracking.")
                    .font(.forgeDynamic(size: 13)).foregroundColor(.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                Chart(recent) { day in
                    AreaMark(
                        x: .value("Day", day.date, unit: .day),
                        y: .value("QOL", day.score)
                    )
                    .foregroundStyle(LinearGradient(
                        colors: [Color.ember.opacity(0.25), Color.ember.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Day", day.date, unit: .day),
                        y: .value("QOL", day.score)
                    )
                    .foregroundStyle(Color.ember)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)
                }
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 50, 100]) { _ in
                        AxisGridLine()
                        AxisValueLabel().font(.forgeDynamic(size: 9))
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .font(.forgeDynamic(size: 9))
                    }
                }
                .frame(height: 140)
            }
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.05), radius: 14, y: 5)
    }
}

struct DailyHabitsCard: View {
    @State private var habits: [DailyHabit] = LifestyleWellbeingStore.loadHabits()

    var completed: Int { habits.filter(\.done).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Daily Habits")
                    .font(.forgeDynamic(size: 18, weight: .bold)).foregroundColor(.textPrimary)
                Spacer()
                Text("\(completed)/\(habits.count)")
                    .font(.forgeDynamic(size: 13, weight: .bold)).foregroundColor(.ember)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.ember.opacity(0.12)).cornerRadius(8)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.borderColor.opacity(0.3))
                    Capsule().fill(LinearGradient(colors: [.ember, .ember.opacity(0.7)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(completed) / CGFloat(habits.count))
                        .animation(.spring(response: 0.6, dampingFraction: 0.72), value: completed)
                }
            }
            .frame(height: 6)
            .padding(.bottom, 4)

            VStack(spacing: 2) {
                ForEach($habits) { $habit in
                    HabitRow(name: habit.name, isDone: habit.done) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
                            habit.done.toggle()
                        }
                        LifestyleWellbeingStore.saveHabits(habits)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
            }

            // Streak
            HStack(spacing: 8) {
                Image(systemName: "flame.fill").foregroundColor(.ember)
                Text("\(LifestyleWellbeingStore.habitStreak())-day streak").font(.forgeDynamic(size: 15, weight: .bold)).foregroundColor(.textPrimary)
                Spacer()
                Text("Keep it up 🔥").font(.forgeDynamic(size: 13)).foregroundColor(.textSecondary)
            }
            .padding(14)
            .background(Color.ember.opacity(0.08))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.ember.opacity(0.2), lineWidth: 1))
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
    }
}

struct HabitRow: View {
    let name: String
    let isDone: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(isDone ? Color.ember : Color.borderColor, lineWidth: 1.5)
                        .frame(width: 24, height: 24)
                    if isDone {
                        Circle().fill(Color.ember).frame(width: 24, height: 24)
                        Image(systemName: "checkmark").font(.forgeDynamic(size: 11, weight: .bold)).foregroundColor(.white)
                    }
                }
                Text(name)
                    .font(.forgeDynamic(size: 14, weight: .medium))
                    .foregroundColor(isDone ? .textTertiary : .textPrimary)
                    .strikethrough(isDone, color: .textTertiary)
                Spacer()
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}

struct MindfulnessCard: View {
    @ObservedObject var vm: LifestyleViewModel
    @State private var isRunning = false
    @State private var remainingSeconds = 300
    @State private var timer: Timer?

    private var todayLabel: String { "\(max(vm.mindfulMinutesToday, 0)) min" }
    private var weekLabel: String { "\(max(vm.mindfulMinutesWeek, 0)) min" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Mindfulness").font(.forgeDynamic(size: 18, weight: .bold)).foregroundColor(.textPrimary)

            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text(todayLabel).font(.forgeDynamic(size: 26, weight: .bold)).foregroundColor(.textPrimary)
                    Text("Today").font(.forgeDynamic(size: 12, weight: .medium)).foregroundColor(.textSecondary)
                }
                .frame(maxWidth: .infinity)
                Divider().frame(height: 40).background(Color.borderColor)
                VStack(spacing: 4) {
                    Text(weekLabel).font(.forgeDynamic(size: 26, weight: .bold)).foregroundColor(.ember)
                    Text("This week").font(.forgeDynamic(size: 12, weight: .medium)).foregroundColor(.textSecondary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 8)

            if isRunning {
                Text(timeString(remainingSeconds))
                    .font(.forgeDynamic(size: 34, weight: .black, design: .rounded))
                    .foregroundColor(.ember)
                    .frame(maxWidth: .infinity)
            }

            Button {
                if isRunning {
                    stopSession(logged: remainingSeconds < 300)
                } else {
                    startSession()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isRunning ? "stop.fill" : "play.fill").font(.forgeDynamic(size: 14))
                    Text(isRunning ? "End Session" : "Start 5-Min Meditation")
                        .font(.forgeDynamic(size: 15, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(LinearGradient.ember)
                .cornerRadius(14)
                .shadow(color: Color.ember.opacity(0.35), radius: 10, y: 4)
            }
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
        .onDisappear { timer?.invalidate() }
    }

    private func startSession() {
        remainingSeconds = 300
        isRunning = true
        timer?.invalidate()
        let newTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if remainingSeconds > 0 {
                remainingSeconds -= 1
            } else {
                stopSession(logged: true)
            }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    private func stopSession(logged: Bool) {
        timer?.invalidate()
        timer = nil
        isRunning = false
        guard logged else { return }
        let minutes = max(1, Int(ceil(Double(300 - remainingSeconds) / 60.0)))
        Task { await vm.logMindfulSession(minutes: minutes) }
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct StressManagementCard: View {
    let stats: DailyHealthStats?
    @State private var selectedLevel = LifestyleWellbeingStore.loadStressLevel()

    private let levels: [(emoji: String, label: String, color: Color)] = [
        ("😌", "Low",    .success),
        ("😐", "Medium", .warning),
        ("😰", "High",   .danger),
    ]

    private var stressTip: String {
        if let stats, stats.hrv > 0, stats.hrv < 40 {
            return "HRV is \(Int(stats.hrv))ms — try 5-minute box breathing or a 10-minute walk."
        }
        switch selectedLevel {
        case 0: return "Great baseline — maintain with light movement and consistent sleep."
        case 2: return "High stress detected — prioritize recovery, hydration, and an earlier bedtime."
        default: return "Try: 5-minute box breathing or a short walk to reset your nervous system."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Stress Management").font(.forgeDynamic(size: 18, weight: .bold)).foregroundColor(.textPrimary)

            HStack(spacing: 12) {
                ForEach(Array(levels.enumerated()), id: \.offset) { i, level in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selectedLevel = i }
                        LifestyleWellbeingStore.saveStressLevel(i)
                    } label: {
                        VStack(spacing: 8) {
                            Text(level.emoji).font(.forgeDynamic(size: 30))
                            Text(level.label)
                                .font(.forgeDynamic(size: 11, weight: .semibold))
                                .foregroundColor(selectedLevel == i ? level.color : .textSecondary)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(selectedLevel == i ? level.color.opacity(0.12) : Color.surfaceElevated)
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(selectedLevel == i ? level.color : Color.borderColor.opacity(0.4), lineWidth: selectedLevel == i ? 1.5 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill").font(.forgeDynamic(size: 12)).foregroundColor(.warning)
                Text(stressTip)
                    .font(.forgeDynamic(size: 13)).foregroundColor(.textSecondary).italic()
            }
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
        .onAppear {
            if let stats, stats.hrv > 0 {
                selectedLevel = stats.hrv < 35 ? 2 : stats.hrv < 50 ? 1 : 0
            }
        }
    }
}

struct SleepOptimizationCard: View {
    let stats: DailyHealthStats?
    let metrics: LifestyleMetrics

    private var tips: [(icon: String, tip: String, color: Color)] {
        let sleepGap = max(0, metrics.sleepTarget - (stats?.sleepHours ?? metrics.sleepAverage))
        var generated: [(icon: String, tip: String, color: Color)] = [
            ("moon.fill", "Aim for \(String(format: "%.1f", metrics.sleepTarget))h tonight (\(String(format: "%.1f", sleepGap))h to go)", .steel),
            ("iphone.slash", "No screens 45 min before bed", .warning),
            ("thermometer.medium", "Keep room at 65–68°F", .success),
        ]
        if (stats?.caffeine ?? 0) > 200 {
            generated.append(("cup.and.saucer.fill", "Caffeine is elevated today — cut off by 2 PM", .danger))
        } else {
            generated.append(("cup.and.saucer.fill", "No caffeine after 2 PM", .danger))
        }
        return generated
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sleep Optimization").font(.forgeDynamic(size: 18, weight: .bold)).foregroundColor(.textPrimary)

            VStack(spacing: 10) {
                ForEach(tips, id: \.tip) { tip in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(tip.color.opacity(0.12)).frame(width: 36, height: 36)
                            Image(systemName: tip.icon).font(.forgeDynamic(size: 15)).foregroundColor(tip.color)
                        }
                        Text(tip.tip).font(.forgeDynamic(size: 13, weight: .medium)).foregroundColor(.textSecondary)
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.surfaceElevated).cornerRadius(12)
                }
            }
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
    }
}

// MARK: - AI Insights Modal (fixed: removed unused scrollOffset)

struct AIInsightsModal: View {
    @Binding var isPresented: Bool
    let recommendations: [AIRecommendation]
    let metrics: LifestyleMetrics
    let stats: DailyHealthStats?
    var summary: String? = nil       // live ARIA narrative (nil → heuristic list only)
    var isLive: Bool = false

    private var insights: [LifestyleInsight] {
        var items: [LifestyleInsight] = recommendations.map { rec in
            LifestyleInsight(
                title: rec.title,
                insight: rec.description,
                action: rec.category.rawValue,
                color: rec.impact.color
            )
        }

        items.append(LifestyleInsight(
            title: "Quality of Life Score",
            insight: "Your composite QOL is \(metrics.qualityOfLifeScore)/100 with physical health at \(metrics.physicalHealth) and mental wellbeing at \(metrics.mentalWellbeing).",
            action: "View breakdown",
            color: .ember
        ))

        if let stats {
            if stats.steps < 8000 {
                items.append(LifestyleInsight(
                    title: "Movement Opportunity",
                    insight: "You're at \(stats.steps.formatted()) steps. A 15-minute walk adds roughly 2,000 steps and improves afternoon energy.",
                    action: "Plan walk",
                    color: .steel
                ))
            }
            if stats.sleepHours < 7.5 {
                items.append(LifestyleInsight(
                    title: "Sleep Debt Alert",
                    insight: "Last night: \(String(format: "%.1f", stats.sleepHours))h. Extending sleep toward 8h improves HRV and training readiness.",
                    action: "Set bedtime",
                    color: Color.violet
                ))
            }
            if stats.hrv < 45 {
                items.append(LifestyleInsight(
                    title: "Recovery Priority",
                    insight: "HRV at \(Int(stats.hrv))ms suggests elevated stress load. Favor mobility, hydration, and lower-intensity training today.",
                    action: "Adjust intensity",
                    color: .warning
                ))
            }
        }

        return items
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 0) {
                    // Drag handle
                    Capsule().fill(Color.textTertiary.opacity(0.5))
                        .frame(width: 36, height: 4).padding(.top, 14).padding(.bottom, 20)

                    HStack {
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles").font(.forgeDynamic(size: 22)).foregroundColor(.ember)
                            Text("AI Life Insights").font(.forgeDynamic(size: 24, weight: .bold)).foregroundColor(.textPrimary)
                        }
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.forgeDynamic(size: 28)).foregroundColor(.textTertiary.opacity(0.7))
                        }
                        .accessibilityLabel("Close")
                    }
                    .padding(.horizontal, 20).padding(.bottom, 20)

                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 14) {
                            if let summary {
                                ariaBanner(summary)
                            }
                            ForEach(insights) { insight in
                                AIInsightCard(insight: insight)
                            }
                        }
                        .padding(.horizontal, 20).padding(.bottom, 40)
                    }
                }
                .frame(maxHeight: UIScreen.main.bounds.height * 0.78)
                .background(Color.surface)
                .cornerRadius(28, corners: [.topLeft, .topRight])
            }
        }
    }

    @ViewBuilder
    private func ariaBanner(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").font(.forgeDynamic(size: 13)).foregroundColor(.ember)
                Text(isLive ? "ARIA · LIVE" : "ARIA")
                    .font(.forgeDynamic(size: 11, weight: .bold)).tracking(0.5).foregroundColor(.ember)
                Spacer()
            }
            Text(text)
                .font(.forgeDynamic(size: 14))
                .foregroundColor(.textPrimary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color.ember.opacity(0.12), Color.ember.opacity(0.04)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.ember.opacity(0.25), lineWidth: 1))
    }

    private func dismiss() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { isPresented = false }
    }
}

struct LifestyleInsight: Identifiable {
    let id = UUID()
    let title: String; let insight: String; let action: String; let color: Color
}

struct AIInsightCard: View {
    let insight: LifestyleInsight
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle().fill(insight.color).frame(width: 8, height: 8)
                    .shadow(color: insight.color.opacity(0.6), radius: 4)
                Text(insight.title).font(.forgeDynamic(size: 16, weight: .bold)).foregroundColor(.textPrimary)
                Spacer()
            }
            Text(insight.insight)
                .font(.forgeDynamic(size: 13)).foregroundColor(.textSecondary).lineSpacing(4)
                .lineLimit(expanded ? nil : 3)
                .animation(.easeInOut(duration: 0.25), value: expanded)
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right.circle.fill").font(.forgeDynamic(size: 13))
                    Text(insight.action).font(.forgeDynamic(size: 13, weight: .semibold))
                }
                .foregroundColor(insight.color)
            }
        }
        .padding(16)
        .background(Color.surfaceElevated)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(insight.color.opacity(0.2), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) { expanded.toggle() }
        }
    }
}

