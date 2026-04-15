import SwiftUI
import Charts

// MARK: - Sleep Page (mirrors sleep-page.tsx)

struct SleepView: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                // Title
                HStack {
                    Text("Sleep & Recovery")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Spacer()
                }

                SleepScoreRingView()
                SleepTimelineView()
                SleepBreakdownView()
                RecoveryTrendsView()
                AISleepInsightView()
            }
            .padding(.horizontal, 16)
            .padding(.top, 48)
            .padding(.bottom, 32)
        }
        .background(Color.background.ignoresSafeArea())
    }
}

// MARK: - Sleep Score Ring (mirrors sleep-score-ring.tsx)

struct SleepScoreRingView: View {
    @EnvironmentObject var store: AppStore
    @State private var progress: CGFloat = 0
    @State private var appear = false

    var latest: SleepData { store.sleepData[0] }
    var score: Int { min(100, max(0, latest.score)) }

    var totalFormatted: String {
        let h = Int(latest.totalHours)
        let m = Int((latest.totalHours - Double(h)) * 60)
        return "\(h)h \(m)m total"
    }

    let size: CGFloat = 160
    let strokeWidth: CGFloat = 10

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                // Background track
                Circle()
                    .stroke(Color.borderColor, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                    .frame(width: size, height: size)

                // Progress arc with blue gradient effect
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        LinearGradient(colors: [.steel, .steelLight, .steel],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                    )
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(-90))
                    .shadow(color: Color.steel.opacity(0.4), radius: 8)
                    .animation(.spring(response: 1.2, dampingFraction: 0.75).delay(0.2), value: progress)

                // Center
                VStack(spacing: 4) {
                    Text("\(score)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundColor(.textPrimary)
                        .scaleEffect(appear ? 1 : 0.6)
                        .opacity(appear ? 1 : 0)
                        .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.2), value: appear)

                    Text("Sleep Score")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.steel)
                        .opacity(appear ? 1 : 0)
                        .offset(y: appear ? 0 : 5)
                        .animation(.easeOut(duration: 0.3).delay(0.4), value: appear)
                }
            }
            .frame(width: size, height: size)

            VStack(spacing: 3) {
                Text(totalFormatted)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Text("Last night")
                    .font(.system(size: 12))
                    .foregroundColor(.textTertiary)
            }
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 8)
            .animation(.easeOut(duration: 0.4).delay(0.5), value: appear)
        }
        .onAppear {
            appear = true
            progress = CGFloat(score) / 100
        }
    }
}

// MARK: - Sleep Timeline (mirrors sleep-timeline.tsx)

struct SleepTimelineView: View {
    @EnvironmentObject var store: AppStore
    @State private var appear = false

    struct StageInfo: Identifiable {
        var id: String
        var label: String
        var minutes: Int
        var color: Color
    }

    var latest: SleepData { store.sleepData[0] }

    var stages: [StageInfo] {
        [
            StageInfo(id: "awake", label: "Awake", minutes: latest.awakeMinutes, color: .danger),
            StageInfo(id: "light", label: "Light",  minutes: latest.lightMinutes, color: .textTertiary),
            StageInfo(id: "deep",  label: "Deep",   minutes: latest.deepMinutes,  color: .steel),
            StageInfo(id: "rem",   label: "REM",    minutes: latest.remMinutes,   color: Color(hex: "A78BFA")),
        ]
    }

    var totalMinutes: Int { stages.reduce(0) { $0 + $1.minutes } }

    func formatMin(_ min: Int) -> String {
        let h = min / 60; let m = min % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sleep Stages")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.textPrimary)

            // Stacked horizontal bar
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(Array(stages.enumerated()), id: \.element.id) { idx, stage in
                        let w = totalMinutes > 0 ? CGFloat(stage.minutes) / CGFloat(totalMinutes) * geo.size.width : 0
                        Rectangle()
                            .fill(stage.color)
                            .frame(width: appear ? w : 0)
                            .frame(height: 32)
                            .shadow(color: stage.id == "deep" ? stage.color.opacity(0.5) : .clear, radius: 6)
                            .animation(.easeOut(duration: 0.8).delay(Double(idx) * 0.1), value: appear)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .frame(height: 32)

            // Legend
            FlowLayout(spacing: 12) {
                ForEach(stages) { stage in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(stage.color)
                            .frame(width: 10, height: 10)
                            .overlay(
                                stage.id == "deep" ? Circle().stroke(Color.steel.opacity(0.4), lineWidth: 1.5) : nil
                            )
                        Text(stage.label)
                            .font(.system(size: 12))
                            .foregroundColor(.textSecondary)
                        Text(formatMin(stage.minutes))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.textPrimary)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.surface)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.borderColor, lineWidth: 1))
        .onAppear { withAnimation { appear = true } }
    }
}

// MARK: - Sleep Breakdown (mirrors sleep-breakdown.tsx)

struct SleepBreakdownView: View {
    @EnvironmentObject var store: AppStore

    var latest: SleepData { store.sleepData[0] }

    var efficiency: Double {
        let total = latest.totalHours * 60
        guard total > 0 else { return 0 }
        return ((total - Double(latest.awakeMinutes)) / total) * 100
    }

    func formatMin(_ m: Int) -> String {
        let h = m / 60; let min = m % 60
        return h > 0 ? "\(h)hr \(min)min" : "\(min)min"
    }

    struct BreakdownItem {
        var label: String
        var value: String
        var progress: Double?
        var progressColor: Color
        var subtitle: String
    }

    var cards: [BreakdownItem] {
        let deepPct = Double(latest.deepMinutes) / 90 * 100
        let remPct  = Double(latest.remMinutes)  / 90 * 100
        return [
            BreakdownItem(label: "Deep Sleep",      value: formatMin(latest.deepMinutes), progress: deepPct,      progressColor: deepPct >= 100 ? .ember : .steel, subtitle: "\(Int(deepPct))% of 90min goal"),
            BreakdownItem(label: "REM Sleep",        value: formatMin(latest.remMinutes),  progress: remPct,       progressColor: remPct  >= 100 ? .ember : .steel, subtitle: "\(Int(remPct))% of 90min goal"),
            BreakdownItem(label: "Sleep Efficiency", value: "\(Int(efficiency))%",         progress: efficiency,   progressColor: efficiency >= 85 ? .success : efficiency >= 75 ? .warning : .danger, subtitle: efficiency >= 85 ? "Excellent" : efficiency >= 75 ? "Good" : "Needs improvement"),
            BreakdownItem(label: "Time Awake",       value: "\(latest.awakeMinutes)min",   progress: nil,          progressColor: .danger, subtitle: latest.awakeMinutes <= 15 ? "Great" : latest.awakeMinutes <= 30 ? "Normal" : "High"),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Breakdown")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.textPrimary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(Array(cards.enumerated()), id: \.offset) { idx, card in
                    SleepBreakdownCard(item: card, index: idx)
                }
            }
        }
    }
}

struct SleepBreakdownCard: View {
    let item: SleepBreakdownView.BreakdownItem
    let index: Int
    @State private var barProgress: CGFloat = 0
    @State private var appear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.textSecondary)
            Text(item.value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.textPrimary)

            if let p = item.progress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.borderColor).frame(height: 6)
                        Capsule()
                            .fill(item.progressColor)
                            .frame(width: appear ? geo.size.width * CGFloat(min(p, 100)) / 100 : 0, height: 6)
                            .animation(.easeOut(duration: 0.8).delay(0.2 + Double(index) * 0.1), value: appear)
                    }
                }
                .frame(height: 6)
            }

            Text(item.subtitle)
                .font(.system(size: 10))
                .foregroundColor(.textTertiary)
        }
        .padding(12)
        .background(Color.surface)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.borderColor, lineWidth: 1))
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : 12)
        .onAppear { withAnimation(.easeOut(duration: 0.4).delay(Double(index) * 0.1)) { appear = true } }
    }
}

// MARK: - Recovery Trends (mirrors recovery-trends.tsx) — uses Swift Charts

private let mockHRV: [Double] = [44, 46, 52, 48, 41, 55, 50]
private let mockRHR: [Double] = [62, 60, 58, 61, 64, 57, 59]

struct RecoveryTrendsView: View {
    @EnvironmentObject var store: AppStore

    struct DayPoint: Identifiable {
        var id = UUID()
        var day: String
        var value: Double
        var series: String
    }

    var recoveryPoints: [DayPoint] {
        let days = store.sleepData.prefix(7).reversed()
        return days.enumerated().map { idx, d in
            DayPoint(day: dayAbbr(d.date), value: Double(d.score), series: "Score")
        }
    }

    var hrvPoints: [DayPoint] {
        store.sleepData.prefix(7).reversed().enumerated().map { idx, d in
            DayPoint(day: dayAbbr(d.date), value: mockHRV[idx % mockHRV.count], series: "HRV")
        }
    }

    var rhrPoints: [DayPoint] {
        store.sleepData.prefix(7).reversed().enumerated().map { idx, d in
            DayPoint(day: dayAbbr(d.date), value: mockRHR[idx % mockRHR.count], series: "RHR")
        }
    }

    func dayAbbr(_ dateStr: String) -> String {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        guard let date = fmt.date(from: dateStr) else { return "" }
        let df = DateFormatter(); df.dateFormat = "EEE"
        return df.string(from: date)
    }

    var body: some View {
        VStack(spacing: 20) {
            // Recovery Trend Chart
            VStack(alignment: .leading, spacing: 12) {
                Text("Recovery Trend")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textPrimary)

                Chart {
                    ForEach(recoveryPoints) { point in
                        AreaMark(
                            x: .value("Day", point.day),
                            y: .value("Score", point.value)
                        )
                        .foregroundStyle(Color.steel.opacity(0.25))
                        LineMark(
                            x: .value("Day", point.day),
                            y: .value("Score", point.value)
                        )
                        .foregroundStyle(Color.steel)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        PointMark(
                            x: .value("Day", point.day),
                            y: .value("Score", point.value)
                        )
                        .foregroundStyle(Color.steel)
                        .symbolSize(40)
                    }
                }
                .chartYScale(domain: 40...100)
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel().foregroundStyle(Color.textTertiary)
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisValueLabel().foregroundStyle(Color.textTertiary)
                        AxisGridLine().foregroundStyle(Color.borderColor.opacity(0.5))
                    }
                }
                .frame(height: 160)
            }
            .padding(12)
            .background(Color.surface)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.borderColor, lineWidth: 1))

            // HRV & Resting HR Chart
            VStack(alignment: .leading, spacing: 12) {
                Text("HRV & Resting HR")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textPrimary)

                Chart {
                    ForEach(hrvPoints) { point in
                        LineMark(x: .value("Day", point.day), y: .value("HRV", point.value))
                            .foregroundStyle(Color.steel)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        PointMark(x: .value("Day", point.day), y: .value("HRV", point.value))
                            .foregroundStyle(Color.steel)
                            .symbolSize(36)
                    }
                    ForEach(rhrPoints) { point in
                        LineMark(x: .value("Day", point.day), y: .value("RHR", point.value))
                            .foregroundStyle(Color.ember)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        PointMark(x: .value("Day", point.day), y: .value("RHR", point.value))
                            .foregroundStyle(Color.ember)
                            .symbolSize(36)
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel().foregroundStyle(Color.textTertiary)
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisValueLabel().foregroundStyle(Color.textTertiary)
                        AxisGridLine().foregroundStyle(Color.borderColor.opacity(0.5))
                    }
                }
                .frame(height: 160)

                // Legend
                HStack(spacing: 20) {
                    HStack(spacing: 6) {
                        Circle().fill(Color.steel).frame(width: 8, height: 8)
                        Text("HRV (ms)").font(.system(size: 11)).foregroundColor(.textSecondary)
                    }
                    HStack(spacing: 6) {
                        Circle().fill(Color.ember).frame(width: 8, height: 8)
                        Text("Resting HR (bpm)").font(.system(size: 11)).foregroundColor(.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(12)
            .background(Color.surface)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.borderColor, lineWidth: 1))
        }
    }
}

// MARK: - AI Sleep Insight (mirrors ai-sleep-insight.tsx)

struct AISleepInsightView: View {
    @EnvironmentObject var store: AppStore

    var insight: String {
        let d = store.sleepData[0]
        let deepHrs = d.deepMinutes / 60; let deepMins = d.deepMinutes % 60
        let deepStr = deepHrs > 0 ? "\(deepHrs)hr \(deepMins)min" : "\(deepMins)min"
        if d.score >= 85 {
            return "Excellent recovery last night, Akshith. \(deepStr) of deep sleep has fully topped up your muscle repair and memory consolidation. You're primed for a heavy session. Protect this sleep window — it's your biggest performance lever."
        } else if d.score >= 70 {
            return "Good sleep last night — \(deepStr) of deep sleep. Your HRV reflects adequate recovery. A slight dip from your recent average, likely from the late screen time. Cut screens 45 min before bed and you'll see this score climb."
        } else {
            return "Sleep was below your target last night — only \(deepStr) of deep sleep. Your body hasn't fully recovered. Consider a lighter session today and prioritize an earlier bedtime. Small adjustments compound over time."
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(Color.steel.opacity(0.15)).frame(width: 36, height: 36)
                Image(systemName: "moon.stars.fill").font(.system(size: 15)).foregroundColor(.steel)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("AI Sleep Insight")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.steel)
                Text(insight)
                    .font(.system(size: 14))
                    .foregroundColor(.textPrimary)
                    .lineSpacing(4)
            }
        }
        .padding(16)
        .background(Color.surface)
        .cornerRadius(16)
        .overlay(
            Rectangle().fill(Color.steel).frame(width: 2),
            alignment: .leading
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
