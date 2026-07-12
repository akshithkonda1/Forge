import SwiftUI
import Charts

// MARK: - Sleep analytics, AI & detail views (extracted from SleepView.swift)

struct SleepTimelineView: View {
    @EnvironmentObject var store: AppStore
    @State private var appeared = false

    struct Stage: Identifiable {
        let id: String; let label: String; let minutes: Int; let color: Color
    }

    var latest: SleepData { store.sleepData[0] }
    var stages: [Stage] {[
        Stage(id: "awake", label: "Awake", minutes: latest.awakeMinutes, color: .danger),
        Stage(id: "light", label: "Light",  minutes: latest.lightMinutes, color: Color.borderColor),
        Stage(id: "deep",  label: "Deep",   minutes: latest.deepMinutes,  color: .steel),
        Stage(id: "rem",   label: "REM",    minutes: latest.remMinutes,   color: Color(hex: "A78BFA")),
    ]}
    var total: Int { stages.reduce(0) { $0 + $1.minutes } }

    func fmt(_ m: Int) -> String { m >= 60 ? "\(m/60)h \(m%60)m" : "\(m)m" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sleep Stages").font(.forgeDynamic(size: 14, weight: .semibold)).foregroundColor(.textPrimary)

            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(Array(stages.enumerated()), id: \.element.id) { i, stage in
                        let w = total > 0 ? CGFloat(stage.minutes) / CGFloat(total) * geo.size.width : 0
                        Rectangle().fill(stage.color)
                            .frame(width: appeared ? w : 0, height: 36)
                            .shadow(color: stage.id == "deep" ? stage.color.opacity(0.4) : .clear, radius: 6)
                            .animation(.easeOut(duration: 0.8).delay(Double(i) * 0.1), value: appeared)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .frame(height: 36)

            FlowLayout(spacing: 12) {
                ForEach(stages) { s in
                    HStack(spacing: 6) {
                        Circle().fill(s.color).frame(width: 9, height: 9)
                        Text(s.label).font(.forgeDynamic(size: 12)).foregroundColor(.textSecondary)
                        Text(fmt(s.minutes)).font(.forgeDynamic(size: 12, weight: .semibold)).foregroundColor(.textPrimary)
                    }
                }
            }
        }
        .padding(18)
        .background(Color.surface)
        .cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.borderColor.opacity(0.5), lineWidth: 1))
        // Fixed: withAnimation requires value: parameter
        .onAppear { withAnimation(.easeOut(duration: 0.6)) { appeared = true } }
    }
}

struct SleepBreakdownView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var hkService: HealthKitSleepService

    var latest: SleepData { store.sleepData[0] }
    var efficiency: Double {
        let t = latest.totalHours * 60
        return t > 0 ? ((t - Double(latest.awakeMinutes)) / t) * 100 : 0
    }
    func fmt(_ m: Int) -> String { m >= 60 ? "\(m/60)hr \(m%60)min" : "\(m)min" }

    struct Card { let label: String; let value: String; let progress: Double?; let color: Color; let subtitle: String }

    var cards: [Card] {
        let deepGoal = hkService.userProfile.chronotype.deepSleepGoalMinutes
        let remGoal = hkService.userProfile.chronotype.remSleepGoalMinutes
        let dp = Double(latest.deepMinutes) / Double(deepGoal) * 100
        let rp = Double(latest.remMinutes) / Double(remGoal) * 100
        return [
            Card(label: "Deep Sleep",      value: fmt(latest.deepMinutes), progress: dp, color: dp >= 100 ? .success : .steel, subtitle: "\(Int(dp))% of \(deepGoal) min goal"),
            Card(label: "REM Sleep",       value: fmt(latest.remMinutes),  progress: rp, color: rp >= 100 ? .success : .steel, subtitle: "\(Int(rp))% of \(remGoal) min goal"),
            Card(label: "Sleep Efficiency",value: "\(Int(efficiency))%",   progress: efficiency, color: efficiency >= 85 ? .success : efficiency >= 75 ? .warning : .danger, subtitle: efficiency >= 85 ? "Excellent" : "Needs work"),
            Card(label: "Time Awake",      value: "\(latest.awakeMinutes)m", progress: nil, color: .danger, subtitle: latest.awakeMinutes <= 15 ? "Great" : "High"),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Breakdown").font(.forgeDynamic(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(Array(cards.enumerated()), id: \.offset) { i, card in
                    SleepBreakdownCard(item: card, index: i)
                }
            }
        }
    }
}

struct SleepBreakdownCard: View {
    let item: SleepBreakdownView.Card
    let index: Int
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.label).font(.forgeDynamic(size: 12, weight: .medium)).foregroundColor(.textSecondary)
            Text(item.value).font(.forgeDynamic(size: 18, weight: .bold)).foregroundColor(.textPrimary)
            if let p = item.progress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.borderColor.opacity(0.4)).frame(height: 5)
                        Capsule().fill(item.color)
                            .frame(width: appeared ? geo.size.width * CGFloat(min(p, 100)) / 100 : 0, height: 5)
                            .animation(.spring(response: 1.0, dampingFraction: 0.7).delay(0.2 + Double(index) * 0.08), value: appeared)
                    }
                }
                .frame(height: 5)
            }
            Text(item.subtitle).font(.forgeDynamic(size: 10)).foregroundColor(.textTertiary)
        }
        .padding(14)
        .background(Color.surface)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(item.color.opacity(0.2), lineWidth: 1))
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .onAppear { withAnimation(.easeOut(duration: 0.4).delay(Double(index) * 0.08)) { appeared = true } }
    }
}

struct AISleepInsightView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var hkService: HealthKitSleepService

    var insight: String {
        let d = store.sleepData[0]
        let s = "\(d.deepMinutes >= 60 ? "\(d.deepMinutes/60)hr " : "")\(d.deepMinutes % 60)min"
        if d.score >= 85 { return "Excellent recovery. \(s) of deep sleep has fully topped up muscle repair. You're primed for a heavy session today." }
        else if d.score >= 70 { return "Good sleep — \(s) deep sleep. HRV reflects adequate recovery. Cut screens 45 min before bed to push this score higher." }
        else { return "Only \(s) of deep sleep last night. Recovery is below target. Consider a lighter session and an earlier bedtime tonight." }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color.steel.opacity(0.12)).frame(width: 38, height: 38)
                Image(systemName: "moon.stars.fill").font(.forgeDynamic(size: 16)).foregroundColor(.steel)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("AI Sleep Insight")
                    .font(.forgeDynamic(size: 12, weight: .bold)).foregroundColor(.steel).tracking(0.5)
                Text(hkService.chronotypeInsightPrefix() + insight)
                    .font(.forgeDynamic(size: 14)).foregroundColor(.textPrimary).lineSpacing(5)
            }
        }
        .padding(18)
        .background(Color.surface)
        .cornerRadius(20)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3).fill(Color.steel).frame(width: 3).padding(.vertical, 12)
        }
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }
}

struct RecoveryTrendsView: View {
    @EnvironmentObject var store: AppStore

    private let mockHRV: [Double] = [44, 46, 52, 48, 41, 55, 50]
    private let mockRHR: [Double] = [62, 60, 58, 61, 64, 57, 59]

    struct Pt: Identifiable { var id = UUID(); var day: String; var value: Double; var series: String }

    func dayAbbr(_ s: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: s) else { return "" }
        let df = DateFormatter(); df.dateFormat = "EEE"; return df.string(from: d)
    }

    var scorePoints: [Pt] { store.sleepData.prefix(7).reversed().enumerated().map { Pt(day: dayAbbr($1.date), value: Double($1.score), series: "Score") }}
    var hrvPoints:   [Pt] { store.sleepData.prefix(7).reversed().enumerated().map { i, d in Pt(day: dayAbbr(d.date), value: mockHRV[i % mockHRV.count], series: "HRV") }}
    var rhrPoints:   [Pt] { store.sleepData.prefix(7).reversed().enumerated().map { i, d in Pt(day: dayAbbr(d.date), value: mockRHR[i % mockRHR.count], series: "RHR") }}

    var body: some View {
        VStack(spacing: 16) {
            ChartCard(title: "Recovery Trend") {
                Chart {
                    ForEach(scorePoints) { p in
                        AreaMark(x: .value("Day", p.day), y: .value("Score", p.value)).foregroundStyle(Color.steel.opacity(0.2))
                        LineMark(x: .value("Day", p.day), y: .value("Score", p.value)).foregroundStyle(Color.steel).lineStyle(StrokeStyle(lineWidth: 2.5))
                        PointMark(x: .value("Day", p.day), y: .value("Score", p.value)).foregroundStyle(Color.steel).symbolSize(44)
                    }
                }
                .chartYScale(domain: 40...100)
                .chartXAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(Color.textTertiary) } }
                .chartYAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(Color.textTertiary); AxisGridLine().foregroundStyle(Color.borderColor.opacity(0.4)) } }
                .frame(height: 150)
            }

            ChartCard(title: "HRV & Resting HR") {
                Chart {
                    ForEach(hrvPoints) { p in LineMark(x: .value("Day", p.day), y: .value("HRV", p.value)).foregroundStyle(Color.steel).lineStyle(StrokeStyle(lineWidth: 2.5)); PointMark(x: .value("Day", p.day), y: .value("HRV", p.value)).foregroundStyle(Color.steel).symbolSize(38) }
                    ForEach(rhrPoints) { p in LineMark(x: .value("Day", p.day), y: .value("RHR", p.value)).foregroundStyle(Color.ember).lineStyle(StrokeStyle(lineWidth: 2.5)); PointMark(x: .value("Day", p.day), y: .value("RHR", p.value)).foregroundStyle(Color.ember).symbolSize(38) }
                }
                .chartXAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(Color.textTertiary) } }
                .chartYAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(Color.textTertiary); AxisGridLine().foregroundStyle(Color.borderColor.opacity(0.4)) } }
                .frame(height: 150)
                HStack(spacing: 16) {
                    Label { Text("HRV (ms)").font(.forgeDynamic(size: 11)).foregroundColor(.textSecondary) } icon: { Circle().fill(Color.steel).frame(width: 8, height: 8) }
                    Label { Text("Resting HR").font(.forgeDynamic(size: 11)).foregroundColor(.textSecondary) } icon: { Circle().fill(Color.ember).frame(width: 8, height: 8) }
                }
            }
        }
    }
}

private struct ChartCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.forgeDynamic(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
            content()
        }
        .padding(16).background(Color.surface).cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.borderColor.opacity(0.4), lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
    }
}

struct SleepWeeklyComparisonChart: View {
    @EnvironmentObject var store: AppStore
    @State private var appeared = false

    struct DayData: Identifiable { let id = UUID(); let day: String; let hours: Double; let score: Int }

    var weekData: [DayData] {
        store.sleepData.prefix(7).reversed().map { s in
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            guard let d = f.date(from: s.date) else { return DayData(day: "", hours: s.totalHours, score: s.score) }
            let df = DateFormatter(); df.dateFormat = "EEE"
            return DayData(day: df.string(from: d), hours: s.totalHours, score: s.score)
        }
    }

    var body: some View {
        ChartCard(title: "Weekly Sleep Duration") {
            Chart {
                ForEach(weekData) { d in
                    BarMark(x: .value("Day", d.day), y: .value("Hours", appeared ? d.hours : 0))
                        .foregroundStyle(d.score >= 75 ? Color.steel : Color.warning)
                        .cornerRadius(6)
                }
            }
            .chartYScale(domain: 0...10)
            .chartXAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(Color.textTertiary) } }
            .chartYAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(Color.textTertiary); AxisGridLine().foregroundStyle(Color.borderColor.opacity(0.4)) } }
            .frame(height: 170)
            .animation(.easeOut(duration: 0.8).delay(0.2), value: appeared)
            HStack {
                Label { Text("Good (≥75)").font(.forgeDynamic(size: 11)).foregroundColor(.textSecondary) } icon: { Circle().fill(Color.steel).frame(width: 8, height: 8) }
                Spacer()
                Label { Text("Below target").font(.forgeDynamic(size: 11)).foregroundColor(.textSecondary) } icon: { Circle().fill(Color.warning).frame(width: 8, height: 8) }
            }
        }
        .onAppear { withAnimation(.easeOut(duration: 0.5)) { appeared = true } }
    }
}

struct AISleepEnvironmentView: View {
    @State private var appeared = false
    private struct Metric: Identifiable { let id = UUID(); let icon: String; let label: String; let value: String; let status: String; let color: Color }
    private let metrics: [Metric] = [
        Metric(icon: "thermometer.medium",   label: "Temperature", value: "68°F", status: "Optimal",  color: .success),
        Metric(icon: "drop.fill",            label: "Humidity",    value: "45%",  status: "Good",     color: .success),
        Metric(icon: "moon.fill",            label: "Light Level", value: "Dark", status: "Perfect",  color: .success),
        Metric(icon: "speaker.wave.2.fill",  label: "Noise",       value: "32 dB", status: "Quiet",  color: .success),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "house.fill").font(.forgeDynamic(size: 14)).foregroundColor(.steel)
                Text("Sleep Environment").font(.forgeDynamic(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(Array(metrics.enumerated()), id: \.element.id) { i, m in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: m.icon).font(.forgeDynamic(size: 12)).foregroundColor(.steel)
                            Text(m.label).font(.forgeDynamic(size: 11)).foregroundColor(.textSecondary)
                        }
                        Text(m.value).font(.forgeDynamic(size: 17, weight: .bold)).foregroundColor(.textPrimary)
                        Text(m.status).font(.forgeDynamic(size: 10, weight: .semibold)).foregroundColor(m.color)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12).background(Color.surfaceElevated).cornerRadius(12)
                    .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 10)
                    .animation(.easeOut(duration: 0.3).delay(Double(i) * 0.08), value: appeared)
                }
            }
        }
        .padding(18).background(Color.surface).cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.borderColor.opacity(0.4), lineWidth: 1))
        .onAppear { withAnimation(.easeOut(duration: 0.5)) { appeared = true } }
    }
}

struct AIPersonalizedGoalsView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var hkService: HealthKitSleepService
    @State private var appeared = false

    var goals: [AdaptiveSleepGoal] {
        hkService.computeAdaptiveGoals(from: store.sleepData)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "target").font(.forgeDynamic(size: 14)).foregroundColor(.ember)
                Text("Sleep Goals").font(.forgeDynamic(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
            }
            VStack(spacing: 10) {
                ForEach(Array(goals.enumerated()), id: \.element.id) { i, g in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: g.icon).font(.forgeDynamic(size: 12)).foregroundColor(.steel)
                            Text(g.title).font(.forgeDynamic(size: 13, weight: .medium)).foregroundColor(.textPrimary)
                            Spacer()
                            Text(String(format: "%.1f / %.1f %@", g.current, g.target, g.unit))
                                .font(.forgeDynamic(size: 13, weight: .semibold)).foregroundColor(.textSecondary)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.borderColor.opacity(0.4)).frame(height: 6)
                                Capsule()
                                    .fill(g.current >= g.target ? Color.success : Color.steel)
                                    .frame(width: appeared ? geo.size.width * CGFloat(min(g.current / g.target, 1.0)) : 0, height: 6)
                                    .animation(.spring(response: 1.0, dampingFraction: 0.7).delay(0.3 + Double(i) * 0.1), value: appeared)
                            }
                        }
                        .frame(height: 6)
                    }
                    .padding(12).background(Color.surfaceElevated).cornerRadius(12)
                    .opacity(appeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.3).delay(Double(i) * 0.1), value: appeared)
                }
            }
        }
        .padding(18).background(Color.surface).cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.borderColor.opacity(0.4), lineWidth: 1))
        .onAppear { withAnimation(.easeOut(duration: 0.5)) { appeared = true } }
    }
}

struct AISmartRecommendationsView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var hkService: HealthKitSleepService
    @State private var appeared = false

    var recs: [SleepRecommendation] {
        hkService.chronotypeRecommendations(debt: hkService.computeSleepDebt(from: store.sleepData))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Smart Recommendations").font(.forgeDynamic(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
            VStack(spacing: 10) {
                ForEach(Array(recs.enumerated()), id: \.element.id) { i, rec in
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            Circle().fill(Color.steel.opacity(0.12)).frame(width: 38, height: 38)
                            Image(systemName: rec.icon).font(.forgeDynamic(size: 14)).foregroundColor(.steel)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(rec.title).font(.forgeDynamic(size: 13, weight: .semibold)).foregroundColor(.textPrimary)
                                Spacer()
                                Text(rec.priority)
                                    .font(.forgeDynamic(size: 10, weight: .bold))
                                    .foregroundColor(rec.priority == "High" ? .ember : .warning)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background((rec.priority == "High" ? Color.ember : Color.warning).opacity(0.12))
                                    .cornerRadius(6)
                            }
                            Text(rec.description).font(.forgeDynamic(size: 12)).foregroundColor(.textSecondary).lineLimit(2)
                        }
                    }
                    .padding(12).background(Color.surfaceElevated).cornerRadius(12)
                    .opacity(appeared ? 1 : 0).offset(x: appeared ? 0 : -10)
                    .animation(.easeOut(duration: 0.3).delay(Double(i) * 0.08), value: appeared)
                }
            }
        }
        .padding(18).background(Color.surface).cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.borderColor.opacity(0.4), lineWidth: 1))
        .onAppear { withAnimation(.easeOut(duration: 0.5)) { appeared = true } }
    }
}

struct SleepAchievementsView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var hkService: HealthKitSleepService
    @State private var appeared = false

    var achievements: [SleepAchievementState] {
        hkService.computeAchievements(from: store.sleepData)
    }

    private func achievementColor(_ name: String, unlocked: Bool) -> Color {
        guard unlocked else { return .textMuted }
        switch name {
        case "ember": return .ember
        case "steel": return .steel
        case "success": return .success
        default: return .steel
        }
    }

    private func achievementIcon(_ id: String) -> String {
        switch id {
        case "perfect-week": return "star.fill"
        case "deep-sleeper": return "moon.stars.fill"
        case "consistency": return "clock.fill"
        default: return "star.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Achievements").font(.forgeDynamic(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(achievements.enumerated()), id: \.element.id) { i, a in
                        let color = achievementColor(a.colorName, unlocked: a.unlocked)
                        VStack(spacing: 10) {
                            ZStack {
                                Circle().fill(a.unlocked ? color.opacity(0.15) : Color.borderColor.opacity(0.25)).frame(width: 58, height: 58)
                                Image(systemName: achievementIcon(a.id)).font(.forgeDynamic(size: 24)).foregroundColor(a.unlocked ? color : .textMuted)
                            }
                            VStack(spacing: 3) {
                                Text(a.title).font(.forgeDynamic(size: 12, weight: .bold)).foregroundColor(.textPrimary)
                                Text(a.description).font(.forgeDynamic(size: 10)).foregroundColor(.textSecondary).multilineTextAlignment(.center)
                            }
                        }
                        .frame(width: 110)
                        .padding(.vertical, 14)
                        .background(Color.surfaceElevated)
                        .cornerRadius(16)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(a.unlocked ? color.opacity(0.3) : Color.borderColor.opacity(0.3), lineWidth: 1))
                        .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 10)
                        .animation(.easeOut(duration: 0.3).delay(Double(i) * 0.08), value: appeared)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(18).background(Color.surface).cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.borderColor.opacity(0.4), lineWidth: 1))
        .onAppear { withAnimation(.easeOut(duration: 0.5)) { appeared = true } }
    }
}

struct SleepDebtTrackerView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var hkService: HealthKitSleepService
    @State private var appeared = false

    var debt: Double {
        hkService.computeSleepDebt(from: store.sleepData)
    }
    var debtColor: Color { debt > 3 ? .danger : debt > 1 ? .warning : .success }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sleep Debt").font(.forgeDynamic(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%.1f", debt)).font(.forgeDynamic(size: 32, weight: .bold, design: .rounded)).foregroundColor(debtColor)
                        Text("hours").font(.forgeDynamic(size: 14)).foregroundColor(.textSecondary)
                    }
                    Text("This week").font(.forgeDynamic(size: 12)).foregroundColor(.textTertiary)
                }
                Spacer()
                Text(debt > 3 ? "Prioritize recovery" : debt > 1 ? "Add 30 min tonight" : "On track! 🎉")
                    .font(.forgeDynamic(size: 13, weight: .semibold))
                    .foregroundColor(debtColor)
                    .multilineTextAlignment(.trailing)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.borderColor.opacity(0.3)).frame(height: 8)
                    Capsule().fill(debtColor)
                        .frame(width: appeared ? geo.size.width * CGFloat(min(debt / 7, 1.0)) : 0, height: 8)
                        .animation(.spring(response: 1.0, dampingFraction: 0.7).delay(0.2), value: appeared)
                }
            }
            .frame(height: 8)
        }
        .padding(18).background(Color.surface).cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.borderColor.opacity(0.4), lineWidth: 1))
        .onAppear { withAnimation(.easeOut(duration: 0.5)) { appeared = true } }
    }
}

struct SleepQuickActionsBar: View {
    @State private var appeared = false
    let onAITap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            QuickActionButton(icon: "moon.fill",                  title: "Tips",   color: .steel,   action: {})
            QuickActionButton(icon: "bell.badge.fill",            title: "Alarm",  color: .ember,   action: {})
            QuickActionButton(icon: "brain.head.profile",         title: "ARIA",   color: .steel,   action: onAITap)
            QuickActionButton(icon: "chart.line.uptrend.xyaxis",  title: "Trends", color: Color.indigo, action: {})
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Color.surface)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.1), radius: 14, y: 5)
        .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 20)
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.3)) { appeared = true } }
    }
}

struct QuickActionButton: View {
    let icon: String; let title: String; let color: Color; let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle().fill(color.opacity(0.14)).frame(width: 44, height: 44)
                    Image(systemName: icon).font(.forgeDynamic(size: 18, weight: .medium)).foregroundColor(color)
                }
                Text(title).font(.forgeDynamic(size: 11, weight: .medium)).foregroundColor(.textPrimary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Streak Detail Sheet (fixed: NavigationView → NavigationStack)

struct SleepStreakDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let streak: Int

    private let milestones: [(days: Int, title: String, icon: String)] = [
        (7,   "Week Warrior",  "flame.fill"),
        (30,  "Month Master",  "moon.stars.fill"),
        (100, "Century Club",  "crown.fill"),
        (365, "Year Legend",   "trophy.fill"),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 28) {
                        // Hero
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(LinearGradient(colors: [Color.ember, Color.ember.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 100, height: 100)
                                    .shadow(color: Color.ember.opacity(0.45), radius: 20, y: 8)
                                Image(systemName: "flame.fill").font(.forgeDynamic(size: 46)).foregroundColor(.white)
                            }
                            Text("\(streak) Days").font(.forgeDynamic(size: 36, weight: .black, design: .rounded)).foregroundColor(.textPrimary)
                            Text("Current Sleep Streak").font(.forgeDynamic(size: 16)).foregroundColor(.textSecondary)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 28)

                        // Milestones
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Milestones").font(.forgeDynamic(size: 18, weight: .bold)).foregroundColor(.textPrimary)
                            VStack(spacing: 10) {
                                ForEach(milestones, id: \.days) { m in
                                    HStack(spacing: 14) {
                                        ZStack {
                                            Circle().fill(streak >= m.days ? Color.ember.opacity(0.15) : Color.surfaceElevated).frame(width: 42, height: 42)
                                            Image(systemName: streak >= m.days ? "checkmark" : m.icon)
                                                .font(.forgeDynamic(size: 16)).foregroundColor(streak >= m.days ? .ember : .textMuted)
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(m.title).font(.forgeDynamic(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
                                            Text("\(m.days) days").font(.forgeDynamic(size: 12)).foregroundColor(.textSecondary)
                                        }
                                        Spacer()
                                        if streak < m.days {
                                            Text("\(m.days - streak) to go")
                                                .font(.forgeDynamic(size: 12, weight: .semibold)).foregroundColor(.steel)
                                                .padding(.horizontal, 10).padding(.vertical, 5)
                                                .background(Color.steel.opacity(0.1)).cornerRadius(8)
                                        }
                                    }
                                    .padding(14).background(Color.surface).cornerRadius(14)
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(streak >= m.days ? Color.ember.opacity(0.3) : Color.borderColor.opacity(0.4), lineWidth: 1))
                                }
                            }
                        }
                        .padding(20).background(Color.surface).cornerRadius(20)

                        // Benefits
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Streak Benefits").font(.forgeDynamic(size: 18, weight: .bold)).foregroundColor(.textPrimary)
                            VStack(spacing: 10) {
                                ForEach([("heart.fill", "Improved cardiovascular health"), ("brain.head.profile", "Enhanced cognitive function"), ("figure.run", "Better athletic performance"), ("face.smiling.fill", "Elevated mood & energy")], id: \.0) { icon, text in
                                    HStack(spacing: 12) {
                                        Image(systemName: icon).font(.forgeDynamic(size: 14)).foregroundColor(.steel).frame(width: 20)
                                        Text(text).font(.forgeDynamic(size: 13)).foregroundColor(.textPrimary)
                                    }
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    .background(Color.surfaceElevated).cornerRadius(12)
                                }
                            }
                        }
                        .padding(20).background(Color.surface).cornerRadius(20)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Sleep Streak")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundColor(.ember).fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - AI Sleep Chat (fixed: NavigationView → NavigationStack)

struct AISleepChatView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var hkService: HealthKitSleepService
    @State private var input = ""

    private var ariaContext: String {
        hkService.buildARIAContext(sleepData: store.sleepData, store: store)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()
                VStack {
                    ScrollView {
                        VStack(spacing: 16) {
                            Text("Ask me anything about your sleep patterns, recovery, or how to optimize your rest for better performance.")
                                .font(.forgeDynamic(size: 14)).foregroundColor(.textSecondary).multilineTextAlignment(.center).lineSpacing(5).padding(.horizontal, 24).padding(.top, 16)
                            if !store.sleepData.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("ARIA Context (ready for backend)")
                                        .font(.forgeDynamic(size: 11, weight: .bold))
                                        .foregroundColor(.steel)
                                        .tracking(0.5)
                                    Text(ariaContext)
                                        .font(.forgeDynamic(size: 11, design: .monospaced))
                                        .foregroundColor(.textTertiary)
                                        .lineSpacing(4)
                                }
                                .padding(14)
                                .background(Color.surface)
                                .cornerRadius(12)
                                .padding(.horizontal, 16)
                            }
                        }
                    }
                    Spacer()
                    HStack(spacing: 12) {
                        TextField("Ask about your sleep…", text: $input)
                            .font(.forgeDynamic(size: 15)).foregroundColor(.textPrimary).tint(.steel)
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            .background(Color.surfaceElevated).cornerRadius(14)
                        Button {} label: {
                            Circle().fill(Color.steel).frame(width: 44, height: 44)
                                .overlay(Image(systemName: "arrow.up").font(.forgeDynamic(size: 16, weight: .bold)).foregroundColor(.white))
                                .shadow(color: Color.steel.opacity(0.35), radius: 8, y: 3)
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 20)
                }
            }
            .navigationTitle("Sleep AI — ARIA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundColor(.steel).fontWeight(.semibold)
                }
            }
        }
    }
}

struct AISleepPredictionDetailView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Tonight's Recommendation").font(.forgeDynamic(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("10:15 PM").font(.forgeDynamic(size: 40, weight: .black, design: .rounded)).foregroundColor(.steel)
                                Text("bedtime").font(.forgeDynamic(size: 16)).foregroundColor(.textSecondary)
                            }
                            Text("Wake at 6:15 AM for 8 hours of sleep").font(.forgeDynamic(size: 14)).foregroundColor(.textSecondary)
                        }
                        .padding(20).background(Color.surface).cornerRadius(20)

                        VStack(alignment: .leading, spacing: 14) {
                            Text("Why This Time?").font(.forgeDynamic(size: 16, weight: .bold)).foregroundColor(.textPrimary)
                            VStack(spacing: 10) {
                                ForEach([("figure.strengthtraining.traditional", "Heavy workout tomorrow — need optimal recovery"),
                                         ("chart.line.uptrend.xyaxis", "Your 90-min sleep cycles align best with 10 PM"),
                                         ("heart.fill", "HRV trends show earlier sleep improves your recovery by 18%")], id: \.0) { icon, text in
                                    HStack(spacing: 12) {
                                        Image(systemName: icon).font(.forgeDynamic(size: 14)).foregroundColor(.steel).frame(width: 20)
                                        Text(text).font(.forgeDynamic(size: 13)).foregroundColor(.textPrimary)
                                    }
                                    .padding(14).background(Color.surfaceElevated).cornerRadius(12)
                                }
                            }
                        }
                        .padding(20).background(Color.surface).cornerRadius(20)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Sleep Prediction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundColor(.steel).fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Chronotype Badge

struct ChronotypeBadge: View {
    @EnvironmentObject var hkService: HealthKitSleepService
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: hkService.userProfile.chronotype.icon)
                    .font(.forgeDynamic(size: 14, weight: .semibold))
                    .foregroundColor(.steel)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(hkService.userProfile.chronotype.displayName) Chronotype")
                        .font(.forgeDynamic(size: 13, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Text(hkService.userProfile.chronotype.tagline)
                        .font(.forgeDynamic(size: 11))
                        .foregroundColor(.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "slider.horizontal.3")
                    .font(.forgeDynamic(size: 12, weight: .semibold))
                    .foregroundColor(.textTertiary)
            }
            .padding(14)
            .background(Color.surface)
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.steel.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Adaptive Sunrise Card

struct AdaptiveSunriseCard: View {
    let config: AdaptiveSunriseConfig
    @Binding var enabled: Bool
    @Binding var duration: Int
    @Binding var colorTemp: Double

    private var displayColor: Color {
        Color(
            red: 1.0,
            green: 0.6 + colorTemp * 0.35,
            blue: 0.3 + colorTemp * 0.7
        ).opacity(0.9)
    }

    var body: some View {
        WakeUpSection(icon: "sunrise.fill", title: "Adaptive Sunrise", color: Color.amber) {
            VStack(spacing: 16) {
                Toggle(isOn: $enabled) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Gradual light increase")
                            .font(.forgeDynamic(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
                        Text(config.rationale)
                            .font(.forgeDynamic(size: 12)).foregroundColor(.textTertiary)
                    }
                }
                .tint(Color.amber)

                if enabled {
                    VStack(spacing: 14) {
                        HStack {
                            Text("Duration").font(.forgeDynamic(size: 13, weight: .semibold)).foregroundColor(.textSecondary)
                            Spacer()
                            HStack(spacing: 4) {
                                Text("\(duration) min")
                                    .font(.forgeDynamic(size: 14, weight: .bold)).foregroundColor(.textPrimary)
                                Stepper("", value: $duration, in: 5...60, step: 5)
                                    .labelsHidden().tint(Color.amber)
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Color Temperature").font(.forgeDynamic(size: 13, weight: .semibold)).foregroundColor(.textSecondary)
                                Spacer()
                                Text(colorTemp < 0.3 ? "2700K Warm" : colorTemp < 0.7 ? "3500K Neutral" : "5000K Cool")
                                    .font(.forgeDynamic(size: 12, weight: .semibold)).foregroundColor(displayColor)
                            }
                            ZStack(alignment: .bottom) {
                                LinearGradient(
                                    colors: [Color(hex: "FF8C42"), Color(hex: "FFD166"), Color(hex: "FEFAE0"), Color(hex: "C8E6FF")],
                                    startPoint: .leading, endPoint: .trailing
                                )
                                .frame(height: 24).cornerRadius(12)
                                Slider(value: $colorTemp)
                                    .tint(.clear)
                                    .padding(.horizontal, 2)
                                    .accessibilityLabel("Color temperature")
                                    .accessibilityValue("\(Int(colorTemp * 100)) percent, warmer to cooler")
                            }
                        }

                        HStack(spacing: 8) {
                            ForEach(Array(stride(from: 0.1, through: 1.0, by: 0.18)), id: \.self) { t in
                                Circle()
                                    .fill(Color(
                                        red: 1.0,
                                        green: 0.4 + t * 0.55,
                                        blue: 0.1 + t * 0.85
                                    ))
                                    .frame(width: 8, height: 8)
                                    .frame(maxWidth: .infinity)
                                    .opacity(0.3 + t * Double(config.intensity))
                            }
                        }
                        .frame(height: 16)
                    }
                    .padding(12).background(Color.amber.opacity(0.06)).cornerRadius(12)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                }
            }
        }
    }
}

// MARK: - Sleep Personalization Sheet

struct SleepPersonalizationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var hkService: HealthKitSleepService
    @EnvironmentObject var store: AppStore
    @State private var draft = UserSleepProfile()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Your chronotype shapes scoring, goals, sunrise, and smart wake.")
                            .font(.forgeDynamic(size: 14))
                            .foregroundColor(.textSecondary)
                            .lineSpacing(4)

                        VStack(spacing: 10) {
                            ForEach(Chronotype.allCases) { type in
                                Button {
                                    draft.chronotype = type
                                    UISelectionFeedbackGenerator().selectionChanged()
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: type.icon)
                                            .font(.forgeDynamic(size: 18))
                                            .foregroundColor(draft.chronotype == type ? .white : .steel)
                                            .frame(width: 40, height: 40)
                                            .background(draft.chronotype == type ? Color.steel : Color.surfaceElevated)
                                            .cornerRadius(12)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(type.displayName)
                                                .font(.forgeDynamic(size: 15, weight: .semibold))
                                                .foregroundColor(.textPrimary)
                                            Text(type.tagline)
                                                .font(.forgeDynamic(size: 12))
                                                .foregroundColor(.textTertiary)
                                        }
                                        Spacer()
                                        if draft.chronotype == type {
                                            Image(systemName: "checkmark.circle.fill").foregroundColor(.steel)
                                        }
                                    }
                                    .padding(14)
                                    .background(Color.surface)
                                    .cornerRadius(14)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(draft.chronotype == type ? Color.steel.opacity(0.5) : Color.borderColor.opacity(0.4), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Coaching personality")
                                .font(.forgeDynamic(size: 13, weight: .semibold))
                                .foregroundColor(.textSecondary)
                            TextField("e.g. direct, encouraging, data-focused", text: $draft.personality)
                                .padding(12)
                                .background(Color.surfaceElevated)
                                .cornerRadius(12)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Lifestyle notes")
                                .font(.forgeDynamic(size: 13, weight: .semibold))
                                .foregroundColor(.textSecondary)
                            TextEditor(text: $draft.notes)
                                .frame(minHeight: 90)
                                .padding(8)
                                .background(Color.surfaceElevated)
                                .cornerRadius(12)
                                .scrollContentBackground(.hidden)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Sleep Profile")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { draft = hkService.userProfile }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        hkService.updateProfile(draft)
                        if !store.sleepData.isEmpty {
                            Task {
                                let rescored = await hkService.fetchRecentSleepData(days: 14)
                                store.mergeSleepDataLocally(rescored)
                            }
                        }
                        dismiss()
                    }
                    .foregroundColor(.steel)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        FlowResult(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews, spacing: spacing).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (i, sv) in subviews.enumerated() {
            sv.place(at: CGPoint(x: bounds.minX + result.positions[i].x, y: bounds.minY + result.positions[i].y), proposal: .unspecified)
        }
    }
    struct FlowResult {
        var size: CGSize = .zero; var positions: [CGPoint] = []
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0; var y: CGFloat = 0; var lineH: CGFloat = 0
            for sv in subviews {
                let sz = sv.sizeThatFits(.unspecified)
                if x + sz.width > maxWidth && x > 0 { x = 0; y += lineH + spacing; lineH = 0 }
                positions.append(CGPoint(x: x, y: y))
                lineH = max(lineH, sz.height); x += sz.width + spacing
            }
            size = CGSize(width: maxWidth, height: y + lineH)
        }
    }
}
