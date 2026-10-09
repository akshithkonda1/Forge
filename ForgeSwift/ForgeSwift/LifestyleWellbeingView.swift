import SwiftUI
import Combine
import Charts
import UIKit
import Contacts
import ForgeCore

struct WellbeingView: View {
    @ObservedObject var vm: LifestyleViewModel

    var body: some View {
        VStack(spacing: 20) {
            YourPeopleCard()
            HobbyPathCard()
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("This week")
                    .font(FDS.TypeScale.Dynamic.body.weight(.semibold)).foregroundStyle(Color.textPrimary)
                Spacer()
                Text("\(total) min")
                    .font(FDS.TypeScale.Dynamic.micro).foregroundStyle(Color.textTertiary).monospacedDigit()
            }

            if trend.isEmpty || trend.allSatisfy({ $0.minutes == 0 }) {
                Text("No sessions yet — 5 minutes still counts.")
                    .font(.system(size: 12)).foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                Chart(trend) { day in
                    BarMark(
                        x: .value("Day", day.date, unit: .day),
                        y: .value("Minutes", day.minutes)
                    )
                    .foregroundStyle(Color.textPrimary.opacity(0.85))
                    .cornerRadius(3)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.narrow)).font(.system(size: 9)).foregroundStyle(Color.textTertiary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine().foregroundStyle(Color.borderColor.opacity(0.12))
                        AxisValueLabel().font(.system(size: 9)).foregroundStyle(Color.textTertiary)
                    }
                }
                .frame(height: 96)
            }
        }
        .padding(18)
        .forgeGlassCard(cornerRadius: FDS.Radius.lg, accent: .success)
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
                        .font(.system(size: 16)).foregroundStyle(Color.ember)
                    Text("Quality of Life Trend")
                        .font(FDS.TypeScale.Dynamic.headline).foregroundStyle(Color.textPrimary)
                }
                Spacer()
                if let last = recent.last {
                    Text("\(last.score)/100")
                        .font(FDS.TypeScale.Dynamic.caption).foregroundStyle(Color.ember)
                }
            }

            if recent.count < 2 {
                Text("Your QOL trend appears after a couple of days of tracking.")
                    .font(.system(size: 13)).foregroundStyle(Color.textSecondary)
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
        .forgeGlassCard(cornerRadius: FDS.Radius.xl, accent: .success)
    }
}

struct DailyHabitsCard: View {
    @State private var habits: [DailyHabit] = LifestyleWellbeingStore.loadHabits()

    var completed: Int { habits.filter(\.done).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Daily Habits")
                    .font(FDS.TypeScale.Dynamic.headline).foregroundStyle(Color.textPrimary)
                Spacer()
                Text("\(completed)/\(habits.count)")
                    .font(FDS.TypeScale.Dynamic.caption).foregroundStyle(Color.ember)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.ember.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: FDS.Radius.sm))
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.borderColor.opacity(0.3))
                    Capsule().fill(LinearGradient(colors: [.ember, .ember.opacity(0.7)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(completed) / CGFloat(habits.count))
                        .animation(.spring(duration: 0.6, bounce: 0.28), value: completed)
                }
            }
            .frame(height: 6)
            .padding(.bottom, 4)

            VStack(spacing: 2) {
                ForEach($habits) { $habit in
                    HabitRow(name: habit.name, isDone: habit.done) {
                        withAnimation(.spring(duration: 0.3, bounce: 0.35)) {
                            habit.done.toggle()
                        }
                        LifestyleWellbeingStore.saveHabits(habits)
                        FDS.haptic(.light)
                    }
                }
            }

            // Streak
            HStack(spacing: 8) {
                Image(systemName: "flame.fill").foregroundStyle(Color.ember)
                Text("\(LifestyleWellbeingStore.habitStreak())-day streak").font(FDS.TypeScale.Dynamic.body.weight(.semibold)).foregroundStyle(Color.textPrimary)
                Spacer()
                Text("Keep it up 🔥").font(.system(size: 13)).foregroundStyle(Color.textSecondary)
            }
            .padding(14)
            .background(Color.ember.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md))
            .overlay { RoundedRectangle(cornerRadius: FDS.Radius.md).stroke(Color.ember.opacity(0.2), lineWidth: 1) }
        }
        .padding(20)
        .forgeGlassCard(cornerRadius: FDS.Radius.xl, accent: .success)
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
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    }
                }
                Text(name)
                    .font(FDS.TypeScale.Dynamic.body)
                    .foregroundStyle(isDone ? Color.textTertiary : Color.textPrimary)
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
        case .body: return Color.aurora
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
        VStack(alignment: .leading, spacing: 16) {
            // Header — editorial, not slop
            HStack(alignment: .firstTextBaseline) {
                Text("Mindfulness")
                    .font(FDS.TypeScale.Dynamic.headline)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text("\(max(vm.mindfulMinutesToday, 0)) min · \(max(vm.mindfulMinutesWeek, 0)) this week")
                    .font(FDS.TypeScale.Dynamic.micro)
                    .foregroundStyle(Color.textTertiary)
                    .monospacedDigit()
            }

            // Practice picker — segmented, not 4 colored pills
            HStack(spacing: 0) {
                ForEach(MindfulPractice.allCases) { item in
                    Button {
                        practice = item
                        FDS.selectionHaptic()
                    } label: {
                        VStack(spacing: 4) {
                            Text(item.title)
                                .font(.system(size: 12, weight: practice == item ? .semibold : .medium))
                                .foregroundStyle(practice == item ? Color.textPrimary : Color.textTertiary)
                            // underline, not filled pill
                            Rectangle()
                                .fill(practice == item ? Color.textPrimary : Color.clear)
                                .frame(height: 1.5)
                                .padding(.horizontal, 8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .disabled(isRunning)
                }
            }
            .background(Color.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))

            Text(practice.line)
                .font(FDS.TypeScale.Dynamic.caption)
                .foregroundStyle(Color.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            if !isRunning {
                HStack(spacing: 6) {
                    ForEach(lengths, id: \.self) { n in
                        Button {
                            minutes = n
                        } label: {
                            Text("\(n)m")
                                .font(.system(size: 12, weight: minutes == n ? .semibold : .medium))
                                .foregroundStyle(minutes == n ? Color.textPrimary : Color.textTertiary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background(minutes == n ? Color.surfaceElevated : Color.clear)
                                .overlay { RoundedRectangle(cornerRadius: 999).stroke(minutes == n ? Color.borderColor : Color.clear, lineWidth: 1) }
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Breathing orb — neutral, not tint-per-practice
            ZStack {
                Circle()
                    .stroke(Color.borderColor.opacity(0.12), lineWidth: 8)
                    .frame(width: 132, height: 132)
                Circle()
                    .fill(Color.textPrimary.opacity(inhale ? 0.06 : 0.03))
                    .frame(width: inhale ? 104 : 78, height: inhale ? 104 : 78)
                    .animation(
                        isRunning
                            ? .easeInOut(duration: 4).repeatForever(autoreverses: true)
                            : .easeOut(duration: 0.35),
                        value: inhale
                    )
                VStack(spacing: 3) {
                    if isRunning {
                        Text(timeString(remainingSeconds))
                            .font(.system(size: 26, weight: .light, design: .rounded))
                            .foregroundStyle(Color.textPrimary)
                            .monospacedDigit()
                        Text(inhale ? "in" : "out")
                            .font(FDS.TypeScale.Dynamic.micro)
                            .foregroundStyle(Color.textTertiary)
                            .textCase(.uppercase).tracking(0.8)
                    } else {
                        Text("\(minutes):00")
                            .font(FDS.TypeScale.Dynamic.title)
                            .foregroundStyle(Color.textPrimary)
                            .monospacedDigit()
                        Text(practice.title.lowercased())
                            .font(FDS.TypeScale.Dynamic.micro)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)

            Button {
                if isRunning {
                    stopSession(logged: remainingSeconds < minutes * 60)
                } else {
                    startSession()
                }
            } label: {
                Text(isRunning ? "End" : "Begin \(practice.title.lowercased())")
                    .font(FDS.TypeScale.Dynamic.body.weight(.semibold))
                    .foregroundStyle(isRunning ? Color.textPrimary : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(isRunning ? Color.surfaceElevated : Color.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: FDS.Radius.md).stroke(Color.borderColor.opacity(isRunning ? 0.12 : 0), lineWidth: 1) }
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .forgeGlassCard(cornerRadius: FDS.Radius.lg, accent: .success)
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

    private let levels: [(label: String, sub: String, color: Color)] = [
        ("Low", "steady", .textTertiary),
        ("Balanced", "okay", .textTertiary),
        ("High", "tense", .textTertiary),
    ]

    private var stressTip: String {
        if let stats, stats.hrv > 0, stats.hrv < 40 {
            return "HRV \(Int(stats.hrv))ms — a short breathe or walk helps."
        }
        switch selectedLevel {
        case 0: return "Steady — keep sleep and movement consistent."
        case 2: return "Tense — easier day, water, earlier wind-down."
        default: return "A 5-min breathe or walk resets more than you'd think."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Stress").font(FDS.TypeScale.Dynamic.body.weight(.semibold)).foregroundStyle(Color.textPrimary)
                Spacer()
                Text(["low","balanced","high"][selectedLevel]).font(FDS.TypeScale.Dynamic.micro).foregroundStyle(Color.textTertiary)
            }

            HStack(spacing: 6) {
                ForEach(Array(levels.enumerated()), id: \.offset) { i, level in
                    Button {
                        withAnimation(.spring(duration: 0.3, bounce: 0.3)) { selectedLevel = i }
                        LifestyleWellbeingStore.saveStressLevel(i)
                    } label: {
                        Text(level.label)
                            .font(.system(size: 12, weight: selectedLevel == i ? .semibold : .medium))
                            .foregroundStyle(selectedLevel == i ? Color.textPrimary : Color.textTertiary)
                            .frame(maxWidth: .infinity).padding(.vertical, 9)
                            .background(selectedLevel == i ? Color.surfaceElevated : Color.clear)
                            .overlay { RoundedRectangle(cornerRadius: 999).stroke(selectedLevel == i ? Color.borderColor : Color.clear, lineWidth: 1) }
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(stressTip)
                .font(FDS.TypeScale.Dynamic.caption)
                .foregroundStyle(Color.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .forgeGlassCard(cornerRadius: FDS.Radius.lg, accent: .success)
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
            Text("Sleep Optimization").font(FDS.TypeScale.Dynamic.headline).foregroundStyle(Color.textPrimary)

            VStack(spacing: 10) {
                ForEach(tips, id: \.tip) { tip in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(tip.color.opacity(0.12)).frame(width: 36, height: 36)
                            Image(systemName: tip.icon).font(.system(size: 15)).foregroundStyle(tip.color)
                        }
                        Text(tip.tip).font(FDS.TypeScale.Dynamic.caption).foregroundStyle(Color.textSecondary)
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.surfaceElevated).clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md))
                }
            }
        }
        .padding(20)
        .forgeGlassCard(cornerRadius: FDS.Radius.xl, accent: .success)
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
                    color: Color.aurora
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
        GeometryReader { geo in
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
                                ARIAIdentityMark(state: .idle, mood: .energized, size: 28, amplitude: 0.24)
                                Text("AI Life Insights").font(FDS.TypeScale.Dynamic.title).foregroundStyle(Color.textPrimary)
                            }
                            Spacer()
                            Button { dismiss() } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 28)).foregroundStyle(Color.textTertiary.opacity(0.7))
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
                    .frame(maxHeight: geo.size.height * 0.78)
                    .background(Color.surface)
                    .cornerRadius(28, corners: [.topLeft, .topRight])
                }
            }
        }
    }

    @ViewBuilder
    private func ariaBanner(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ARIAIdentityMark(state: isLive ? .speaking : .idle, mood: .energized, size: 18, amplitude: isLive ? 0.45 : 0.2)
                Text(isLive ? "ARIA · LIVE" : "ARIA")
                    .font(FDS.TypeScale.Dynamic.micro).tracking(0.5).foregroundStyle(Color.ember)
                Spacer()
            }
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Color.textPrimary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color.ember.opacity(0.12), Color.ember.opacity(0.04)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.lg))
        .overlay { RoundedRectangle(cornerRadius: FDS.Radius.lg).stroke(Color.ember.opacity(0.25), lineWidth: 1) }
    }

    private func dismiss() {
        withAnimation(.spring(duration: 0.35, bounce: 0.25)) { isPresented = false }
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
                Text(insight.title).font(FDS.TypeScale.Dynamic.headline).foregroundStyle(Color.textPrimary)
                Spacer()
            }
            Text(insight.insight)
                .font(.system(size: 13)).foregroundStyle(Color.textSecondary).lineSpacing(4)
                .lineLimit(expanded ? nil : 3)
                .animation(.easeInOut(duration: 0.25), value: expanded)
            Button {
                withAnimation(.spring(duration: 0.3, bounce: 0.28)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right.circle.fill").font(.system(size: 13))
                    Text(insight.action).font(FDS.TypeScale.Dynamic.caption)
                }
                .foregroundStyle(insight.color)
            }
        }
        .padding(16)
        .background(Color.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.lg))
        .overlay { RoundedRectangle(cornerRadius: FDS.Radius.lg).stroke(insight.color.opacity(0.2), lineWidth: 1) }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(duration: 0.3, bounce: 0.28)) { expanded.toggle() }
        }
    }
}

/// Wellbeing isn't only fitness. ARIA names a hobby path from how this
/// person actually works — reserved vs burned-out social energy — and the
/// same snapshot Chat / Home send.
struct HobbyPathCard: View {
    @EnvironmentObject var store: AppStore

    private var hobby: HobbyPathEngine.Snapshot {
        store.predictiveCoachPicture().hobby
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("HOBBY PATH")
                    .font(FDS.TypeScale.Dynamic.micro)
                    .foregroundColor(.textTertiary)
                    .tracking(2)
                Spacer()
                Text(hobby.path.rawValue.replacingOccurrences(of: "_", with: " "))
                    .font(FDS.TypeScale.Dynamic.micro)
                    .foregroundStyle(Color.ember)
                    .textCase(.uppercase)
            }
            Text(hobby.headline)
                .font(FDS.TypeScale.Dynamic.headline)
                .foregroundColor(.textPrimary)
            Text(hobby.coachingLine)
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
                .lineSpacing(3)
            Text(hobby.windowLine)
                .font(.system(size: 12))
                .foregroundColor(.textTertiary)
                .lineSpacing(3)
            ForEach(hobby.suggestions.prefix(3)) { item in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 5))
                        .foregroundStyle(Color.ember)
                        .padding(.top, 6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.hobby.title)
                            .font(FDS.TypeScale.Dynamic.caption)
                            .foregroundColor(.textPrimary)
                        Text(item.firstStep)
                            .font(.system(size: 12))
                            .foregroundColor(.textTertiary)
                    }
                }
            }
            Button {
                FDS.haptic(.light)
                store.openChat(with: HomeInsightFlow.hobbyPrompt(hobby: hobby), voice: false)
            } label: {
                HStack {
                    Image(systemName: "message.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Ask ARIA to pick a hobby")
                        .font(FDS.TypeScale.Dynamic.caption)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Color.ember)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(Color.ember.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .forgeGlassCard(cornerRadius: FDS.Radius.lg, accent: .ember)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(hobby.headline). \(hobby.coachingLine) \(hobby.windowLine)")
    }
}

struct YourPeopleCard: View {
    @EnvironmentObject var store: AppStore
    @State private var directory = PeopleDirectoryStore.load()
    @State private var showSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("YOUR PEOPLE")
                .font(FDS.TypeScale.Dynamic.micro)
                .foregroundColor(.textTertiary)
                .tracking(2)
            if directory.coachingPeople.isEmpty {
                Text("ARIA doesn't know who matters yet.")
                    .font(FDS.TypeScale.Dynamic.headline)
                    .foregroundColor(.textPrimary)
                Text("Pick a few first names — partner, roommate, training buddy. Not your whole address book. Phone numbers stay in Contacts.")
                    .font(.system(size: 13))
                    .foregroundColor(.textSecondary)
            } else {
                ForEach(directory.coachingPeople) { person in
                    Text("\(person.firstName) · \(person.relation.title)")
                        .font(FDS.TypeScale.Dynamic.body.weight(.semibold))
                        .foregroundColor(.textPrimary)
                }
            }
            Button {
                FDS.haptic(.light)
                showSheet = true
            } label: {
                Text(directory.coachingPeople.isEmpty ? "Add your people" : "Edit your people")
                    .font(FDS.TypeScale.Dynamic.caption)
                    .foregroundStyle(Color.ember)
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .forgeGlassCard(cornerRadius: FDS.Radius.lg, accent: .ember)
        .sheet(isPresented: $showSheet, onDismiss: reload) {
            YourPeopleSheet()
                .environmentObject(store)
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        directory = PeopleDirectoryStore.load()
        store.objectWillChange.send()
    }
}

struct PeopleSettingsSection: View {
    @EnvironmentObject var store: AppStore
    @State private var directory = PeopleDirectoryStore.load()
    @State private var showSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Your people")
                .forgeSectionLabel()
                .padding(.top, 28)
                .padding(.bottom, 10)
            Text(honesty)
                .font(.system(size: 12))
                .foregroundColor(.textTertiary)
                .padding(.bottom, 10)
            SectionCard {
                SettingsRow(
                    icon: "person.2.fill",
                    iconColor: .ember,
                    label: "Contacts access",
                    trailingText: accessLabel
                )
                Divider().background(Color.borderColor)
                Button {
                    showSheet = true
                } label: {
                    SettingsRow(icon: "person.crop.circle.badge.plus", iconColor: .steel, label: "Edit your people", trailingText: countLabel, showChevron: true)
                }
                .buttonStyle(.plain)
                Divider().background(Color.borderColor)
                Button {
                    PeopleDirectoryStore.forget()
                    directory = PeopleDirectoryStore.load()
                    store.objectWillChange.send()
                } label: {
                    SettingsRow(icon: "trash", iconColor: Color.alert, label: "Forget your people", trailingText: "On this iPhone")
                }
                .buttonStyle(.plain)
                Divider().background(Color.borderColor)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    SettingsRow(icon: "gear", iconColor: .textSecondary, label: "Revoke Contacts in Settings", showChevron: true)
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showSheet, onDismiss: { directory = PeopleDirectoryStore.load() }) {
            YourPeopleSheet().environmentObject(store)
        }
        .onAppear { directory = PeopleDirectoryStore.load() }
    }

    private var countLabel: String {
        let n = directory.coachingPeople.count
        return n == 1 ? "1 person" : "\(n) people"
    }

    private var accessLabel: String {
        switch directory.contactsAccess {
        case .granted: return "Allowed"
        case .denied: return "Off"
        case .notAsked: return "Not asked"
        }
    }

    private var honesty: String {
        switch directory.contactsAccess {
        case .denied:
            return "Contacts access is off. You can still type a first name. Forge stores that name and a label on this iPhone — never a phone number or email, and never a medical read. Turn Contacts back on in iPhone Settings → Forge."
        case .granted:
            return "Contacts is allowed. ARIA only keeps the first names you confirm, plus a label. The rest of the address book stays in Contacts and is not uploaded."
        case .notAsked:
            return "Optional. ARIA can use a few first names for social stretch and quieter weeks. Nothing is read until you ask."
        }
    }
}

struct YourPeopleSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var directory = PeopleDirectoryStore.load()
    @State private var draft = ""
    @State private var relation: PeopleDirectory.Relation = .friend
    @State private var suggestions: [(name: String, id: String)] = []
    @State private var notice: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("First names and a label only. Phone numbers, emails, and the rest of your address book stay in Contacts. This is lifestyle coaching — not a read on your social life.")
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)
                    if let notice {
                        Text(notice)
                            .font(.system(size: 12))
                            .foregroundColor(.textTertiary)
                    }
                    if directory.contactsAccess != .granted {
                        Button("Allow Contacts (optional)") {
                            Task { await requestContacts() }
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.ember)
                    }
                    HStack {
                        TextField("First name", text: $draft)
                            .textInputAutocapitalization(.words)
                        Menu(relation.title) {
                            ForEach(PeopleDirectory.Relation.allCases, id: \.self) { item in
                                Button(item.title) { relation = item }
                            }
                        }
                        Button("Add") { addDraft() }
                            .font(.system(size: 14, weight: .semibold))
                    }
                    if !suggestions.isEmpty {
                        Text("From Contacts — tap to confirm")
                            .font(FDS.TypeScale.Dynamic.caption)
                            .foregroundColor(.textTertiary)
                        ForEach(suggestions, id: \.id) { row in
                            Button {
                                confirm(name: row.name, identifier: row.id)
                            } label: {
                                Text(row.name)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    ForEach(directory.people) { person in
                        HStack {
                            Text("\(person.firstName) · \(person.relation.title)")
                            Spacer()
                            Button("Remove") { remove(person) }
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.ember)
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("Your people")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { refreshSuggestionsIfAllowed() }
    }

    private func persist(_ next: PeopleDirectory.Directory) {
        var updated = next
        updated.optedIn = true
        updated.people = Array(updated.people.prefix(PeopleDirectory.maxPeople))
        PeopleDirectoryStore.save(updated)
        directory = updated
        store.objectWillChange.send()
    }

    private func addDraft() {
        guard let person = PeopleDirectory.admit(rawName: draft, relation: relation) else {
            notice = "Use a first name. Not an email or a phone number."
            return
        }
        notice = nil
        draft = ""
        var next = directory
        next.people.removeAll { $0.firstName.lowercased() == person.firstName.lowercased() }
        next.people.append(person)
        persist(next)
    }

    private func confirm(name: String, identifier: String) {
        guard let person = PeopleDirectory.admit(rawName: name, relation: relation, contactIdentifier: identifier) else { return }
        var next = directory
        next.contactsAccess = .granted
        next.people.removeAll { $0.contactIdentifier == identifier || $0.firstName.lowercased() == person.firstName.lowercased() }
        next.people.append(person)
        persist(next)
    }

    private func remove(_ person: PeopleDirectory.Person) {
        var next = directory
        next.people.removeAll { $0.id == person.id }
        persist(next)
    }

    private func requestContacts() async {
        let ok = await PeopleContactsBridge.requestAccess()
        var next = directory
        next.contactsAccess = ok ? .granted : .denied
        if ok { next.optedIn = true }
        PeopleDirectoryStore.save(next)
        directory = next
        notice = ok ? "Pick the people who matter. The rest stay in Contacts." : "Contacts stayed off. You can still type a first name."
        if ok { suggestions = PeopleContactsBridge.suggestions() }
    }

    private func refreshSuggestionsIfAllowed() {
        let status = PeopleContactsBridge.currentAccess()
        if directory.contactsAccess != status {
            var next = directory
            next.contactsAccess = status
            directory = next
            PeopleDirectoryStore.save(next)
        }
        if status == .granted {
            suggestions = PeopleContactsBridge.suggestions()
        }
    }
}

enum PeopleContactsBridge {
    static func currentAccess() -> PeopleDirectory.ContactsAccess {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized, .limited:
            return .granted
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .notAsked
        @unknown default:
            return .notAsked
        }
    }

    static func requestAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            CNContactStore().requestAccess(for: .contacts) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Given name + identifier only. Phone and email keys are not requested.
    static func suggestions() -> [(name: String, id: String)] {
        let store = CNContactStore()
        let request = CNContactFetchRequest(keysToFetch: [CNContactGivenNameKey as CNKeyDescriptor])
        request.unifyResults = true
        var rows: [(name: String, id: String)] = []
        try? store.enumerateContacts(with: request) { contact, stop in
            guard let person = PeopleDirectory.admit(rawName: contact.givenName, contactIdentifier: contact.identifier) else { return }
            rows.append((person.firstName, contact.identifier))
            if rows.count >= 40 { stop.pointee = true }
        }
        return rows
    }
}
