import SwiftUI
import UIKit
import ForgeCore

/// One macro-to-color mapping for every food surface (rings, tiles, chips,
/// pick cards, menu items). Carbs and water are deliberately distinct.
enum FoodMacroPalette {
    static let calories = Color.amber
    static let protein = Color.ember
    static let carbs = Color.indigo
    static let fat = Color.aurora
    static let fiber = Color.vitality
    static let water = Color.steel
}

struct DailyNutritionView: View {
    @ObservedObject var vm: LifestyleViewModel
    @EnvironmentObject var store: AppStore
    @State private var showDevices = false

    var body: some View {
        VStack(spacing: ForgeLayout.sectionGap) {
            MacroRingsCard(vm: vm)
            AINutritionCoachCard(vm: vm)
            if store.metabolicHealthEnabled {
                MetabolicTranslationCard(
                    mealsLogged: vm.loggedMeals.count,
                    glucoseMgDl: vm.latestGlucoseMgDl,
                    storyLine: vm.metabolicSnapshot.storyLine,
                    watchLines: vm.metabolicSnapshot.watchEstimate?.displayLines ?? [],
                    onDevices: { showDevices = true }
                )
            }
            MealLogCard(vm: vm)
            AIMealSuggestionsCard(vm: vm)
            WaterIntakeCard(vm: vm)
            MicronutrientsCard(vm: vm)
        }
        .sheet(isPresented: $showDevices) {
            ConnectedDevicesLibraryView()
                .environmentObject(store)
        }
    }
}

// MARK: - Hero: macro rings

struct MacroRingsCard: View {
    @ObservedObject var vm: LifestyleViewModel
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private struct Macro {
        let label: String; let current: Int; let target: Int
        let color: Color; let unit: String; let radius: CGFloat
    }

    private static let ringStroke: CGFloat = 12
    private static let ringFrameHeight: CGFloat = 196

    private var macros: [Macro] {
        let stats = vm.healthStats
        return [
            Macro(label: "Carbs", current: Int(stats?.carbs ?? 0), target: 280, color: FoodMacroPalette.carbs, unit: "g", radius: 92),
            Macro(label: "Protein", current: Int(stats?.protein ?? 0), target: 180, color: FoodMacroPalette.protein, unit: "g", radius: 68),
            Macro(label: "Fats", current: Int(stats?.fat ?? 0), target: 70, color: FoodMacroPalette.fat, unit: "g", radius: 44),
        ]
    }

    private var totalCal: Int { vm.healthStats?.totalCalories ?? 0 }
    private var targetCal: Int { 2600 }
    private var isOverTarget: Bool { totalCal > targetCal }
    private var isAccessibilityLayout: Bool { dynamicTypeSize.isAccessibilitySize }

    private var calorieMetaText: String {
        isOverTarget ? "\(totalCal - targetCal) over" : "\(targetCal - totalCal) cal left"
    }

    private var calorieMetaColor: Color {
        isOverTarget ? ForgeProgressChrome.miss : Color.ember
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.heroGap) {
            ForgeCardHeader("TODAY'S MACROS", meta: calorieMetaText, metaColor: calorieMetaColor)
            ringStack
            if isAccessibilityLayout {
                accessibleTotal
            }
            legend
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeContentCard()
        .accessibilityElement(children: .contain)
        .onAppear { appeared = true }
    }

    // MARK: Rings

    private var ringStack: some View {
        ZStack {
            ForEach(Array(macros.enumerated()), id: \.offset) { i, macro in
                macroRing(macro, index: i)
            }
            if !isAccessibilityLayout {
                ringCenter
            }
        }
        .frame(height: Self.ringFrameHeight)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Calories, \(totalCal) of \(targetCal) kcal")
    }

    private func macroRing(_ macro: Macro, index: Int) -> some View {
        let fraction = min(1, Double(macro.current) / Double(max(1, macro.target)))
        let shown = appeared || reduceMotion
        let diameter = macro.radius * 2
        return ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: Self.ringStroke, lineCap: .round))
            Circle()
                .trim(from: 0, to: shown ? CGFloat(fraction) : 0)
                .stroke(macro.color, style: StrokeStyle(lineWidth: Self.ringStroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : ForgeMotion.sweep(staggeredBy: index), value: appeared)
        }
        .frame(width: diameter, height: diameter)
    }

    private var ringCenter: some View {
        VStack(spacing: ForgeLayout.labelValueGap) {
            Text("\(totalCal)")
                .font(HomeType.heroScore)
                .foregroundStyle(Color.textPrimary)
                .forgeGlanceText()
                .contentTransition(.numericText())
            Text("of \(targetCal) kcal")
                .font(HomeType.micro)
                .foregroundStyle(Color.textTertiary)
                .forgeGlanceText()
        }
        .frame(maxWidth: 68)
    }

    /// At accessibility sizes the number and its meta move below the ring,
    /// where they can use the full card width.
    private var accessibleTotal: some View {
        VStack(spacing: ForgeLayout.pairGap) {
            Text("\(totalCal)")
                .font(HomeType.heroScore)
                .foregroundStyle(Color.textPrimary)
                .forgeSingleLine()
                .contentTransition(.numericText())
            Text("of \(targetCal) kcal")
                .font(HomeType.body)
                .foregroundStyle(Color.textTertiary)
                .forgeWrapping()
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    // MARK: Legend

    private var legend: some View {
        VStack(spacing: ForgeLayout.rowGap) {
            ForEach(Array(macros.enumerated()), id: \.offset) { _, macro in
                legendRow(macro)
            }
        }
    }

    private func legendRow(_ macro: Macro) -> some View {
        let fraction = Double(macro.current) / Double(max(1, macro.target))
        let overBy = macro.current - macro.target
        return VStack(alignment: .leading, spacing: ForgeLayout.labelValueGap) {
            ForgeMetricRow(
                label: macro.label,
                value: "\(macro.current) / \(macro.target)",
                unit: macro.unit,
                tint: macro.color
            )
            ForgeProgressBar(fraction: fraction, tint: macro.color)
            if overBy > 0 {
                Text("\(overBy)\(macro.unit) over")
                    .font(HomeType.micro)
                    .foregroundStyle(ForgeProgressChrome.miss)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - ARIA coach

struct AINutritionCoachCard: View {
    @ObservedObject var vm: LifestyleViewModel
    @EnvironmentObject var store: AppStore
    @State private var tipIndex = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Live ARIA insight overrides the local heuristic tip when present.
    private var liveInsight: String? { vm.aiNutritionInsight }

    private var tips: [(icon: String, color: Color, headline: String, body: String)] {
        guard let stats = vm.healthStats else {
            return [("arrow.triangle.2.circlepath", .ember, "Syncing nutrition data", "Connect Apple Health to unlock personalized macro coaching.")]
        }
        var generated: [(icon: String, color: Color, headline: String, body: String)] = []
        let proteinGap = max(0, Int(180 - stats.protein))
        if proteinGap > 0 {
            generated.append(("bolt.fill", .ember, "Protein gap — act before dinner", "You're \(proteinGap)g short today. Add lean protein to your next meal to hit 180g."))
        }
        if stats.water < 6 {
            generated.append(("drop.fill", .steel, "Hydration needs attention", "Only \(Int(stats.water)) glasses logged. Open Hydration to catch up — it syncs with Apple Health."))
        } else {
            generated.append(("drop.fill", .steel, "Hydration is on track", "\(Int(stats.water)) glasses today, including anything Apple Health already had."))
        }
        if stats.sleepHours < 7 {
            generated.append(("moon.stars.fill", Color.aurora, "Sleep is limiting recovery", "Last night: \(String(format: "%.1f", stats.sleepHours))h. Better sleep improves nutrient partitioning."))
        } else {
            generated.append(("moon.stars.fill", Color.aurora, "Recovery window is strong", "Sleep and activity are aligned — great day to push training intensity."))
        }
        return generated
    }

    var tip: (icon: String, color: Color, headline: String, body: String) { tips[tipIndex % max(tips.count, 1)] }

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            coachHeader
            tipDetailRow
            macroSnapshotChips
        }
        .forgeContentCard(tint: .amber)
        .task { await vm.refreshNutritionCoachNote(store: store) }
    }

    private var coachHeader: some View {
        HStack(spacing: ForgeLayout.rowGap) {
            coachMark
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text("AI Nutrition Coach")
                    .font(HomeType.status)
                    .foregroundStyle(Color.textPrimary)
                    .forgeSingleLine(minScale: ForgeLayout.labelMinScale)
                coachSubtitleLine
            }
            .layoutPriority(1)
            Spacer(minLength: 0)
            refreshButton
        }
    }

    private var coachMark: some View {
        ZStack {
            Circle().fill(Color.amber.opacity(0.16))
            ARIAIdentityMark(state: .idle, mood: .energized, size: 20, amplitude: 0.24)
        }
        .frame(width: ForgeLayout.iconWell, height: ForgeLayout.iconWell)
        .accessibilityHidden(true)
    }

    private var coachSubtitleLine: some View {
        ForgeAdaptiveStack(spacing: ForgeLayout.chipGap, alignment: .firstTextBaseline) {
            Text(coachSubtitle)
                .font(HomeType.micro)
                .foregroundStyle(Color.textTertiary)
            if liveInsight != nil {
                ForgeVibeChip(label: vm.aiInsightsLive ? "LIVE" : "ARIA", energy: Color.amber)
            }
        }
    }

    private var refreshButton: some View {
        ForgeIconButton(systemImage: "arrow.clockwise", accessibilityLabel: "Refresh", tinted: false) {
            advanceTip()
        }
        .opacity(liveInsight == nil ? 1 : 0.4)
        .disabled(liveInsight != nil)
    }

    private func advanceTip() {
        withAnimation(reduceMotion ? nil : ForgeMotion.smooth) { tipIndex += 1 }
    }

    private var coachSubtitle: String {
        if vm.aiInsightsLoading { return "Consulting ARIA…" }
        if liveInsight != nil { return "Live insight" }
        return "Insight ready"
    }

    private var tipDetailRow: some View {
        HStack(alignment: .top, spacing: ForgeLayout.rowGap) {
            ForgeIconWell(systemImage: liveInsight != nil ? "text.bubble" : tip.icon, tint: .amber)
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text(liveInsight != nil ? "ARIA's take" : tip.headline)
                    .font(HomeType.status)
                    .foregroundStyle(Color.textPrimary)
                    .forgeWrapping()
                Text(liveInsight ?? tip.body)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
            }
            Spacer(minLength: 0)
        }
        .transition(.opacity)
        .id(liveInsight ?? "tip-\(tipIndex)")
    }

    private var macroSnapshotChips: some View {
        ForgeStatGrid(columns: 3) {
            ForEach(macroSnapshots, id: \.label) { snapshot in
                ForgeStatTile(
                    label: snapshot.label,
                    value: "\(snapshot.percent)",
                    unit: "%",
                    energy: snapshot.color
                )
            }
        }
    }

    private var macroSnapshots: [(label: String, percent: Int, color: Color)] {
        let stats = vm.healthStats
        return [
            ("Protein", min(Int((stats?.protein ?? 0) / 180 * 100), 100), FoodMacroPalette.protein),
            ("Carbs", min(Int((stats?.carbs ?? 0) / 280 * 100), 100), FoodMacroPalette.carbs),
            ("Fats", min(Int((stats?.fat ?? 0) / 70 * 100), 100), FoodMacroPalette.fat),
            ("Cal", min(Int(Double(stats?.totalCalories ?? 0) / 2600 * 100), 100), FoodMacroPalette.calories),
        ]
    }
}

// MARK: - Meal suggestions

struct AIMealSuggestionsCard: View {
    @ObservedObject var vm: LifestyleViewModel
    @EnvironmentObject var store: AppStore
    @State private var setIndex = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var suggestions: [AIMealSuggestion] {
        let stats = vm.healthStats
        let proteinGap = max(0, Int(180 - (stats?.protein ?? 0)))
        let calRemaining = max(0, 2600 - (stats?.totalCalories ?? 0))

        let pool = popularRestaurants.flatMap { restaurant in
            restaurant.items.filter(\.isHealthy).map { item in
                AIMealSuggestion(
                    name: "\(restaurant.name) · \(item.name)",
                    cal: item.calories,
                    protein: item.protein,
                    carbs: item.carbs,
                    fat: item.fat,
                    reason: item.protein >= proteinGap
                        ? "Covers your \(proteinGap)g protein gap"
                        : "Fits your \(calRemaining) cal budget"
                )
            }
        }
        .sorted { $0.protein > $1.protein }

        if pool.isEmpty {
            return [
                AIMealSuggestion(name: "Grilled Chicken + Rice", cal: 480, protein: 42, carbs: 52, fat: 8, reason: "High-protein recovery meal"),
                AIMealSuggestion(name: "Greek Yogurt Parfait", cal: 320, protein: 28, carbs: 38, fat: 6, reason: "Light protein boost"),
            ]
        }

        let start = (setIndex * 3) % pool.count
        return Array(pool[start..<min(start + 3, pool.count)])
    }

    private var basisLine: String {
        let calLeft = max(0, 2600 - (vm.healthStats?.totalCalories ?? 0))
        let proteinLeft = max(0, Int(180 - (vm.healthStats?.protein ?? 0)))
        return "Based on \(calLeft) cal · \(proteinLeft)g protein remaining"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                header
                Text(basisLine)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textTertiary)
                    .forgeWrapping()
            }

            if let note = vm.aiMealNote {
                ariaNote(note)
            }

            VStack(spacing: ForgeLayout.rowGap) {
                ForEach(suggestions) { suggestion in
                    AIMealRow(suggestion: suggestion)
                        .transition(.opacity)
                        .id("\(setIndex)-\(suggestion.id)")
                }
            }
        }
        .forgeContentCard(tint: .amber)
        .task { await vm.refreshMealNote(store: store) }
    }

    @ViewBuilder
    private var header: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                ForgeCardHeader("AI Meal Suggestions")
                regenerateLink
            }
        } else {
            ForgeCardHeader(title: "AI Meal Suggestions") { regenerateLink }
        }
    }

    private var regenerateLink: some View {
        ForgeTextLink(title: "Regenerate", accent: .amber) {
            withAnimation(reduceMotion ? nil : ForgeMotion.smooth) { setIndex += 1 }
        }
    }

    private func ariaNote(_ note: String) -> some View {
        HStack(alignment: .top, spacing: FDS.Spacing.sm) {
            Image(systemName: "text.bubble")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.amber)
                .accessibilityHidden(true)
            Text(note)
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeWell()
    }
}

struct AIMealRow: View {
    let suggestion: AIMealSuggestion
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            Button(action: toggle) {
                rowLabel
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            .accessibilityHint("Shows protein, carbs and fat")

            if expanded {
                macroChips
                    .forgeTransition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }
        }
        .forgeWell()
    }

    private var rowLabel: some View {
        HStack(spacing: ForgeLayout.rowGap) {
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text(suggestion.name)
                    .font(HomeType.status)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                Text(suggestion.reason)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            Text("\(suggestion.cal) cal")
                .font(HomeType.label)
                .monospacedDigit()
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textMuted)
                .accessibilityHidden(true)
        }
        .frame(minHeight: ForgeUX.minTap)
        .contentShape(Rectangle())
    }

    private var macroChips: some View {
        ForgeFlowLayout(spacing: ForgeLayout.chipGap, lineSpacing: ForgeLayout.chipGap) {
            InlineMacroChip(label: "P", value: "\(suggestion.protein)g", color: FoodMacroPalette.protein)
            InlineMacroChip(label: "C", value: "\(suggestion.carbs)g", color: FoodMacroPalette.carbs)
            InlineMacroChip(label: "F", value: "\(suggestion.fat)g", color: FoodMacroPalette.fat)
        }
    }

    private func toggle() {
        withAnimation(reduceMotion ? nil : ForgeMotion.smooth) { expanded.toggle() }
    }
}

struct InlineMacroChip: View {
    let label: String; let value: String; let color: Color

    private var fullName: String {
        switch label {
        case "P": return "Protein"
        case "C": return "Carbs"
        case "F": return "Fat"
        default: return label
        }
    }

    var body: some View {
        ForgeChip(label: "\(label) \(value)", energy: color, selected: true)
            .accessibilityLabel("\(fullName) \(value)")
    }
}

// MARK: - Meal log (the one halo card)

struct MealLogCard: View {
    @ObservedObject var vm: LifestyleViewModel
    @State private var showScanner = false
    @State private var scanResult: FoodLookup.Result?
    @State private var isLookingUp = false

    private func mealIcon(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<11: return "sunrise.fill"
        case 11..<15: return "sun.max.fill"
        case 15..<17: return "leaf.fill"
        default: return "moon.fill"
        }
    }

    private var sortedMeals: [MealLog] {
        vm.loggedMeals.sorted(by: { $0.date > $1.date })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            header
            scanButton
            if vm.loggedMeals.isEmpty {
                ForgeEmptyNote(
                    title: "No meals logged yet today.",
                    message: "Use Quick Location Log or Restaurants to add your first meal.",
                    systemImage: "fork.knife",
                    tint: .amber
                )
            } else {
                mealRows
            }
        }
        .forgeContentCard(accent: .amber)
        .sheet(isPresented: $showScanner) {
            BarcodeScannerView(
                onScan: { code in
                    showScanner = false
                    Task {
                        isLookingUp = true
                        scanResult = await FoodLookup.lookup(barcode: code)
                        isLookingUp = false
                    }
                },
                onCancel: { showScanner = false }
            )
            .ignoresSafeArea()
        }
        .sheet(item: $scanResult) { food in
            ScannedFoodConfirmSheet(food: food) {
                Task {
                    await vm.logMeal(name: food.name, calories: food.calories, protein: food.protein, carbs: food.carbs, fat: food.fat)
                    scanResult = nil
                }
            } onDismiss: {
                scanResult = nil
            }
        }
    }

    private var header: some View {
        ForgeCardHeader(title: "Meal Log") {
            HStack(spacing: ForgeLayout.chipGap) {
                if isLookingUp {
                    ProgressView()
                        .controlSize(.mini)
                        .accessibilityLabel("Looking up barcode")
                }
                ForgeCardMeta(text: "\(vm.loggedMeals.count) logged", color: .textTertiary)
            }
        }
    }

    private var scanButton: some View {
        ForgeSecondaryButton(title: "Scan", icon: "barcode.viewfinder", accent: .amber) {
            showScanner = true
        }
        .disabled(isLookingUp)
        .opacity(isLookingUp ? 0.5 : 1)
    }

    private var mealRows: some View {
        VStack(spacing: ForgeLayout.rowGap) {
            ForEach(sortedMeals) { meal in
                ForgeListRow(
                    icon: mealIcon(for: meal.date),
                    iconColor: .amber,
                    title: meal.name,
                    subtitle: meal.date.formatted(.dateTime.hour().minute()),
                    trailing: "\(Int(meal.calories)) cal"
                )
            }
        }
    }
}

// MARK: - Hydration

struct WaterIntakeCard: View {
    @ObservedObject var vm: LifestyleViewModel
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var target: Int {
        max(4, LifestyleTargets.resolve(
            profile: store.userProfile,
            overrides: store.nutritionPreferences
        ).waterGlassesTarget)
    }
    private var consumed: Int { Int((vm.healthStats?.water ?? 0).rounded()) }

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            hydrationHeader
            dropGrid
            addWaterBlock
        }
        .forgeContentCard(tint: .steel)
    }

    private var hydrationHeader: some View {
        Button {
            store.openHydration()
        } label: {
            HStack(spacing: FDS.Spacing.sm) {
                Text("Hydration")
                    .forgeSectionLabel(tint: .textTertiary)
                    .forgeSingleLine(minScale: ForgeLayout.labelMinScale)
                Spacer(minLength: FDS.Spacing.sm)
                Text("\(consumed)/\(target)")
                    .font(HomeType.label)
                    .monospacedDigit()
                    .foregroundStyle(FoodMacroPalette.water)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textMuted)
                    .accessibilityHidden(true)
            }
            .forgeTapOutset(vertical: 14)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hydration, \(consumed) of \(target) glasses")
        .accessibilityHint("Opens hydration, synced with Apple Health")
    }

    private var dropGrid: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 24, maximum: 40), spacing: FDS.Spacing.sm)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(0..<target, id: \.self) { i in
                    dropGlyph(i)
                }
            }
            if consumed > target {
                Text("+\(consumed - target) over")
                    .font(HomeType.micro)
                    .foregroundStyle(ForgeProgressChrome.miss)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Water, \(consumed) of \(target) glasses")
    }

    private func dropGlyph(_ index: Int) -> some View {
        let filled = index < consumed
        return Image(systemName: filled ? "drop.fill" : "drop")
            .font(.system(size: 22))
            .foregroundStyle(filled ? FoodMacroPalette.water : Color.white.opacity(0.22))
            .scaleEffect(filled ? 1 : 0.85)
            .animation(reduceMotion ? nil : ForgeMotion.snappy, value: consumed)
    }

    private var addWaterBlock: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
            ForgeSecondaryButton(title: "Log a glass", icon: "plus", accent: .steel) {
                Task { await vm.logWater(glasses: 1) }
            }
            Text("Writes to Apple Health")
                .font(HomeType.micro)
                .foregroundStyle(Color.textTertiary)
                .forgeWrapping()
        }
    }
}

// MARK: - Micronutrients

struct MicronutrientsCard: View {
    @ObservedObject var vm: LifestyleViewModel

    private typealias Micro = (label: String, current: Double, target: Double, unit: String, color: Color, limit: Bool)

    private var micros: [Micro] {
        let stats = vm.healthStats
        return [
            ("Fiber", stats?.fiber ?? 0, 30, "g", FoodMacroPalette.fiber, false),
            ("Sugar", stats?.sugar ?? 0, 50, "g", Color.amber, true),
            ("Sodium", stats?.sodium ?? 0, 2300, "mg", Color.steel, true),
            ("Caffeine", stats?.caffeine ?? 0, 400, "mg", Color.ember, true),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("Key Micronutrients")

            VStack(spacing: ForgeLayout.rowGap) {
                ForEach(Array(micros.enumerated()), id: \.offset) { _, m in
                    microRow(m)
                }
            }
        }
        .forgeContentCard(tint: .amber)
    }

    private func valueText(_ m: Micro) -> String {
        let target = Int(m.target)
        if m.current < 10 {
            return String(format: "%.1f", m.current) + " / \(target) \(m.unit)"
        }
        return "\(Int(m.current)) / \(target) \(m.unit)"
    }

    private func microRow(_ m: Micro) -> some View {
        let isOver = m.limit && m.current > m.target
        let barColor: Color = isOver ? ForgeProgressChrome.miss : m.color
        let valueColor: Color = isOver ? ForgeProgressChrome.miss : Color.textPrimary
        let fraction = m.target > 0 ? m.current / m.target : 0
        return VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
            HStack(spacing: FDS.Spacing.sm) {
                Text(m.label)
                    .font(HomeType.label)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: FDS.Spacing.sm)
                Text(valueText(m))
                    .font(HomeType.label)
                    .monospacedDigit()
                    .foregroundStyle(valueColor)
                    .forgeSingleLine(minScale: 0.8)
            }
            ForgeProgressBar(fraction: fraction, tint: barColor)
        }
        .accessibilityElement(children: .combine)
    }
}
