import SwiftUI
import Charts
import ForgeCore

struct HomeWinCard: View {
    @EnvironmentObject var store: AppStore

    private var title: String {
        if store.isWorkoutActive { return "You’re in a session" }
        if store.didTrainToday { return "You trained today" }
        if store.currentStreak > 0 { return "\(store.currentStreak) days trained in a row" }
        return "Nothing logged yet — that’s fine"
    }

    private var subtitle: String {
        if store.isWorkoutActive { return "Finish, then give recovery a real chance." }
        if store.didTrainToday { return "Sleep tonight is the rest of the work." }
        if store.currentStreak > 0 { return "A quiet fact, not a score to protect." }
        return "When you’re ready, ARIA will write today’s session from how you live."
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.ember.opacity(0.18))
                    .frame(width: 42, height: 42)
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.ember)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("TODAY")
                    .forgeSectionLabel()
                    .foregroundStyle(Color.ember)
                Text(title)
                    .font(HomeType.status)
                    .foregroundColor(.textPrimary)
                Text(subtitle)
                    .font(HomeType.body)
                    .foregroundColor(.textTertiary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.ember)
        }
        .padding(HomeMetrics.cardPadding)
        .forgeGlassCard(accent: .ember)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle)")
        .accessibilityHint("Opens the matching tab")
        .accessibilityAddTraits(.isButton)
        .onTapGesture {
            FDS.haptic(.light)
            if store.isWorkoutActive {
                store.activeTab = .workout
            } else if store.didTrainToday {
                store.activeTab = .sleep
                store.pendingSleepTab = "night"
            } else {
                store.openTrainHome()
            }
        }
    }
}

struct HomeAgendaCard: View {
    @EnvironmentObject var store: AppStore

    private var items: [(icon: String, title: String, sub: String, color: Color, action: () -> Void)] {
        var rows: [(icon: String, title: String, sub: String, color: Color, action: () -> Void)] = []

        if store.isWorkoutActive {
            rows.append((
                "figure.strengthtraining.traditional",
                "Continue session",
                store.todayWorkout?.name ?? "Active workout",
                .ember,
                { store.startExistingWorkout() }
            ))
        } else if let plan = store.todayWorkout {
            rows.append((
                "dumbbell.fill",
                plan.name,
                "\(plan.duration) min · \(plan.intensity.label)",
                .ember,
                { store.openTrainHome() }
            ))
        } else {
            rows.append((
                "sparkles",
                "Write today’s session",
                "ARIA shapes it from sleep and readiness",
                .ember,
                { store.openTrainHome() }
            ))
        }

        let sleepHours = store.dailyMetrics.totalSleep > 0
            ? Double(store.dailyMetrics.totalSleep) / 60.0
            : store.sleepData.first?.totalHours
        if let h = sleepHours, h > 0 {
            rows.append((
                "moon.zzz.fill",
                String(format: "Sleep · %.1fh", h),
                store.readiness.overall < 60 ? "Protect recovery tonight" : "Review wind-down",
                .steel,
                { store.activeTab = .sleep; store.pendingSleepTab = "night" }
            ))
        } else {
            rows.append((
                "moon.zzz.fill",
                "Log or sync sleep",
                "Apple Health sleep improves readiness",
                .steel,
                { store.activeTab = .sleep; store.pendingSleepTab = "night" }
            ))
        }

        rows.append((
            "drop.fill",
            "Hydration",
            "Log water and keep the pace",
            Color(hex: "4A9EFF"),
            { store.openHydration() }
        ))

        rows.append((
            "leaf.fill",
            "Lifestyle check-in",
            "Protein · water · meals",
            Color.vitality,
            { store.activeTab = .lifestyle }
        ))

        if MenstrualHealthStore.shared.settings.enabled {
            let snap = MenstrualHealthStore.shared.snapshot
            rows.append((
                snap.phase.icon,
                "Cycle · \(snap.phase.shortLabel)",
                snap.dayInCycle.map { "Day \($0)" } ?? snap.phase.label,
                Color(hex: snap.phase.accentHex),
                { store.openCycleHealth(pane: "me") }
            ))
        }

        return rows
    }

    var body: some View {
        // `items` is a computed property that rebuilds the whole row array; it was
        // being evaluated twice per render, once for the count and once for the
        // ForEach. Bind it once.
        let rows = items
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("TODAY'S AGENDA")
                    .forgeSectionLabel()
                Spacer()
                Text("\(rows.count) items")
                    .font(HomeType.micro)
                    .foregroundColor(.textMuted)
            }

            ForEach(Array(rows.enumerated()), id: \.offset) { _, item in
                Button {
                    FDS.haptic(.light)
                    item.action()
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(item.color.opacity(0.16))
                                .frame(width: 36, height: 36)
                            Image(systemName: item.icon)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(item.color)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(HomeType.status)
                                .foregroundColor(.textPrimary)
                                .lineLimit(1)
                            Text(item.sub)
                                .font(HomeType.body)
                                .foregroundColor(.textTertiary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.textMuted)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityHint(item.sub)
            }
        }
        .padding(HomeMetrics.cardPadding)
        .forgeGlassCard(accent: .ember.opacity(0.5))
        .homeEntrance(delay: 0.16)
    }
}

struct HomeLifestylePreviewCard: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        Button {
            FDS.haptic(.light)
            store.activeTab = .lifestyle
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("LIFESTYLE")
                        .forgeSectionLabel()
                    Spacer()
                    if let snap = QualityOfLifeLivingStore.load() {
                        Text("QoL \(snap.overall) · \(snap.qualityBand.label)")
                            .font(FDS.TypeScale.label(12))
                            .foregroundStyle(snap.qualityBand.color)
                    } else {
                        Text("Open")
                            .font(FDS.TypeScale.label(12))
                            .foregroundStyle(Color.vitality)
                    }
                }

                HStack(spacing: 10) {
                    lifestyleChip(
                        icon: "figure.walk",
                        value: store.dailyMetrics.steps > 0 ? store.dailyMetrics.steps.formatted() : "—",
                        label: "Steps",
                        color: Color.vitality
                    )
                    lifestyleChip(
                        icon: "flame.fill",
                        value: store.dailyMetrics.activeCalories > 0 ? "\(store.dailyMetrics.activeCalories)" : "—",
                        label: "Active",
                        color: .ember
                    )
                    lifestyleChip(
                        icon: "heart.fill",
                        value: store.dailyMetrics.hrv > 0 ? "\(store.dailyMetrics.hrv)" : "—",
                        label: "HRV",
                        color: .danger
                    )
                    lifestyleChip(
                        icon: "drop.fill",
                        value: {
                            let glasses = HealthKitManager.shared.todayStats?.water ?? 0
                            return glasses > 0 ? String(format: "%.1f", glasses) : "—"
                        }(),
                        label: "Water",
                        color: Color(hex: "4A9EFF")
                    )
                }

                HStack(spacing: 8) {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.amber)
                    Text("Nutrition · hydration · wellbeing — tap water for the full page")
                        .font(FDS.TypeScale.body(12))
                        .foregroundColor(.textTertiary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textMuted)
                }
            }
            .padding(HomeMetrics.cardPadding)
            .forgeGlassCard(accent: Color.vitality)
        }
        .buttonStyle(.plain)
        .homeEntrance(delay: 0.22)
        .accessibilityLabel("Lifestyle preview")
        .accessibilityHint("Opens the Lifestyle tab")
    }

    private func lifestyleChip(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: HomeMetrics.innerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: HomeMetrics.innerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

struct HomeDayPreviewStrip: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("DAY PREVIEW")
                    .forgeSectionLabel()
                Spacer()
                Button("Sleep") { store.activeTab = .sleep }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.ember)
            }

            // The tiles bleed to the screen edge instead of stopping at the page
            // inset, so the row reads as scrollable rather than clipped. The
            // negative outer inset is paid back as leading content padding, which
            // keeps the first tile aligned with the header above it.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    HomeMetricTile(
                        icon: "moon.zzz.fill",
                        iconColor: .steel,
                        value: sleepValue,
                        label: "Sleep"
                    )
                    HomeMetricTile(
                        icon: "waveform.path.ecg",
                        iconColor: .danger,
                        value: store.dailyMetrics.hrv > 0 ? "\(store.dailyMetrics.hrv)ms" : "—",
                        label: "HRV"
                    )
                    HomeMetricTile(
                        icon: "figure.walk",
                        iconColor: Color.vitality,
                        value: store.dailyMetrics.steps > 0 ? store.dailyMetrics.steps.formatted() : "—",
                        label: "Steps"
                    )
                    HomeMetricTile(
                        icon: "flame.fill",
                        iconColor: .ember,
                        value: store.dailyMetrics.activeCalories > 0 ? "\(store.dailyMetrics.activeCalories)" : "—",
                        label: "Active Cal"
                    )
                }
                .padding(.horizontal, HomeMetrics.inset)
            }
            .padding(.horizontal, -HomeMetrics.inset)
        }
        .homeEntrance(delay: 0.28)
    }

    private var sleepValue: String {
        let total = store.dailyMetrics.totalSleep
        if total <= 0 {
            if let last = store.sleepData.first {
                return String(format: "%.1fh", last.totalHours)
            }
            return "—"
        }
        let hours = Double(total) / 60.0
        return String(format: "%.1fh", hours)
    }
}

private struct HomeMetricTile: View {
    let icon: String
    let iconColor: Color
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                Circle().fill(iconColor.opacity(0.16)).frame(width: 36, height: 36)
                Image(systemName: icon).font(.system(size: 16)).foregroundColor(iconColor)
            }
            Text(value)
                .font(HomeType.metric)
                .foregroundColor(.textPrimary)
                .minimumScaleFactor(0.75)
                .lineLimit(1)
                .contentTransition(.numericText())
            Text(label)
                .font(HomeType.micro)
                .foregroundColor(.textTertiary)
        }
        .padding(14)
        .frame(width: 118, alignment: .leading)
        .forgeGlassCard(cornerRadius: HomeMetrics.innerRadius)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

/// Sleep-score series for the Home 7-day chart. Mapping is the existing
/// contract: last 7 nights, need ≥3, score clamped 30…100, oldest → newest.
struct HomeTrendPoint: Identifiable, Equatable {
    let id: String
    let day: String
    let score: Int
}

enum HomeTrendSeries {
    static let minimumNights = 3

    static func points(from sleeps: [SleepData]) -> [HomeTrendPoint] {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        let slice = Array(sleeps.prefix(7))
        guard slice.count >= minimumNights else { return [] }

        return slice.reversed().enumerated().map { index, sleep in
            let date = ISO8601DateFormatter().date(from: sleep.date)
                ?? DateFormatter.cachedYMD.date(from: sleep.date)
            let label = date.map { formatter.string(from: $0) } ?? formatter.string(from: Date())
            let score = min(100, max(30, sleep.score))
            return HomeTrendPoint(id: "\(sleep.date)-\(index)", day: label, score: score)
        }
    }

    static func average(_ points: [HomeTrendPoint]) -> Int? {
        guard !points.isEmpty else { return nil }
        return points.map(\.score).reduce(0, +) / points.count
    }

    static func accessibilitySummary(_ points: [HomeTrendPoint]) -> String {
        guard !points.isEmpty else {
            return "Seven-day signal. Not enough nights yet. Sleep a few more nights and the trend will show up here."
        }
        let latest = points[points.count - 1]
        let avg = average(points) ?? latest.score
        let days = points.map { "\($0.day) \($0.score)" }.joined(separator: ", ")
        return "Seven-day signal. Latest \(latest.score), average \(avg). \(days)."
    }
}

struct HomeTrendSection: View {
    @EnvironmentObject var store: AppStore
    @Binding var isExpanded: Bool
    /// Drives the chart grow-from-zero only; the card enters via `.homeEntrance`.
    @State private var chartGrown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var trendData: [HomeTrendPoint] {
        HomeTrendSeries.points(from: store.sleepData)
    }

    private var isLoading: Bool {
        store.dataLoadState == .loading && store.sleepData.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                guard !trendData.isEmpty else { return }
                FDS.haptic(.light)
                withAnimation(reduceMotion ? .easeOut(duration: 0.15) : FDS.Spring.standard) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text("7-DAY SIGNAL")
                        .forgeSectionLabel()
                    Spacer()
                    if isLoading {
                        ProgressView().controlSize(.mini)
                    } else if let avg = HomeTrendSeries.average(trendData) {
                        Text("Avg \(avg)")
                            .font(HomeType.micro)
                            .foregroundColor(.textMuted)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.ember)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(trendData.isEmpty)
            .accessibilityLabel(HomeTrendSeries.accessibilitySummary(trendData))
            .accessibilityHint(trendData.isEmpty ? "" : "Double tap to show more chart detail")
            .accessibilityAddTraits(.isHeader)

            if isLoading {
                RoundedRectangle(cornerRadius: HomeMetrics.innerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 72)
                    .overlay {
                        Text("Gathering the last few nights…")
                            .font(HomeType.body)
                            .foregroundColor(.textTertiary)
                    }
                    .accessibilityLabel("Seven-day signal is loading")
            } else if trendData.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("A few more nights")
                        .font(HomeType.status)
                        .foregroundColor(.textPrimary)
                    Text("Sleep three nights with Apple Health and this chart will fill in — no rush.")
                        .font(HomeType.body)
                        .foregroundColor(.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            } else {
                chart
                    .frame(height: isExpanded ? 140 : 88)
                    .accessibilityHidden(true)
            }
        }
        .padding(HomeMetrics.cardPadding)
        .forgeGlassCard()
        .onAppear {
            guard !chartGrown else { return }
            if reduceMotion {
                chartGrown = true
            } else {
                withAnimation(FDS.Spring.hero.delay(0.45)) { chartGrown = true }
            }
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced { chartGrown = true }
        }
        .homeEntrance(delay: 0.35)
    }

    private var chart: some View {
        let latest = trendData.last?.score ?? 0
        return Chart {
            if let avg = HomeTrendSeries.average(trendData) {
                RuleMark(y: .value("Average", avg))
                    .foregroundStyle(Color.textMuted.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .accessibilityHidden(true)
            }

            ForEach(Array(trendData.enumerated()), id: \.element.id) { i, point in
                AreaMark(
                    x: .value("Day", point.day),
                    y: .value("Score", plottedScore(point.score))
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [HomeReadiness.color(point.score).opacity(0.28), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Day", point.day),
                    y: .value("Score", plottedScore(point.score))
                )
                .foregroundStyle(HomeReadiness.color(latest))
                .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round))
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("Day", point.day),
                    y: .value("Score", plottedScore(point.score))
                )
                .foregroundStyle(HomeReadiness.color(point.score))
                .symbolSize(i == trendData.count - 1 ? 56 : 28)
            }
        }
        .chartYScale(domain: 0...100)
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .foregroundStyle(Color.textMuted)
                    .font(HomeType.micro)
            }
        }
        .chartYAxis(isExpanded ? .automatic : .hidden)
    }

    private func plottedScore(_ score: Int) -> Int {
        chartGrown || reduceMotion ? score : 0
    }
}

extension DateFormatter {
    static let cachedYMD: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
