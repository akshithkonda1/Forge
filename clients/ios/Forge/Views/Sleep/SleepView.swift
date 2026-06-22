import SwiftUI
import Charts

// MARK: - Sleep View

struct SleepView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var hkService: HealthKitSleepService

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Sleep & Recovery")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)

                SleepScoreRing()
                SleepTimeline()
                SleepBreakdown()
                RecoveryTrends()
                AiSleepInsight()
            }
            .padding(.horizontal, 16)
            .padding(.top, 48)
            .padding(.bottom, 100)
        }
        .background(Color.forgeBackground)
    }
}

// MARK: - Sleep Score Ring

struct SleepScoreRing: View {
    @EnvironmentObject var store: AppStore
    @State private var ringProgress: Double = 0
    @State private var displayedScore: Int = 0
    @State private var counterStart: Date?

    var body: some View {
        let latest = store.sleepData.first!
        let score = latest.score
        let hours = Int(latest.totalHours)
        let minutes = Int((latest.totalHours - Double(hours)) * 60)
        let fraction = Double(score) / 100

        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.forgeBorder, lineWidth: 10)

                Circle()
                    .trim(from: 0, to: ringProgress)
                    .stroke(
                        LinearGradient.steelGradient,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: .steel.opacity(0.4), radius: 8)

                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    let value: Int = {
                        guard let start = counterStart else { return 0 }
                        let elapsed = timeline.date.timeIntervalSince(start)
                        let progress = min(1, elapsed / 1.0)
                        return Int(Double(score) * progress)
                    }()
                    VStack(spacing: 2) {
                        Text("\(value)")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("Sleep Score")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.steel)
                    }
                }
            }
            .frame(width: 160, height: 160)
            .onAppear {
                ringProgress = 0
                displayedScore = 0
                counterStart = Date()
                withAnimation(.easeOut(duration: 1.2).delay(0.3)) {
                    ringProgress = fraction
                }
            }
            .onDisappear {
                counterStart = nil
            }

            VStack(spacing: 2) {
                Text("\(hours)h \(minutes)m total")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text("Last night")
                    .font(.system(size: 12))
                    .foregroundColor(.textTertiary)
            }
        }
    }
}

// MARK: - Sleep Timeline

struct SleepTimeline: View {
    @EnvironmentObject var store: AppStore

    private struct StageInfo {
        let key: String
        let label: String
        let minutes: Int
        let color: Color
    }

    var body: some View {
        let latest = store.sleepData.first!
        let stages = [
            StageInfo(key: "awake", label: "Awake", minutes: latest.awakeMinutes, color: .sleepAwake),
            StageInfo(key: "light", label: "Light", minutes: latest.lightMinutes, color: .sleepLight),
            StageInfo(key: "deep", label: "Deep", minutes: latest.deepMinutes, color: .sleepDeep),
            StageInfo(key: "rem", label: "REM", minutes: latest.remMinutes, color: .sleepREM),
        ]
        let total = stages.reduce(0) { $0 + $1.minutes }

        VStack(alignment: .leading, spacing: 12) {
            Text("Sleep Stages")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)

            // Timeline bar
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(stages, id: \.key) { stage in
                        let width = total > 0 ? CGFloat(stage.minutes) / CGFloat(total) * geo.size.width : 0
                        Rectangle()
                            .fill(stage.color)
                            .frame(width: width, height: 32)
                            .shadow(
                                color: stage.key == "deep" ? stage.color.opacity(0.6) : .clear,
                                radius: stage.key == "deep" ? 6 : 0
                            )
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .frame(height: 32)

            // Legend
            HStack(spacing: 16) {
                ForEach(stages, id: \.key) { stage in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(stage.color)
                            .frame(width: 8, height: 8)
                        Text(stage.label)
                            .font(.system(size: 11))
                            .foregroundColor(.textSecondary)
                        Text(formatMinutes(stage.minutes))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .padding(16)
        .forgeBorderedCard()
    }

    private func formatMinutes(_ min: Int) -> String {
        let h = min / 60
        let m = min % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

// MARK: - Sleep Breakdown

struct SleepBreakdown: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        let latest = store.sleepData.first!
        let deepGoal = 90
        let remGoal = 90
        let deepPct = Double(latest.deepMinutes) / Double(deepGoal) * 100
        let remPct = Double(latest.remMinutes) / Double(remGoal) * 100
        let totalMin = latest.totalHours * 60
        let efficiency = totalMin > 0 ? (totalMin - Double(latest.awakeMinutes)) / totalMin * 100 : 0

        VStack(alignment: .leading, spacing: 10) {
            Text("Breakdown")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                breakdownCard("Deep Sleep", formatMin(latest.deepMinutes), deepPct, deepPct >= 100 ? .ember : .steel, "\(Int(deepPct))% of \(deepGoal)min goal")
                breakdownCard("REM Sleep", formatMin(latest.remMinutes), remPct, remPct >= 100 ? .ember : .steel, "\(Int(remPct))% of \(remGoal)min goal")
                breakdownCard("Efficiency", "\(Int(efficiency))%", efficiency, efficiency >= 85 ? .forgeSuccess : .forgeWarning, efficiency >= 85 ? "Excellent" : "Good")
                breakdownCard("Time Awake", "\(latest.awakeMinutes)min", nil, .forgeDanger, latest.awakeMinutes <= 15 ? "Great" : "Normal")
            }
        }
    }

    private func breakdownCard(_ label: String, _ value: String, _ progress: Double?, _ color: Color, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.textSecondary)
            Text(value)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.white)

            if let progress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.forgeBorder).frame(height: 4)
                        Capsule().fill(color).frame(width: geo.size.width * min(progress / 100, 1), height: 4)
                    }
                }
                .frame(height: 4)
            }

            Text(subtitle)
                .font(.system(size: 10))
                .foregroundColor(.textTertiary)
        }
        .padding(12)
        .forgeBorderedCard()
    }

    private func formatMin(_ min: Int) -> String {
        let h = min / 60
        let m = min % 60
        return h > 0 ? "\(h)hr \(m)min" : "\(m)min"
    }
}

// MARK: - Recovery Trends

struct RecoveryTrends: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        let chartData = Array(store.sleepData.prefix(7).reversed())

        VStack(alignment: .leading, spacing: 10) {
            Text("Recovery Trend")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)

            Chart(chartData) { d in
                AreaMark(
                    x: .value("Date", d.date.suffix(2)),
                    y: .value("Score", d.score)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [.steel.opacity(0.3), .steel.opacity(0)],
                        startPoint: .top, endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Date", d.date.suffix(2)),
                    y: .value("Score", d.score)
                )
                .foregroundStyle(Color.steel)
                .lineStyle(StrokeStyle(lineWidth: 2))

                PointMark(
                    x: .value("Date", d.date.suffix(2)),
                    y: .value("Score", d.score)
                )
                .foregroundStyle(Color.steel)
                .symbolSize(20)
            }
            .chartYScale(domain: 40...100)
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .foregroundStyle(Color.textTertiary)
                        .font(.system(size: 10))
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .foregroundStyle(Color.textTertiary)
                        .font(.system(size: 10))
                }
            }
            .frame(height: 160)
            .padding(12)
            .forgeBorderedCard()
        }
    }
}

// MARK: - AI Sleep Insight

struct AiSleepInsight: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        CoachingBadge(
            message: "Your deep sleep has dropped 18% this week. This correlates with your increased evening screen time. Try the wind-down routine I suggested."
        )
    }
}
