import SwiftUI
import ForgeCore

// MARK: - Shared bottom panel

/// One surface recipe for the Set Logger and the Pain Logger: a scrim, a
/// continuous top-rounded elevated panel, a real drag-to-dismiss on the
/// grabber and a scroll fallback so fixed content never runs off a small
/// phone. The scrim ignores the safe area; the panel respects it, so the
/// tab bar never covers its actions.
private struct WorkoutBottomPanel<Content: View>: View {
    let onCancel: () -> Void
    let content: Content

    init(onCancel: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.onCancel = onCancel
        self.content = content()
    }

    private var panelShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: FDS.Radius.xxl,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: FDS.Radius.xxl,
            style: .continuous
        )
    }

    private var padded: some View {
        content
            .padding(.horizontal, ForgeLayout.cardPadding)
            .padding(.top, FDS.Spacing.xs)
            .padding(.bottom, ForgeLayout.sectionGap)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var grabber: some View {
        Capsule()
            .fill(Color.white.opacity(0.18))
            .frame(width: 36, height: 4)
            .frame(maxWidth: .infinity, minHeight: ForgeUX.minTap / 2)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 12).onEnded { value in
                    if value.translation.height > 60 { onCancel() }
                }
            )
            .accessibilityHidden(true)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onCancel() }
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                grabber
                ViewThatFits(in: .vertical) {
                    padded
                    ScrollView(showsIndicators: false) { padded }
                }
            }
            .frame(maxWidth: .infinity)
            .background(panelShape.fill(Color.surfaceElevated))
            .overlay(panelShape.stroke(Color.white.opacity(0.08), lineWidth: ForgeUX.hairline))
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape) { onCancel() }
        }
    }
}

// MARK: - Auto-reg strip

struct AutoRegStrip: View {
    let recommendation: SetRecommendation

    /// Status map applied locally: met is vitality, on track steel, a
    /// moderate pull-back amber, a stop or swap the miss steel.
    private var tone: Color {
        switch recommendation.primaryAction {
        case .increaseLoad, .addReps: return .vitality
        case .hold: return .steel
        case .decreaseLoad, .reduceReps, .extendRest, .deload: return .amber
        case .substitute, .stopExercise: return HudChrome.miss
        }
    }

    private var deltaLabel: String {
        let delta = recommendation.weightDelta
        return "\(delta > 0 ? "+" : "")\(delta) lb"
    }

    var body: some View {
        HStack(alignment: .top, spacing: ForgeLayout.rowGap) {
            ForgeIconWell(systemImage: recommendation.primaryAction.icon, tint: tone)
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                ForgeCardHeader(title: "ARIA AUTO-REG") {
                    if recommendation.weightDelta != 0 {
                        ForgeChip(label: deltaLabel, energy: tone, selected: true)
                    }
                }
                Text(recommendation.rationale)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
            }
            .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeWell()
    }
}

// MARK: - Substitution banner

struct SubstitutionBanner: View {
    let target: ExerciseDefinition
    let reason: String
    let onApply: () -> Void
    let onDismiss: () -> Void

    private var card: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            HStack(alignment: .top, spacing: ForgeLayout.rowGap) {
                ForgeIconWell(systemImage: "arrow.triangle.swap", tint: .steel)
                VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                    Text("ARIA SUGGESTS A SWAP")
                        .forgeSectionLabel(tint: .steel)
                        .forgeSingleLine(minScale: ForgeLayout.labelMinScale)
                        .accessibilityAddTraits(.isHeader)
                    Text("\(reason) — try \(target.name)")
                        .font(HomeType.status)
                        .foregroundStyle(Color.textPrimary)
                        .forgeWrapping()
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
                ForgeIconButton(
                    systemImage: "xmark",
                    accent: .steel,
                    accessibilityLabel: "Dismiss swap suggestion",
                    tinted: false,
                    action: onDismiss
                )
            }
            ForgeSecondaryButton(
                title: "Swap to \(target.name)",
                icon: "checkmark.circle.fill",
                accent: .steel,
                action: onApply
            )
        }
        .forgeContentCard(tint: .steel, padding: ForgeLayout.compactCardPadding)
    }

    var body: some View {
        VStack(spacing: 0) {
            card
                .padding(.horizontal, ForgeLayout.screenInset)
                .padding(.top, FDS.Spacing.sm)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Set logger

struct SetLoggerPanel: View {
    let exercise: Exercise
    let definition: ExerciseDefinition?
    let currentSet: Int
    let recommendation: SetRecommendation
    @Binding var proposedReps: Int
    @Binding var proposedWeight: Int
    @Binding var proposedRPE: Int
    let onConfirm: () -> Void
    let onCancel:  () -> Void

    private func rpeLabel(_ r: Int) -> String {
        switch r {
        case 1...3: return "Easy"
        case 4...5: return "Moderate"
        case 6...7: return "Hard"
        case 8: return "Very Hard"
        case 9: return "Max Effort"
        default: return "All Out 🔥"
        }
    }

    /// Effort ramp: steel while easy, amber at moderate, ember when hard.
    private func rpeColor(_ r: Int) -> Color {
        if r <= 4 { return .steel }
        if r <= 7 { return .amber }
        return .ember
    }

    private var rationaleRow: some View {
        HStack(alignment: .top, spacing: ForgeLayout.rowGap) {
            Image(systemName: recommendation.primaryAction.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(recommendation.primaryAction.tone)
                .accessibilityHidden(true)
            Text(recommendation.rationale)
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeWell()
    }

    private var repsBlock: some View {
        LoggerStepper(
            title: "REPS PERFORMED",
            spokenName: "Reps",
            value: proposedReps,
            onMinus: { if proposedReps > 1 { proposedReps -= 1 } },
            onPlus: { proposedReps += 1 }
        )
    }

    private var weightBlock: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            LoggerStepper(
                title: "WEIGHT (LBS)",
                spokenName: "Weight in pounds",
                value: proposedWeight,
                onMinus: { proposedWeight = max(0, proposedWeight - 1) },
                onPlus: { proposedWeight += 1 }
            )
            ForgeEqualColumnsLayout(columns: 4, spacing: FDS.Spacing.sm) {
                ForEach([-10, -5, 5, 10], id: \.self) { delta in
                    ForgeChipButton(
                        label: delta > 0 ? "+\(delta)" : "\(delta)",
                        energy: .ember,
                        fillsWidth: true
                    ) {
                        proposedWeight = max(0, proposedWeight + delta)
                    }
                }
            }
        }
    }

    private var effortBlock: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            ForgeCardHeader(title: "EFFORT") {
                Text("RPE \(proposedRPE) — \(rpeLabel(proposedRPE))")
                    .font(HomeType.label)
                    .foregroundStyle(rpeColor(proposedRPE))
                    .forgeSingleLine(minScale: ForgeLayout.labelMinScale)
            }
            ForgeEqualColumnsLayout(columns: 5, spacing: FDS.Spacing.sm) {
                ForEach(1...10, id: \.self) { level in
                    ForgeScaleCell(
                        title: "\(level)",
                        selected: level == proposedRPE,
                        tint: .ember,
                        accessibilityLabel: "RPE \(level)"
                    ) {
                        proposedRPE = level
                    }
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: ForgeLayout.tileGap) {
            ForgePrimaryButton(title: "Log Set", icon: "checkmark.circle.fill", accent: .ember, action: onConfirm)
            ForgeSecondaryButton(title: "Cancel", accent: HudChrome.emberSteel, action: onCancel)
        }
    }

    var body: some View {
        WorkoutBottomPanel(onCancel: onCancel) {
            VStack(alignment: .leading, spacing: ForgeLayout.sectionGap) {
                Text("SET \(currentSet) — \(exercise.name)")
                    .forgeSectionLabel(tint: .textTertiary)
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                rationaleRow
                repsBlock
                if exercise.weight != nil && proposedWeight > 0 {
                    weightBlock
                }
                effortBlock
                actions
            }
        }
    }
}

/// Big value with 44 pt minus and plus buttons. The value is also an
/// adjustable element, so VoiceOver can swipe up and down.
private struct LoggerStepper: View {
    let title: String
    let spokenName: String
    let value: Int
    let onMinus: () -> Void
    let onPlus: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var numeralSize: CGFloat = 64

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            Text(title)
                .forgeSectionLabel(tint: .textTertiary)
                .forgeSingleLine(minScale: ForgeLayout.labelMinScale)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: ForgeLayout.rowGap) {
                ForgeIconButton(
                    systemImage: "minus",
                    accent: .ember,
                    accessibilityLabel: "Decrease \(spokenName.lowercased())",
                    tinted: false,
                    action: onMinus
                )
                Text("\(value)")
                    .font(ForgeFont.sans(ForgeLayout.scaledCap(numeralSize, base: 64), weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(spokenName)
                    .accessibilityValue("\(value)")
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: onPlus()
                        case .decrement: onMinus()
                        @unknown default: break
                        }
                    }
                ForgeIconButton(
                    systemImage: "plus",
                    accent: .ember,
                    accessibilityLabel: "Increase \(spokenName.lowercased())",
                    action: onPlus
                )
            }
        }
    }
}

// MARK: - Pain logger

struct PainLoggerPanel: View {
    let exerciseName: String
    let onLog:    (PainEntry) -> Void
    let onCancel: () -> Void
    @State private var selectedLocation = "Knee"
    @State private var severity = 5
    private let locations = ["Shoulder", "Elbow", "Wrist", "Lower Back", "Hip", "Knee", "Ankle", "Neck", "Other"]

    private var severityTone: Color { severity >= 7 ? HudChrome.miss : Color.amber }

    private var severityNote: String {
        if severity >= 7 { return "Sharp pain — ARIA will pull you off this movement." }
        if severity >= 5 { return "ARIA may swap to a joint-friendly variant." }
        return "Logged for ARIA to monitor."
    }

    private var headerRow: some View {
        HStack(spacing: ForgeLayout.rowGap) {
            ForgeIconWell(systemImage: "exclamationmark.triangle.fill", tint: .amber)
            Text("LOG PAIN / DISCOMFORT")
                .forgeSectionLabel(tint: .textTertiary)
                .lineLimit(2)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
        }
    }

    private var locationBlock: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            Text("LOCATION")
                .forgeSectionLabel(tint: .textTertiary)
                .accessibilityAddTraits(.isHeader)
            ForgeFlowLayout(lineSpacing: ForgeLayout.interactiveChipLineGap) {
                ForEach(locations, id: \.self) { loc in
                    ForgeChipButton(label: loc, selected: selectedLocation == loc) {
                        selectedLocation = loc
                    }
                }
            }
        }
    }

    private var severityBlock: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            ForgeCardHeader(title: "SEVERITY") {
                Text("\(severity)/10")
                    .font(HomeType.label)
                    .monospacedDigit()
                    .foregroundStyle(severityTone)
                    .forgeSingleLine(minScale: ForgeLayout.labelMinScale)
            }
            ForgeEqualColumnsLayout(columns: 5, spacing: FDS.Spacing.sm) {
                ForEach(1...10, id: \.self) { level in
                    ForgeScaleCell(
                        title: "\(level)",
                        selected: level == severity,
                        tint: HudChrome.miss,
                        accessibilityLabel: "Severity \(level)"
                    ) {
                        severity = level
                    }
                }
            }
            Text(severityNote)
                .font(HomeType.body)
                .foregroundStyle(Color.textTertiary)
                .forgeWrapping()
        }
    }

    private var actions: some View {
        VStack(spacing: ForgeLayout.tileGap) {
            ForgePrimaryButton(title: "Log Pain", icon: "plus.circle.fill", accent: .ember) {
                onLog(PainEntry(location: selectedLocation, severity: severity, exerciseName: exerciseName))
            }
            ForgeSecondaryButton(title: "Cancel", accent: HudChrome.emberSteel, action: onCancel)
        }
    }

    var body: some View {
        WorkoutBottomPanel(onCancel: onCancel) {
            VStack(alignment: .leading, spacing: ForgeLayout.groupBreak) {
                headerRow
                locationBlock
                severityBlock
                actions
            }
        }
    }
}

// MARK: - PR banner

struct PRBannerView: View {
    let exerciseName: String

    private var card: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("Personal record", tint: .ember)
            HStack(spacing: ForgeLayout.rowGap) {
                ForgeIconWell(systemImage: "trophy.fill", tint: .ember)
                Text(exerciseName)
                    .font(HomeType.status)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
        }
        .forgeContentCard(accent: .ember)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Personal record, \(exerciseName)")
    }

    var body: some View {
        VStack(spacing: 0) {
            card
                .padding(.horizontal, ForgeLayout.screenInset)
                .padding(.top, FDS.Spacing.sm)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Rest

struct RestTimerView: View {
    let restTimeLeft: Int
    let totalRest:    Int
    let nextLabel:    String
    let onSkip:       () -> Void
    /// Optional nudge (-15 / +15 seconds). When nil only Skip is offered.
    var onAdjust:     ((Int) -> Void)? = nil

    @ScaledMetric(relativeTo: .largeTitle) private var restRingSize: CGFloat = 200
    @ScaledMetric(relativeTo: .largeTitle) private var restNumeralSize: CGFloat = 56
    @Environment(\.dynamicTypeSize) private var typeSize

    private var percent: Int {
        guard totalRest > 0 else { return 0 }
        let fraction = Double(restTimeLeft) / Double(totalRest)
        return Int((fraction * 100).rounded())
    }
    private var getReady: Bool { restTimeLeft > 0 && restTimeLeft <= 3 }
    private var restDone: Bool { totalRest > 0 && restTimeLeft == 0 }
    private var ringEnergy: Color { getReady ? Color.ember : HudChrome.miss }

    private var ringCenter: some View {
        VStack(spacing: ForgeLayout.labelValueGap) {
            Text("\(restTimeLeft)")
                .font(ForgeFont.sans(ForgeLayout.scaledCap(restNumeralSize, base: 56), weight: .bold))
                .monospacedDigit()
                .foregroundStyle(getReady ? Color.ember : Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(getReady ? "Get ready" : "sec")
                .font(HomeType.micro)
                .foregroundStyle(Color.textTertiary)
                .hudInArcText()
        }
        .padding(.horizontal, ForgeLayout.cardPadding)
    }

    private var ring: some View {
        HudProgressRing(
            progress: percent,
            energy: ringEnergy,
            size: ForgeLayout.scaledCap(restRingSize, base: 200),
            eventGlow: restDone
        ) {
            ringCenter
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rest")
        .accessibilityValue("\(restTimeLeft) seconds left")
        .accessibilityAddTraits(.updatesFrequently)
    }

    @ViewBuilder
    private var controlButtons: some View {
        if let onAdjust {
            ForgeSecondaryButton(title: "−15s", accent: HudChrome.emberSteel) { onAdjust(-15) }
            ForgeSecondaryButton(title: "Skip", icon: "forward.fill", accent: HudChrome.emberSteel, action: onSkip)
            ForgeSecondaryButton(title: "+15s", accent: HudChrome.emberSteel) { onAdjust(15) }
        } else {
            ForgeSecondaryButton(title: "Skip Rest", icon: "forward.fill", accent: HudChrome.emberSteel, action: onSkip)
        }
    }

    @ViewBuilder
    private var controls: some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: ForgeLayout.tileGap) { controlButtons }
        } else if onAdjust != nil {
            ForgeEqualColumnsLayout(columns: 3, spacing: ForgeLayout.tileGap) { controlButtons }
        } else {
            controlButtons
        }
    }

    private var upNext: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("Up next")
            ForgeListRow(icon: "figure.strengthtraining.traditional", iconColor: .steel, title: nextLabel)
        }
        .forgeContentCard(tint: .steel)
    }

    var body: some View {
        VStack(spacing: ForgeLayout.heroGap) {
            Text("REST")
                .forgeSectionLabel(tint: .textTertiary)
                .accessibilityAddTraits(.isHeader)
            ring
            controls
            upNext
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, ForgeLayout.screenInset)
        .padding(.top, ForgeLayout.screenTop)
        .padding(.bottom, ForgeLayout.sectionGap)
    }
}
