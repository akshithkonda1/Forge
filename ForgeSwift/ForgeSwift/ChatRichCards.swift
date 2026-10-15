import SwiftUI

struct RichCardView: View {
    let card: RichCardData
    var body: some View {
        switch card.type {
        case .workoutPlan: WorkoutRichCardView(card: card)
        case .dataChart:   DataChartRichCardView(card: card)
        }
    }
}

struct WorkoutRichCardView: View {
    let card: RichCardData
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    @ScaledMetric(relativeTo: .caption) private var badgeSize: CGFloat = 28

    private var exercises: [RichCardExercise] { card.workoutExercises ?? [] }

    private var durationText: String {
        guard let minutes = card.workoutDuration, minutes > 0 else { return "—" }
        return "\(minutes) min"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            header

            if expanded, !exercises.isEmpty {
                exerciseList
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }

            if !exercises.isEmpty {
                ForgeTextLink(
                    title: expanded ? "Hide exercises" : "Show exercises",
                    accent: .ember,
                    expanded: expanded
                ) {
                    withAnimation(reduceMotion ? nil : FDS.Spring.standard) { expanded.toggle() }
                }
            }

            ForgePrimaryButton(title: "Start this workout", icon: "play.fill") {
                startWorkout()
            }
        }
        .forgeContentCard(tint: .ember)
        .accessibilityElement(children: .contain)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            HStack(spacing: ForgeLayout.rowGap) {
                ForgeIconWell(systemImage: "dumbbell.fill", tint: .ember)
                Text(card.workoutName ?? "Workout Plan")
                    .font(HomeType.status)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                    .layoutPriority(1)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
            }

            ForgeFlowLayout {
                ForgeChip(label: durationText, icon: "clock.fill")
                if !exercises.isEmpty {
                    ForgeChip(label: "\(exercises.count) exercises", icon: "list.bullet")
                }
            }
        }
    }

    // MARK: Exercises

    private var exerciseList: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            ForEach(Array(exercises.enumerated()), id: \.offset) { i, ex in
                exerciseRow(index: i, exercise: ex)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeWell()
    }

    private func exerciseRow(index: Int, exercise ex: RichCardExercise) -> some View {
        let badge = ForgeLayout.scaledCap(badgeSize, base: 28)
        return HStack(spacing: ForgeLayout.rowGap) {
            Text("\(index + 1)")
                .font(HomeType.label)
                .foregroundStyle(Color.ember)
                .monospacedDigit()
                .hudInArcText()
                .frame(width: badge, height: badge)
                .background(Circle().fill(Color.ember.opacity(0.16)))
                .accessibilityHidden(true)
            Text(ex.name)
                .font(HomeType.status)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)
                .forgeWrapping()
                .layoutPriority(1)
            Spacer(minLength: FDS.Spacing.xs)
            Text("\(ex.sets) × \(ex.reps)")
                .font(HomeType.label)
                .foregroundStyle(Color.textSecondary)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Exercise \(index + 1), \(ex.name), \(ex.sets) sets of \(ex.reps)")
    }

    // MARK: Action

    private func startWorkout() {
        store.adoptWorkoutFromRichCard(card)
        if store.todayWorkout != nil {
            store.startExistingWorkout()
        } else {
            store.openChat(with: HomeInsightFlow.todayPlanPrompt, voice: false)
        }
    }
}

struct DataChartRichCardView: View {
    let card: RichCardData
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .caption) private var plotHeight: CGFloat = 72
    @State private var appeared = false
    @State private var selectedIdx: Int? = nil
    var values:   [Double] { card.chartValues ?? [] }
    var maxVal:   Double   { values.max() ?? 1 }
    var minVal:   Double   { values.min() ?? 0 }
    var barColor: Color    { card.chartColor ?? .steel }

    private var showsAxisLabels: Bool { values.count <= 12 }

    private var selectedValueText: String? {
        guard let idx = selectedIdx, idx < values.count else { return nil }
        return String(format: "%.0f", values[idx])
    }

    private var chartSummary: String {
        let title = card.chartTitle ?? "Trend"
        guard !values.isEmpty else { return title }
        let low = String(format: "%.0f", minVal)
        let high = String(format: "%.0f", maxVal)
        return "\(title), \(values.count) values from \(low) to \(high)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            header

            if !values.isEmpty || card.chartInsight != nil {
                chartWell
            }
        }
        .forgeContentCard(tint: barColor)
        .onAppear { withAnimation(reduceMotion ? nil : FDS.Spring.hero.delay(0.1)) { appeared = true } }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: ForgeLayout.rowGap) {
            ForgeIconWell(systemImage: "chart.line.uptrend.xyaxis", tint: barColor)
            Text(card.chartTitle ?? "Trend")
                .font(HomeType.status)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)
                .layoutPriority(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: FDS.Spacing.xs)
            if let selected = selectedValueText {
                Text(selected)
                    .font(HomeType.metric)
                    .foregroundStyle(barColor)
                    .monospacedDigit()
                    .forgeSingleLine()
                    .contentTransition(.numericText())
                    .transition(.opacity)
            }
        }
    }

    // MARK: Chart

    private var chartWell: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            if !values.isEmpty {
                bars
            }
            if let insight = card.chartInsight {
                HStack(alignment: .firstTextBaseline, spacing: FDS.Spacing.sm) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(barColor.opacity(0.75))
                        .accessibilityHidden(true)
                    Text(insight)
                        .font(HomeType.body)
                        .foregroundStyle(Color.textSecondary)
                        .forgeWrapping()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeWell()
    }

    private var bars: some View {
        HStack(alignment: .bottom, spacing: FDS.Spacing.xs) {
            ForEach(Array(values.enumerated()), id: \.offset) { i, val in
                barColumn(index: i, value: val)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(chartSummary)
    }

    private func barColumn(index i: Int, value: Double) -> some View {
        let fraction: Double = maxVal > 0 ? max(0, value) / maxVal : 0
        let isSelected = selectedIdx == i
        let shown: CGFloat = (appeared || reduceMotion) ? CGFloat(fraction) : 0
        let barHeight: CGFloat = max(2, plotHeight * shown)
        let fillOpacity: Double = isSelected ? 0.95 : (selectedIdx == nil ? 0.8 : 0.4)
        let grow: Animation? = reduceMotion ? nil : FDS.Spring.hero.delay(Double(i) * 0.04)
        let valueText = String(format: "%.0f", value)

        return Button {
            withAnimation(reduceMotion ? nil : FDS.Spring.snap) {
                selectedIdx = selectedIdx == i ? nil : i
            }
            FDS.haptic(.select)
        } label: {
            VStack(spacing: FDS.Spacing.xs) {
                ZStack(alignment: .bottom) {
                    Color.clear.frame(height: plotHeight)
                    RoundedRectangle(cornerRadius: FDS.Radius.xs, style: .continuous)
                        .fill(barColor.opacity(fillOpacity))
                        .frame(height: barHeight)
                        .animation(grow, value: appeared)
                }
                if showsAxisLabels {
                    Text("\(i + 1)")
                        .font(HomeType.micro)
                        .foregroundStyle(Color.textTertiary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Point \(i + 1), \(valueText)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
