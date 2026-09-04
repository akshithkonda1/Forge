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

    private let tick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                hero
                syncBanner
                presets
                if showCustom { customField }
                if let lastError {
                    Text(lastError)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.alert)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                guidanceCard
                timeline
                week
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .background(Color.background.ignoresSafeArea())
        .navigationTitle("Hydration")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Goal") { showGoalEditor = true }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.ember)
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

    private var statusColor: Color {
        switch status {
        case .behind: return .amber
        case .onTrack: return Color(hex: "4A9EFF")
        case .met: return .vitality
        case .over: return .steel
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
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.borderColor.opacity(0.35), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AngularGradient(
                            colors: [Color(hex: "4A9EFF"), Color(hex: "00D4FF"), Color(hex: "4A9EFF")],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.7, dampingFraction: 0.8), value: progress)
                VStack(spacing: 4) {
                    Text(formatMl(consumedMl))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundColor(.textPrimary)
                        .monospacedDigit()
                    Button { showGoalEditor = true } label: {
                        HStack(spacing: 4) {
                            Text("of \(formatMl(targetMl))")
                            Image(systemName: "pencil")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Daily goal \(formatMl(targetMl)). Double tap to change.")
                }
            }
            .frame(width: 196, height: 196)
            .padding(.top, 8)

            HStack(spacing: 16) {
                stat(title: statusTitle, value: "\(Int((progress * 100).rounded()))%", tint: statusColor)
                stat(title: "Left", value: formatMl(remainingMl), tint: Color(hex: "4A9EFF"))
                stat(title: "Glasses",
                     value: String(format: "%.1f", HydrationEngine.glasses(fromMilliliters: consumedMl)),
                     tint: .aurora)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(Color.surface)
        .cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.borderColor.opacity(0.4), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Hydration \(formatMl(consumedMl)) of \(formatMl(targetMl)), \(statusTitle)")
    }

    private func stat(title: String, value: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    // ------------------------------------------------------------
    // MARK: Sync
    // ------------------------------------------------------------

    private var syncBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: health.isAuthorized ? "heart.circle.fill" : "heart.slash")
                .foregroundColor(health.isAuthorized ? .vitality : .warning)
            VStack(alignment: .leading, spacing: 2) {
                Text(health.isAuthorized ? "Apple Health, both ways" : "Apple Health not connected")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Text(health.isAuthorized
                     ? "Logs you add here land in Health. Drinks from Watch and other apps land here."
                     : "Connect Apple Health to read today's water and write what you log.")
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.surfaceElevated)
        .cornerRadius(14)
    }

    // ------------------------------------------------------------
    // MARK: Presets
    // ------------------------------------------------------------

    private var presets: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Log a drink")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.textPrimary)
            HStack(spacing: 8) {
                ForEach(HydrationEngine.presets) { preset in
                    Button {
                        Task { await log(preset.milliliters) }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: preset.symbolName)
                                .font(.system(size: 16, weight: .semibold))
                            Text(preset.title)
                                .font(.system(size: 11, weight: .semibold))
                            Text("\(Int(preset.milliliters)) ml")
                                .font(.system(size: 10))
                                .foregroundColor(.textTertiary)
                        }
                        .foregroundColor(Color(hex: "4A9EFF"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(hex: "4A9EFF").opacity(0.10))
                        .cornerRadius(14)
                    }
                    .buttonStyle(.plain)
                    .disabled(writing)
                    .accessibilityLabel("Log \(preset.title), \(Int(preset.milliliters)) milliliters")
                }
            }
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showCustom.toggle() }
            } label: {
                Text(showCustom ? "Hide custom amount" : "Custom amount")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color.surface)
        .cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.borderColor.opacity(0.4), lineWidth: 1))
    }

    private var customField: some View {
        HStack(spacing: 10) {
            TextField("ml", text: $customMilliliters)
                .keyboardType(.numberPad)
                .padding(12)
                .background(Color.surfaceElevated)
                .cornerRadius(12)
            Button("Add") {
                guard let ml = Double(customMilliliters), ml > 0, ml <= 2_000 else { return }
                Task { await log(ml); customMilliliters = ""; showCustom = false }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(hex: "4A9EFF"))
            .cornerRadius(12)
            .disabled(writing)
        }
    }

    // ------------------------------------------------------------
    // MARK: Guidance + timeline + week
    // ------------------------------------------------------------

    private var guidanceCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "drop.triangle.fill")
                .foregroundColor(statusColor)
                .font(.system(size: 16, weight: .semibold))
            VStack(alignment: .leading, spacing: 4) {
                Text(HydrationEngine.guidance(
                    status: status,
                    remaining: remainingMl,
                    hoursUntilOnset: hoursUntilOnset
                ))
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                if !hasCustomGoal, cycleAdjustment != .none {
                    Text(cycleAdjustment == .menstruation
                         ? "Suggested need is up \(Int(HydrationEngine.menstruationBonusMilliliters)) ml this phase."
                         : "Luteal phase adds \(Int(HydrationEngine.lutealBonusMilliliters)) ml to the suggested need.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.textTertiary)
                } else if hasCustomGoal {
                    Text("Your goal. Change it any time — the estimate is only a suggestion.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.surface)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.borderColor.opacity(0.35), lineWidth: 1))
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Today")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("\(health.todayWaterLogs.count) drink\(health.todayWaterLogs.count == 1 ? "" : "s")")
                    .font(.system(size: 12))
                    .foregroundColor(.textTertiary)
            }

            if health.todayWaterLogs.isEmpty {
                Text("Nothing from Apple Health yet. A glass here, or a drink logged on your Watch, will show up.")
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(health.todayWaterLogs) { log in
                    HStack(spacing: 10) {
                        Image(systemName: log.isForge ? "drop.fill" : "heart.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(log.isForge ? Color(hex: "4A9EFF") : .vitality)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(formatMl(log.milliliters))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.textPrimary)
                            Text(log.sourceName)
                                .font(.system(size: 11))
                                .foregroundColor(.textTertiary)
                        }
                        Spacer()
                        Text(log.date.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.textSecondary)
                        if log.isForge {
                            Button {
                                Task { await delete(log) }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.textTertiary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Delete this Forge log from Apple Health")
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(16)
        .background(Color.surface)
        .cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.borderColor.opacity(0.4), lineWidth: 1))
    }

    private var week: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Last 7 days")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.textPrimary)

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(health.weeklyWaterMilliliters) { day in
                    VStack(spacing: 6) {
                        Capsule()
                            .fill(day.milliliters >= targetMl * 0.9 ? Color(hex: "4A9EFF") : Color(hex: "4A9EFF").opacity(0.35))
                            .frame(height: barHeight(day.milliliters))
                        Text(dayLabel(day.date))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("\(dayLabel(day.date)), \(formatMl(day.milliliters))")
                }
            }
            .frame(height: 120, alignment: .bottom)
        }
        .padding(16)
        .background(Color.surface)
        .cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.borderColor.opacity(0.4), lineWidth: 1))
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
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
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

    private func barHeight(_ ml: Double) -> CGFloat {
        let maxMl = max(targetMl, health.weeklyWaterMilliliters.map(\.milliliters).max() ?? targetMl, 1)
        return max(8, 96 * CGFloat(ml / maxMl))
    }

    private func dayLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return String(f.string(from: date).prefix(1))
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
            VStack(spacing: 24) {
                VStack(spacing: 6) {
                    Text(format(draft))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundColor(.textPrimary)
                        .monospacedDigit()
                    Text("\(Int(HydrationEngine.glasses(fromMilliliters: draft).rounded())) glasses · \(Int(HydrationEngine.fluidOunces(fromMilliliters: draft).rounded())) fl oz")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.textSecondary)
                }
                .padding(.top, 12)

                VStack(spacing: 10) {
                    Slider(
                        value: $draft,
                        in: HydrationEngine.minimumTargetMilliliters...HydrationEngine.maximumTargetMilliliters,
                        step: 50
                    )
                    .tint(Color(hex: "4A9EFF"))
                    HStack {
                        Text("1.5 L")
                        Spacer()
                        Text("5 L")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textTertiary)
                }

                HStack(spacing: 10) {
                    stepButton("− 250") { draft = max(HydrationEngine.minimumTargetMilliliters, draft - 250) }
                    stepButton("+ 250") { draft = min(HydrationEngine.maximumTargetMilliliters, draft + 250) }
                }

                Button {
                    draft = suggestedMl
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Suggested for you")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.textPrimary)
                        Text("\(format(suggestedMl)) from weight, today’s work, and cycle. You can still change it.")
                            .font(.system(size: 12))
                            .foregroundColor(.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.surfaceElevated)
                    .cornerRadius(14)
                }
                .buttonStyle(.plain)

                if isCustom {
                    Button("Use suggested instead") {
                        onSave(nil)
                        dismiss()
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.textSecondary)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
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
    }

    private func stepButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color(hex: "4A9EFF"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(hex: "4A9EFF").opacity(0.12))
                .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    private func format(_ ml: Double) -> String {
        String(format: "%.2f L", ml / 1_000)
    }
}
