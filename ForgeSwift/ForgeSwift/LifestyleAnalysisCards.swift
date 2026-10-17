import SwiftUI
import UIKit
import HealthKit
import ForgeCore

// MARK: - Local status maps (spec §5)
//
// `InsightStatus.color` and `ImpactLevel.color` live in LifestyleModels.swift,
// which this area does not own, so the spec's status map is applied here.

/// excellent → vitality, good → steel, warning → amber, poor → miss (never red).
private func lifestyleInsightStatusColor(_ status: InsightStatus) -> Color {
    switch status {
    case .excellent: return Color.vitality
    case .good:      return Color.steel
    case .warning:   return Color.amber
    case .poor:      return ForgeProgressChrome.miss
    }
}

/// Recommendation impact: high is the ARIA action color, medium amber, low steel.
/// `warning` stays reserved for "connection needed".
private func lifestyleImpactColor(_ impact: ImpactLevel) -> Color {
    switch impact {
    case .high:   return Color.ember
    case .medium: return Color.amber
    case .low:    return Color.steel
    }
}

struct AILifeAnalysisCard: View {
    let metrics: LifestyleMetrics
    var analysis: String? = nil
    var isLive: Bool = false
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var rows: [(icon: String, label: String, current: String, optimal: String, status: InsightStatus)] {[
        ("moon.zzz.fill", "Sleep", String(format: "%.1fh avg", metrics.sleepAverage), String(format: "%.0fh target", metrics.sleepTarget), metrics.sleepAverage >= metrics.sleepTarget ? .excellent : metrics.sleepAverage >= metrics.sleepTarget * 0.9 ? .good : .warning),
        ("fork.knife", "Nutrition", "\(Int(metrics.nutritionQuality * 100))% whole foods", "85%+", metrics.nutritionQuality >= 0.85 ? .excellent : metrics.nutritionQuality >= 0.75 ? .good : .warning),
        ("figure.walk", "Movement", "\(metrics.dailySteps.formatted()) steps", "10,000 steps", metrics.dailySteps >= 10000 ? .excellent : metrics.dailySteps >= 8000 ? .good : .warning),
        ("brain.fill", "Stress", metrics.stressLevel.rawValue, "Low", metrics.stressLevel == .low ? .excellent : metrics.stressLevel == .medium ? .warning : .poor),
    ]}

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            // Block 1: eyebrow + lead line
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                ForgeCardHeader(title: "ARIA Life Analysis") {
                    if analysis != nil { liveBadge }
                }
                Text("Behavioral pattern analysis")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textTertiary)
                    .forgeWrapping()
            }

            // Block 2: one agenda row per pillar, status carried by the icon well
            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    AnalysisInsightRow(
                        icon: row.icon, label: row.label,
                        current: row.current, optimal: row.optimal, status: row.status
                    )
                }
            }

            // Block 3: disclosure footer
            ForgeTextLink(
                title: expanded ? "Hide Full Analysis" : "View Full Analysis",
                accent: .aurora,
                expanded: expanded
            ) {
                if reduceMotion {
                    expanded.toggle()
                } else {
                    withForgeMotion(ForgeMotion.smooth) { expanded.toggle() }
                }
            }

            if expanded {
                // The toggle above is unanimated under Reduce Motion, so this
                // transition only plays when motion is allowed.
                fullAnalysisSection
                    .forgeTransition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }
        }
        .forgeContentCard(tint: .aurora)
    }

    private var liveBadge: some View {
        ForgeVibeChip(label: isLive ? "LIVE" : "ARIA", energy: .aurora)
    }

    @ViewBuilder
    private var fullAnalysisSection: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.sm) {
            HStack(spacing: FDS.Spacing.sm) {
                ARIAIdentityMark(state: .idle, mood: .energized, size: 18, amplitude: 0.22)
                    .accessibilityHidden(true)
                Text(isLive ? "ARIA's analysis" : "Summary")
                    .font(HomeType.label)
                    .foregroundStyle(Color.textPrimary)
                    .accessibilityAddTraits(.isHeader)
            }
            if let analysis {
                Text(analysis)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
            } else {
                Text("Connect ARIA to unlock a personalized breakdown of how your sleep, nutrition, movement, and stress are interacting today.")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textTertiary)
                    .forgeWrapping()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeWell()
    }
}

/// Agenda-row anatomy: a status-tinted icon well, the pillar name over its
/// target, and the current value trailing (it drops under the name at
/// accessibility sizes so neither truncates). Status is drawn once, by the well.
struct AnalysisInsightRow: View {
    let icon: String
    let label: String
    let current: String
    let optimal: String
    let status: InsightStatus

    @Environment(\.dynamicTypeSize) private var typeSize

    private var tint: Color { lifestyleInsightStatusColor(status) }

    var body: some View {
        HStack(alignment: .center, spacing: ForgeLayout.rowGap) {
            ForgeIconWell(systemImage: icon, tint: tint)
            VStack(alignment: .leading, spacing: ForgeLayout.labelValueGap) {
                Text(label)
                    .font(HomeType.status)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                targetLine
                if typeSize.isAccessibilitySize {
                    currentValue
                }
            }
            .layoutPriority(1)
            Spacer(minLength: FDS.Spacing.sm)
            if !typeSize.isAccessibilitySize {
                currentValue
            }
        }
        .padding(.vertical, ForgeLayout.rowVerticalPadding)
        .frame(minHeight: ForgeUX.minTap)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(current), \(optimal)")
    }

    private var currentValue: some View {
        Text(current)
            .font(HomeType.label)
            .foregroundStyle(Color.textPrimary)
            .monospacedDigit()
            .forgeSingleLine(minScale: ForgeLayout.labelMinScale)
            .contentTransition(.numericText())
    }

    private var targetLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: FDS.Spacing.xs) {
            Image(systemName: "arrow.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.textMuted)
                .accessibilityHidden(true)
            Text(optimal)
                .font(HomeType.micro)
                .foregroundStyle(Color.textTertiary)
                .lineLimit(2)
        }
    }
}

struct AIRecommendationsCard: View {
    let recommendations: [AIRecommendation]
    @ObservedObject var store: AppStore

    private var ariaPrompt: String {
        if let top = recommendations.first {
            return "Based on my lifestyle data, help me act on this: \(top.title). \(top.description)"
        }
        return "Review my lifestyle optimization metrics and suggest one high-impact change for today."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            // Block 1: eyebrow + tinted count chip
            ForgeCardHeader(title: "ARIA Recommendations") {
                ForgeVibeChip(label: "\(recommendations.count) active", energy: .aurora)
            }

            // Block 2: the recommendations, or a calm in-card empty note
            if recommendations.isEmpty {
                ForgeEmptyNote(
                    title: "You're doing great! No new recommendations.",
                    systemImage: "checkmark.circle.fill",
                    tint: .vitality
                )
            } else {
                VStack(alignment: .leading, spacing: ForgeLayout.tileGap) {
                    ForEach(recommendations) { rec in
                        RecommendationCard(recommendation: rec)
                    }
                }
            }

            // Block 3: footer action, after the list it acts on
            ForgeTextLink(title: "Ask ARIA to optimize", accent: .ember) {
                store.openChat(with: ariaPrompt)
            }
        }
        .forgeContentCard(tint: .aurora)
    }
}

/// One expandable recommendation in a well: category eyebrow and chevron,
/// then the title with its impact chip (stacks at accessibility sizes so the
/// two never collide), then the description when expanded.
struct RecommendationCard: View {
    let recommendation: AIRecommendation
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var impactTint: Color { lifestyleImpactColor(recommendation.impact) }

    private var stateDescription: String { expanded ? "Expanded" : "Collapsed" }

    var body: some View {
        Button {
            if reduceMotion {
                expanded.toggle()
            } else {
                withForgeMotion(ForgeMotion.smooth) { expanded.toggle() }
            }
        } label: {
            VStack(alignment: .leading, spacing: FDS.Spacing.sm) {
                categoryLine
                titleLine
                if expanded {
                    Text(recommendation.description)
                        .font(HomeType.body)
                        .foregroundStyle(Color.textSecondary)
                        .forgeWrapping()
                        .forgeTransition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .forgeWell()
            .contentShape(RoundedRectangle(cornerRadius: ForgeLayout.innerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityValue(stateDescription)
    }

    private var categoryLine: some View {
        HStack(spacing: FDS.Spacing.xs) {
            Image(systemName: recommendation.category.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(impactTint)
                .accessibilityHidden(true)
            Text(recommendation.category.rawValue)
                .font(HomeType.micro)
                .foregroundStyle(impactTint)
                .tracking(1.4)
                .textCase(.uppercase)
                .forgeSingleLine(minScale: ForgeLayout.labelMinScale)
            Spacer(minLength: FDS.Spacing.sm)
            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textMuted)
                .accessibilityHidden(true)
        }
    }

    private var titleLine: some View {
        ForgeAdaptiveStack(spacing: FDS.Spacing.sm, alignment: .firstTextBaseline) {
            Text(recommendation.title)
                .font(HomeType.status)
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForgeChip(label: recommendation.impact.rawValue, energy: impactTint, selected: true)
                .fixedSize()
        }
    }
}

struct OptimizationGoalsCard: View {
    @ObservedObject var vm: LifestyleViewModel

    // Derived from live HealthKit data (was a hardcoded array).
    // Colors are presentation only: each goal takes its own §5 domain token
    // (sleep steel, mind aurora, nutrition amber, wellbeing vitality).
    private var goals: [(title: String, progress: Double, current: String, target: String, color: Color)] {
        let m = vm.metrics
        let protein = Int(vm.healthStats?.protein ?? 0)
        let mindfulWeek = vm.mindfulMinutesWeek
        let stressProgress: Double = {
            switch m.stressLevel {
            case .low: return 1.0
            case .medium: return 0.6
            case .high: return 0.3
            }
        }()
        return [
            ("Sleep → 8h", min(m.sleepAverage / 8.0, 1.0),
             String(format: "%.1fh avg", m.sleepAverage), "8h", Color.steel),
            ("Lower stress", stressProgress,
             m.stressLevel.rawValue, "Low", Color.aurora),
            ("Daily protein 180g", min(Double(protein) / 180.0, 1.0),
             "\(protein)g", "180g", Color.amber),
            ("Mindfulness 70 min/wk", min(Double(mindfulWeek) / 70.0, 1.0),
             "\(mindfulWeek) min", "70 min", Color.vitality),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("Optimization Goals")

            // Four goals render 2 x 2 and drop to one column at AX3.
            ForgeStatGrid(columns: 2) {
                ForEach(Array(goals.enumerated()), id: \.offset) { i, goal in
                    GoalProgressItem(
                        title: goal.title, progress: goal.progress,
                        current: goal.current, target: goal.target,
                        color: goal.color, appeared: true, index: i
                    )
                }
            }
        }
        .forgeContentCard(tint: .ember)
    }
}

/// One goal as a stat-tile cell (Home's lifestyleChip recipe in a well): the
/// current value in headline with its percent, the goal as a sentence-case
/// label, a clamped progress bar, and the target. `appeared` and `index` are
/// kept for source compatibility; the bar animates value changes itself.
struct GoalProgressItem: View {
    let title: String
    let progress: Double
    let current: String
    let target: String
    let color: Color
    let appeared: Bool
    let index: Int

    private var percent: Int {
        guard progress.isFinite else { return 0 }
        return Int(progress * 100)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: FDS.Spacing.xs) {
                Text(current)
                    .font(FDS.TypeScale.Dynamic.headline)
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
                    .forgeSingleLine()
                    .contentTransition(.numericText())
                    .layoutPriority(1)
                Spacer(minLength: FDS.Spacing.xs)
                Text("\(percent)%")
                    .font(HomeType.label)
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .forgeSingleLine(minScale: ForgeLayout.labelMinScale)
                    .contentTransition(.numericText())
            }
            Text(title)
                .font(HomeType.micro)
                .foregroundStyle(Color.textTertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            ForgeProgressBar(fraction: progress, tint: color)
            HStack(alignment: .firstTextBaseline, spacing: FDS.Spacing.xs) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.textMuted)
                Text(target)
                    .font(HomeType.micro)
                    .foregroundStyle(color)
                    .forgeSingleLine(minScale: ForgeLayout.labelMinScale)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .forgeWell()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(current), \(target)")
        .accessibilityValue("\(percent)%")
    }
}
