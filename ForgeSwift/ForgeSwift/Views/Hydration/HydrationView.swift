import SwiftUI
import Combine
import ForgeCore

// ============================================================
// MARK: - Page
// ============================================================

/// Today's water against a goal the person can set. The estimate from
/// weight, work, and cycle is the starting suggestion — never a lock.
struct HydrationView: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject private var health = HealthKitManager.shared
    @ObservedObject private var cycle = MenstrualHealthStore.shared

    @State private var now = Date()
    @State private var customMilliliters = ""
    @State private var showCustom = false
    @State private var showGoalEditor = false
    @State private var lastError: String?
    @State private var writing = false

    @FocusState private var customFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var hydrationRingSize: CGFloat = 168
    @ScaledMetric(relativeTo: .caption) private var weekPlotSize: CGFloat = 96

    private let tick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: ForgeLayout.sectionGap) {
                hero
                if !health.isAuthorized { permissionNotice }
                presets
                if let lastError { errorBanner(lastError) }
                guidanceCard
                timeline
                week
            }
            .forgeScreenInsets(top: ForgeLayout.screenTop)
        }
        .refreshable { await health.refreshHydration() }
        .forgeScreenBackground(accent: Color.steel)
        .navigationTitle("Hydration")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Goal") { showGoalEditor = true }
                    .font(HomeType.status)
                    .foregroundColor(.ember)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { customFocused = false }
            }
        }
        .sheet(isPresented: $showGoalEditor) {
            HydrationGoalEditor(
                suggestedMl: suggestedMl,
                currentMl: targetMl,
                isCustom: hasCustomGoal
            ) { newGoal in
                applyGoal(newGoal)
            }
        }
        .onReceive(tick) { now = $0 }
        .task { await health.refreshHydration() }
    }

    // ------------------------------------------------------------
    // MARK: Derived
    // ------------------------------------------------------------

    private var consumedMl: Double { health.todayWaterMilliliters }
    private var suggestedMl: Double {
        HydrationEngine.targetMilliliters(
            weightKilograms: store.userProfile.weight,
            activeCalories: Double(health.todayStats?.activeCalories ?? store.dailyMetrics.activeCalories),
            cycle: cycleAdjustment
        )
    }
    private var hasCustomGoal: Bool {
        store.nutritionPreferences.hydrationTargetMl != nil
            || store.nutritionPreferences.waterGlassesTarget != nil
    }
    private var targetMl: Double {
        LifestyleTargets.hydrationMilliliters(
            profile: store.userProfile,
            overrides: store.nutritionPreferences,
            activeCalories: Double(health.todayStats?.activeCalories ?? store.dailyMetrics.activeCalories),
            cycle: cycleAdjustment
        )
    }
    private var remainingMl: Double { max(0, targetMl - consumedMl) }
    private var progress: Double { targetMl > 0 ? min(1, consumedMl / targetMl) : 0 }
    private var progressPercent: Int { Int((progress * 100).rounded()) }

    private var cycleAdjustment: HydrationEngine.CycleAdjustment {
        guard cycle.settings.enabled else { return .none }
        switch cycle.snapshot.phase {
        case .menstruation: return .menstruation
        case .luteal: return .luteal
        default: return .none
        }
    }

    private var phase: CircadianRhythm.Phase {
        CircadianRhythm.phase(
            from: store.sleepData.compactMap { entry in
                guard let onset = entry.onset, let wake = entry.wake, wake > onset else { return nil }
                return CircadianRhythm.Night(onset: onset, wake: wake, asleepHours: entry.totalHours)
            }.sorted { $0.wake < $1.wake }
        ) ?? CircadianRhythm.Phase(wakeHour: 7, onsetHour: 23, confidence: 0)
    }

    private var expectedMl: Double {
        HydrationEngine.expectedMilliliters(
            atHour: HydrationEngine.hourOfDay(now),
            target: targetMl,
            wakeHour: phase.wakeHour,
            onsetHour: phase.onsetHour
        )
    }

    private var status: HydrationEngine.Status {
        HydrationEngine.status(consumed: consumedMl, target: targetMl, expected: expectedMl)
    }

    private var hoursUntilOnset: Double {
        HydrationEngine.normalizedHour(phase.onsetHour - HydrationEngine.hourOfDay(now))
    }

    /// Behind reads as a miss (steel family), never amber (nutrition) or red.
    private var statusColor: Color {
        switch status {
        case .behind: return ForgeProgressChrome.miss
        case .onTrack: return Color.steel
        case .met: return Color.vitality
        case .over: return Color.steelLight
        }
    }

    private var statusTitle: String {
        switch status {
        case .behind: return "Behind pace"
        case .onTrack: return "On pace"
        case .met: return "Need covered"
        case .over: return "Past today's need"
        }
    }

    // ------------------------------------------------------------
    // MARK: Hero
    // ------------------------------------------------------------

    private var hero: some View {
        VStack(spacing: ForgeLayout.heroGap) {
            heroRing
            heroStatus
            heroStats
        }
        .frame(maxWidth: .infinity)
        .forgePlate(energy: Color.steel)
        .accessibilityElement(children: .contain)
    }

    private var heroRing: some View {
        ForgeProgressRing(
            progress: progressPercent,
            energy: Color.steel,
            size: ForgeLayout.scaledCap(hydrationRingSize, base: 168)
        ) {
            VStack(spacing: FDS.Spacing.xs) {
                Text(formatMl(consumedMl))
                    .font(HomeType.heroScore)
                    .foregroundStyle(Color.textPrimary)
                    .forgeGlanceText()
                    .contentTransition(.numericText())
                    .accessibilityLabel(
                        "Hydration \(formatMl(consumedMl)) of \(formatMl(targetMl)), \(statusTitle)"
                    )
                goalButton
            }
        }
    }

    private var goalButton: some View {
        Button { showGoalEditor = true } label: {
            HStack(spacing: FDS.Spacing.xs) {
                Text("of \(formatMl(targetMl))")
                    .forgeGlanceText()
                Image(systemName: "pencil")
                    .font(.system(size: 11, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .font(HomeType.label)
            .foregroundStyle(Color.textSecondary)
            .frame(minHeight: ForgeUX.minTap)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Daily goal \(formatMl(targetMl)). Double tap to change.")
    }

    /// Status chip, plus Home's live pill when Health is connected.
    private var heroStatus: some View {
        VStack(spacing: ForgeLayout.tileGap) {
            ForgeVibeChip(label: statusTitle, energy: statusColor)
            if health.isAuthorized { syncPill }
        }
    }

    private var syncPill: some View {
        HStack(spacing: FDS.Spacing.xs) {
            Circle()
                .fill(Color.vitality)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text("Apple Health, both ways")
                .font(HomeType.micro)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, FDS.Spacing.sm)
        .padding(.vertical, FDS.Spacing.xs)
        .background(Capsule().fill(Color.white.opacity(0.05)))
        .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityHint(syncDetail)
    }

    private var syncDetail: String {
        "Logs you add here land in Health. Drinks from Watch and other apps land here."
    }

    private var heroStats: some View {
        ForgeStatGrid(columns: 3) {
            ForgeStatTile(label: "Progress", value: "\(progressPercent)%", energy: statusColor)
            ForgeStatTile(label: "Left", value: formatMl(remainingMl), energy: Color.steel)
            ForgeStatTile(
                label: "Glasses",
                value: String(format: "%.1f", HydrationEngine.glasses(fromMilliliters: consumedMl)),
                energy: Color.steel
            )
        }
    }

    // ------------------------------------------------------------
    // MARK: Notices
    // ------------------------------------------------------------

    private var permissionNotice: some View {
        HStack(alignment: .top, spacing: ForgeLayout.rowGap) {
            ForgeIconWell(systemImage: "heart.slash", tint: .warning)
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text("Apple Health not connected")
                    .font(HomeType.status)
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Connect Apple Health to read today's water and write what you log.")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
            }
            Spacer(minLength: 0)
        }
        .forgeContentCard(tint: .warning, padding: ForgeLayout.compactCardPadding)
        .accessibilityElement(children: .combine)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: ForgeLayout.rowGap) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: ForgeUX.icon, weight: .semibold))
                .foregroundStyle(Color.danger)
                .accessibilityHidden(true)
            Text(message)
                .font(HomeType.body)
                .foregroundStyle(Color.textPrimary)
                .forgeWrapping()
            Spacer(minLength: 0)
        }
        .forgeContentCard(tint: .danger, padding: ForgeLayout.compactCardPadding)
        .accessibilityElement(children: .combine)
    }

    // ------------------------------------------------------------
    // MARK: Presets
    // ------------------------------------------------------------

    private var presets: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("Log a drink")
            ForgeEqualColumnsLayout(
                columns: typeSize.isAccessibilitySize ? 2 : 4,
                spacing: ForgeLayout.tileGap,
                minCellWidth: 64
            ) {
                ForEach(HydrationEngine.presets) { preset in
                    presetTile(preset)
                }
            }
            ForgeTextLink(
                title: showCustom ? "Hide custom amount" : "Custom amount",
                accent: Color.steel
            ) {
                withAnimation(reduceMotion ? nil : ForgeMotion.smooth) { showCustom.toggle() }
            }
            if showCustom {
                customField
                    .transition(.opacity)
            }
        }
        .forgeContentCard(tint: .steel)
    }

    private func presetTile(_ preset: HydrationEngine.Preset) -> some View {
        Button {
            Task { await log(preset.milliliters) }
        } label: {
            VStack(spacing: ForgeLayout.pairGap) {
                Image(systemName: preset.symbolName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.steel)
                    .accessibilityHidden(true)
                Text(preset.title)
                    .font(HomeType.label)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text("\(Int(preset.milliliters)) ml")
                    .font(HomeType.micro)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: ForgeUX.minTap, maxHeight: .infinity)
            .forgeWell()
        }
        .buttonStyle(ForgePressStyle())
        .disabled(writing)
        .accessibilityLabel("Log \(preset.title), \(Int(preset.milliliters)) milliliters")
    }

    private var customField: some View {
        ForgeAdaptiveStack(spacing: ForgeLayout.tileGap) {
            TextField("ml", text: $customMilliliters)
                .keyboardType(.numberPad)
                .focused($customFocused)
                .accessibilityLabel("Amount in milliliters")
                .font(HomeType.body)
                .foregroundStyle(Color.textPrimary)
                .frame(minHeight: ForgeUX.minTap - ForgeLayout.tilePadding * 2)
                .forgeWell()
                .contentShape(Rectangle())
                .onTapGesture { customFocused = true }
            ForgeSecondaryButton(title: "Add", accent: Color.steel) {
                addCustom()
            }
            .disabled(writing)
        }
    }

    private func addCustom() {
        guard let ml = Double(customMilliliters), ml > 0, ml <= 2_000 else { return }
        customFocused = false
        Task { await log(ml); customMilliliters = ""; showCustom = false }
    }

    // ------------------------------------------------------------
    // MARK: Guidance + timeline + week
    // ------------------------------------------------------------

    private var guidanceCard: some View {
        HStack(alignment: .top, spacing: ForgeLayout.rowGap) {
            ForgeIconWell(systemImage: "drop.triangle.fill", tint: statusColor)
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text(HydrationEngine.guidance(
                    status: status,
                    remaining: remainingMl,
                    hoursUntilOnset: hoursUntilOnset
                ))
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
                guidanceNote
            }
            Spacer(minLength: 0)
        }
        .forgeContentCard(tint: .steel)
    }

    private var cycleNote: String {
        cycleAdjustment == .menstruation
            ? "Suggested need is up \(Int(HydrationEngine.menstruationBonusMilliliters)) ml this phase."
            : "Luteal phase adds \(Int(HydrationEngine.lutealBonusMilliliters)) ml to the suggested need."
    }

    @ViewBuilder
    private var guidanceNote: some View {
        if !hasCustomGoal, cycleAdjustment != .none {
            Text(cycleNote)
                .font(HomeType.body)
                .foregroundStyle(Color.textTertiary)
                .forgeWrapping()
        } else if hasCustomGoal {
            Text("Your goal. Change it any time — the estimate is only a suggestion.")
                .font(HomeType.body)
                .foregroundStyle(Color.textTertiary)
                .forgeWrapping()
        }
    }

    private var timeline: some View {
        let count = health.todayWaterLogs.count
        return VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("Today", meta: "\(count) drink\(count == 1 ? "" : "s")")

            if health.todayWaterLogs.isEmpty {
                ForgeEmptyNote(
                    title: "Nothing from Apple Health yet",
                    message: "A glass here, or a drink logged on your Watch, will show up.",
                    systemImage: "drop",
                    tint: Color.steel
                )
            } else {
                VStack(spacing: ForgeLayout.rowGap) {
                    ForEach(health.todayWaterLogs) { entry in
                        logRow(entry)
                    }
                }
            }

            if health.isAuthorized {
                Text(syncDetail)
                    .font(HomeType.micro)
                    .foregroundStyle(Color.textTertiary)
                    .forgeWrapping()
            }
        }
        .forgeContentCard(tint: .steel)
    }

    private func logRow(_ entry: WaterLog) -> some View {
        ForgeAdaptiveStack(spacing: ForgeLayout.rowGap) {
            HStack(spacing: ForgeLayout.rowGap) {
                ForgeIconWell(
                    systemImage: entry.isForge ? "drop.fill" : "heart.fill",
                    tint: entry.isForge ? Color.steel : Color.vitality
                )
                VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                    Text(formatMl(entry.milliliters))
                        .font(HomeType.status)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(2)
                    Text(logSubtitle(entry))
                        .font(HomeType.body)
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            if entry.isForge {
                deleteButton(for: entry)
            }
        }
        .padding(.vertical, ForgeLayout.rowVerticalPadding)
    }

    private func logSubtitle(_ entry: WaterLog) -> String {
        "\(entry.sourceName) · \(entry.date.formatted(date: .omitted, time: .shortened))"
    }

    private func deleteButton(for entry: WaterLog) -> some View {
        Button {
            ForgeHaptics.play(.warning)
            Task { await delete(entry) }
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .frame(width: ForgeUX.minTap, height: ForgeUX.minTap)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Delete this Forge log from Apple Health")
    }

    private var week: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("Last 7 days", meta: "Goal \(formatMl(targetMl))")
            weekChart
        }
        .forgeContentCard(tint: .steel)
    }

    private var weekChart: some View {
        VStack(spacing: FDS.Spacing.sm) {
            weekBars
            weekAxis
        }
        .accessibilityElement(children: .contain)
    }

    private var weekBars: some View {
        HStack(alignment: .bottom, spacing: FDS.Spacing.sm) {
            ForEach(health.weeklyWaterMilliliters) { day in
                Capsule()
                    .fill(weekBarColor(day.milliliters))
                    .frame(height: barHeight(day.milliliters))
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(weekAccessibility(day))
            }
        }
        .frame(height: weekPlotSize, alignment: .bottom)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.18))
                .frame(height: 1)
                .offset(y: -goalLineOffset)
                .accessibilityHidden(true)
        }
    }

    private var weekAxis: some View {
        HStack(spacing: FDS.Spacing.sm) {
            ForEach(health.weeklyWaterMilliliters) { day in
                Text(dayLabel(day.date))
                    .font(HomeType.micro)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private func weekBarColor(_ ml: Double) -> Color {
        ml >= targetMl * 0.9 ? Color.steel : Color.steel.opacity(0.35)
    }

    private func weekAccessibility(_ day: DailyWaterTotal) -> String {
        let weekday = day.date.formatted(.dateTime.weekday(.wide))
        let met = day.milliliters >= targetMl * 0.9 ? "goal met" : "goal not met"
        return "\(weekday), \(formatMl(day.milliliters)), \(met)"
    }

    // ------------------------------------------------------------
    // MARK: Actions
    // ------------------------------------------------------------

    private func applyGoal(_ milliliters: Double?) {
        var prefs = store.nutritionPreferences
        if let milliliters {
            let clamped = HydrationEngine.resolvedTargetMilliliters(
                userGoal: milliliters,
                suggested: suggestedMl
            )
            prefs.hydrationTargetMl = clamped
            prefs.waterGlassesTarget = max(4, Int(HydrationEngine.glasses(fromMilliliters: clamped).rounded()))
        } else {
            prefs.hydrationTargetMl = nil
            prefs.waterGlassesTarget = nil
        }
        store.updateNutritionPreferences(prefs)
        store.publishHomeWidgets()
    }

    private func log(_ milliliters: Double) async {
        writing = true
        defer { writing = false }
        do {
            try await health.logWater(milliliters: milliliters)
            store.publishHomeWidgets()
            lastError = nil
            ForgeHaptics.play(.success)
        } catch {
            lastError = "Could not write to Apple Health. Check Water permissions."
        }
    }

    private func delete(_ log: WaterLog) async {
        do {
            try await health.deleteWaterLog(log)
            lastError = nil
        } catch {
            lastError = "Could not delete that sample from Apple Health."
        }
    }

    private func formatMl(_ ml: Double) -> String {
        if ml >= 1_000 { return String(format: "%.2f L", ml / 1_000) }
        return "\(Int(ml.rounded())) ml"
    }

    private var weekMaxMl: Double {
        max(targetMl, health.weeklyWaterMilliliters.map(\.milliliters).max() ?? targetMl, 1)
    }

    private var goalLineOffset: CGFloat {
        weekPlotSize * CGFloat(targetMl / weekMaxMl)
    }

    private func barHeight(_ ml: Double) -> CGFloat {
        max(8, weekPlotSize * CGFloat(ml / weekMaxMl))
    }

    private func dayLabel(_ date: Date) -> String {
        String(date.formatted(.dateTime.weekday(.abbreviated)).prefix(1))
    }
}

// ============================================================
// MARK: - Goal editor
// ============================================================

private struct HydrationGoalEditor: View {
    @Environment(\.dismiss) private var dismiss

    let suggestedMl: Double
    let currentMl: Double
    let isCustom: Bool
    let onSave: (Double?) -> Void

    @State private var draft: Double = 2_000

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: ForgeLayout.groupBreak) {
                    numberBlock
                    sliderBlock
                    stepRow
                    suggestionTile
                    if isCustom {
                        ForgeTextLink(title: "Use suggested instead", accent: Color.steel) {
                            onSave(nil)
                            dismiss()
                        }
                    }
                }
                .forgeScreenInsets(top: FDS.Spacing.lg)
            }
            .background(Color.background.ignoresSafeArea())
            .navigationTitle("Daily goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(.ember)
                }
            }
            .onAppear { draft = currentMl }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var numberBlock: some View {
        VStack(spacing: ForgeLayout.pairGap) {
            Text(format(draft))
                .font(HomeType.heroScore)
                .foregroundStyle(Color.textPrimary)
                .forgeSingleLine()
                .contentTransition(.numericText())
            Text("\(Int(HydrationEngine.glasses(fromMilliliters: draft).rounded())) glasses · \(Int(HydrationEngine.fluidOunces(fromMilliliters: draft).rounded())) fl oz")
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .forgeWrapping()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var sliderBlock: some View {
        VStack(spacing: ForgeLayout.rowGap) {
            Slider(
                value: $draft,
                in: HydrationEngine.minimumTargetMilliliters...HydrationEngine.maximumTargetMilliliters,
                step: 50
            )
            .tint(Color.steel)
            .accessibilityLabel("Daily water goal")
            .accessibilityValue(format(draft))
            HStack {
                Text("1.5 L")
                Spacer()
                Text("5 L")
            }
            .font(HomeType.micro)
            .foregroundStyle(Color.textTertiary)
            .accessibilityHidden(true)
        }
    }

    private var stepRow: some View {
        ForgeAdaptiveStack(spacing: ForgeLayout.tileGap) {
            ForgeSecondaryButton(title: "− 250", accent: Color.steel) {
                draft = max(HydrationEngine.minimumTargetMilliliters, draft - 250)
            }
            ForgeSecondaryButton(title: "+ 250", accent: Color.steel) {
                draft = min(HydrationEngine.maximumTargetMilliliters, draft + 250)
            }
        }
    }

    private var suggestionTile: some View {
        Button {
            draft = suggestedMl
        } label: {
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text("Suggested for you")
                    .font(HomeType.status)
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(format(suggestedMl)) from weight, today’s work, and cycle. You can still change it.")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
            }
            .frame(maxWidth: .infinity, minHeight: ForgeUX.minTap, alignment: .leading)
            .forgeWell(padding: ForgeLayout.compactCardPadding)
        }
        .buttonStyle(ForgePressStyle())
    }

    private func format(_ ml: Double) -> String {
        String(format: "%.2f L", ml / 1_000)
    }
}
