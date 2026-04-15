import SwiftUI
import Charts

// MARK: - Sleep Page (Enhanced & Gamified)

struct SleepView: View {
    @EnvironmentObject var store: AppStore
    @State private var showAIChat = false
    @State private var showSleepPrediction = false
    @State private var showStreakDetail = false
    @State private var celebrateStreak = false
    
    var currentStreak: Int {
        var streak = 0
        for sleep in store.sleepData {
            if sleep.score >= 75 { streak += 1 }
            else { break }
        }
        return streak
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    // Header with AI button
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Sleep & Recovery")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.textPrimary)
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 11))
                                    .foregroundColor(.steel)
                                Text("AI-powered optimization")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.steel)
                            }
                        }
                        Spacer()
                        
                        // AI Chat Button with pulse animation
                        Button(action: { showAIChat = true }) {
                            ZStack {
                                Circle()
                                    .fill(LinearGradient(
                                        colors: [Color.steel, Color.steelLight],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ))
                                    .frame(width: 44, height: 44)
                                    .shadow(color: Color.steel.opacity(0.3), radius: 8)
                                
                                Image(systemName: "brain.head.profile")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                    }

                    SleepScoreRingView()
                    
                    // Streak card - gamification
                    SleepStreakCard(streak: currentStreak, showDetail: $showStreakDetail)
                    
                    // AI Sleep Prediction Card
                    AISleepPredictionCard(showDetail: $showSleepPrediction)
                    
                    SleepTimelineView()
                    SleepBreakdownView()
                    
                    // Weekly comparison chart
                    SleepWeeklyComparisonChart()
                    
                    // Achievements & Badges
                    SleepAchievementsView()
                    
                    // Smart Recommendations
                    SleepSmartTipsView()
                    
                    // Sleep debt tracker
                    SleepDebtTrackerView()
                }
                .padding(.horizontal, 16)
                .padding(.top, 48)
                .padding(.bottom, 120)
            }
            .background(Color.background.ignoresSafeArea())
            
            // Floating Quick Actions
            VStack(spacing: 0) {
                Spacer()
                SleepQuickActionsBar()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
            }
        }
        .sheet(isPresented: $showAIChat) {
            AISleepChatView()
        }
        .sheet(isPresented: $showStreakDetail) {
            SleepStreakDetailView(streak: currentStreak)
        }
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

// MARK: - AI Sleep Prediction Card

struct AISleepPredictionCard: View {
    @Binding var showDetail: Bool
    @State private var appear = false
    
    var body: some View {
        Button(action: { showDetail = true }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle().fill(Color.steel.opacity(0.15)).frame(width: 32, height: 32)
                        Image(systemName: "sparkles").font(.system(size: 14)).foregroundColor(.steel)
                    }
                    Text("AI Sleep Prediction")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textTertiary)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tonight's Optimal Bedtime")
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("10:15 PM")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.steel)
                        Text("for peak recovery")
                            .font(.system(size: 13))
                            .foregroundColor(.textTertiary)
                    }
                }
                
                Text("Based on your workout intensity and recovery needs")
                    .font(.system(size: 12))
                    .foregroundColor(.textTertiary)
                    .lineLimit(2)
            }
            .padding(16)
            .background(Color.surface)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.borderColor, lineWidth: 1))
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 10)
        }
        .buttonStyle(.plain)
        .onAppear { withAnimation(.easeOut(duration: 0.4).delay(0.1)) { appear = true } }
    }
}

// MARK: - AI Smart Recommendations

struct AISmartRecommendationsView: View {
    @State private var appear = false
    
    struct Recommendation: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let description: String
        let priority: String
    }
    
    let recommendations: [Recommendation] = [
        Recommendation(icon: "sun.max.fill", title: "Morning Sunlight", description: "Get 10-15 min of sunlight within 1 hour of waking", priority: "High"),
        Recommendation(icon: "cup.and.saucer.fill", title: "Caffeine Cutoff", description: "Last coffee by 2:00 PM for better sleep quality", priority: "Medium"),
        Recommendation(icon: "figure.cooldown", title: "Wind-Down Routine", description: "Start your evening routine at 9:30 PM", priority: "High")
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Smart Recommendations")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.textPrimary)
            
            VStack(spacing: 10) {
                ForEach(Array(recommendations.enumerated()), id: \.element.id) { idx, rec in
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            Circle().fill(Color.steel.opacity(0.15)).frame(width: 36, height: 36)
                            Image(systemName: rec.icon)
                                .font(.system(size: 14))
                                .foregroundColor(.steel)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(rec.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.textPrimary)
                                Spacer()
                                Text(rec.priority)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(rec.priority == "High" ? .ember : .warning)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(rec.priority == "High" ? Color.ember.opacity(0.1) : Color.warning.opacity(0.1))
                                    .cornerRadius(6)
                            }
                            Text(rec.description)
                                .font(.system(size: 12))
                                .foregroundColor(.textSecondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(12)
                    .background(Color.surfaceElevated)
                    .cornerRadius(10)
                    .opacity(appear ? 1 : 0)
                    .offset(x: appear ? 0 : -10)
                    .animation(.easeOut(duration: 0.3).delay(Double(idx) * 0.1), value: appear)
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

// MARK: - AI Sleep Environment

struct AISleepEnvironmentView: View {
    @State private var appear = false
    
    struct EnvironmentMetric: Identifiable {
        let id = UUID()
        let icon: String
        let label: String
        let value: String
        let status: String
        let statusColor: Color
    }
    
    let metrics: [EnvironmentMetric] = [
        EnvironmentMetric(icon: "thermometer.medium", label: "Temperature", value: "68°F", status: "Optimal", statusColor: .success),
        EnvironmentMetric(icon: "drop.fill", label: "Humidity", value: "45%", status: "Good", statusColor: .success),
        EnvironmentMetric(icon: "moon.fill", label: "Light Level", value: "Dark", status: "Perfect", statusColor: .success),
        EnvironmentMetric(icon: "speaker.wave.2.fill", label: "Noise", value: "32 dB", status: "Quiet", statusColor: .success)
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(Color.steel.opacity(0.15)).frame(width: 28, height: 28)
                    Image(systemName: "house.fill").font(.system(size: 12)).foregroundColor(.steel)
                }
                Text("Sleep Environment")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textPrimary)
            }
            
            Text("Your bedroom conditions last night")
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(Array(metrics.enumerated()), id: \.element.id) { idx, metric in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: metric.icon)
                                .font(.system(size: 13))
                                .foregroundColor(.steel)
                            Text(metric.label)
                                .font(.system(size: 11))
                                .foregroundColor(.textSecondary)
                        }
                        Text(metric.value)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.textPrimary)
                        Text(metric.status)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(metric.statusColor)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.surfaceElevated)
                    .cornerRadius(10)
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 10)
                    .animation(.easeOut(duration: 0.3).delay(Double(idx) * 0.1), value: appear)
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

// MARK: - AI Personalized Goals

struct AIPersonalizedGoalsView: View {
    @EnvironmentObject var store: AppStore
    @State private var appear = false
    
    struct SleepGoal: Identifiable {
        let id = UUID()
        let title: String
        let current: Double
        let target: Double
        let unit: String
        let icon: String
    }
    
    var goals: [SleepGoal] {
        let latest = store.sleepData[0]
        return [
            SleepGoal(title: "Total Sleep", current: latest.totalHours, target: 8.0, unit: "hrs", icon: "bed.double.fill"),
            SleepGoal(title: "Deep Sleep", current: Double(latest.deepMinutes) / 60, target: 1.5, unit: "hrs", icon: "moon.zzz.fill"),
            SleepGoal(title: "Sleep Score", current: Double(latest.score), target: 85, unit: "", icon: "star.fill")
        ]
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(Color.ember.opacity(0.15)).frame(width: 28, height: 28)
                    Image(systemName: "target").font(.system(size: 12)).foregroundColor(.ember)
                }
                Text("Your Sleep Goals")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textPrimary)
            }
            
            Text("Personalized targets based on your training intensity")
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)
            
            VStack(spacing: 12) {
                ForEach(Array(goals.enumerated()), id: \.element.id) { idx, goal in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: goal.icon)
                                .font(.system(size: 12))
                                .foregroundColor(.steel)
                            Text(goal.title)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.textPrimary)
                            Spacer()
                            HStack(spacing: 4) {
                                Text(String(format: "%.1f", goal.current))
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.textPrimary)
                                Text("/")
                                    .font(.system(size: 12))
                                    .foregroundColor(.textTertiary)
                                Text("\(String(format: "%.1f", goal.target)) \(goal.unit)")
                                    .font(.system(size: 12))
                                    .foregroundColor(.textSecondary)
                            }
                        }
                        
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.borderColor).frame(height: 6)
                                Capsule()
                                    .fill(goal.current >= goal.target ? Color.success : Color.steel)
                                    .frame(width: appear ? geo.size.width * CGFloat(min(goal.current / goal.target, 1.0)) : 0, height: 6)
                                    .animation(.easeOut(duration: 0.8).delay(Double(idx) * 0.15), value: appear)
                            }
                        }
                        .frame(height: 6)
                    }
                    .padding(12)
                    .background(Color.surfaceElevated)
                    .cornerRadius(10)
                    .opacity(appear ? 1 : 0)
                    .offset(x: appear ? 0 : -10)
                    .animation(.easeOut(duration: 0.3).delay(Double(idx) * 0.1), value: appear)
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

// MARK: - AI Sleep Chat View

struct AISleepChatView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                ScrollView {
                    VStack(spacing: 16) {
                        Text("Ask me anything about your sleep patterns, recovery, or how to optimize your rest for better performance.")
                            .font(.system(size: 14))
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                }
                
                Spacer()
                
                // Chat input placeholder
                HStack(spacing: 12) {
                    TextField("Ask about your sleep...", text: .constant(""))
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(Color.surfaceElevated)
                        .cornerRadius(12)
                    
                    Button(action: {}) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.steel)
                    }
                }
                .padding()
            }
            .background(Color.background.ignoresSafeArea())
            .navigationTitle("Sleep AI Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - AI Sleep Prediction Detail View

struct AISleepPredictionDetailView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Optimal bedtime
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Tonight's Recommendation")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.textPrimary)
                        
                        HStack(alignment: .firstTextBaseline) {
                            Text("10:15 PM")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundColor(.steel)
                            Text("bedtime")
                                .font(.system(size: 16))
                                .foregroundColor(.textSecondary)
                        }
                        
                        Text("Wake at 6:15 AM for 8 hours of sleep")
                            .font(.system(size: 14))
                            .foregroundColor(.textSecondary)
                    }
                    .padding()
                    .background(Color.surface)
                    .cornerRadius(14)
                    
                    // Reasoning
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Why This Time?")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.textPrimary)
                        
                        VStack(alignment: .leading, spacing: 10) {
                            ReasonItem(icon: "figure.strengthtraining.traditional", text: "Heavy workout planned tomorrow — need optimal recovery")
                            ReasonItem(icon: "chart.line.uptrend.xyaxis", text: "Your sleep cycles align best with 10 PM bedtime")
                            ReasonItem(icon: "heart.fill", text: "Recent HRV trends suggest earlier sleep improves recovery")
                        }
                    }
                    .padding()
                    .background(Color.surface)
                    .cornerRadius(14)
                }
                .padding()
            }
            .background(Color.background.ignoresSafeArea())
            .navigationTitle("Sleep Prediction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct ReasonItem: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.steel)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.textPrimary)
        }
    }
}

// MARK: - Sleep Streak Card

struct SleepStreakCard: View {
    let streak: Int
    @Binding var showDetail: Bool
    @State private var appear = false
    
    var body: some View {
        Button(action: { showDetail = true }) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color.ember, Color.emberLight],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 60, height: 60)
                        .shadow(color: Color.ember.opacity(0.4), radius: 8)
                    
                    Image(systemName: "flame.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("\(streak)")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.textPrimary)
                        Text("Day Streak")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.textSecondary)
                    }
                    Text("Keep it going!")
                        .font(.system(size: 13))
                        .foregroundColor(.textTertiary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.textTertiary)
            }
            .padding(16)
            .background(Color.surface)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.borderColor, lineWidth: 1))
            .opacity(appear ? 1 : 0)
            .scaleEffect(appear ? 1 : 0.95)
        }
        .buttonStyle(.plain)
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { appear = true } }
    }
}

// MARK: - Sleep Streak Detail View

struct SleepStreakDetailView: View {
    @Environment(\.dismiss) var dismiss
    let streak: Int
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Current streak
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(
                                    colors: [Color.ember, Color.emberLight],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                                .frame(width: 100, height: 100)
                                .shadow(color: Color.ember.opacity(0.4), radius: 12)
                            
                            Image(systemName: "flame.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.white)
                        }
                        
                        Text("\(streak) Days")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.textPrimary)
                        
                        Text("Current Streak")
                            .font(.system(size: 16))
                            .foregroundColor(.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    
                    // Milestones
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Milestones")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.textPrimary)
                        
                        VStack(spacing: 12) {
                            MilestoneRow(days: 7, title: "Week Warrior", achieved: streak >= 7)
                            MilestoneRow(days: 30, title: "Month Master", achieved: streak >= 30)
                            MilestoneRow(days: 100, title: "Century Club", achieved: streak >= 100)
                            MilestoneRow(days: 365, title: "Year Legend", achieved: streak >= 365)
                        }
                    }
                    .padding()
                    .background(Color.surface)
                    .cornerRadius(14)
                    
                    // Benefits
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Streak Benefits")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.textPrimary)
                        
                        VStack(alignment: .leading, spacing: 10) {
                            BenefitRow(icon: "heart.fill", text: "Improved cardiovascular health")
                            BenefitRow(icon: "brain.head.profile", text: "Enhanced cognitive function")
                            BenefitRow(icon: "figure.run", text: "Better athletic performance")
                            BenefitRow(icon: "face.smiling.fill", text: "Elevated mood & energy")
                        }
                    }
                    .padding()
                    .background(Color.surface)
                    .cornerRadius(14)
                }
                .padding()
            }
            .background(Color.background.ignoresSafeArea())
            .navigationTitle("Sleep Streak")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct MilestoneRow: View {
    let days: Int
    let title: String
    let achieved: Bool
    
    var body: some View {
        HStack {
            Image(systemName: achieved ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundColor(achieved ? .success : .textTertiary)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.textPrimary)
                Text("\(days) days")
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
            }
            
            Spacer()
            
            if !achieved {
                Text("Next: \(days)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.steel)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.steel.opacity(0.1))
                    .cornerRadius(8)
            }
        }
        .padding(12)
        .background(Color.surfaceElevated)
        .cornerRadius(10)
    }
}

struct BenefitRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.steel)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.textPrimary)
        }
    }
}

// MARK: - Sleep Weekly Comparison Chart

struct SleepWeeklyComparisonChart: View {
    @EnvironmentObject var store: AppStore
    @State private var appear = false
    
    struct DayData: Identifiable {
        let id = UUID()
        let day: String
        let hours: Double
        let score: Int
    }
    
    var weekData: [DayData] {
        store.sleepData.prefix(7).reversed().map { sleep in
            DayData(day: dayAbbr(sleep.date), hours: sleep.totalHours, score: sleep.score)
        }
    }
    
    func dayAbbr(_ dateStr: String) -> String {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        guard let date = fmt.date(from: dateStr) else { return "" }
        let df = DateFormatter(); df.dateFormat = "EEE"
        return df.string(from: date)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weekly Sleep Duration")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.textPrimary)
            
            Chart {
                ForEach(weekData) { data in
                    BarMark(
                        x: .value("Day", data.day),
                        y: .value("Hours", appear ? data.hours : 0)
                    )
                    .foregroundStyle(data.score >= 75 ? Color.steel : Color.warning)
                    .cornerRadius(6)
                }
            }
            .chartYScale(domain: 0...10)
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
            .frame(height: 180)
            .animation(.easeOut(duration: 0.8).delay(0.2), value: appear)
            
            HStack {
                Label {
                    Text("Good sleep (≥75)")
                        .font(.system(size: 11))
                        .foregroundColor(.textSecondary)
                } icon: {
                    Circle().fill(Color.steel).frame(width: 8, height: 8)
                }
                
                Spacer()
                
                Label {
                    Text("Below target")
                        .font(.system(size: 11))
                        .foregroundColor(.textSecondary)
                } icon: {
                    Circle().fill(Color.warning).frame(width: 8, height: 8)
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

// MARK: - Sleep Achievements View

struct SleepAchievementsView: View {
    @State private var appear = false
    
    struct Achievement: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let description: String
        let unlocked: Bool
        let color: Color
    }
    
    let achievements: [Achievement] = [
        Achievement(icon: "star.fill", title: "Perfect Week", description: "7 days of 85+ sleep scores", unlocked: true, color: .ember),
        Achievement(icon: "moon.stars.fill", title: "Deep Sleeper", description: "Averaged 90+ min deep sleep", unlocked: true, color: .steel),
        Achievement(icon: "clock.fill", title: "Consistency King", description: "Same bedtime for 14 days", unlocked: false, color: .textTertiary)
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Achievements")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.textPrimary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(achievements.enumerated()), id: \.element.id) { idx, achievement in
                        VStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(achievement.unlocked ? achievement.color.opacity(0.15) : Color.borderColor.opacity(0.3))
                                    .frame(width: 60, height: 60)
                                
                                Image(systemName: achievement.icon)
                                    .font(.system(size: 24))
                                    .foregroundColor(achievement.unlocked ? achievement.color : .textTertiary)
                            }
                            
                            VStack(spacing: 4) {
                                Text(achievement.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.textPrimary)
                                Text(achievement.description)
                                    .font(.system(size: 10))
                                    .foregroundColor(.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(width: 120)
                        .padding(.vertical, 12)
                        .background(Color.surfaceElevated)
                        .cornerRadius(12)
                        .opacity(appear ? 1 : 0)
                        .offset(y: appear ? 0 : 10)
                        .animation(.easeOut(duration: 0.3).delay(Double(idx) * 0.1), value: appear)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(16)
        .background(Color.surface)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.borderColor, lineWidth: 1))
        .onAppear { withAnimation { appear = true } }
    }
}

// MARK: - Sleep Smart Tips View

struct SleepSmartTipsView: View {
    @State private var appear = false
    
    struct Tip: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let description: String
        let color: Color
    }
    
    let tips: [Tip] = [
        Tip(icon: "sun.max.fill", title: "Morning Light", description: "Get sunlight within 30 min of waking to regulate circadian rhythm", color: .warning),
        Tip(icon: "thermometer.medium", title: "Cool Room", description: "Keep bedroom at 65-68°F for optimal sleep", color: .steel),
        Tip(icon: "moon.fill", title: "Dark Environment", description: "Use blackout curtains or eye mask", color: .textPrimary)
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Smart Tips")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.textPrimary)
            
            VStack(spacing: 10) {
                ForEach(Array(tips.enumerated()), id: \.element.id) { idx, tip in
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(tip.color.opacity(0.15))
                                .frame(width: 36, height: 36)
                            Image(systemName: tip.icon)
                                .font(.system(size: 14))
                                .foregroundColor(tip.color)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tip.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.textPrimary)
                            Text(tip.description)
                                .font(.system(size: 12))
                                .foregroundColor(.textSecondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(12)
                    .background(Color.surfaceElevated)
                    .cornerRadius(10)
                    .opacity(appear ? 1 : 0)
                    .offset(x: appear ? 0 : -10)
                    .animation(.easeOut(duration: 0.3).delay(Double(idx) * 0.1), value: appear)
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

// MARK: - Sleep Debt Tracker View

struct SleepDebtTrackerView: View {
    @EnvironmentObject var store: AppStore
    @State private var appear = false
    
    var weeklyDebt: Double {
        let targetHours = 8.0
        let actualTotal = store.sleepData.prefix(7).reduce(0.0) { $0 + $1.totalHours }
        let targetTotal = targetHours * 7
        return max(0, targetTotal - actualTotal)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sleep Debt")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.textPrimary)
            
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%.1f", weeklyDebt))
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(weeklyDebt > 3 ? .danger : weeklyDebt > 1 ? .warning : .success)
                        Text("hours")
                            .font(.system(size: 14))
                            .foregroundColor(.textSecondary)
                    }
                    
                    Text("This week")
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 6) {
                    if weeklyDebt > 3 {
                        Label {
                            Text("High debt")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.danger)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.danger)
                        }
                        Text("Prioritize recovery")
                            .font(.system(size: 11))
                            .foregroundColor(.textSecondary)
                    } else if weeklyDebt > 1 {
                        Label {
                            Text("Moderate")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.warning)
                        } icon: {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.warning)
                        }
                        Text("Add 30min tonight")
                            .font(.system(size: 11))
                            .foregroundColor(.textSecondary)
                    } else {
                        Label {
                            Text("On track")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.success)
                        } icon: {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.success)
                        }
                        Text("Keep it up!")
                            .font(.system(size: 11))
                            .foregroundColor(.textSecondary)
                    }
                }
            }
            
            // Debt visualization
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.borderColor)
                        .frame(height: 8)
                    
                    Capsule()
                        .fill(weeklyDebt > 3 ? Color.danger : weeklyDebt > 1 ? Color.warning : Color.success)
                        .frame(width: appear ? geo.size.width * CGFloat(min(weeklyDebt / 7, 1.0)) : 0, height: 8)
                        .animation(.easeOut(duration: 0.8).delay(0.2), value: appear)
                }
            }
            .frame(height: 8)
        }
        .padding(16)
        .background(Color.surface)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.borderColor, lineWidth: 1))
        .onAppear { withAnimation { appear = true } }
    }
}

// MARK: - Sleep Quick Actions Bar

struct SleepQuickActionsBar: View {
    @State private var appear = false
    
    var body: some View {
        HStack(spacing: 12) {
            QuickActionButton(icon: "moon.fill", title: "Sleep Tips", color: .steel)
            QuickActionButton(icon: "bell.badge.fill", title: "Bedtime", color: .warning)
            QuickActionButton(icon: "chart.line.uptrend.xyaxis", title: "Trends", color: .ember)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.surface)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 10, y: 4)
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : 20)
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.3)) { appear = true } }
    }
}

// MARK: - Quick Action Button

struct QuickActionButton: View {
    let icon: String
    let title: String
    let color: Color
    
    var body: some View {
        Button(action: {}) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(color)
                }
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textPrimary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let subviewSize = subview.sizeThatFits(.unspecified)
                
                if x + subviewSize.width > maxWidth && x > 0 {
                    // Move to next line
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                lineHeight = max(lineHeight, subviewSize.height)
                x += subviewSize.width + spacing
            }
            
            size = CGSize(width: maxWidth, height: y + lineHeight)
        }
    }
}

