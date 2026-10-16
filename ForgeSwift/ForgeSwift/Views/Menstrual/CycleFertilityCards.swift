import SwiftUI
import ForgeCore

// ============================================================
// MARK: - Shared choice tiles (private to this file)
// ============================================================

/// One single-select choice. A tile (icon over a wrapping label) in a grid, or
/// a full-width option row when the grid would be too tight (accessibility
/// sizes). Selected state is a tinted fill and hairline, plus the
/// `.isSelected` trait for VoiceOver.
private struct CycleChoiceTile: View {
    let title: String
    let icon: String?
    let selected: Bool
    let tint: Color
    let asRow: Bool
    let action: () -> Void

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ForgeLayout.innerRadius, style: .continuous)
    }

    private var fill: Color {
        selected ? tint.opacity(0.14) : Color.white.opacity(0.045)
    }

    private var stroke: Color {
        selected ? tint.opacity(0.32) : Color.white.opacity(0.08)
    }

    private var foreground: Color {
        selected ? tint : Color.textSecondary
    }

    var body: some View {
        Button {
            ForgeHaptics.play(.selection)
            action()
        } label: {
            label
                .foregroundStyle(foreground)
                .background(shape.fill(fill))
                .overlay(shape.stroke(stroke, lineWidth: ForgeUX.stroke))
                .contentShape(shape)
        }
        .buttonStyle(ForgePressStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var label: some View {
        if asRow {
            rowLabel
        } else {
            tileLabel
        }
    }

    private var tileLabel: some View {
        VStack(spacing: FDS.Spacing.xs) {
            if let icon {
                Image(systemName: icon)
                    .font(.title3)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(HomeType.micro)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, FDS.Spacing.sm)
        .padding(.vertical, ForgeLayout.tilePadding)
        .frame(maxWidth: .infinity, minHeight: ForgeUX.minTap, maxHeight: .infinity)
    }

    private var rowLabel: some View {
        HStack(spacing: ForgeLayout.rowGap) {
            if let icon {
                Image(systemName: icon)
                    .font(.title3)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(HomeType.status)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: FDS.Spacing.sm)
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .accessibilityHidden(true)
            }
        }
        .padding(ForgeLayout.tilePadding)
        .frame(maxWidth: .infinity, minHeight: ForgeUX.minTap, alignment: .leading)
    }
}

/// Equal-height tiles in `columns`, or vertical option rows at accessibility
/// sizes.
private struct CycleChoiceGrid<Item: Identifiable>: View {
    let items: [Item]
    let columns: Int
    var tint: Color = .ember
    let title: (Item) -> String
    let icon: (Item) -> String?
    let isSelected: (Item) -> Bool
    let onSelect: (Item) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: ForgeLayout.tileGap) {
                ForEach(items) { item in
                    tile(item, asRow: true)
                }
            }
        } else {
            ForgeEqualColumnsLayout(columns: columns, spacing: ForgeLayout.tileGap) {
                ForEach(items) { item in
                    tile(item, asRow: false)
                }
            }
        }
    }

    private func tile(_ item: Item, asRow: Bool) -> some View {
        CycleChoiceTile(
            title: title(item),
            icon: icon(item),
            selected: isSelected(item),
            tint: tint,
            asRow: asRow,
            action: { onSelect(item) }
        )
    }
}

// ============================================================
// MARK: - Fertile score
// ============================================================

struct FertileScoreCard: View {
    let score: Int
    let phase: MenstrualPhase
    let onAskARIA: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    /// Peak-window tone: the cycle palette's pink, declared once for this file.
    private static let peakTone = Color(hex: "F472B6")

    private var band: (label: String, color: Color) {
        switch score {
        case 75...: return ("Peak window", Self.peakTone)
        case 45..<75: return ("Elevated", Color.ember)
        case 20..<45: return ("Rising / fading", Color.steel)
        default: return ("Low likelihood", Color.textTertiary)
        }
    }

    private var detailAlignment: HorizontalAlignment {
        typeSize.isAccessibilitySize ? .leading : .trailing
    }

    private var meterGradient: LinearGradient {
        LinearGradient(
            colors: [Color.steel, Color.ember, Self.peakTone],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("FERTILE SCORE")

            scoreHeader
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Fertile score \(score) out of 100, \(band.label)")

            VStack(alignment: .leading, spacing: FDS.Spacing.sm) {
                meter
                Text("Multi-signal confidence from ovulation method, cycle history, and phase proximity. Lifestyle timing only — not contraception.")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textTertiary)
                    .forgeWrapping()
            }

            ForgeTextLink(title: "Ask ARIA about this score", accent: .ember) {
                onAskARIA()
            }
        }
        .forgeContentCard(tint: band.color)
        .accessibilityElement(children: .contain)
    }

    private var scoreHeader: some View {
        ForgeAdaptiveStack(spacing: ForgeLayout.rowGap, alignment: .firstTextBaseline) {
            HStack(alignment: .firstTextBaseline, spacing: ForgeLayout.pairGap) {
                Text("\(score)")
                    .font(HomeType.heroScore)
                    .foregroundStyle(band.color)
                    .forgeSingleLine()
                    .contentTransition(.numericText())
                    .layoutPriority(1)
                Text("/ 100")
                    .font(HomeType.label)
                    .foregroundStyle(Color.textTertiary)
                    .forgeSingleLine(minScale: ForgeLayout.labelMinScale)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: detailAlignment, spacing: ForgeLayout.pairGap) {
                Text(band.label)
                    .font(HomeType.status)
                    .foregroundStyle(band.color)
                    .multilineTextAlignment(detailAlignment == .leading ? .leading : .trailing)
                    .fixedSize(horizontal: false, vertical: true)
                Text(phase.label)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textTertiary)
                    .multilineTextAlignment(detailAlignment == .leading ? .leading : .trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var meter: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(meterGradient)
                    .frame(width: max(8, geo.size.width * CGFloat(score) / 100.0))
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

// ============================================================
// MARK: - Goal selector
// ============================================================

struct CycleGoalSelectorCard: View {
    let goal: CycleGoal
    var lifestyleGoal: CycleLifestyleGoal = .none
    var periodTrainingStyle: CyclePeriodTrainingStyle = .easy
    let onUpdate: (CycleGoal) -> Void
    var onLifestyle: (CycleLifestyleGoal) -> Void = { _ in }
    var onPeriodStyle: (CyclePeriodTrainingStyle) -> Void = { _ in }

    /// Training goals in display order, with "Ask me" (`.none`) last.
    private var lifestyleOptions: [CycleLifestyleGoal] {
        CycleLifestyleGoal.allCases.filter { $0 != .none } + [CycleLifestyleGoal.none]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            goalGroup
            trainingGroup
            if lifestyleGoal != .none {
                periodGroup
            }
            if goal == .intimacy {
                Text("Healthy sex, safe sex, positions, period sex, partner tips — on this iPhone. Forge is not a contraceptive.")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textTertiary)
                    .forgeWrapping()
            }
        }
        .forgeContentCard(tint: .ember)
    }

    private var goalGroup: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.sm) {
            ForgeCardHeader("Your cycle goal")
            CycleChoiceGrid(
                items: CycleGoal.allCases,
                columns: 3,
                title: { $0.label },
                icon: { $0.icon },
                isSelected: { $0 == goal },
                onSelect: { onUpdate($0) }
            )
        }
    }

    private var trainingGroup: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.sm) {
            Text("What ARIA should design training around")
                .forgeSectionLabel()
                .forgeWrapping()
                .accessibilityAddTraits(.isHeader)
            CycleChoiceGrid(
                items: lifestyleOptions,
                columns: 3,
                title: { $0 == .none ? "Ask me" : $0.label },
                icon: { $0.icon },
                isSelected: { $0 == lifestyleGoal },
                onSelect: { onLifestyle($0) }
            )
        }
    }

    private var periodGroup: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.sm) {
            Text("While you’re on your period")
                .forgeSectionLabel()
                .forgeWrapping()
                .accessibilityAddTraits(.isHeader)
            CycleChoiceGrid(
                items: CyclePeriodTrainingStyle.allCases,
                columns: 2,
                title: { $0.label },
                icon: { _ in nil },
                isSelected: { $0 == periodTrainingStyle },
                onSelect: { onPeriodStyle($0) }
            )
            Text(periodTrainingStyle.runningCopy)
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
        }
    }
}

// ============================================================
// MARK: - Two-week wait
// ============================================================

struct TWWSectionCard: View {
    let daysElapsed: Int
    let onAskARIA: () -> Void

    @ScaledMetric(relativeTo: .title3) private var windowRingSize: CGFloat = 72

    private var windowLength: Int { 14 }

    private var daysClamped: Int {
        min(max(0, daysElapsed), windowLength)
    }

    private var progressPercent: Int {
        let fraction = Double(daysClamped) / Double(max(1, windowLength))
        return Int((fraction * 100).rounded())
    }

    /// Steel while waiting, ember once it is test day.
    private var tone: Color {
        daysElapsed >= windowLength ? Color.ember : Color.steel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("Two-Week Wait")

            HStack(spacing: ForgeLayout.blockGap) {
                HudProgressRing(
                    progress: progressPercent,
                    energy: tone,
                    size: ForgeLayout.scaledCap(windowRingSize, base: 72)
                ) {
                    Text("\(daysElapsed)")
                        .font(HomeType.metric)
                        .foregroundStyle(Color.textPrimary)
                        .hudInArcText()
                }
                VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                    Text("Day \(daysElapsed)")
                        .font(HomeType.metric)
                        .foregroundStyle(Color.textPrimary)
                        .forgeSingleLine()
                        .contentTransition(.numericText())
                    Text("of \(windowLength)")
                        .font(HomeType.micro)
                        .foregroundStyle(Color.textTertiary)
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Day \(daysElapsed) of your two-week wait")
            .accessibilityValue("\(progressPercent) percent")

            Text("\(max(0, windowLength - daysElapsed)) days until you can test")
                .font(HomeType.body)
                .foregroundStyle(Color.textTertiary)
                .forgeWrapping()

            ForgeTextLink(title: "Ask ARIA about the two-week wait", accent: .ember) {
                onAskARIA()
            }
        }
        .forgeContentCard(tint: tone)
        .accessibilityElement(children: .contain)
    }
}

// ============================================================
// MARK: - Health condition
// ============================================================

/// Rendered as plain content: its single host (Settings, Privacy & control)
/// already provides the card, so this view adds no chrome of its own.
struct CycleConditionSelectorCard: View {
    @Binding var condition: CycleCondition

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text("HEALTH CONDITION")
                    .forgeSectionLabel()
                    .accessibilityAddTraits(.isHeader)
                Text("Personalises cycle predictions and ARIA coaching")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textTertiary)
                    .forgeWrapping()
            }
            CycleChoiceGrid(
                items: CycleCondition.allCases,
                columns: 2,
                title: { $0.label },
                icon: { $0.icon },
                isSelected: { $0 == condition },
                onSelect: { condition = $0 }
            )
        }
    }
}
