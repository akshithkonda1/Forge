import SwiftUI
import Charts
import HealthKit
import ForgeCore

/// Today's Apple Health numbers plus the 7-day chart. Two zones split by one
/// hairline: today's stat tiles, then the weekly trend. Tile colors use the
/// domain tokens (steps vitality as on Home, active ember, sleep steel) and
/// match the chart's metric colors so a tile and its bars read as one series.
struct LiveHealthDashboard: View {
    let stats: DailyHealthStats
    let trends: [WeeklyHealthTrend]

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            header

            // Today's key metrics. Missing readings show an em dash, as on Home.
            ForgeStatGrid(columns: 2) {
                HealthMetricTile(
                    icon: "figure.walk",
                    label: "Steps",
                    value: stats.steps > 0 ? stats.steps.formatted() : "—",
                    target: "10,000",
                    progress: Double(stats.steps) / 10000.0,
                    color: Color.vitality
                )

                HealthMetricTile(
                    icon: "flame.fill",
                    label: "Active Cal",
                    value: stats.activeCalories > 0 ? "\(stats.activeCalories)" : "—",
                    target: "600",
                    progress: Double(stats.activeCalories) / 600.0,
                    color: Color.ember
                )

                HealthMetricTile(
                    icon: "moon.zzz.fill",
                    label: "Sleep",
                    value: stats.sleepHours > 0 ? String(format: "%.1fh", stats.sleepHours) : "—",
                    target: "8h",
                    progress: stats.sleepHours / 8.0,
                    color: Color.steel
                )

                HealthMetricTile(
                    icon: "waveform.path.ecg",
                    label: "HRV",
                    value: stats.hrv > 0 ? "\(Int(stats.hrv))" : "—",
                    target: "50+",
                    progress: stats.hrv / 50.0,
                    color: Color.aurora
                )

                // Cardio fitness — surfaced from HealthKit, previously unused
                if stats.vo2Max > 0 {
                    HealthMetricTile(
                        icon: "lungs.fill",
                        label: "VO₂ Max",
                        value: String(format: "%.0f", stats.vo2Max),
                        target: "50",
                        progress: stats.vo2Max / 50.0,
                        color: Color.indigo
                    )
                }

                if stats.exerciseMinutes > 0 {
                    HealthMetricTile(
                        icon: "figure.run",
                        label: "Exercise",
                        value: "\(Int(stats.exerciseMinutes))m",
                        target: "30m",
                        progress: stats.exerciseMinutes / 30.0,
                        color: Color.amber
                    )
                }
            }

            // Weekly Trend Chart (Swift Charts — interactive, multi-metric)
            if !trends.isEmpty {
                Divider().background(Color.white.opacity(0.08))
                WeeklyTrendChart(trends: trends)
            }
        }
        .forgeContentCard(tint: .vitality)
    }

    /// Eyebrow with Home's live pill trailing, then the source line.
    private var header: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
            ForgeCardHeader(title: "Live Health Data") {
                livePill
            }
            Text("Powered by Apple Health")
                .font(HomeType.body)
                .foregroundStyle(Color.textTertiary)
                .forgeWrapping()
        }
    }

    /// Home's live pill (HomeDataStatusPill): a static 6 pt dot and a micro
    /// label in a hairline capsule. No pulse and no glow at rest.
    private var livePill: some View {
        HStack(spacing: FDS.Spacing.xs) {
            Circle()
                .fill(Color.vitality)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text("Live")
                .font(HomeType.micro)
                .foregroundStyle(Color.vitality)
                .textCase(.uppercase)
                .lineLimit(1)
        }
        .padding(.horizontal, FDS.Spacing.sm)
        .padding(.vertical, FDS.Spacing.xs)
        .background(Color.white.opacity(0.05))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

private enum TrendMetric: String, CaseIterable, Identifiable {
    case steps = "Steps"
    case activeCalories = "Active"
    case sleep = "Sleep"
    case hrv = "HRV"
    var id: String { rawValue }

    /// Same tokens as the matching `HealthMetricTile`s above.
    var color: Color {
        switch self {
        case .steps:          return Color.vitality
        case .activeCalories: return Color.ember
        case .sleep:          return Color.steel
        case .hrv:            return Color.aurora
        }
    }

    func value(_ t: WeeklyHealthTrend) -> Double {
        switch self {
        case .steps:          return Double(t.steps)
        case .activeCalories: return Double(t.activeCalories)
        case .sleep:          return t.sleepHours
        case .hrv:            return t.avgHRV
        }
    }

    func format(_ v: Double) -> String {
        switch self {
        case .steps:          return Int(v).formatted()
        case .activeCalories: return "\(Int(v)) cal"
        case .sleep:          return String(format: "%.1f h", v)
        case .hrv:            return "\(Int(v)) ms"
        }
    }
}

/// Interactive 7-day chart replacing the old steps-only sparkline. Toggles between
/// Steps / Active Cal / Sleep / HRV and supports tap-to-read on any day.
struct WeeklyTrendChart: View {
    let trends: [WeeklyHealthTrend]
    @State private var metric: TrendMetric = .steps
    @State private var selectedDate: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Plot height grows with Dynamic Type so the micro axis labels keep room.
    @ScaledMetric(relativeTo: .caption) private var trendPlotSize: CGFloat = 150

    private var selectedTrend: WeeklyHealthTrend? {
        guard let selectedDate else { return nil }
        return trends.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    private var metricOptions: [ForgeSegmentOption<TrendMetric>] {
        TrendMetric.allCases.map { ForgeSegmentOption(value: $0, title: $0.rawValue) }
    }

    /// VoiceOver summary: the metric, then every day's value, so the numbers
    /// are reachable without drag selection.
    private var chartSummary: String {
        let days = trends.map { t in
            "\(t.date.formatted(.dateTime.weekday(.abbreviated))) \(metric.format(metric.value(t)))"
        }
        return "7-Day Trends, \(metric.rawValue): " + days.joined(separator: ", ")
    }

    /// The chart is the card's second zone: header, selector and plot are its
    /// blocks, so they sit at `blockGap` like the zone above the hairline.
    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader(title: "7-Day Trends") {
                if let t = selectedTrend {
                    Text("\(t.date.formatted(.dateTime.weekday(.abbreviated))) · \(metric.format(metric.value(t)))")
                        .font(HomeType.micro)
                        .foregroundStyle(metric.color)
                        .monospacedDigit()
                        .lineLimit(1)
                        .transition(.opacity)
                }
            }

            ForgeSegmentedControl(
                metricOptions,
                selection: $metric,
                accent: .vitality,
                bleed: ForgeLayout.cardPadding
            )
            .accessibilityLabel("Metric")

            trendChart
        }
    }

    private var trendChart: some View {
        Chart(trends) { t in
            BarMark(
                x: .value("Day", t.date, unit: .day),
                y: .value(metric.rawValue, metric.value(t))
            )
            .foregroundStyle(metric.color.gradient)
            .cornerRadius(FDS.Radius.xs) // Charts mark API (continuous by default), not View.cornerRadius
            .opacity(selectedTrend == nil || selectedTrend?.id == t.id ? 1 : 0.35)
        }
        .chartXSelection(value: $selectedDate)
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
        .frame(height: ForgeLayout.scaledCap(trendPlotSize, base: 150))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: metric)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(chartSummary)
    }
}

/// `ForgeStatTile` anatomy (Home's lifestyleChip in a well) plus a clamped
/// progress bar and its target. The target sits under the bar instead of on
/// the value line, so a five-digit value never collides with it in a narrow
/// two-column cell. Fills its `ForgeStatGrid` row so wells line up.
struct HealthMetricTile: View {
    let icon: String
    let label: String
    let value: String
    let target: String
    let progress: Double
    let color: Color
    /// Kept for source compatibility. There is no entrance sweep any more:
    /// `ForgeProgressBar` animates only when the value changes (and never
    /// under Reduce Motion).
    var appeared: Bool = true

    private var percent: Int {
        guard progress.isFinite else { return 0 }
        return Int((min(1, max(0, progress)) * 100).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: ForgeLayout.labelValueGap) {
                Text(value)
                    .font(FDS.TypeScale.Dynamic.headline)
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
                    .forgeSingleLine()
                    .contentTransition(.numericText())
                Text(label)
                    .font(HomeType.micro)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                ForgeProgressBar(fraction: progress, tint: color, height: 4)
                Text("/ \(target)")
                    .font(HomeType.micro)
                    .foregroundStyle(Color.textTertiary)
                    .monospacedDigit()
                    .forgeSingleLine(minScale: ForgeLayout.labelMinScale)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .forgeWell()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(value) of \(target)")
        .accessibilityValue("\(percent) percent")
    }
}

/// Recovery read-out: eyebrow with the status band, the score ring beside the
/// training call (answer first), then the three contributing readings as
/// agenda-style rows.
struct RecoveryMetricsCard: View {
    let stats: DailyHealthStats
    @ScaledMetric(relativeTo: .title3) private var recoveryRingSize: CGFloat = 96

    var recoveryScore: Int {
        var score = 0
        
        // HRV component (40% weight). Clamp the Double first — Int() of a
        // huge finite HRV still traps if min(..., 100) runs after the convert.
        let hrv = stats.hrv.isFinite ? stats.hrv : 0
        let hrvScaled = min(100, max(0, hrv * 1.5)).rounded()
        let hrvScore = hrvScaled.isFinite ? Int(hrvScaled) : 0
        score += Int(Double(hrvScore) * 0.4)
        
        // Resting HR component (30% weight)
        let resting = stats.restingHeartRate
        let hrScore = resting > 0 && resting.isFinite
            ? max(100 - Int(((resting - 60) * 2).rounded()), 0)
            : 70
        score += Int(Double(hrScore) * 0.3)
        
        // Sleep component (30% weight)
        let sleepHours = stats.sleepHours.isFinite ? stats.sleepHours : 0
        let sleepScore = Int(min(100, max(0, (sleepHours / 8.0) * 100)).rounded())
        score += Int(Double(sleepScore) * 0.3)
        
        return min(score, 100)
    }
    
    /// Status map (spec §5): excellent vitality, good steel, moderate amber,
    /// low steel-miss. Never alert red for a body state.
    var recoveryStatus: (label: String, color: Color) {
        switch recoveryScore {
        case 80...: return ("Excellent", Color.vitality)
        case 60..<80: return ("Good", Color.steel)
        case 40..<60: return ("Moderate", Color.amber)
        default: return ("Low", ForgeProgressChrome.miss)
        }
    }

    private typealias Reading = (value: String, status: String, color: Color)

    private var isReadyToTrain: Bool { recoveryScore > 70 }

    // Readings. Same thresholds and labels as before; colors follow the §5
    // status map. A missing reading shows an em dash and no status at all,
    // so an absent resting heart rate never reads "Excellent" and an absent
    // HRV or sleep never reads "Low".

    private var missingReading: Reading { ("—", "", Color.textTertiary) }

    private var hrvReading: Reading {
        guard stats.hrv > 0 else { return missingReading }
        let value = "\(Int(stats.hrv)) ms"
        if stats.hrv > 50 { return (value, "Optimal", Color.vitality) }
        if stats.hrv > 30 { return (value, "Good", Color.steel) }
        return (value, "Low", ForgeProgressChrome.miss)
    }

    private var restingHeartRateReading: Reading {
        guard stats.restingHeartRate > 0 else { return missingReading }
        let value = "\(Int(stats.restingHeartRate)) bpm"
        if stats.restingHeartRate < 60 { return (value, "Excellent", Color.vitality) }
        if stats.restingHeartRate < 70 { return (value, "Good", Color.steel) }
        return (value, "Elevated", Color.amber)
    }

    private var sleepReading: Reading {
        guard stats.sleepHours > 0 else { return missingReading }
        let value = String(format: "%.1f hours", stats.sleepHours)
        if stats.sleepHours >= 8 { return (value, "Optimal", Color.vitality) }
        if stats.sleepHours >= 7 { return (value, "Good", Color.steel) }
        return (value, "Low", ForgeProgressChrome.miss)
    }

    var body: some View {
        let status = recoveryStatus
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("Recovery Status", meta: status.label, metaColor: status.color)
            summary(status)
            metricRows
        }
        .forgeContentCard(tint: .steel)
    }

    /// Ring and training call side by side; stacks at accessibility sizes so
    /// the sentence never squeezes against the ring.
    private func summary(_ status: (label: String, color: Color)) -> some View {
        ForgeAdaptiveStack(spacing: FDS.Spacing.lg, alignment: .center) {
            ForgeProgressRing(
                progress: recoveryScore,
                energy: status.color,
                size: ForgeLayout.scaledCap(recoveryRingSize, base: 96),
                stroke: ForgeProgressChrome.compactStroke
            ) {
                Text("\(recoveryScore)")
                    .font(HomeType.metric)
                    .foregroundStyle(Color.textPrimary)
                    .forgeGlanceText()
                    .contentTransition(.numericText())
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Recovery Status \(recoveryScore), \(status.label)")

            readinessCopy
        }
    }

    private var readinessCopy: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
            HStack(alignment: .firstTextBaseline, spacing: FDS.Spacing.sm) {
                Image(systemName: isReadyToTrain ? "checkmark.circle.fill" : "leaf.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isReadyToTrain ? Color.vitality : ForgeProgressChrome.miss)
                    .accessibilityHidden(true)
                Text(isReadyToTrain ? "Ready to Train" : "Consider Active Recovery")
                    .font(HomeType.status)
                    .foregroundStyle(Color.textPrimary)
                    .forgeWrapping()
            }
            Text(isReadyToTrain
                 ? "Your body is primed for a hard session"
                 : "Focus on mobility, stretching, or light cardio")
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var metricRows: some View {
        let hrv = hrvReading
        let resting = restingHeartRateReading
        let sleep = sleepReading
        return VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            RecoveryMetricRow(
                icon: "waveform.path.ecg",
                label: "Heart Rate Variability",
                value: hrv.value,
                status: hrv.status,
                color: hrv.color
            )
            RecoveryMetricRow(
                icon: "heart.fill",
                label: "Resting Heart Rate",
                value: resting.value,
                status: resting.status,
                color: resting.color
            )
            RecoveryMetricRow(
                icon: "bed.double.fill",
                label: "Sleep Duration",
                value: sleep.value,
                status: sleep.status,
                color: sleep.color
            )
        }
    }
}

/// Agenda-row anatomy for one recovery reading: icon well, a stat label over
/// the value, and a tinted status chip. At accessibility sizes the chip
/// drops under the value so neither the label nor the chip is squeezed.
/// An empty `status` (a missing reading) shows no chip.
struct RecoveryMetricRow: View {
    let icon: String
    let label: String
    let value: String
    let status: String
    let color: Color

    @Environment(\.dynamicTypeSize) private var typeSize

    private var showsChip: Bool { !status.isEmpty }

    var body: some View {
        HStack(alignment: .center, spacing: ForgeLayout.rowGap) {
            ForgeIconWell(systemImage: icon, tint: color)

            VStack(alignment: .leading, spacing: ForgeLayout.labelValueGap) {
                Text(label)
                    .font(HomeType.micro)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                    .minimumScaleFactor(ForgeLayout.labelMinScale)
                Text(value)
                    .font(HomeType.metric)
                    .foregroundStyle(Color.textPrimary)
                    .forgeSingleLine()
                    .contentTransition(.numericText())
                if showsChip && typeSize.isAccessibilitySize {
                    statusChip
                }
            }
            .layoutPriority(1)

            Spacer(minLength: FDS.Spacing.sm)

            if showsChip && !typeSize.isAccessibilitySize {
                statusChip
            }
        }
        .padding(.vertical, ForgeLayout.rowVerticalPadding)
        .accessibilityElement(children: .combine)
    }

    private var statusChip: some View {
        ForgeChip(label: status, energy: color, selected: true)
            .fixedSize()
    }
}

/// Seven concentric pillar arcs around the QoL score, then one full-width
/// contributor row per pillar (Home's metric rows), then ARIA's read.
struct MultiArcQOLCard: View {
    let metrics: LifestyleMetrics
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The arc chart grows a little with Dynamic Type (capped at 1.15x so it
    /// still fits a 375 pt phone inside the card's 20 pt padding).
    @ScaledMetric(relativeTo: .largeTitle) private var qolChartSize: CGFloat = 230

    private typealias PillarArc = (label: String, value: Int, color: Color, radius: CGFloat)

    /// Categorical palette exception (spec §5): the seven pillars must stay
    /// distinct and pink has no token, so the existing literal is declared once.
    private static let pillarPink = Color(hex: "F472B6")
    private static let chartBase: CGFloat = 230
    /// Radii step by 12, so a 6 pt stroke leaves an even 6 pt of air between
    /// rings, and the inner arc (radius 36) keeps a clear hole for the score.
    private static let arcStroke: CGFloat = 6
    private static let scoreHole: CGFloat = 56

    private var snapshot: QualityOfLifeLivingStore.Snapshot? {
        QualityOfLifeLivingStore.load()
    }

    private var chartSide: CGFloat {
        ForgeLayout.scaledCap(qolChartSize, base: MultiArcQOLCard.chartBase, maxGrowth: 1.15)
    }

    /// Takes the snapshot so the body decodes the living store once per render
    /// instead of three times.
    private func pillarArcs(_ snap: QualityOfLifeLivingStore.Snapshot?) -> [PillarArc] {
        let colors: [Color] = [
            Color.aurora, Color.success, Color.amber,
            Color.steel, Color.ember, Color.indigo, MultiArcQOLCard.pillarPink,
        ]
        let radii: [CGFloat] = [108, 96, 84, 72, 60, 48, 36]
        return QualityOfLifePillar.allCases.enumerated().map { index, pillar in
            let value = snap?.pillarScores[pillar.rawValue]
                ?? legacyProjection(for: pillar)
            return (pillar.title, value, colors[index % colors.count], radii[index % radii.count])
        }
    }

    private func arcFraction(_ value: Int, drawn: Bool) -> CGFloat {
        guard drawn else { return 0 }
        return CGFloat(max(0, min(100, value))) / 100
    }

    /// Status map (spec §5), applied locally so the model stays untouched:
    /// thriving vitality, steady steel, strained amber, depleted steel-miss.
    private func bandTone(_ band: QualityOfLifeBand) -> Color {
        switch band {
        case .thriving: return Color.vitality
        case .steady: return Color.steel
        case .strained: return Color.amber
        case .depleted: return ForgeProgressChrome.miss
        }
    }

    private func hasInsights(_ snap: QualityOfLifeLivingStore.Snapshot) -> Bool {
        !snap.drivers.isEmpty || !snap.missingPillars.isEmpty || !snap.coaching.isEmpty
    }

    private func legacyProjection(for pillar: QualityOfLifePillar) -> Int {
        switch pillar {
        case .sleep: return metrics.sleepQuality
        case .activity: return metrics.physicalHealth
        case .nutrition: return metrics.nutritionScore
        case .hydration: return metrics.physicalHealth
        case .vitals: return metrics.energyLevels
        case .mind: return metrics.mentalWellbeing
        case .social: return metrics.mentalWellbeing
        }
    }

    var body: some View {
        let snap = snapshot
        let arcs = pillarArcs(snap)
        let band = snap?.qualityBand ?? QualityOfLifeBand(score: metrics.qualityOfLifeScore)
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("Quality of Life", meta: band.label, metaColor: bandTone(band))

            arcChart(arcs, band: band)

            // One full-width contributor row per pillar, same order and colors
            // as the arcs. Stacked at Home's 2 pt, never in two columns.
            VStack(alignment: .leading, spacing: ForgeLayout.labelValueGap) {
                ForEach(Array(arcs.enumerated()), id: \.offset) { _, arc in
                    ArcLegendItem(label: arc.label, value: arc.value, color: arc.color)
                }
            }

            if let snap, hasInsights(snap) {
                insights(snap, band: band)
            }
        }
        .forgeContentCard(tint: .vitality)
        .onAppear { appeared = true }
    }

    /// The arcs sweep in once on appear (no stagger, no glow); under Reduce
    /// Motion they render at rest.
    private func arcChart(_ arcs: [PillarArc], band: QualityOfLifeBand) -> some View {
        let unit = chartSide / MultiArcQOLCard.chartBase
        let lineWidth = MultiArcQOLCard.arcStroke * unit
        let drawn = appeared || reduceMotion
        return VStack(spacing: ForgeLayout.pairGap) {
            ZStack {
                ForEach(Array(arcs.enumerated()), id: \.offset) { _, arc in
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: lineWidth)
                        .frame(width: arc.radius * 2 * unit, height: arc.radius * 2 * unit)
                }

                ForEach(Array(arcs.enumerated()), id: \.offset) { _, arc in
                    Circle()
                        .trim(from: 0, to: arcFraction(arc.value, drawn: drawn))
                        .stroke(arc.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .frame(width: arc.radius * 2 * unit, height: arc.radius * 2 * unit)
                        .rotationEffect(.degrees(-90))
                }

                centerScore(maxWidth: MultiArcQOLCard.scoreHole * unit)
            }
            .frame(width: chartSide, height: chartSide)
            .animation(reduceMotion ? nil : ForgeMotion.sweep, value: appeared)

            // At accessibility sizes the meta label moves under the chart so
            // the score keeps the whole hole.
            if typeSize.isAccessibilitySize {
                qolLabel
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Quality of life \(metrics.qualityOfLifeScore), \(band.label)")
    }

    private func centerScore(maxWidth: CGFloat) -> some View {
        VStack(spacing: ForgeLayout.labelValueGap) {
            Text("\(metrics.qualityOfLifeScore)")
                .font(HomeType.heroScore)
                .foregroundStyle(Color.textPrimary)
                .forgeGlanceText()
                .contentTransition(.numericText())
            if !typeSize.isAccessibilitySize {
                qolLabel
            }
        }
        .frame(maxWidth: maxWidth)
    }

    private var qolLabel: some View {
        Text("QOL")
            .font(HomeType.micro)
            .foregroundStyle(Color.textTertiary)
            .tracking(1.4)
            .lineLimit(1)
    }

    private func insights(_ snap: QualityOfLifeLivingStore.Snapshot, band: QualityOfLifeBand) -> some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.sm) {
            if !snap.drivers.isEmpty {
                Text(band == .thriving
                     ? "Holding you up: \(snap.drivers.joined(separator: " · "))"
                     : "Pulling the grade: \(snap.drivers.joined(separator: " · "))")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
            }
            if !snap.missingPillars.isEmpty {
                Text("Still unmeasured: \(snap.missingPillars.prefix(3).joined(separator: ", "))")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textTertiary)
                    .forgeWrapping()
            }
            if !snap.coaching.isEmpty {
                Text(snap.coaching)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One QoL pillar as Home's contributor row (`ForgeMetricRow`): a 2 x 16
/// tint bar in the pillar's arc color, the name, and the score. Stack a
/// group of them at `ForgeLayout.labelValueGap`.
struct ArcLegendItem: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        ForgeMetricRow(label: label, value: "\(value)", tint: color)
    }
}

enum AgingVendorStore {
    static var ages: [AgingVendorAge] = []

    static func replaceAll(_ incoming: [AgingVendorAge]) {
        ages = incoming
    }

    static func ingest(metricType: String, years: Double, source: String, confidence: Double = 0.85) {
        guard let age = AgingVendorAge(metricType: metricType, years: years, source: source, confidence: confidence) else {
            return
        }
        ages.removeAll { $0.kind == age.kind && $0.source.caseInsensitiveCompare(age.source) == .orderedSame }
        ages.append(age)
    }

    static func ingest(metrics: [CloudHealthMetric]) {
        for metric in metrics {
            ingest(metricType: metric.metricType, years: metric.value, source: metric.source)
        }
    }
}

enum AgingBridge {
    static func snapshot(
        age: Int?,
        sexFemale: Bool?,
        stats: DailyHealthStats?,
        vendorAges: [AgingVendorAge]? = nil
    ) -> AgingSnapshot {
        AgingSnapshot.evaluate(
            chronologicalAge: age.map(Double.init),
            sexFemale: sexFemale,
            vo2Max: stats.flatMap { $0.vo2Max > 0 ? $0.vo2Max : nil },
            hrv: stats.flatMap { $0.hrv > 0 ? $0.hrv : nil },
            restingHR: stats.flatMap { $0.restingHeartRate > 0 ? $0.restingHeartRate : nil },
            sleepHours: stats.flatMap { $0.sleepHours > 0 ? $0.sleepHours : nil },
            vendorAges: vendorAges ?? AgingVendorStore.ages
        )
    }

    @MainActor
    static func snapshot(store: AppStore) -> AgingSnapshot {
        let stats = HealthKitManager.shared.todayStats
        let sleepHours = stats.flatMap { $0.sleepHours > 0 ? $0.sleepHours : nil }
            ?? (store.dailyMetrics.totalSleep > 0 ? Double(store.dailyMetrics.totalSleep) / 60.0 : nil)
        let sexFemale: Bool? = {
            guard let sex = store.userProfile.biologicalSex else { return nil }
            switch sex {
            case .female: return true
            case .male: return false
            case .intersex, .preferNotToSay: return nil
            }
        }()
        return AgingSnapshot.evaluate(
            chronologicalAge: store.userProfile.age.map(Double.init),
            sexFemale: sexFemale,
            vo2Max: stats.flatMap { $0.vo2Max > 0 ? $0.vo2Max : nil },
            hrv: stats.flatMap { $0.hrv > 0 ? $0.hrv : nil }
                ?? (store.dailyMetrics.hrv > 0 ? Double(store.dailyMetrics.hrv) : nil),
            restingHR: stats.flatMap { $0.restingHeartRate > 0 ? $0.restingHeartRate : nil }
                ?? (store.dailyMetrics.restingHR > 0 ? Double(store.dailyMetrics.restingHR) : nil),
            sleepHours: sleepHours,
            vendorAges: AgingVendorStore.ages
        )
    }
}

/// A content card (not a plate): eyebrow, the two ages and their bar, the
/// one-breath sentence, then everything else behind a "Details" disclosure.
/// Four blocks at most; nothing is removed, only folded.
struct BiologicalAgeCard: View {
    let snapshot: AgingSnapshot
    @State private var showDetails = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            header

            if snapshot.showsOnTrain {
                ageBlock

                if !snapshot.oneBreathLine.isEmpty {
                    Text(snapshot.oneBreathLine)
                        .font(ForgeType.title)
                        .foregroundStyle(Color.textPrimary)
                        .forgeWrapping()
                        .accessibilityAddTraits(.isHeader)
                }

                detailsDisclosure
            } else {
                missingAgeNote
            }
        }
        .forgeContentCard(tint: .aurora)
        // The card now holds a button (Details), so it contains its children
        // instead of combining them; the summary stays as the container label.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLine)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
            ForgeCardHeader("Heart")
            Text("One sentence from the signals Forge already has")
                .font(HomeType.body)
                .foregroundStyle(Color.textTertiary)
                .forgeWrapping()
        }
    }

    /// Calendar and training age as stat pairs (value over a sentence-case
    /// label), with the comparison bar beneath.
    private var ageBlock: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            HStack(alignment: .firstTextBaseline, spacing: FDS.Spacing.lg) {
                ageColumn(title: "Calendar", value: snapshot.chronologicalAge)
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.textMuted)
                    .accessibilityHidden(true)
                ageColumn(
                    title: "Training",
                    value: snapshot.confidence > 0.25 ? snapshot.biologicalAge : nil,
                    emphasis: true
                )
                Spacer(minLength: 0)
            }

            if snapshot.hasComparison, snapshot.confidence > 0.25 {
                // Decorative: the two ages above carry the same comparison.
                ForgeProgressBar(fraction: Double(barFraction), tint: tone, height: 8)
                    .accessibilityHidden(true)
            }
        }
    }

    private var detailsDisclosure: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeTextLink(title: "Details", accent: .aurora, expanded: showDetails) {
                if reduceMotion {
                    showDetails.toggle()
                } else {
                    withForgeMotion(ForgeMotion.smooth) { showDetails.toggle() }
                }
            }

            if showDetails {
                // The toggle is unanimated under Reduce Motion, so this
                // transition only plays when motion is allowed.
                detailsContent
                    .forgeTransition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }
        }
    }

    private var detailsContent: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            if !snapshot.comparisonLine.isEmpty {
                Text(snapshot.comparisonLine)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textPrimary)
                    .forgeWrapping()
            }

            FourBulletList(bullets: TranslationCatalog.heart.bullets)

            if !snapshot.trainingHint.isEmpty {
                Text(snapshot.trainingHint)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
            }

            if AgingNorms.webConfirmed {
                Text("Cardio norms confirmed from a public fitness page.")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textTertiary)
                    .forgeWrapping()
            }

            if !snapshot.components.isEmpty {
                componentRows
            }

            Text("Lifestyle estimate from the signals Forge already has — not a medical biological age.")
                .font(HomeType.body)
                .foregroundStyle(Color.textTertiary)
                .forgeWrapping()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Two-line rows (name over source) with the age trailing, grouped in a
    /// well so they read as one nested list.
    private var componentRows: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            ForEach(Array(snapshot.components.prefix(4).enumerated()), id: \.offset) { _, component in
                componentRow(component)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeWell()
    }

    private func componentRow(_ component: AgingComponent) -> some View {
        HStack(alignment: .center, spacing: ForgeLayout.rowGap) {
            VStack(alignment: .leading, spacing: ForgeLayout.labelValueGap) {
                Text(component.name)
                    .font(HomeType.status)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                Text(component.source)
                    .font(HomeType.micro)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(2)
            }
            .layoutPriority(1)
            Spacer(minLength: FDS.Spacing.sm)
            Text("\(Int(component.years.rounded()))")
                .font(HomeType.metric)
                .foregroundStyle(Color.textPrimary)
                .forgeSingleLine()
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .combine)
    }

    /// No age yet: Home's in-card empty anatomy (icon well plus a sentence).
    private var missingAgeNote: some View {
        HStack(alignment: .top, spacing: ForgeLayout.rowGap) {
            ForgeIconWell(systemImage: "clock.arrow.2.circlepath", tint: tone)
            Text("Add your age in You, then ARIA can compare calendar age with training age from VO₂, HRV, resting heart rate, and sleep.")
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
            Spacer(minLength: 0)
        }
    }

    private var accessibilityLine: String {
        if !snapshot.oneBreathLine.isEmpty { return snapshot.oneBreathLine }
        if !snapshot.comparisonLine.isEmpty { return snapshot.comparisonLine }
        return "Training age unavailable"
    }

    /// Status map (spec §5): younger is a positive state, older a
    /// fair/warning-level metric, matched or unknown stays the card's aurora.
    private var tone: Color {
        switch snapshot.state {
        case .younger: return Color.vitality
        case .older: return Color.amber
        case .matched, .unknown: return Color.aurora
        }
    }

    private var barFraction: CGFloat {
        guard let chrono = snapshot.chronologicalAge, let bio = snapshot.biologicalAge, chrono > 0 else { return 0.5 }
        return CGFloat(min(1.0, max(0.15, bio / max(chrono, bio))))
    }

    private func ageColumn(title: String, value: Double?, emphasis: Bool = false) -> some View {
        let text = value.map { "\(Int($0.rounded()))" } ?? "—"
        return VStack(alignment: .leading, spacing: ForgeLayout.labelValueGap) {
            Text(text)
                .font(emphasis ? HomeType.heroScore : HomeType.metric)
                .foregroundStyle(emphasis ? tone : Color.textPrimary)
                .forgeSingleLine()
                .contentTransition(.numericText())
            Text(title)
                .font(HomeType.micro)
                .foregroundStyle(Color.textTertiary)
                .forgeSingleLine(minScale: ForgeLayout.labelMinScale)
        }
        .layoutPriority(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(text)")
    }
}

/// Up to four bulleted sentences (`ForgeBulletRow`: body text, the bullet on
/// the first baseline, wrapping instead of truncating).
struct FourBulletList: View {
    let bullets: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.sm) {
            ForEach(bullets, id: \.self) { bullet in
                ForgeBulletRow(text: bullet)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct MetabolicTranslationCard: View {
    let mealsLogged: Int
    let glucoseMgDl: Double?
    var storyLine: String = ""
    /// Apple Watch-derived hints, each labeled as an estimate. Empty when a
    /// CGM is connected (glucose is the source of truth) or the toggle is off.
    var watchLines: [String] = []
    var onDevices: () -> Void = {}

    /// Four blocks: eyebrow with today's lead facts, what Forge reads, the
    /// watch estimate (in a well, so estimates stay visibly apart from
    /// measurements), and the devices link as the card footer.
    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            leadBlock

            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                FourBulletList(bullets: TranslationCatalog.metabolic.bullets)
                if let note = TranslationCatalog.metabolic.accessoryNote {
                    Text(note)
                        .font(HomeType.body)
                        .foregroundStyle(Color.textTertiary)
                        .forgeWrapping()
                }
            }

            if !watchLines.isEmpty {
                watchEstimate
            }

            ForgeTextLink(
                title: glucoseMgDl == nil ? "Connect a CGM in Devices" : "Devices",
                accent: .ember,
                action: onDevices
            )
            .accessibilityHint("Opens the device library")
        }
        .forgeContentCard(tint: .amber)
        // Contains (not combines) so the bullets and the Devices link stay
        // reachable; the glucose line remains the container's label.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(glucoseLine)
    }

    private var leadBlock: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
            ForgeCardHeader(TranslationCatalog.metabolic.title)
            Text(glucoseLine)
                .font(HomeType.status)
                .foregroundStyle(Color.textPrimary)
                .forgeWrapping()
            if mealsLogged > 0 {
                Text(mealsLogged == 1 ? "1 meal logged today." : "\(mealsLogged) meals logged today.")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
            }
        }
    }

    private var watchEstimate: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.sm) {
            // `forgeSectionLabel` uppercases through `.textCase`, so the
            // eyebrow renders exactly as before.
            Text("Estimated from Apple Watch")
                .forgeSectionLabel(tint: Color.textTertiary)
                .forgeSingleLine(minScale: ForgeLayout.labelMinScale)
                .accessibilityAddTraits(.isHeader)
            ForEach(watchLines, id: \.self) { line in
                ForgeBulletRow(text: line)
            }
            Text("Estimates, not measurements — not medical advice.")
                .font(HomeType.body)
                .foregroundStyle(Color.textTertiary)
                .forgeWrapping()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeWell()
    }

    private var glucoseLine: String {
        if !storyLine.isEmpty { return storyLine }
        if let glucoseMgDl {
            return "Latest glucose · \(Int(glucoseMgDl.rounded())) mg/dL"
        }
        return "Glucose from a CGM — sold separately"
    }
}

