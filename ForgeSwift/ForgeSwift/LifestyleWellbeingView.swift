import SwiftUI
import Combine
import Charts
import UIKit
import ForgeCore

struct WellbeingView: View {
    @ObservedObject var vm: LifestyleViewModel

    var body: some View {
        VStack(spacing: 20) {
            HabitLoopListCard(vm: vm)
            DailyHabitsCard()
            MindfulnessCard(vm: vm)
            MindfulTrendCard(trend: vm.mindfulTrend)
            StressManagementCard(stats: vm.healthStats)
            SleepOptimizationCard(stats: vm.healthStats, metrics: vm.metrics)
        }
    }
}

struct MindfulTrendCard: View {
    let trend: [MindfulDay]

    private var total: Int { Int(trend.reduce(0) { $0 + $1.minutes }) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 16)).foregroundColor(Color(hex: "A855F7"))
                    Text("This week").font(.system(size: 18, weight: .semibold)).foregroundColor(.textPrimary)
                }
                Spacer()
                Text("\(total) min this week")
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(.textTertiary)
            }

            if trend.isEmpty || trend.allSatisfy({ $0.minutes == 0 }) {
                Text("No mindful sessions logged this week. Even 5 minutes a day supports recovery.")
                    .font(.system(size: 13)).foregroundColor(.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                Chart(trend) { day in
                    BarMark(
                        x: .value("Day", day.date, unit: .day),
                        y: .value("Minutes", day.minutes)
                    )
                    .foregroundStyle(Color(hex: "A855F7").gradient)
                    .cornerRadius(4)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.narrow)).font(.system(size: 9))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine()
                        AxisValueLabel().font(.system(size: 9))
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

struct QOLTrendCard: View {
    let history: [QOLDay]

    private var recent: [QOLDay] { Array(history.suffix(30)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 16)).foregroundColor(.ember)
                    Text("Quality of Life Trend")
                        .font(.system(size: 18, weight: .bold)).foregroundColor(.textPrimary)
                }
                Spacer()
                if let last = recent.last {
                    Text("\(last.score)/100")
                        .font(.system(size: 12, weight: .semibold)).foregroundColor(.ember)
                }
            }

            if recent.count < 2 {
                Text("Your QOL trend appears after a couple of days of tracking.")
                    .font(.system(size: 13)).foregroundColor(.textSecondary)
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
                        AxisValueLabel().font(.system(size: 9))
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .font(.system(size: 9))
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
                    .font(.system(size: 18, weight: .bold)).foregroundColor(.textPrimary)
                Spacer()
                Text("\(completed)/\(habits.count)")
                    .font(.system(size: 13, weight: .bold)).foregroundColor(.ember)
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
                Text("\(LifestyleWellbeingStore.habitStreak())-day streak").font(.system(size: 15, weight: .bold)).foregroundColor(.textPrimary)
                Spacer()
                Text("Keep it up 🔥").font(.system(size: 13)).foregroundColor(.textSecondary)
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
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundColor(.white)
                    }
                }
                Text(name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isDone ? .textTertiary : .textPrimary)
                    .strikethrough(isDone, color: .textTertiary)
                Spacer()
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}

private enum MindfulPractice: String, CaseIterable, Identifiable {
    case breathe, body, focus, rest
    var id: String { rawValue }

    var title: String {
        switch self {
        case .breathe: return "Breathe"
        case .body: return "Body"
        case .focus: return "Focus"
        case .rest: return "Rest"
        }
    }

    var line: String {
        switch self {
        case .breathe: return "Box breathing. Four in, hold, four out."
        case .body: return "A slow scan from the feet up."
        case .focus: return "One point. Come back when you wander."
        case .rest: return "Wind-down. Nothing to achieve."
        }
    }

    var symbol: String {
        switch self {
        case .breathe: return "wind"
        case .body: return "figure.mind.and.body"
        case .focus: return "circle.dotted"
        case .rest: return "moon.haze.fill"
        }
    }

    var tint: Color {
        switch self {
        case .breathe: return Color(hex: "67E8F9")
        case .body: return Color(hex: "A78BFA")
        case .focus: return Color.ember
        case .rest: return Color.aurora
        }
    }
}

struct MindfulnessCard: View {
    @ObservedObject var vm: LifestyleViewModel
    @State private var practice: MindfulPractice = .breathe
    @State private var minutes = 5
    @State private var isRunning = false
    @State private var remainingSeconds = 300
    @State private var inhale = false
    @State private var timer: Timer?

    private let lengths = [3, 5, 10, 15]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Mindfulness")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("\(max(vm.mindfulMinutesToday, 0)) min today  ·  \(max(vm.mindfulMinutesWeek, 0)) this week")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textTertiary)
            }

            HStack(spacing: 8) {
                ForEach(MindfulPractice.allCases) { item in
                    Button {
                        practice = item
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 14, weight: .semibold))
                            Text(item.title)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(practice == item ? practice.tint : .textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(practice == item ? practice.tint.opacity(0.12) : Color.white.opacity(0.04))
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    .disabled(isRunning)
                }
            }

            Text(practice.line)
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)

            if !isRunning {
                HStack(spacing: 8) {
                    ForEach(lengths, id: \.self) { n in
                        Button {
                            minutes = n
                        } label: {
                            Text("\(n)m")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(minutes == n ? .textPrimary : .textTertiary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(minutes == n ? Color.white.opacity(0.10) : Color.clear)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            ZStack {
                Circle()
                    .stroke(practice.tint.opacity(0.18), lineWidth: 10)
                    .frame(width: 148, height: 148)
                Circle()
                    .fill(practice.tint.opacity(inhale ? 0.28 : 0.12))
                    .frame(width: inhale ? 118 : 86, height: inhale ? 118 : 86)
                    .animation(
                        isRunning
                            ? .easeInOut(duration: 4).repeatForever(autoreverses: true)
                            : .easeOut(duration: 0.4),
                        value: inhale
                    )
                VStack(spacing: 4) {
                    if isRunning {
                        Text(timeString(remainingSeconds))
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .foregroundColor(.textPrimary)
                            .monospacedDigit()
                        Text(inhale ? "In" : "Out")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(practice.tint)
                    } else {
                        Text("\(minutes):00")
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                            .foregroundColor(.textPrimary)
                            .monospacedDigit()
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)

            Button {
                if isRunning {
                    stopSession(logged: remainingSeconds < minutes * 60)
                } else {
                    startSession()
                }
            } label: {
                Text(isRunning ? "End" : "Begin")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(practice.tint.opacity(0.9))
                    .cornerRadius(14)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(
            ZStack {
                Color.surface
                RadialGradient(colors: [practice.tint.opacity(0.10), .clear], center: .center, startRadius: 20, endRadius: 220)
            }
        )
        .cornerRadius(22)
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.borderColor.opacity(0.35), lineWidth: 1))
        .onDisappear { timer?.invalidate() }
    }

    private func startSession() {
        remainingSeconds = minutes * 60
        isRunning = true
        inhale = true
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
        inhale = false
        guard logged else { return }
        let elapsed = minutes * 60 - remainingSeconds
        let loggedMinutes = max(1, Int(ceil(Double(elapsed) / 60.0)))
        Task { await vm.logMindfulSession(minutes: loggedMinutes) }
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
            Text("Stress Management").font(.system(size: 18, weight: .bold)).foregroundColor(.textPrimary)

            HStack(spacing: 12) {
                ForEach(Array(levels.enumerated()), id: \.offset) { i, level in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selectedLevel = i }
                        LifestyleWellbeingStore.saveStressLevel(i)
                    } label: {
                        VStack(spacing: 8) {
                            Text(level.emoji).font(.system(size: 30))
                            Text(level.label)
                                .font(.system(size: 11, weight: .semibold))
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
                Image(systemName: "lightbulb.fill").font(.system(size: 12)).foregroundColor(.warning)
                Text(stressTip)
                    .font(.system(size: 13)).foregroundColor(.textSecondary).italic()
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
            Text("Sleep Optimization").font(.system(size: 18, weight: .bold)).foregroundColor(.textPrimary)

            VStack(spacing: 10) {
                ForEach(tips, id: \.tip) { tip in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(tip.color.opacity(0.12)).frame(width: 36, height: 36)
                            Image(systemName: tip.icon).font(.system(size: 15)).foregroundColor(tip.color)
                        }
                        Text(tip.tip).font(.system(size: 13, weight: .medium)).foregroundColor(.textSecondary)
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
                    color: Color(hex: "A855F7")
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
                            Image(systemName: "sparkles").font(.system(size: 22)).foregroundColor(.ember)
                            Text("AI Life Insights").font(.system(size: 24, weight: .bold)).foregroundColor(.textPrimary)
                        }
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 28)).foregroundColor(.textTertiary.opacity(0.7))
                        }
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
                Image(systemName: "sparkles").font(.system(size: 13)).foregroundColor(.ember)
                Text(isLive ? "ARIA · LIVE" : "ARIA")
                    .font(.system(size: 11, weight: .bold)).tracking(0.5).foregroundColor(.ember)
                Spacer()
            }
            Text(text)
                .font(.system(size: 14))
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

struct AIInsightCard: View {
    let insight: LifestyleInsight
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle().fill(insight.color).frame(width: 8, height: 8)
                    .shadow(color: insight.color.opacity(0.6), radius: 4)
                Text(insight.title).font(.system(size: 16, weight: .bold)).foregroundColor(.textPrimary)
                Spacer()
            }
            Text(insight.insight)
                .font(.system(size: 13)).foregroundColor(.textSecondary).lineSpacing(4)
                .lineLimit(expanded ? nil : 3)
                .animation(.easeInOut(duration: 0.25), value: expanded)
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right.circle.fill").font(.system(size: 13))
                    Text(insight.action).font(.system(size: 13, weight: .semibold))
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
