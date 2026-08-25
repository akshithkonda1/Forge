import SwiftUI
import Charts

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
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.textTertiary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(HomeMetrics.cardPadding)
        .forgeGlassCard(accent: .ember)
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
                { store.activeTab = .workout }
            ))
        } else if let plan = store.todayWorkout {
            rows.append((
                "dumbbell.fill",
                plan.name,
                "\(plan.duration) min · \(plan.intensity.label)",
                .ember,
                { store.activeTab = .workout }
            ))
        } else {
            rows.append((
                "sparkles",
                "Build today's plan",
                "ARIA will shape a session from readiness",
                .ember,
                { store.openChat(with: "Build today's training plan from my readiness.", voice: false) }
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
                { store.activeTab = .sleep }
            ))
        } else {
            rows.append((
                "moon.zzz.fill",
                "Log or sync sleep",
                "Apple Health sleep improves readiness",
                .steel,
                { store.activeTab = .sleep }
            ))
        }

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
                    .font(.system(size: 11, weight: .medium))
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
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.textPrimary)
                                .lineLimit(1)
                            Text(item.sub)
                                .font(.system(size: 12))
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
                    Text("Open")
                        .font(FDS.TypeScale.label(12))
                        .foregroundStyle(Color.vitality)
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
        .background(Color.surfaceElevated.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: HomeMetrics.innerRadius, style: .continuous))
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
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.textPrimary)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.textTertiary)
        }
        .padding(14)
        .frame(width: 118, alignment: .leading)
        .forgeGlassCard(cornerRadius: HomeMetrics.innerRadius)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

struct HomeTrendSection: View {
    @EnvironmentObject var store: AppStore
    @Binding var isExpanded: Bool
    /// Drives the chart grow-from-zero only; the card enters via `.homeEntrance`.
    @State private var chartGrown = false

    /// Real-ish series from sleep scores when available; otherwise empty.
    private var trendData: [(day: String, score: Int)] {
        _ = Calendar.current
        let f = DateFormatter()
        f.dateFormat = "EEE"
        let sleeps = store.sleepData.prefix(7)
        guard sleeps.count >= 3 else { return [] }

        return sleeps.reversed().enumerated().map { _, sleep in
            let label: String = {
                if let date = ISO8601DateFormatter().date(from: sleep.date)
                    ?? DateFormatter.cachedYMD.date(from: sleep.date) {
                    return f.string(from: date)
                }
                return f.string(from: Date())
            }()
            // Map sleep score into readiness-like 0–100 band
            let score = min(100, max(30, sleep.score))
            return (label, score)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                FDS.haptic(.light)
                withAnimation(FDS.Spring.standard) { isExpanded.toggle() }
            } label: {
                HStack {
                    Text("7-DAY SIGNAL")
                        .forgeSectionLabel()
                    Spacer()
                    if trendData.isEmpty {
                        Text("Not enough data")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.textMuted)
                    } else {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.ember)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(trendData.isEmpty)

            if isExpanded, !trendData.isEmpty {
                Chart {
                    ForEach(Array(trendData.enumerated()), id: \.offset) { i, point in
                        AreaMark(
                            x: .value("Day", point.day),
                            y: .value("Score", chartGrown ? point.score : 0)
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
                            y: .value("Score", chartGrown ? point.score : 0)
                        )
                        .foregroundStyle(HomeReadiness.color(point.score))
                        .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round))
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Day", point.day),
                            y: .value("Score", chartGrown ? point.score : 0)
                        )
                        .foregroundStyle(HomeReadiness.color(point.score))
                        .symbolSize(i == trendData.count - 1 ? 56 : 28)
                    }
                }
                .chartYScale(domain: 0...100)
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel().foregroundStyle(Color.textMuted)
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 88)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(HomeMetrics.cardPadding)
        .forgeGlassCard()
        .onAppear {
            guard !chartGrown else { return }
            withAnimation(FDS.Spring.hero.delay(0.45)) { chartGrown = true }
        }
        .homeEntrance(delay: 0.35)
    }
}

extension DateFormatter {
    static let cachedYMD: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
