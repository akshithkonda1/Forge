import SwiftUI
import UIKit
import ForgeCore

struct DailyNutritionView: View {
    @ObservedObject var vm: LifestyleViewModel
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(spacing: 20) {
            AINutritionCoachCard(vm: vm)
            MacroRingsCard(vm: vm)
            MealLogCard(vm: vm)
            AIMealSuggestionsCard(vm: vm)
            WaterIntakeCard(vm: vm)
            MicronutrientsCard(vm: vm)
        }
    }
}

struct MacroRingsCard: View {
    @ObservedObject var vm: LifestyleViewModel
    @State private var appeared = false

    private struct Macro {
        let label: String; let current: Int; let target: Int
        let color: Color; let unit: String; let radius: CGFloat
    }

    private var macros: [Macro] {
        let stats = vm.healthStats
        return [
            Macro(label: "Carbs", current: Int(stats?.carbs ?? 0), target: 280, color: .steel, unit: "g", radius: 92),
            Macro(label: "Protein", current: Int(stats?.protein ?? 0), target: 180, color: .ember, unit: "g", radius: 68),
            Macro(label: "Fats", current: Int(stats?.fat ?? 0), target: 70, color: Color(hex: "FFB84D"), unit: "g", radius: 44),
        ]
    }

    private var totalCal: Int { vm.healthStats?.totalCalories ?? 0 }
    private var targetCal: Int { 2600 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("TODAY'S MACROS")
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(.textTertiary)
                    .tracking(2.5)
                Spacer()
                Text("\(targetCal - totalCal) cal left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.ember)
            }
            .padding(.bottom, 28)

            // Three concentric macro rings
            ZStack {
                ForEach(Array(macros.enumerated()), id: \.offset) { i, macro in
                    let progress = appeared ? CGFloat(macro.current) / CGFloat(macro.target) : 0

                    // Track
                    Circle()
                        .stroke(Color.borderColor.opacity(0.3), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .frame(width: macro.radius * 2, height: macro.radius * 2)

                    // Glow
                    Circle()
                        .trim(from: 0, to: min(progress, 1))
                        .stroke(macro.color.opacity(0.3), style: StrokeStyle(lineWidth: 16, lineCap: .round))
                        .frame(width: macro.radius * 2, height: macro.radius * 2)
                        .rotationEffect(.degrees(-90))
                        .blur(radius: 7)

                    // Main
                    Circle()
                        .trim(from: 0, to: min(progress, 1))
                        .stroke(macro.color, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .frame(width: macro.radius * 2, height: macro.radius * 2)
                        .rotationEffect(.degrees(-90))
                        .shadow(color: macro.color.opacity(0.45), radius: 8)
                        .animation(.spring(response: 1.3, dampingFraction: 0.68).delay(0.25 + Double(i) * 0.15), value: appeared)
                }

                // Center: calorie total
                VStack(spacing: 2) {
                    Text("\(totalCal)")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundColor(.textPrimary)
                    Text("of \(targetCal) kcal")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.textTertiary)
                }
            }
            .frame(height: 210)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 28)

            // Macro legend — responsive bars using GeometryReader (fixed hardcoded bug)
            VStack(spacing: 14) {
                ForEach(Array(macros.enumerated()), id: \.offset) { _, macro in
                    HStack(spacing: 12) {
                        Circle().fill(macro.color).frame(width: 8, height: 8)
                            .shadow(color: macro.color.opacity(0.5), radius: 3)
                        Text(macro.label)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.textSecondary)
                            .frame(width: 52, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.borderColor.opacity(0.3))
                                Capsule().fill(macro.color.opacity(0.8))
                                    .frame(width: appeared ? geo.size.width * CGFloat(macro.current) / CGFloat(macro.target) : 0)
                                    .animation(.spring(response: 1.1, dampingFraction: 0.7).delay(0.5), value: appeared)
                            }
                        }
                        .frame(height: 6)
                        Text("\(macro.current)\(macro.unit)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.textPrimary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
        }
        .padding(24)
        .background(Color.surface)
        .cornerRadius(24)
        .shadow(color: .black.opacity(0.07), radius: 20, y: 8)
        .onAppear { appeared = true }
    }
}

struct AINutritionCoachCard: View {
    @ObservedObject var vm: LifestyleViewModel
    @EnvironmentObject var store: AppStore
    @State private var tipIndex = 0
    @State private var sparkleScale: Double = 1.0
    @State private var appeared = false

    // Live ARIA insight overrides the local heuristic tip when present.
    private var liveInsight: String? { vm.aiNutritionInsight }

    private var tips: [(icon: String, color: Color, headline: String, body: String)] {
        guard let stats = vm.healthStats else {
            return [("sparkles", .ember, "Syncing nutrition data", "Connect Apple Health to unlock personalized macro coaching.")]
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
            generated.append(("moon.stars.fill", Color(hex: "A855F7"), "Sleep is limiting recovery", "Last night: \(String(format: "%.1f", stats.sleepHours))h. Better sleep improves nutrient partitioning."))
        } else {
            generated.append(("moon.stars.fill", Color(hex: "A855F7"), "Recovery window is strong", "Sleep and activity are aligned — great day to push training intensity."))
        }
        return generated
    }

    var tip: (icon: String, color: Color, headline: String, body: String) { tips[tipIndex % max(tips.count, 1)] }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            coachHeader
            if appeared {
                coachInsightSection
            }
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.ember.opacity(0.2), lineWidth: 1))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                sparkleScale = 1.25
            }
            withAnimation(.easeOut(duration: 0.4)) { appeared = true }
        }
        .task { await vm.refreshNutritionCoachNote(store: store) }
    }

    private var coachHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.ember.opacity(0.15)).frame(width: 40, height: 40)
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.ember)
                    .scaleEffect(coachHeaderIconScale)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("AI Nutrition Coach").font(.system(size: 16, weight: .bold)).foregroundColor(.textPrimary)
                    if liveInsight != nil { coachBadge }
                }
                Text(coachSubtitle)
                    .font(.system(size: 11, weight: .medium)).foregroundColor(.textTertiary)
            }
            Spacer()
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { tipIndex += 1 }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textTertiary)
                    .frame(width: 32, height: 32)
                    .background(Color.surfaceElevated)
                    .clipShape(Circle())
            }
            .opacity(liveInsight == nil ? 1 : 0.4)
            .disabled(liveInsight != nil)
        }
    }

    private var coachSubtitle: String {
        if vm.aiInsightsLoading { return "Consulting ARIA…" }
        if liveInsight != nil { return "Live insight" }
        return "Insight ready"
    }

    private var coachBadge: some View {
        Text(vm.aiInsightsLive ? "LIVE" : "ARIA")
            .font(.system(size: 8, weight: .black))
            .tracking(0.5)
            .foregroundColor(.ember)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.ember.opacity(0.12))
            .cornerRadius(5)
    }

    private var coachHeaderIconScale: CGFloat { vm.aiInsightsLoading ? sparkleScale : 1.0 }

    @ViewBuilder
    private var coachInsightSection: some View {
        Divider().background(Color.borderColor)
        tipDetailRow
        macroSnapshotChips
    }

    private var tipDetailRow: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: liveInsight != nil ? "sparkles" : tip.icon)
                .font(.system(size: 22))
                .foregroundColor(liveInsight != nil ? .ember : tip.color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 5) {
                Text(liveInsight != nil ? "ARIA's take" : tip.headline)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Text(liveInsight ?? tip.body)
                    .font(.system(size: 13))
                    .foregroundColor(.textSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .id(liveInsight ?? "tip-\(tipIndex)")
    }

    private var macroSnapshotChips: some View {
        HStack(spacing: 0) {
            ForEach(macroSnapshots, id: \.label) { snapshot in
                VStack(spacing: 3) {
                    Text(snapshot.label)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.textTertiary)
                    Text("\(snapshot.percent)%")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(snapshot.color)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(snapshot.color.opacity(0.08))
                if snapshot.label != "Cal" {
                    Divider().frame(height: 28).background(Color.borderColor)
                }
            }
        }
        .cornerRadius(12)
        .transition(.opacity)
    }

    private var macroSnapshots: [(label: String, percent: Int, color: Color)] {
        let stats = vm.healthStats
        return [
            ("Protein", min(Int((stats?.protein ?? 0) / 180 * 100), 100), Color.ember),
            ("Carbs", min(Int((stats?.carbs ?? 0) / 280 * 100), 100), Color.steel),
            ("Fats", min(Int((stats?.fat ?? 0) / 70 * 100), 100), Color(hex: "FFB84D")),
            ("Cal", min(Int(Double(stats?.totalCalories ?? 0) / 2600 * 100), 100), Color(hex: "A855F7")),
        ]
    }
}

struct AIMealSuggestionsCard: View {
    @ObservedObject var vm: LifestyleViewModel
    @EnvironmentObject var store: AppStore
    @State private var setIndex = 0

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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "fork.knife.circle.fill").font(.system(size: 20)).foregroundColor(.steel)
                    Text("AI Meal Suggestions").font(.system(size: 18, weight: .bold)).foregroundColor(.textPrimary)
                }
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { setIndex += 1 }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles").font(.system(size: 10))
                        Text("Regenerate").font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.steel)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.steel.opacity(0.12))
                    .cornerRadius(8)
                }
            }

            Text("Based on \(max(0, 2600 - (vm.healthStats?.totalCalories ?? 0))) cal · \(max(0, Int(180 - (vm.healthStats?.protein ?? 0))))g protein remaining")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.textTertiary)

            if let note = vm.aiMealNote {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "sparkles").font(.system(size: 11)).foregroundColor(.steel)
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.steel.opacity(0.08))
                .cornerRadius(10)
            }

            VStack(spacing: 10) {
                ForEach(suggestions) { suggestion in
                    AIMealRow(suggestion: suggestion)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                        .id("\(setIndex)-\(suggestion.id)")
                }
            }
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.05), radius: 14, y: 5)
        .task { await vm.refreshMealNote(store: store) }
    }
}

struct AIMealRow: View {
    let suggestion: AIMealSuggestion
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) { expanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(suggestion.name).font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
                        Text(suggestion.reason).font(.system(size: 11)).foregroundColor(.textTertiary).lineLimit(1)
                    }
                    Spacer()
                    Text("\(suggestion.cal) cal")
                        .font(.system(size: 13, weight: .bold)).foregroundColor(.ember)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold)).foregroundColor(.textMuted)
                }
                .padding(13)
            }
            .buttonStyle(.plain)

            if expanded {
                HStack(spacing: 0) {
                    InlineMacroChip(label: "P", value: "\(suggestion.protein)g", color: .ember)
                    InlineMacroChip(label: "C", value: "\(suggestion.carbs)g",   color: .steel)
                    InlineMacroChip(label: "F", value: "\(suggestion.fat)g",     color: Color(hex: "FFB84D"))
                }
                .padding(.horizontal, 13).padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.surfaceElevated)
        .cornerRadius(12)
    }
}

struct InlineMacroChip: View {
    let label: String; let value: String; let color: Color
    var body: some View {
        VStack(spacing: 3) {
            Text(label).font(.system(size: 10, weight: .bold)).foregroundColor(.textTertiary)
            Text(value).font(.system(size: 13, weight: .bold)).foregroundColor(color)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(color.opacity(0.09)).cornerRadius(8)
    }
}

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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Meal Log").font(.system(size: 18, weight: .bold)).foregroundColor(.textPrimary)
                Spacer()
                Text("\(vm.loggedMeals.count) logged")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textTertiary)
                Button { showScanner = true } label: {
                    HStack(spacing: 5) {
                        if isLookingUp {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Image(systemName: "barcode.viewfinder").font(.system(size: 13, weight: .semibold))
                        }
                        Text("Scan").font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.ember)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.ember.opacity(0.1))
                    .cornerRadius(8)
                }
                .disabled(isLookingUp)
            }

            if vm.loggedMeals.isEmpty {
                Text("No meals logged yet today. Use Quick Location Log or Restaurants to add your first meal.")
                    .font(.system(size: 13))
                    .foregroundColor(.textSecondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.surfaceElevated)
                    .cornerRadius(12)
            } else {
                VStack(spacing: 10) {
                    ForEach(vm.loggedMeals.sorted(by: { $0.date > $1.date })) { meal in
                        HStack(spacing: 14) {
                            ZStack {
                                Circle().fill(Color.surface).frame(width: 38, height: 38)
                                Image(systemName: mealIcon(for: meal.date))
                                    .font(.system(size: 15)).foregroundColor(.ember)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(meal.name).font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary).lineLimit(1)
                                Text(meal.date, format: .dateTime.hour().minute())
                                    .font(.system(size: 12)).foregroundColor(.textTertiary)
                            }
                            Spacer()
                            Text("\(Int(meal.calories)) cal")
                                .font(.system(size: 13, weight: .medium)).foregroundColor(.textSecondary)
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18)).foregroundColor(.success)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Color.surfaceElevated).cornerRadius(12)
                    }
                }
            }
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.05), radius: 14, y: 5)
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
}

struct WaterIntakeCard: View {
    @ObservedObject var vm: LifestyleViewModel
    @EnvironmentObject var store: AppStore

    private var target: Int {
        max(4, LifestyleTargets.resolve(
            profile: store.userProfile,
            overrides: store.nutritionPreferences
        ).waterGlassesTarget)
    }
    private var consumed: Int { Int((vm.healthStats?.water ?? 0).rounded()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { store.openHydration() } label: {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "drop.fill")
                            .font(.system(size: 16)).foregroundColor(Color(hex: "4A9EFF"))
                        Text("Hydration").font(.system(size: 18, weight: .bold)).foregroundColor(.textPrimary)
                    }
                    Spacer()
                    Text("\(consumed)/\(target)")
                        .font(.system(size: 14, weight: .bold)).foregroundColor(Color(hex: "4A9EFF"))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textTertiary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens hydration, synced with Apple Health")

            HStack(spacing: 8) {
                ForEach(0..<target, id: \.self) { i in
                    Image(systemName: i < consumed ? "drop.fill" : "drop")
                        .foregroundColor(i < consumed ? Color(hex: "4A9EFF") : Color.borderColor)
                        .font(.system(size: 22))
                        .scaleEffect(i < consumed ? 1 : 0.85)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6).delay(Double(i) * 0.03), value: consumed)
                }
            }

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                Task { await vm.logWater(glasses: 1) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill").font(.system(size: 15))
                    Text("Log a glass").font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text("Writes to Apple Health")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(hex: "4A9EFF").opacity(0.7))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color(hex: "4A9EFF").opacity(0.1))
                        .cornerRadius(4)
                }
                .foregroundColor(Color(hex: "4A9EFF"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(hex: "4A9EFF").opacity(0.1))
                .cornerRadius(12)
            }
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.05), radius: 14, y: 5)
    }
}

struct MicronutrientsCard: View {
    @ObservedObject var vm: LifestyleViewModel
    @State private var appeared = false

    private var micros: [(label: String, current: Double, target: Double, unit: String, color: Color)] {
        let stats = vm.healthStats
        return [
            ("Fiber", stats?.fiber ?? 0, 30, "g", .success),
            ("Sugar", stats?.sugar ?? 0, 50, "g", .warning),
            ("Sodium", stats?.sodium ?? 0, 2300, "mg", .steel),
            ("Caffeine", stats?.caffeine ?? 0, 400, "mg", .ember),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Key Micronutrients")
                .font(.system(size: 18, weight: .bold)).foregroundColor(.textPrimary)

            VStack(spacing: 14) {
                ForEach(Array(micros.enumerated()), id: \.offset) { i, m in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(m.label).font(.system(size: 13, weight: .medium)).foregroundColor(.textSecondary)
                            Spacer()
                            Text(m.current < 10
                                 ? String(format: "%.1f / %.1f %@", m.current, m.target, m.unit)
                                 : "\(Int(m.current)) / \(Int(m.target)) \(m.unit)")
                                .font(.system(size: 13, weight: .semibold)).foregroundColor(.textPrimary)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.borderColor.opacity(0.3))
                                Capsule().fill(m.color)
                                    .frame(width: appeared ? geo.size.width * CGFloat(min(m.current / m.target, 1)) : 0)
                                    // Fixed: now animated
                                    .animation(.spring(response: 1.0, dampingFraction: 0.7).delay(0.3 + Double(i) * 0.1), value: appeared)
                            }
                        }
                        .frame(height: 6)
                    }
                }
            }
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.05), radius: 14, y: 5)
        .onAppear { appeared = true }
    }
}
