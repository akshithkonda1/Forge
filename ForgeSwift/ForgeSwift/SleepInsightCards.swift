import SwiftUI
import Charts

struct SleepStreakCard: View {
    let streak: Int
    @Binding var showDetail: Bool
    @State private var appeared = false

    var body: some View {
        Button { showDetail = true } label: {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color.ember, Color.ember.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 58, height: 58)
                        .shadow(color: Color.ember.opacity(0.45), radius: 10, y: 4)
                    Image(systemName: "moon.fill").font(.system(size: 26)).foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(streak)").font(.system(size: 28, weight: .black, design: .rounded)).foregroundColor(.textPrimary)
                        Text("nights in a row").font(.system(size: 16, weight: .medium)).foregroundColor(.textSecondary)
                    }
                    Text(streak >= 7 ? "A full week logged." : "Nights you actually slept — not a score.")
                        .font(.system(size: 13)).foregroundColor(.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundColor(.textMuted)
            }
            .padding(18)
            .background(Color.surface)
            .cornerRadius(20)
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.ember.opacity(0.2), lineWidth: 1))
            .shadow(color: .black.opacity(0.05), radius: 12, y: 4)
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.96)
        }
        .buttonStyle(.plain)
        .onAppear { withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) { appeared = true } }
    }
}

struct AISleepPredictionCard: View {
    @State private var appear = false
    @State private var showDetail = false

    var body: some View {
        Button { showDetail = true } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(Color.steel.opacity(0.15)).frame(width: 34, height: 34)
                        Image(systemName: "sparkles").font(.system(size: 14)).foregroundColor(.steel)
                    }
                    Text("AI Sleep Prediction").font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(.textMuted)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Optimal Bedtime Tonight")
                        .font(.system(size: 12)).foregroundColor(.textSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("10:15 PM")
                            .font(.system(size: 26, weight: .bold, design: .rounded)).foregroundColor(.steel)
                        Text("for peak recovery")
                            .font(.system(size: 13)).foregroundColor(.textTertiary)
                    }
                }
                Text("Based on workout intensity and your 7-day sleep pattern")
                    .font(.system(size: 12)).foregroundColor(.textMuted).lineLimit(2)
            }
            .padding(18)
            .background(Color.surface)
            .cornerRadius(20)
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.steel.opacity(0.25), lineWidth: 1))
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 10)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) { AISleepPredictionDetailView() }
        .onAppear { withAnimation(.easeOut(duration: 0.4).delay(0.1), { appear = true }) }
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
                    Label { Text("HRV (ms)").font(.system(size: 11)).foregroundColor(.textSecondary) } icon: { Circle().fill(Color.steel).frame(width: 8, height: 8) }
                    Label { Text("Resting HR").font(.system(size: 11)).foregroundColor(.textSecondary) } icon: { Circle().fill(Color.ember).frame(width: 8, height: 8) }
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
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
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
                Label { Text("Good (≥75)").font(.system(size: 11)).foregroundColor(.textSecondary) } icon: { Circle().fill(Color.steel).frame(width: 8, height: 8) }
                Spacer()
                Label { Text("Below target").font(.system(size: 11)).foregroundColor(.textSecondary) } icon: { Circle().fill(Color.warning).frame(width: 8, height: 8) }
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
                Image(systemName: "house.fill").font(.system(size: 14)).foregroundColor(.steel)
                Text("Sleep Environment").font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(Array(metrics.enumerated()), id: \.element.id) { i, m in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: m.icon).font(.system(size: 12)).foregroundColor(.steel)
                            Text(m.label).font(.system(size: 11)).foregroundColor(.textSecondary)
                        }
                        Text(m.value).font(.system(size: 17, weight: .bold)).foregroundColor(.textPrimary)
                        Text(m.status).font(.system(size: 10, weight: .semibold)).foregroundColor(m.color)
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
                Image(systemName: "target").font(.system(size: 14)).foregroundColor(.ember)
                Text("Sleep Goals").font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
            }
            VStack(spacing: 10) {
                ForEach(Array(goals.enumerated()), id: \.element.id) { i, g in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: g.icon).font(.system(size: 12)).foregroundColor(.steel)
                            Text(g.title).font(.system(size: 13, weight: .medium)).foregroundColor(.textPrimary)
                            Spacer()
                            Text(String(format: "%.1f / %.1f %@", g.current, g.target, g.unit))
                                .font(.system(size: 13, weight: .semibold)).foregroundColor(.textSecondary)
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
            Text("Smart Recommendations").font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
            VStack(spacing: 10) {
                ForEach(Array(recs.enumerated()), id: \.element.id) { i, rec in
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            Circle().fill(Color.steel.opacity(0.12)).frame(width: 38, height: 38)
                            Image(systemName: rec.icon).font(.system(size: 14)).foregroundColor(.steel)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(rec.title).font(.system(size: 13, weight: .semibold)).foregroundColor(.textPrimary)
                                Spacer()
                                Text(rec.priority)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(rec.priority == "High" ? .ember : .warning)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background((rec.priority == "High" ? Color.ember : Color.warning).opacity(0.12))
                                    .cornerRadius(6)
                            }
                            Text(rec.description).font(.system(size: 12)).foregroundColor(.textSecondary).lineLimit(2)
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
            Text("Achievements").font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(achievements.enumerated()), id: \.element.id) { i, a in
                        let color = achievementColor(a.colorName, unlocked: a.unlocked)
                        VStack(spacing: 10) {
                            ZStack {
                                Circle().fill(a.unlocked ? color.opacity(0.15) : Color.borderColor.opacity(0.25)).frame(width: 58, height: 58)
                                Image(systemName: achievementIcon(a.id)).font(.system(size: 24)).foregroundColor(a.unlocked ? color : .textMuted)
                            }
                            VStack(spacing: 3) {
                                Text(a.title).font(.system(size: 12, weight: .bold)).foregroundColor(.textPrimary)
                                Text(a.description).font(.system(size: 10)).foregroundColor(.textSecondary).multilineTextAlignment(.center)
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
    // Thresholds match EnergyScheduleCard's, deliberately. The two cards render
    // the same number and disagreeing about whether it is bad would be worse
    // than either of them being slightly off.
    var debtColor: Color { debt >= 8 ? .alert : debt >= 2 ? .amber : .vitality }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sleep Debt").font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%.1f", debt)).font(.system(size: 32, weight: .bold, design: .rounded)).foregroundColor(debtColor)
                        Text("hours").font(.system(size: 14)).foregroundColor(.textSecondary)
                    }
                    Text("Last 14 nights").font(.system(size: 12)).foregroundColor(.textTertiary)
                }
                Spacer()
                Text(debt >= 8 ? "Prioritize recovery" : debt >= 2 ? "Add 30 min tonight" : "On track! 🎉")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(debtColor)
                    .multilineTextAlignment(.trailing)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.borderColor.opacity(0.3)).frame(height: 8)
                    Capsule().fill(debtColor)
                        .frame(width: appeared ? geo.size.width * CGFloat(min(debt / 14, 1.0)) : 0, height: 8)
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
            QuickActionButton(icon: "chart.line.uptrend.xyaxis",  title: "Trends", color: Color(hex: "6366F1"), action: {})
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
                    Image(systemName: icon).font(.system(size: 18, weight: .medium)).foregroundColor(color)
                }
                Text(title).font(.system(size: 11, weight: .medium)).foregroundColor(.textPrimary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
