import SwiftUI
import Combine
import Charts
import UIKit
import Contacts
import ForgeCore

/// Wellbeing segment (spec §14). The DailyHabitsCard plate opens the segment
/// directly under the rail; every other card is a tinted content card at
/// Home's 16 pt section rhythm, with no halos.
struct WellbeingView: View {
    @ObservedObject var vm: LifestyleViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.sectionGap) {
            DailyHabitsCard()
            YourPeopleCard()
            HobbyPathCard()
            HabitLoopListCard(vm: vm)
            MindfulnessCard(vm: vm)
            MindfulTrendCard(trend: vm.mindfulTrend)
            StressManagementCard(stats: vm.healthStats)
            SleepOptimizationCard(stats: vm.healthStats, metrics: vm.metrics)
        }
    }
}

struct MindfulTrendCard: View {
    let trend: [MindfulDay]

    /// Plot height grows with Dynamic Type so the micro axis labels keep room.
    @ScaledMetric(relativeTo: .caption) private var trendPlotSize: CGFloat = 96

    private var total: Int { Int(trend.reduce(0) { $0 + $1.minutes }) }

    private var hasSessions: Bool {
        !trend.isEmpty && !trend.allSatisfy({ $0.minutes == 0 })
    }

    /// VoiceOver summary: the week's total, then every day's minutes, so the
    /// bars are reachable without reading the plot.
    private var chartSummary: String {
        let days = trend.map { day in
            "\(day.date.formatted(.dateTime.weekday(.abbreviated))) \(Int(day.minutes.rounded())) min"
        }
        return "This week, \(total) min: " + days.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("This week", meta: "\(total) min")

            if hasSessions {
                trendChart
            } else {
                ForgeEmptyNote(
                    title: "No sessions yet — 5 minutes still counts.",
                    systemImage: "figure.mind.and.body",
                    tint: .vitality
                )
            }
        }
        .forgeContentCard(tint: .vitality)
    }

    private var trendChart: some View {
        Chart(trend) { day in
            BarMark(
                x: .value("Day", day.date, unit: .day),
                y: .value("Minutes", day.minutes)
            )
            .foregroundStyle(Color.vitality.gradient)
            .cornerRadius(FDS.Radius.xs) // Charts mark API (continuous), not View.cornerRadius
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.narrow))
                    .font(HomeType.micro)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine()
                    .foregroundStyle(Color.white.opacity(0.06))
                AxisValueLabel()
                    .font(HomeType.micro)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .frame(height: ForgeLayout.scaledCap(trendPlotSize, base: 96))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(chartSummary)
    }
}

struct QOLTrendCard: View {
    let history: [QOLDay]

    /// Plot height grows with Dynamic Type so the micro axis labels keep room.
    @ScaledMetric(relativeTo: .caption) private var qolPlotSize: CGFloat = 140

    private var recent: [QOLDay] { Array(history.suffix(30)) }

    /// Area wash under the line: the card's own domain color, fading out.
    private static let areaFill = LinearGradient(
        colors: [Color.vitality.opacity(0.22), Color.vitality.opacity(0.02)],
        startPoint: .top,
        endPoint: .bottom
    )

    /// VoiceOver summary built from the plotted values.
    private var chartSummary: String {
        let scores = recent.map(\.score)
        guard let last = scores.last, let low = scores.min(), let high = scores.max() else {
            return "Quality of Life Trend"
        }
        return "Quality of Life Trend, last \(recent.count) days: now \(last) of 100, range \(low) to \(high)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader(title: "Quality of Life Trend") {
                if let last = recent.last {
                    ForgeCardMeta(text: "\(last.score)/100", color: HomeReadiness.color(last.score))
                }
            }

            if recent.count < 2 {
                ForgeEmptyNote(
                    title: "Your QOL trend appears after a couple of days of tracking.",
                    systemImage: "chart.line.uptrend.xyaxis",
                    tint: .vitality
                )
            } else {
                qolChart
            }
        }
        .forgeContentCard(tint: .vitality)
    }

    private var qolChart: some View {
        Chart(recent) { day in
            AreaMark(
                x: .value("Day", day.date, unit: .day),
                y: .value("QOL", day.score)
            )
            .foregroundStyle(Self.areaFill)
            .interpolationMethod(.catmullRom)

            LineMark(
                x: .value("Day", day.date, unit: .day),
                y: .value("QOL", day.score)
            )
            .foregroundStyle(Color.vitality)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .interpolationMethod(.catmullRom)
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 50, 100]) { _ in
                AxisGridLine()
                    .foregroundStyle(Color.white.opacity(0.06))
                AxisValueLabel()
                    .font(HomeType.micro)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .font(HomeType.micro)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .frame(height: ForgeLayout.scaledCap(qolPlotSize, base: 140))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(chartSummary)
    }
}

/// The Wellbeing hero (spec §14): one plate, one ring that answers "how is
/// today going", then the habits themselves. No primary CTA; the rows are the
/// action. The ring glows once, with a success haptic, when the last habit
/// closes (event-only glow, spec §8).
struct DailyHabitsCard: View {
    @State private var habits: [DailyHabit] = LifestyleWellbeingStore.loadHabits()
    /// Presentation only: the one-shot ring glow when every habit is done.
    @State private var eventGlow = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title3) private var habitRingSize: CGFloat = 96

    var completed: Int { habits.filter(\.done).count }

    /// 0–100 for the ring. An empty list reads 0 instead of dividing by zero.
    private var percent: Int {
        habits.isEmpty ? 0 : completed * 100 / habits.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.heroGap) {
            summary
            habitList
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .hudPlate(energy: .vitality)
        .accessibilityElement(children: .contain)
    }

    /// Ring beside the eyebrow and streak; stacks at accessibility sizes so
    /// the streak line never squeezes against the ring.
    private var summary: some View {
        ForgeAdaptiveStack(spacing: FDS.Spacing.lg, alignment: .center) {
            habitRing
            summaryCopy
        }
    }

    private var habitRing: some View {
        HudProgressRing(
            progress: percent,
            energy: .vitality,
            size: ForgeLayout.scaledCap(habitRingSize, base: 96),
            stroke: HudChrome.compactStroke,
            eventGlow: eventGlow
        ) {
            Text("\(completed)/\(habits.count)")
                .font(HomeType.metric)
                .foregroundStyle(Color.textPrimary)
                .hudInArcText()
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Daily habits, \(completed) of \(habits.count) done")
    }

    private var summaryCopy: some View {
        let streak = LifestyleWellbeingStore.habitStreak()
        return VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
            Text("Daily Habits")
                .forgeSectionLabel()
                .lineLimit(1)
                .minimumScaleFactor(ForgeLayout.labelMinScale)
                .accessibilityAddTraits(.isHeader)
            Text("\(streak)-day streak")
                .font(HomeType.status)
                .foregroundStyle(Color.textPrimary)
                .contentTransition(.numericText())
                .forgeWrapping()
            // Encouragement only once there is a streak to keep.
            if streak > 0 {
                Text("Keep it up 🔥")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var habitList: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            ForEach($habits) { $habit in
                HabitRow(name: habit.name, isDone: habit.done) {
                    if reduceMotion {
                        habit.done.toggle()
                    } else {
                        withAnimation(FDS.Spring.snap) {
                            habit.done.toggle()
                        }
                    }
                    LifestyleWellbeingStore.saveHabits(habits)
                    acknowledgeToggle()
                }
            }
        }
    }

    /// Selection haptic per tap; closing the last habit is the event moment.
    private func acknowledgeToggle() {
        guard !habits.isEmpty, completed == habits.count else {
            FDS.haptic(.select)
            return
        }
        FDS.haptic(.success)
        eventGlow = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.35) {
            eventGlow = false
        }
    }
}

/// Agenda-row anatomy for a checkable habit: a scaled check, the name in the
/// row-title role, 44 pt of tap height from `forgeTapOutset` so rows keep
/// Home's 12 pt rhythm without crowding.
struct HabitRow: View {
    let name: String
    let isDone: Bool
    let onToggle: () -> Void

    @ScaledMetric(relativeTo: .subheadline) private var checkSize: CGFloat = 24

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: ForgeLayout.rowGap) {
                checkMark
                Text(name)
                    .font(HomeType.status)
                    .foregroundStyle(isDone ? Color.textTertiary : Color.textPrimary)
                    .strikethrough(isDone, color: .textTertiary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, ForgeLayout.rowVerticalPadding)
            .forgeTapOutset(vertical: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isDone ? .isSelected : [])
    }

    private var checkMark: some View {
        let size = ForgeLayout.scaledCap(checkSize, base: 24)
        return ZStack {
            Circle()
                .stroke(isDone ? Color.vitality : Color.white.opacity(0.24), lineWidth: 1.5)
            if isDone {
                Circle()
                    .fill(Color.vitality)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.46, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
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
        case .breathe: return Color.steel
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The orb grows with Dynamic Type (capped) so the timer never overflows it.
    @ScaledMetric(relativeTo: .largeTitle) private var orbSize: CGFloat = 132

    private var practiceOptions: [ForgeSegmentOption<MindfulPractice>] {
        MindfulPractice.allCases.map { ForgeSegmentOption(value: $0, title: $0.title) }
    }

    private var lengthOptions: [ForgeSegmentOption<Int>] {
        lengths.map { ForgeSegmentOption(value: $0, title: "\($0)m") }
    }

    /// Four blocks (spec §2.4): header, practice, length, session.
    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader(title: "Mindfulness") {
                ForgeCardMeta(text: "\(max(vm.mindfulMinutesToday, 0)) min · \(max(vm.mindfulMinutesWeek, 0)) this week")
                    .minimumScaleFactor(ForgeLayout.labelMinScale)
            }
            practiceBlock
            if !isRunning {
                ForgeSegmentedControl(
                    lengthOptions,
                    selection: $minutes,
                    accent: .vitality,
                    bleed: ForgeLayout.cardPadding
                )
            }
            sessionBlock
        }
        .forgeContentCard(tint: .vitality)
        .onDisappear { timer?.invalidate() }
    }

    /// Practice selector and its one-line description. Locked while a
    /// session runs.
    private var practiceBlock: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            ForgeSegmentedControl(
                practiceOptions,
                selection: $practice,
                accent: .vitality,
                bleed: ForgeLayout.cardPadding
            )
            .disabled(isRunning)
            .opacity(isRunning ? 0.5 : 1)

            Text(practice.line)
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
        }
    }

    /// The orb and its one action.
    private var sessionBlock: some View {
        VStack(spacing: ForgeLayout.blockGap) {
            breathingOrb
            ForgeSecondaryButton(
                title: isRunning ? "End" : "Begin \(practice.title.lowercased())",
                icon: isRunning ? "stop.fill" : "play.fill",
                accent: isRunning ? HudChrome.emberSteel : Color.vitality
            ) {
                if isRunning {
                    stopSession(logged: remainingSeconds < minutes * 60)
                } else {
                    startSession()
                }
            }
        }
    }

    /// Box-breath cue from the session clock, in step with the orb's
    /// 4 s inhale / 4 s exhale.
    private var breathCue: String {
        let elapsed = max(0, minutes * 60 - remainingSeconds)
        return (elapsed / 4) % 2 == 0 ? "in" : "out"
    }

    /// The disc breathes only while a user-started session runs (spec §8);
    /// under Reduce Motion it holds still.
    private var orbAnimation: Animation? {
        if reduceMotion { return nil }
        if isRunning {
            return Animation.easeInOut(duration: 4).repeatForever(autoreverses: true)
        }
        return Animation.easeOut(duration: 0.35)
    }

    private var breathingOrb: some View {
        let size = ForgeLayout.scaledCap(orbSize, base: 132)
        let disc = size * (inhale ? 104.0 / 132.0 : 78.0 / 132.0)
        return ZStack {
            Circle()
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 8)
            Circle()
                .fill(Color.vitality.opacity(inhale ? 0.14 : 0.07))
                .frame(width: disc, height: disc)
                .animation(orbAnimation, value: inhale)
            orbLabel
                .padding(.horizontal, FDS.Spacing.lg)
        }
        .frame(width: size, height: size)
        .frame(maxWidth: .infinity)
        .padding(.vertical, FDS.Spacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isRunning ? .updatesFrequently : [])
    }

    /// One number style idle and running, so nothing jumps on Begin.
    private var orbLabel: some View {
        VStack(spacing: ForgeLayout.labelValueGap) {
            Text(isRunning ? timeString(remainingSeconds) : "\(minutes):00")
                .font(HomeType.heroScore)
                .foregroundStyle(Color.textPrimary)
                .hudInArcText()
                .contentTransition(.numericText())
            Text(isRunning ? breathCue : practice.title.lowercased())
                .font(HomeType.micro)
                .foregroundStyle(Color.textTertiary)
                .tracking(1.4)
                .textCase(.uppercase)
                .hudInArcText()
        }
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

    private var levelOptions: [ForgeSegmentOption<Int>] {
        levels.enumerated().map { ForgeSegmentOption(value: $0.offset, title: $0.element.label) }
    }

    /// The user's pick is saved the moment they make it, exactly as before;
    /// the HRV read in `onAppear` still only updates what is shown.
    private var levelSelection: Binding<Int> {
        Binding(
            get: { selectedLevel },
            set: { level in
                selectedLevel = level
                LifestyleWellbeingStore.saveStressLevel(level)
            }
        )
    }

    private var levelName: String {
        let names = ["low", "balanced", "high"]
        return names.indices.contains(selectedLevel) ? names[selectedLevel] : names[1]
    }

    /// Status map (spec §5): low stress reads as met, high as a fair-band
    /// warning, never alert red.
    private var levelColor: Color {
        switch selectedLevel {
        case 0: return Color.vitality
        case 2: return Color.amber
        default: return Color.steel
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("Stress", meta: levelName, metaColor: levelColor)

            ForgeSegmentedControl(
                levelOptions,
                selection: levelSelection,
                accent: .vitality,
                bleed: ForgeLayout.cardPadding
            )

            Text(stressTip)
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
        }
        .forgeContentCard(tint: .vitality)
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
        // Colors follow the spec §5 status map: this is advice, not an error,
        // so nothing here is warning yellow or alert red.
        var generated: [(icon: String, tip: String, color: Color)] = [
            ("moon.fill", "Aim for \(String(format: "%.1f", metrics.sleepTarget))h tonight (\(String(format: "%.1f", sleepGap))h to go)", .steel),
            ("iphone.slash", "No screens 45 min before bed", .amber),
            ("thermometer.medium", "Keep room at 65–68°F", .vitality),
        ]
        if (stats?.caffeine ?? 0) > 200 {
            generated.append(("cup.and.saucer.fill", "Caffeine is elevated today — cut off by 2 PM", .aurora))
        } else {
            generated.append(("cup.and.saucer.fill", "No caffeine after 2 PM", .aurora))
        }
        return generated
    }

    /// Agenda-row anatomy without per-row wells: a small tinted icon well
    /// and the tip as a regular-weight sentence that wraps.
    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("Sleep Optimization")

            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                ForEach(tips, id: \.tip) { tip in
                    HStack(alignment: .center, spacing: ForgeLayout.rowGap) {
                        ForgeIconWell(systemImage: tip.icon, tint: tip.color, diameter: 28)
                        Text(tip.tip)
                            .font(HomeType.body)
                            .foregroundStyle(Color.textSecondary)
                            .forgeWrapping()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .forgeContentCard(tint: .steel)
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
                    color: .amber
                ))
            }
        }

        return items
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Top corners of the panel, continuous like every other Forge surface.
    private static let panelShape = UnevenRoundedRectangle(
        topLeadingRadius: FDS.Radius.xxl,
        bottomLeadingRadius: 0,
        bottomTrailingRadius: 0,
        topTrailingRadius: FDS.Radius.xxl,
        style: .continuous
    )

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Dim layer: tap to close. VoiceOver closes with the labelled
                // button instead, so the layer itself stays out of its way.
                Color.black.opacity(0.65).ignoresSafeArea()
                    .onTapGesture { dismiss() }
                    .accessibilityHidden(true)

                VStack(spacing: 0) {
                    Spacer()
                    panel
                        .frame(maxHeight: geo.size.height * 0.78)
                }
            }
        }
    }

    /// The sheet surface: grabber, header, then the insights at the sheet
    /// rhythm (16 between cards, 28 after the last).
    private var panel: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.textTertiary.opacity(0.5))
                .frame(width: 36, height: 4)
                .padding(.vertical, FDS.Spacing.md)
                .accessibilityHidden(true)

            header
                .padding(.horizontal, ForgeLayout.screenInset)
                .padding(.bottom, FDS.Spacing.md)

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: ForgeLayout.sectionGap) {
                    if let summary {
                        ariaBanner(summary)
                    }
                    ForEach(insights) { insight in
                        AIInsightCard(insight: insight)
                    }
                }
                .forgeScreenInsets(top: FDS.Spacing.xs)
            }
        }
        .background(Color.surface)
        .clipShape(Self.panelShape)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    /// ARIA mark (32 pt or smaller holds its still pose) beside the shared
    /// sheet header, which brings the labelled 44 pt close button.
    private var header: some View {
        HStack(alignment: .center, spacing: FDS.Spacing.md) {
            ARIAIdentityMark(state: .idle, mood: .energized, size: 28, amplitude: 0.24)
            ForgeSheetHeader(title: "AI Life Insights", onClose: dismiss)
        }
    }

    /// ARIA's read: the one aurora (ARIA intelligence) card at the top.
    private func ariaBanner(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            HStack(spacing: FDS.Spacing.sm) {
                ARIAIdentityMark(state: isLive ? .speaking : .idle, mood: .energized, size: 18, amplitude: isLive ? 0.45 : 0.2)
                Text(isLive ? "ARIA · LIVE" : "ARIA")
                    .forgeSectionLabel(tint: .aurora)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
            }
            Text(text)
                .font(HomeType.body)
                .foregroundStyle(Color.textPrimary)
                .lineSpacing(3)
                .forgeWrapping()
        }
        .forgeContentCard(tint: .aurora)
    }

    private func dismiss() {
        if reduceMotion {
            isPresented = false
        } else {
            withAnimation(FDS.Spring.standard) { isPresented = false }
        }
    }
}

/// One insight: a row-title lead, the sentence (first three lines, the rest
/// behind the disclosure link), then the link. Tinted by the insight's color;
/// no glowing dot.
struct AIInsightCard: View {
    let insight: LifestyleInsight
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text(insight.title)
                    .font(HomeType.status)
                    .foregroundStyle(Color.textPrimary)
                    .forgeWrapping()
                Text(insight.insight)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .lineSpacing(3)
                    .lineLimit(expanded ? nil : 3)
                    .forgeWrapping()
            }
            ForgeTextLink(title: insight.action, accent: insight.color, expanded: expanded) {
                toggle()
            }
        }
        .forgeContentCard(tint: insight.color)
        .contentShape(Rectangle())
        .onTapGesture { toggle() }
    }

    private func toggle() {
        if reduceMotion {
            expanded.toggle()
        } else {
            withAnimation(FDS.Spring.standard) { expanded.toggle() }
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

    /// Row glyphs for the agenda-row icon wells, keyed by `LivingHobby`'s raw
    /// value so a new hobby falls back instead of breaking the build.
    private static let hobbySymbols: [String: String] = [
        "outdoors": "leaf.fill",
        "gym": "dumbbell.fill",
        "cooking": "fork.knife",
        "making": "hammer.fill",
        "music": "music.note",
        "reading": "book.fill",
        "games": "gamecontroller.fill",
        "rest": "sofa.fill",
    ]

    /// Four blocks (spec §2.4): eyebrow, lead pair, suggestions, link.
    var body: some View {
        let snapshot = hobby
        return VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader(title: "Hobby path") {
                ForgeCardMeta(
                    text: snapshot.path.rawValue.replacingOccurrences(of: "_", with: " "),
                    color: .amber
                )
                .textCase(.uppercase)
            }

            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text(snapshot.headline)
                    .font(ForgeType.title)
                    .foregroundStyle(Color.textPrimary)
                    .forgeWrapping()
                Text(snapshot.coachingLine)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
            }

            suggestionBlock(snapshot)

            ForgeTextLink(title: "Ask ARIA to pick a hobby", accent: .amber) {
                store.openChat(with: HomeInsightFlow.hobbyPrompt(hobby: snapshot), voice: false)
            }
        }
        .forgeContentCard(tint: .amber)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(snapshot.headline). \(snapshot.coachingLine) \(snapshot.windowLine)")
    }

    /// The timing line introduces the suggestions it qualifies; each
    /// suggestion is an agenda row (icon well, status title, body subtitle).
    private func suggestionBlock(_ snapshot: HobbyPathEngine.Snapshot) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            Text(snapshot.windowLine)
                .font(HomeType.body)
                .foregroundStyle(Color.textTertiary)
                .forgeWrapping()
            ForEach(snapshot.suggestions.prefix(3)) { item in
                suggestionRow(item)
            }
        }
    }

    private func suggestionRow(_ item: HobbyPathEngine.Suggestion) -> some View {
        HStack(alignment: .top, spacing: ForgeLayout.rowGap) {
            ForgeIconWell(
                systemImage: Self.hobbySymbols[item.hobby.rawValue] ?? "circle.grid.2x2",
                tint: .amber
            )
            VStack(alignment: .leading, spacing: ForgeLayout.labelValueGap) {
                Text(item.hobby.title)
                    .font(HomeType.status)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                Text(item.firstStep)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textTertiary)
                    .forgeWrapping()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

struct YourPeopleCard: View {
    @EnvironmentObject var store: AppStore
    @State private var directory = PeopleDirectoryStore.load()
    @State private var showSheet = false

    /// Empty: a lead statement and one clear action (the card's whole job).
    /// Filled: the names as static chips that wrap, with an edit link.
    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("Your people")
            if directory.coachingPeople.isEmpty {
                VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                    Text("ARIA doesn't know who matters yet.")
                        .font(ForgeType.title)
                        .foregroundStyle(Color.textPrimary)
                        .forgeWrapping()
                    Text("Pick a few first names — partner, roommate, training buddy. Not your whole address book. Phone numbers stay in Contacts.")
                        .font(HomeType.body)
                        .foregroundStyle(Color.textSecondary)
                        .forgeWrapping()
                }
                ForgeSecondaryButton(title: "Add your people", icon: "person.badge.plus", accent: .vitality) {
                    showSheet = true
                }
            } else {
                ForgeFlowLayout(spacing: ForgeLayout.chipGap) {
                    ForEach(directory.coachingPeople) { person in
                        ForgeChip(
                            label: "\(person.firstName) · \(person.relation.title)",
                            icon: "person.fill",
                            energy: .vitality
                        )
                    }
                }
                ForgeTextLink(title: "Edit your people", accent: .vitality) {
                    showSheet = true
                }
            }
        }
        .forgeContentCard(tint: .vitality)
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
                .padding(.top, FDS.Spacing.xl)
                .padding(.bottom, FDS.Spacing.md)
                .accessibilityAddTraits(.isHeader)
            Text(honesty)
                .font(HomeType.body)
                .foregroundStyle(Color.textTertiary)
                .forgeWrapping()
                .padding(.bottom, FDS.Spacing.md)
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

    /// Sheet rhythm (spec §2.3): the toolbar keeps its Done button, content
    /// sits at 16 pt insets with 16 between groups, and every control is 44 pt.
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ForgeLayout.sectionGap) {
                    introBlock
                    addCard
                    if !suggestions.isEmpty {
                        suggestionsCard
                    }
                    if !directory.people.isEmpty {
                        peopleCard
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .forgeScreenInsets(top: FDS.Spacing.lg)
            }
            .forgeScreenBackground(accent: .vitality)
            .navigationTitle("Your people")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
        .onAppear { refreshSuggestionsIfAllowed() }
    }

    /// The privacy line, any notice, and the optional Contacts opt-in.
    private var introBlock: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            Text("First names and a label only. Phone numbers, emails, and the rest of your address book stay in Contacts. This is lifestyle coaching — not a read on your social life.")
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
            if let notice {
                Text(notice)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textTertiary)
                    .forgeWrapping()
            }
            if directory.contactsAccess != .granted {
                ForgeSecondaryButton(title: "Allow Contacts (optional)", icon: "person.crop.circle", accent: .vitality) {
                    Task { await requestContacts() }
                }
            }
        }
    }

    /// Name field over the relation picker and Add, which sit side by side
    /// and stack at accessibility sizes.
    private var addCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            TextField("First name", text: $draft)
                .textInputAutocapitalization(.words)
                .font(HomeType.status)
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, ForgeLayout.tilePadding)
                .frame(minHeight: ForgeUX.minTap)
                .forgeWell(padding: 0)
            ForgeAdaptiveStack(spacing: ForgeLayout.tileGap) {
                relationMenu
                ForgeSecondaryButton(title: "Add", icon: "plus", accent: .vitality) {
                    addDraft()
                }
            }
        }
        .forgeContentCard()
    }

    private var relationMenu: some View {
        Menu {
            ForEach(PeopleDirectory.Relation.allCases, id: \.self) { item in
                Button(item.title) { relation = item }
            }
        } label: {
            HStack(spacing: FDS.Spacing.sm) {
                Text(relation.title)
                    .font(HomeType.label)
                    .forgeSingleLine(minScale: ForgeLayout.labelMinScale)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Color.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: ForgeUX.minTap)
            .padding(.horizontal, FDS.Spacing.lg)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: ForgeUX.hairline)
            )
        }
        .tint(Color.textPrimary)
    }

    /// Contacts suggestions as 44 pt rows; tapping one confirms that person.
    private var suggestionsCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            Text("From Contacts — tap to confirm")
                .forgeSectionLabel()
                .forgeWrapping()
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(suggestions, id: \.id) { row in
                    Button {
                        FDS.haptic(.press)
                        confirm(name: row.name, identifier: row.id)
                    } label: {
                        HStack(spacing: ForgeLayout.rowGap) {
                            Text(row.name)
                                .font(HomeType.status)
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "plus.circle")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color.vitality)
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: ForgeUX.minTap)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .forgeContentCard()
    }

    /// The confirmed people as agenda rows, each with a 44 pt Remove.
    private var peopleCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            ForEach(directory.people) { person in
                HStack(spacing: ForgeLayout.rowGap) {
                    ForgeIconWell(systemImage: "person.fill", tint: .vitality)
                    Text("\(person.firstName) · \(person.relation.title)")
                        .font(HomeType.status)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        FDS.haptic(.press)
                        remove(person)
                    } label: {
                        Text("Remove")
                            .font(HomeType.label)
                            .foregroundStyle(Color.danger)
                            .padding(.horizontal, FDS.Spacing.sm)
                            .frame(minHeight: ForgeUX.minTap)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(person.firstName)")
                }
            }
        }
        .forgeContentCard()
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
