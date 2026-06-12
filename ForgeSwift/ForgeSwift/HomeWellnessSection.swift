import SwiftUI

// MARK: - Proactive ARIA Brief

struct ARIABriefCard: View {
    @EnvironmentObject var store: AppStore
    @State private var appeared = false

    private var brief: ARIABrief? { store.activeBrief }

    private var periodLabel: String {
        guard let brief else { return "" }
        switch brief.focus {
        case .evening: return "PM"
        case .morning: return "AM"
        case .postWorkout: return "POST"
        default: return "NOW"
        }
    }

    var body: some View {
        Group {
            if let brief {
                Button {
                    FDS.haptic(.light)
                    store.activeTab = .chat
                } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "bell.badge.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.ember)
                            Text(brief.title.uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.textTertiary)
                                .tracking(1.5)
                            Spacer()
                            Text(periodLabel)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.ember)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.ember.opacity(0.12))
                                .cornerRadius(FDS.Radius.pill)
                        }

                        Text(brief.headline)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(brief.body)
                            .font(.system(size: 14))
                            .foregroundColor(.textSecondary)
                            .lineSpacing(4)
                            .lineLimit(4)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 6) {
                            Image(systemName: brief.trainingDecision.icon)
                            Text(brief.trainingDecision.label)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.ember)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        ZStack {
                            Color.surface
                            LinearGradient(
                                colors: [Color.ember.opacity(0.07), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        }
                    )
                    .cornerRadius(FDS.Radius.xl)
                    .overlay(
                        RoundedRectangle(cornerRadius: FDS.Radius.xl)
                            .stroke(Color.ember.opacity(0.22), lineWidth: 1)
                    )
                    .forgeCardShadow()
                }
                .buttonStyle(.plain)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)
                .onAppear {
                    withAnimation(FDS.Spring.hero.delay(0.08)) { appeared = true }
                }
            }
        }
    }
}

// MARK: - Daily Trilogy (Strain / Recovery / Sleep)

enum TrilogyMetric: String, Identifiable {
    case strain, recovery, sleep
    var id: String { rawValue }
}

struct DailyTrilogySection: View {
    @EnvironmentObject var store: AppStore
    @State private var appeared = false
    @State private var selectedMetric: TrilogyMetric?

    private var scores: DailyScores? { store.dailyScores }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("DAILY TRILOGY")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.textTertiary)
                        .tracking(2)
                    Text("Strain · Recovery · Sleep")
                        .font(.system(size: 11))
                        .foregroundColor(.textMuted)
                }
                Spacer()
                if let need = scores?.sleep.sleepNeedMinutes, need > 0 {
                    SleepNeedBadge(minutes: need)
                }
            }

            HStack(spacing: 12) {
                trilogyButton(.strain) {
                    TrilogyRingCard(
                        title: "Strain",
                        score: scores?.strain.score ?? store.readiness.overall,
                        color: Color(hex: "F97316"),
                        icon: "bolt.fill",
                        subtitle: scores?.strain.trend.capitalized ?? "—"
                    )
                }
                trilogyButton(.recovery) {
                    TrilogyRingCard(
                        title: "Recovery",
                        score: scores?.recovery.score ?? store.readiness.recoveryScore,
                        color: Color(hex: "22C55E"),
                        icon: "heart.fill",
                        subtitle: scores?.recovery.hrv.map { "HRV \($0)ms" } ?? "—"
                    )
                }
                trilogyButton(.sleep) {
                    TrilogyRingCard(
                        title: "Sleep",
                        score: scores?.sleep.score ?? store.readiness.sleepQuality,
                        color: Color(hex: "6366F1"),
                        icon: "moon.zzz.fill",
                        subtitle: sleepHoursLabel
                    )
                }
            }

            Text("Tap a ring for the breakdown")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.textMuted)
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(FDS.Radius.xl)
        .overlay(
            RoundedRectangle(cornerRadius: FDS.Radius.xl)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .forgeCardShadow()
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16)
        .onAppear {
            withAnimation(FDS.Spring.hero.delay(0.1)) { appeared = true }
        }
        .sheet(item: $selectedMetric) { metric in
            TrilogyDetailSheet(metric: metric)
                .environmentObject(store)
                .presentationDetents([.medium, .large])
        }
    }

    private func trilogyButton<Content: View>(_ metric: TrilogyMetric, @ViewBuilder content: () -> Content) -> some View {
        Button {
            FDS.haptic(.light)
            selectedMetric = metric
        } label: {
            content()
        }
        .buttonStyle(.plain)
    }

    private var sleepHoursLabel: String {
        guard let minutes = scores?.sleep.totalSleepMinutes, minutes > 0 else { return "—" }
        let h = minutes / 60
        let m = minutes % 60
        return m > 0 ? "\(h)h \(m)m" : "\(h)h"
    }
}

struct TrilogyDetailSheet: View {
    let metric: TrilogyMetric
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    private var scores: DailyScores? { store.dailyScores }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    ForEach(detailRows, id: \.0) { row in
                        DetailRow(label: row.0, value: row.1, note: row.2)
                    }
                    if !explainLines.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("WHY THIS SCORE")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.textTertiary)
                                .tracking(1.5)
                            ForEach(explainLines, id: \.self) { line in
                                Text("• \(line)")
                                    .font(.system(size: 13))
                                    .foregroundColor(.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.surfaceElevated)
                        .cornerRadius(FDS.Radius.lg)
                    }
                    Button {
                        dismiss()
                        store.activeTab = .chat
                    } label: {
                        Label("Ask ARIA why", systemImage: "sparkles")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.ember)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.ember.opacity(0.12))
                            .cornerRadius(FDS.Radius.lg)
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
            }
            .background(Color.background.ignoresSafeArea())
            .navigationTitle(metricTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.ember)
                }
            }
        }
    }

    private var metricTitle: String {
        switch metric {
        case .strain: return "Strain"
        case .recovery: return "Recovery"
        case .sleep: return "Sleep"
        }
    }

    private var header: some View {
        let score: Int = {
            switch metric {
            case .strain: return scores?.strain.score ?? store.readiness.overall
            case .recovery: return scores?.recovery.score ?? store.readiness.recoveryScore
            case .sleep: return scores?.sleep.score ?? store.readiness.sleepQuality
            }
        }()
        return HStack(alignment: .lastTextBaseline, spacing: 8) {
            Text("\(score)")
                .font(.system(size: 48, weight: .black, design: .rounded))
                .foregroundColor(.textPrimary)
            Text("/ 100")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.textMuted)
        }
    }

    private var detailRows: [(String, String, String?)] {
        switch metric {
        case .strain:
            let strain = scores?.strain
            return [
                ("Today's load", "\(strain?.todayLoad ?? 0)", "Steps + calories + workout volume"),
                ("Baseline", "\(strain?.baselineLoad ?? 0)", "Your recent training norm"),
                ("Trend", (strain?.trend ?? "flat").capitalized, nil),
                ("Steps", "\(store.dailyMetrics.steps)", nil),
                ("Active calories", "\(store.dailyMetrics.activeCalories) kcal", nil),
            ]
        case .recovery:
            let recovery = scores?.recovery
            return [
                ("HRV", recovery?.hrv.map { "\($0) ms" } ?? "—", "Higher HRV supports harder training"),
                ("Trend", (recovery?.trend ?? "unknown").capitalized, nil),
                ("Readiness", "\(store.readiness.overall)", "Composite recovery signal"),
                ("Training decision", scores?.trainingDecision.label ?? "—", nil),
            ]
        case .sleep:
            let sleep = scores?.sleep
            return [
                ("Total sleep", formatMinutes(sleep?.totalSleepMinutes ?? store.dailyMetrics.totalSleep), nil),
                ("Deep sleep", formatMinutes(sleep?.deepSleepMinutes ?? store.dailyMetrics.deepSleep), nil),
                ("Sleep need", formatMinutes(sleep?.sleepNeedMinutes ?? 0), "Debt-aware target"),
                ("Last night score", "\(sleep?.score ?? store.readiness.sleepQuality)", nil),
            ]
        }
    }

    private var explainLines: [String] {
        var lines: [String] = []
        let flags = store.dataConclusions?.compoundFlags ?? []
        switch metric {
        case .strain:
            if let strain = scores?.strain {
                if strain.todayLoad > strain.baselineLoad {
                    lines.append("Today's load is above your baseline — strain is elevated.")
                } else {
                    lines.append("Load is within your baseline band.")
                }
                if strain.trend == "rising" {
                    lines.append("Training load trend is rising across recent sessions.")
                }
            }
        case .recovery:
            if flags.contains("recovery-debt-under-load") {
                lines.append("Recovery debt is stacking under continued load.")
            }
            if let hrv = scores?.recovery.hrv, hrv < 40 {
                lines.append("HRV is suppressed — prioritize down-regulation today.")
            }
            if scores?.cycleContext.recommendRecovery == true {
                lines.append("Cycle context suggests a recovery bias.")
            }
        case .sleep:
            if let sleep = scores?.sleep, sleep.totalSleepMinutes < sleep.sleepNeedMinutes {
                lines.append("You're under your sleep need — score is discounted.")
            }
            if store.dailyMetrics.deepSleep < 60 {
                lines.append("Deep sleep is light; quality component is reduced.")
            }
        }
        return lines
    }

    private func formatMinutes(_ minutes: Int) -> String {
        guard minutes > 0 else { return "—" }
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }
}

private struct DetailRow: View {
    let label: String
    let value: String
    let note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.textSecondary)
                Spacer()
                Text(value)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.textPrimary)
            }
            if let note {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundColor(.textMuted)
            }
        }
    }
}

private struct TrilogyRingCard: View {
    let title: String
    let score: Int
    let color: Color
    let icon: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.15), lineWidth: 6)
                    .frame(width: 72, height: 72)
                Circle()
                    .trim(from: 0, to: CGFloat(score) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 72, height: 72)
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(color)
                    Text("\(score)")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(.textPrimary)
                }
            }
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.textSecondary)
            Text(subtitle)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SleepNeedBadge: View {
    let minutes: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "bed.double.fill")
                .font(.system(size: 10))
            Text("Need \(formatNeed(minutes))")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(Color(hex: "6366F1"))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(hex: "6366F1").opacity(0.12))
        .cornerRadius(FDS.Radius.pill)
    }

    private func formatNeed(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }
}

// MARK: - Today Action Card

struct TodayActionCard: View {
    @EnvironmentObject var store: AppStore
    @State private var appeared = false

    private var decision: TrainingDecision {
        store.dailyScores?.trainingDecision ?? .activeRest
    }

    private var accent: Color {
        switch decision {
        case .train: return .ember
        case .activeRest: return Color(hex: "F59E0B")
        case .recover: return Color(hex: "6366F1")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.18))
                        .frame(width: 48, height: 48)
                    Image(systemName: decision.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(accent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("TODAY'S ACTION")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.textTertiary)
                        .tracking(1.5)
                    Text(decision.label)
                        .font(.system(size: 22, weight: .black))
                        .foregroundColor(.textPrimary)
                }
                Spacer()
            }

            Text(actionCopy)
                .font(.system(size: 14))
                .foregroundColor(.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            if let workout = store.todayWorkout, decision == .train {
                HStack(spacing: 8) {
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.ember)
                    Text(workout.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Spacer()
                    Text("\(workout.duration) min")
                        .font(.system(size: 12))
                        .foregroundColor(.textMuted)
                }
                .padding(12)
                .background(Color.surfaceElevated)
                .cornerRadius(FDS.Radius.md)
            }
        }
        .padding(20)
        .background(
            ZStack {
                Color.surface
                LinearGradient(
                    colors: [accent.opacity(0.08), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
        .cornerRadius(FDS.Radius.xl)
        .overlay(
            RoundedRectangle(cornerRadius: FDS.Radius.xl)
                .stroke(accent.opacity(0.25), lineWidth: 1)
        )
        .forgeCardShadow()
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .onAppear {
            withAnimation(FDS.Spring.hero.delay(0.15)) { appeared = true }
        }
    }

    private var actionCopy: String {
        if let brief = store.dataConclusions?.coachingBrief, !brief.isEmpty {
            return brief
        }
        if let note = store.dailyScores?.cycleContext.coachingNote {
            return note
        }
        switch decision {
        case .train:
            return "Recovery and sleep support a hard session. Execute today's plan with intent."
        case .activeRest:
            return "Keep movement light — mobility, zone-2 cardio, or technique work. Protect tomorrow's performance."
        case .recover:
            return "Prioritize sleep, hydration, and down-regulation. Skip max-effort work until markers rebound."
        }
    }
}

// MARK: - Biological Age Card

struct BiologicalAgeCard: View {
    @EnvironmentObject var store: AppStore

    private var bio: BiologicalAge? { store.biologicalAge }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "hourglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(hex: "38BDF8"))
                Text("BIOLOGICAL AGE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.textTertiary)
                    .tracking(1.5)
            }

            if let bio {
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(String(format: "%.1f", bio.biologicalAge))
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundColor(.textPrimary)
                    Text("yrs")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.textMuted)
                }

                HStack(spacing: 6) {
                    Text("Chrono \(bio.chronologicalAge)")
                        .font(.system(size: 11))
                        .foregroundColor(.textMuted)
                    DeltaBadge(delta: bio.deltaYears)
                }

                if !bio.drivers.isEmpty {
                    Text(driverLabel(bio.drivers.first ?? ""))
                        .font(.system(size: 11))
                        .foregroundColor(.textSecondary)
                        .lineLimit(2)
                }
            } else {
                Text("—")
                    .font(.system(size: 28, weight: .black))
                    .foregroundColor(.textMuted)
                Text("Connect health data")
                    .font(.system(size: 11))
                    .foregroundColor(.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.surface)
        .cornerRadius(FDS.Radius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: FDS.Radius.lg)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func driverLabel(_ key: String) -> String {
        switch key {
        case "strong_hrv": return "Strong HRV pulling age down"
        case "quality_sleep": return "Quality sleep supporting youth markers"
        case "active_lifestyle": return "Active lifestyle offsetting age"
        case "recovery_lag": return "Recovery lag adding biological years"
        case "youthful_markers": return "Markers trending younger than calendar age"
        default: return key.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

private struct DeltaBadge: View {
    let delta: Double

    var body: some View {
        let positive = delta > 0
        HStack(spacing: 2) {
            Image(systemName: positive ? "arrow.up" : "arrow.down")
                .font(.system(size: 9, weight: .bold))
            Text(String(format: "%+.1f", delta))
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(positive ? Color(hex: "EF4444") : Color(hex: "22C55E"))
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background((positive ? Color(hex: "EF4444") : Color(hex: "22C55E")).opacity(0.12))
        .cornerRadius(FDS.Radius.pill)
    }
}

// MARK: - Cycle Context Card

struct CycleContextCard: View {
    @EnvironmentObject var store: AppStore

    private var cycle: CycleContext? { store.dailyScores?.cycleContext }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: cycle?.phase.icon ?? "circle.dashed")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(hex: "EC4899"))
                Text("CYCLE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.textTertiary)
                    .tracking(1.5)
            }

            if let cycle, cycle.hasData {
                Text(cycle.phase.label)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.textPrimary)
                if let day = cycle.dayInCycle {
                    Text("Day \(day)")
                        .font(.system(size: 11))
                        .foregroundColor(.textMuted)
                }
                if cycle.recommendRecovery {
                    Label("Recovery focus", systemImage: "heart.text.square")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(hex: "EC4899"))
                }
            } else {
                Text("No data")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.textMuted)
                Text("Enable cycle tracking in Health")
                    .font(.system(size: 10))
                    .foregroundColor(.textMuted)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.surface)
        .cornerRadius(FDS.Radius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: FDS.Radius.lg)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

// MARK: - Home nutrition snapshot

struct HomeNutritionSection: View {
    @EnvironmentObject var store: AppStore
    @State private var appeared = false

    private var nutrition: LifestyleNutritionSnapshot? { store.nutritionSnapshot }
    private var targetCal: Int { Int(nutrition?.targets.calories ?? 2600) }
    private var currentCal: Int { Int(nutrition?.calories ?? 0) }
    private var proteinTarget: Int { Int(nutrition?.targets.protein ?? 180) }
    private var proteinCurrent: Int { Int(nutrition?.protein ?? 0) }
    private var waterMl: Int { Int(nutrition?.waterMl ?? 0) }
    private var waterGoal: Int { 2500 }

    var body: some View {
        Button {
            FDS.haptic(.light)
            store.pendingProfileSubTab = "Lifestyle"
            store.activeTab = .profile
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("NUTRITION")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.textTertiary)
                            .tracking(2)
                        Text(hasData ? "Today's fuel" : "Log your first meal")
                            .font(.system(size: 11))
                            .foregroundColor(.textMuted)
                    }
                    Spacer()
                    Image(systemName: "fork.knife")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.ember)
                }

                HStack(spacing: 16) {
                    NutritionStatRing(
                        label: "Calories",
                        current: currentCal,
                        target: targetCal,
                        color: .ember
                    )
                    NutritionStatRing(
                        label: "Protein",
                        current: proteinCurrent,
                        target: proteinTarget,
                        color: Color(hex: "22C55E")
                    )
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Water")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.textSecondary)
                        Text("\(waterMl) ml")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundColor(.textPrimary)
                        ProgressView(value: min(Double(waterMl) / Double(waterGoal), 1))
                            .tint(Color(hex: "38BDF8"))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
            .background(Color.surface)
            .cornerRadius(FDS.Radius.xl)
            .overlay(
                RoundedRectangle(cornerRadius: FDS.Radius.xl)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
            .forgeCardShadow()
        }
        .buttonStyle(.plain)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .onAppear {
            withAnimation(FDS.Spring.hero.delay(0.12)) { appeared = true }
        }
    }

    private var hasData: Bool {
        currentCal > 0 || proteinCurrent > 0 || waterMl > 0 || !(nutrition?.meals.isEmpty ?? true)
    }
}

private struct NutritionStatRing: View {
    let label: String
    let current: Int
    let target: Int
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.15), lineWidth: 5)
                    .frame(width: 56, height: 56)
                Circle()
                    .trim(from: 0, to: target > 0 ? CGFloat(current) / CGFloat(target) : 0)
                    .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 56, height: 56)
                    .rotationEffect(.degrees(-90))
                Text("\(current)")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(.textPrimary)
            }
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.textSecondary)
            Text("\(max(target - current, 0)) left")
                .font(.system(size: 9))
                .foregroundColor(.textMuted)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Wellness insights row (bio age + cycle)

struct WellnessInsightsRow: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        HStack(spacing: 12) {
            BiologicalAgeCard()
            if showCycleCard {
                CycleContextCard()
            }
        }
    }

    private var showCycleCard: Bool {
        let gender = store.userProfile.gender
        return gender == .female || store.dailyScores?.cycleContext.hasData == true
    }
}