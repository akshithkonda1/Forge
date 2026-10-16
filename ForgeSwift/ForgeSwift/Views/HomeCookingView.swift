import SwiftUI
import ForgeCore

// MARK: - Home Cooking (recipe library)

/// Browsable library of home-cooked meals with ingredient-derived macros, filters that
/// actually narrow the set, and one-tap logging into the day's nutrition.
///
/// A search tool, not a dashboard: no hero. The search field and the sort / filter row are
/// the segment header, then one neutral card of agenda rows.
struct HomeCookingView: View {
    @ObservedObject var vm: LifestyleViewModel

    @State private var searchText = ""
    @State private var course: MealCourse?
    @State private var cuisine: MealCuisine?
    @State private var dietTags: Set<MealDietTag> = []
    @State private var maxMinutes: Double = 240
    @State private var sort: MealSort = .proteinDensity
    @State private var selected: HomeMeal?
    @State private var visibleCount = 24
    @State private var showFilters = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let pageSize = 24

    enum MealSort: String, CaseIterable, Identifiable {
        case proteinDensity, protein, calories, time, name
        var id: String { rawValue }
        var label: String {
            switch self {
            case .proteinDensity: return "Protein density"
            case .protein: return "Most protein"
            case .calories: return "Fewest calories"
            case .time: return "Fastest"
            case .name: return "A–Z"
            }
        }
    }

    // MARK: Filtering

    private var filtered: [HomeMeal] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let terms = query.split(separator: " ").map(String.init)

        var meals = HomeCookedMeals.all.filter { meal in
            if let course, meal.course != course { return false }
            if let cuisine, meal.cuisine != cuisine { return false }
            if Double(meal.minutes) > maxMinutes { return false }
            if !dietTags.isSubset(of: meal.tags) { return false }
            guard !terms.isEmpty else { return true }
            let index = meal.searchIndex
            return terms.allSatisfy { index.contains($0) }
        }

        switch sort {
        case .proteinDensity: meals.sort { $0.proteinDensity > $1.proteinDensity }
        case .protein:        meals.sort { $0.protein > $1.protein }
        case .calories:       meals.sort { $0.calories < $1.calories }
        case .time:           meals.sort { $0.minutes < $1.minutes }
        case .name:           meals.sort { $0.name < $1.name }
        }
        return meals
    }

    private var activeFilterCount: Int {
        (course == nil ? 0 : 1) + (cuisine == nil ? 0 : 1) + dietTags.count + (maxMinutes < 240 ? 1 : 0)
    }

    // MARK: Body

    var body: some View {
        let results = filtered
        return VStack(alignment: .leading, spacing: ForgeLayout.sectionGap) {
            CookingSearchField(text: $searchText, prompt: "Search recipes or ingredients")
            controlsRow

            if showFilters {
                filterPanel
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }

            if results.isEmpty {
                emptyState
            } else {
                resultsCard(results)
            }
        }
        .animation(reduceMotion ? nil : ForgeMotion.smooth, value: showFilters)
        // Any change to the result set restarts paging, otherwise a narrowed search
        // would keep showing a stale "show more" offset.
        .onChange(of: searchText) { _, _ in visibleCount = Self.pageSize }
        .onChange(of: course) { _, _ in visibleCount = Self.pageSize }
        .onChange(of: cuisine) { _, _ in visibleCount = Self.pageSize }
        .onChange(of: dietTags) { _, _ in visibleCount = Self.pageSize }
        .onChange(of: sort) { _, _ in visibleCount = Self.pageSize }
        .sheet(item: $selected) { meal in
            MealDetailSheet(meal: meal, vm: vm)
        }
    }

    // MARK: Sort and filter row

    private var filtersLabel: String {
        activeFilterCount > 0 ? "Filters (\(activeFilterCount))" : "Filters"
    }

    /// Sort and Filters stay on one line while they fit, then shorten the sort label,
    /// then stack. Every control keeps a 44 pt hit area.
    private var controlsRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: ForgeLayout.tileGap) {
                sortMenu(label: sort.label)
                Spacer(minLength: 0)
                filtersToggle
            }
            HStack(spacing: ForgeLayout.tileGap) {
                sortMenu(label: "Sort")
                Spacer(minLength: 0)
                filtersToggle
            }
            VStack(alignment: .leading, spacing: ForgeLayout.tileGap) {
                sortMenu(label: "Sort")
                filtersToggle
            }
        }
    }

    private func sortMenu(label: String) -> some View {
        Menu {
            Picker("Sort", selection: $sort) {
                ForEach(MealSort.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
        } label: {
            ForgeChip(label: label, icon: "arrow.up.arrow.down", energy: .ember, selected: true)
                .forgeTapOutset(vertical: ForgeLayout.chipTapOutset)
        }
        .accessibilityLabel("Sort")
        .accessibilityValue(sort.label)
    }

    private var filtersToggle: some View {
        ForgeChipButton(
            label: filtersLabel,
            icon: activeFilterCount > 0
                ? "line.3.horizontal.decrease.circle.fill"
                : "line.3.horizontal.decrease.circle",
            energy: .ember,
            selected: activeFilterCount > 0
        ) {
            withAnimation(reduceMotion ? nil : ForgeMotion.smooth) { showFilters.toggle() }
        }
        .accessibilityValue(showFilters ? "Expanded" : "Collapsed")
    }

    // MARK: Filter panel

    private var courseOptions: [ForgeSegmentOption<MealCourse?>] {
        var options: [ForgeSegmentOption<MealCourse?>] = [
            ForgeSegmentOption<MealCourse?>(value: nil, title: "Any")
        ]
        for option in MealCourse.allCases {
            options.append(ForgeSegmentOption<MealCourse?>(value: option, title: option.label, icon: option.icon))
        }
        return options
    }

    private var cuisineOptions: [ForgeSegmentOption<MealCuisine?>] {
        var options: [ForgeSegmentOption<MealCuisine?>] = [
            ForgeSegmentOption<MealCuisine?>(value: nil, title: "Any")
        ]
        for option in MealCuisine.allCases {
            options.append(ForgeSegmentOption<MealCuisine?>(value: option, title: "\(option.emoji) \(option.label)"))
        }
        return options
    }

    private var filterPanel: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader(title: "Filters", tint: .textTertiary) {
                if activeFilterCount > 0 {
                    ForgeTextLink(title: "Clear filters", accent: .ember) { clearFilters() }
                }
            }

            filterGroup("Meal") {
                ForgeSegmentedControl(
                    courseOptions,
                    selection: $course,
                    accent: .ember,
                    bleed: ForgeLayout.cardPadding
                )
            }

            filterGroup("Cuisine") {
                ForgeSegmentedControl(
                    cuisineOptions,
                    selection: $cuisine,
                    accent: .ember,
                    bleed: ForgeLayout.cardPadding
                )
            }

            filterGroup("Diet") { dietChips }

            maxTimeControl
        }
        .forgeContentCard(tint: .ember)
    }

    private var dietChips: some View {
        ForgeFlowLayout(spacing: ForgeLayout.chipGap, lineSpacing: ForgeLayout.interactiveChipLineGap) {
            ForEach(MealDietTag.allCases) { tag in
                ForgeChipButton(
                    label: tag.label,
                    icon: tag.icon,
                    energy: .ember,
                    selected: dietTags.contains(tag)
                ) {
                    if dietTags.contains(tag) { dietTags.remove(tag) } else { dietTags.insert(tag) }
                }
            }
        }
    }

    private var maxTimeControl: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
            HStack(alignment: .firstTextBaseline, spacing: FDS.Spacing.sm) {
                Text("Max time")
                    .font(HomeType.label)
                    .foregroundStyle(Color.textSecondary)
                    .accessibilityHidden(true)
                Spacer(minLength: FDS.Spacing.sm)
                Text(maxMinutes >= 240 ? "Any" : "\(Int(maxMinutes)) min")
                    .font(HomeType.label)
                    .monospacedDigit()
                    .foregroundStyle(Color.ember)
                    .accessibilityHidden(true)
            }
            Slider(value: $maxMinutes, in: 15...240, step: 5) { _ in
                visibleCount = Self.pageSize
            }
            .tint(.ember)
            .frame(minHeight: ForgeUX.minTap)
            .accessibilityLabel("Maximum cooking time")
            .accessibilityValue(maxMinutes >= 240 ? "Any" : "\(Int(maxMinutes)) minutes")
        }
    }

    private func filterGroup<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
            Text(title)
                .font(HomeType.label)
                .foregroundStyle(Color.textSecondary)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func clearFilters() {
        course = nil
        cuisine = nil
        dietTags = []
        maxMinutes = 240
        visibleCount = Self.pageSize
    }

    // MARK: Results

    private func resultsCard(_ results: [HomeMeal]) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader(title: "\(results.count) meal\(results.count == 1 ? "" : "s")")

            LazyVStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                ForEach(results.prefix(visibleCount)) { meal in
                    Button {
                        selected = meal
                    } label: {
                        MealRowCard(meal: meal)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the recipe")
                }
            }

            if results.count > visibleCount {
                ForgeTextLink(
                    title: "Show \(min(Self.pageSize, results.count - visibleCount)) more · \(results.count - visibleCount) left",
                    accent: .ember
                ) {
                    withAnimation(reduceMotion ? nil : ForgeMotion.smooth) { visibleCount += Self.pageSize }
                }
            }
        }
        .forgeContentCard()
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeEmptyNote(
                title: "Nothing matches those filters",
                message: "Try widening the time limit or clearing a diet filter.",
                systemImage: "fork.knife.circle",
                tint: .ember
            )
            if activeFilterCount > 0 {
                ForgeSecondaryButton(title: "Clear filters", accent: .ember) { clearFilters() }
            }
        }
        .forgeContentCard(tint: .ember)
    }
}

// MARK: - Search field

/// Magnifier, field and clear button on the opaque inset tile used for fields that sit
/// directly on the screen background. Padding 12, 44 pt tall, 44 pt clear target.
private struct CookingSearchField: View {
    @Binding var text: String
    var prompt: String

    var body: some View {
        HStack(spacing: FDS.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.textTertiary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .font(HomeType.body)
                .foregroundStyle(Color.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .padding(.trailing, text.isEmpty ? ForgeLayout.tilePadding : 0)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.textMuted)
                        .frame(width: ForgeUX.minTap, height: ForgeUX.minTap)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, ForgeLayout.tilePadding)
        .frame(minHeight: ForgeUX.minTap)
        .forgeInsetTile(radius: ForgeLayout.innerRadius)
    }
}

// MARK: - Row

/// Agenda row: cuisine emoji, name, one meta line, macros, calories and a chevron. No
/// chrome of its own; the results card is the surface.
private struct MealRowCard: View {
    let meal: HomeMeal

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .center, spacing: ForgeLayout.rowGap) {
            Text(meal.cuisine.emoji)
                .font(.system(size: 24))
                .frame(minWidth: ForgeLayout.iconWell)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text(meal.name)
                    .font(HomeType.status)
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Text(meal.subtitle)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textTertiary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                if typeSize.isAccessibilitySize {
                    calories
                }
                detailFlow
            }
            .layoutPriority(1)
            Spacer(minLength: FDS.Spacing.xs)
            if !typeSize.isAccessibilitySize {
                calories
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textMuted)
                .accessibilityHidden(true)
        }
        .padding(.vertical, ForgeLayout.rowVerticalPadding)
        .frame(minHeight: ForgeUX.minTap)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(meal.name). \(meal.calories) calories, \(meal.protein) grams protein, \(meal.minutes) minutes.")
    }

    private var calories: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text("\(meal.calories)")
                .font(HomeType.status)
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
                .forgeSingleLine()
            Text("kcal")
                .font(HomeType.micro)
                .foregroundStyle(Color.textTertiary)
                .lineLimit(1)
        }
    }

    /// Macros as one coloured line (protein, carbs, fat) plus an optional tag chip. It
    /// wraps instead of squeezing at large type sizes.
    private var detailFlow: some View {
        ForgeFlowLayout {
            macroLine
            if let badge {
                ForgeChip(label: badge.label, energy: badge.color, selected: true)
            }
        }
    }

    private var macroLine: Text {
        let protein = Text("P").foregroundStyle(Color.ember)
        let carbs = Text("C").foregroundStyle(Color.steel)
        let fat = Text("F").foregroundStyle(Color.amber)
        return Text("\(protein) \(meal.protein)g · \(carbs) \(meal.carbs)g · \(fat) \(meal.fat)g")
            .font(HomeType.label)
            .monospacedDigit()
            .foregroundStyle(Color.textSecondary)
    }

    private var badge: (label: String, color: Color)? {
        if meal.tags.contains(.highProtein) { return ("High protein", Color.success) }
        if meal.tags.contains(.vegan) { return ("Vegan", Color.success) }
        if meal.tags.contains(.quick) { return ("Quick", Color.steel) }
        return nil
    }
}

// MARK: - Detail

private struct MealDetailSheet: View {
    let meal: HomeMeal
    @ObservedObject var vm: LifestyleViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var logged = false
    @ScaledMetric(relativeTo: .caption) private var stepBadgeSize: CGFloat = 24

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: ForgeLayout.sectionGap) {
                    header
                    macroCard
                    ingredientsCard
                    methodCard
                    if !meal.tags.isEmpty {
                        suitsCard
                    }
                    Text("Macros are calculated from the ingredient amounts above, per serving (makes \(meal.servings)). Swapping ingredients changes them.")
                        .font(HomeType.body)
                        .foregroundStyle(Color.textTertiary)
                        .forgeWrapping()
                }
                .forgeScreenInsets(top: FDS.Spacing.lg)
            }
            .background(Color.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                logDock
            }
            .navigationTitle("Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(Color.ember)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.tileGap) {
            Text(meal.cuisine.emoji)
                .font(.system(size: 40))
                .accessibilityHidden(true)
            Text(meal.name)
                .font(FDS.TypeScale.Dynamic.title)
                .foregroundStyle(Color.textPrimary)
                .forgeWrapping()
                .accessibilityAddTraits(.isHeader)
            ForgeFlowLayout {
                ForgeChip(label: "\(meal.minutes) min", icon: "timer")
                ForgeChip(label: meal.method.label, icon: meal.method.icon)
                ForgeChip(label: "Serves \(meal.servings)", icon: "person.2.fill")
            }
        }
    }

    // MARK: Cards

    /// One card, four inner wells. `ForgeStatGrid` lays four tiles out 2 x 2 and drops to
    /// one column at the largest accessibility size.
    private var macroCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("Macros", meta: "Per serving")
            ForgeStatGrid(columns: 4) {
                ForgeStatTile(label: "Calories", value: "\(meal.calories)", unit: "kcal", energy: .textSecondary)
                ForgeStatTile(label: "Protein", value: "\(meal.protein)", unit: "g", energy: .ember)
                ForgeStatTile(label: "Carbs", value: "\(meal.carbs)", unit: "g", energy: .steel)
                ForgeStatTile(label: "Fat", value: "\(meal.fat)", unit: "g", energy: .amber)
            }
        }
        .forgeContentCard(tint: .ember)
    }

    private var ingredientsCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("Ingredients", meta: "\(meal.components.count) items")
            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                ForEach(meal.components) { component in
                    ForgeBulletRow(text: component.displayLine, tint: .ember)
                }
            }
        }
        .forgeContentCard(tint: .ember)
    }

    private var methodCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("Method", meta: "\(meal.steps.count) steps")
            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                ForEach(Array(meal.steps.enumerated()), id: \.offset) { index, step in
                    stepRow(number: index + 1, text: step)
                }
            }
        }
        .forgeContentCard(tint: .ember)
    }

    private func stepRow(number: Int, text: String) -> some View {
        let badge = ForgeLayout.scaledCap(stepBadgeSize, base: 24)
        return HStack(alignment: .top, spacing: ForgeLayout.rowGap) {
            Text("\(number)")
                .font(HomeType.label)
                .monospacedDigit()
                .foregroundStyle(Color.ember)
                .hudInArcText()
                .frame(width: badge, height: badge)
                .background(Circle().fill(Color.ember.opacity(0.16)))
            Text(text)
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(number). \(text)")
    }

    private var suitsCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("Suits")
            ForgeFlowLayout {
                ForEach(Array(meal.tags).sorted(by: { $0.label < $1.label })) { tag in
                    ForgeChip(label: tag.label, icon: tag.icon, energy: .success, selected: true)
                }
            }
        }
        .forgeContentCard(tint: .ember)
    }

    // MARK: Log

    /// The sheet's one primary, pinned to the bottom.
    private var logDock: some View {
        logAction
            .padding(.horizontal, ForgeLayout.screenInset)
            .padding(.vertical, FDS.Spacing.sm)
            .forgeBarChrome(edge: .bottom)
    }

    @ViewBuilder
    private var logAction: some View {
        if logged {
            loggedBanner
        } else {
            ForgePrimaryButton(title: "Log this meal", icon: "plus.circle.fill") {
                logMeal()
            }
        }
    }

    private var loggedBanner: some View {
        HStack(spacing: FDS.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .accessibilityHidden(true)
            Text("Logged to today")
                .font(HomeType.cta)
        }
        .foregroundStyle(Color.success)
        .frame(maxWidth: .infinity, minHeight: ForgeUX.minTap + 8)
        .background(Color.success.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous)
                .stroke(Color.success.opacity(0.32), lineWidth: ForgeUX.hairline)
        )
        .accessibilityElement(children: .combine)
    }

    private func logMeal() {
        guard !logged else { return }
        logged = true
        ForgeHaptics.play(.success)
        let macros = meal.macros
        Task {
            await vm.logMeal(
                name: meal.name,
                calories: macros.kcal,
                protein: macros.protein,
                carbs: macros.carbs,
                fat: macros.fat
            )
        }
    }
}
