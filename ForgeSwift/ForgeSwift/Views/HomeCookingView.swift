import SwiftUI

// MARK: - Home Cooking (recipe library)

/// Browsable library of home-cooked meals with ingredient-derived macros, filters that
/// actually narrow the set, and one-tap logging into the day's nutrition.
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
        return VStack(spacing: 16) {
            searchBar
            headerRow(total: results.count)

            if showFilters {
                filterPanel
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if results.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(results.prefix(visibleCount)) { meal in
                        Button { selected = meal } label: { MealRowCard(meal: meal) }
                            .buttonStyle(.plain)
                    }
                    if results.count > visibleCount {
                        Button {
                            withAnimation { visibleCount += Self.pageSize }
                        } label: {
                            Text("Show \(min(Self.pageSize, results.count - visibleCount)) more · \(results.count - visibleCount) left")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.ember)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.surface)
                                .cornerRadius(12)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.borderColor, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showFilters)
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

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundColor(.textTertiary)
            TextField("Search \(HomeCookedMeals.count) meals, ingredients, cuisines…", text: $searchText)
                .foregroundColor(.textPrimary)
                .autocapitalization(.none)
                .disableAutocorrection(true)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.textMuted)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(13)
        .background(Color.surface)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.borderColor.opacity(0.5), lineWidth: 1))
    }

    private func headerRow(total: Int) -> some View {
        HStack(spacing: 10) {
            Text("\(total) meal\(total == 1 ? "" : "s")")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.textSecondary)
            Spacer()
            Menu {
                Picker("Sort", selection: $sort) {
                    ForEach(MealSort.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.arrow.down").font(.system(size: 11, weight: .semibold))
                    Text(sort.label).font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.ember)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color.ember.opacity(0.12))
                .cornerRadius(20)
            }
            Button {
                withAnimation { showFilters.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "line.3.horizontal.decrease.circle\(activeFilterCount > 0 ? ".fill" : "")")
                        .font(.system(size: 12, weight: .semibold))
                    Text(activeFilterCount > 0 ? "Filters (\(activeFilterCount))" : "Filters")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(activeFilterCount > 0 ? .white : .textSecondary)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(activeFilterCount > 0 ? Color.ember : Color.surfaceElevated)
                .cornerRadius(20)
            }
            .buttonStyle(.plain)
        }
    }

    private var filterPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            filterSection("Meal") {
                chip("Any", selected: course == nil) { course = nil }
                ForEach(MealCourse.allCases) { option in
                    chip(option.label, icon: option.icon, selected: course == option) {
                        course = course == option ? nil : option
                    }
                }
            }

            filterSection("Cuisine") {
                chip("Any", selected: cuisine == nil) { cuisine = nil }
                ForEach(MealCuisine.allCases) { option in
                    chip("\(option.emoji) \(option.label)", selected: cuisine == option) {
                        cuisine = cuisine == option ? nil : option
                    }
                }
            }

            filterSection("Diet") {
                ForEach(MealDietTag.allCases) { tag in
                    chip(tag.label, icon: tag.icon, selected: dietTags.contains(tag)) {
                        if dietTags.contains(tag) { dietTags.remove(tag) } else { dietTags.insert(tag) }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("MAX TIME")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.textTertiary)
                        .tracking(1)
                    Spacer()
                    Text(maxMinutes >= 240 ? "Any" : "\(Int(maxMinutes)) min")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.ember)
                }
                Slider(value: $maxMinutes, in: 15...240, step: 5) { _ in
                    visibleCount = Self.pageSize
                }
                .tint(.ember)
                .accessibilityLabel("Maximum cooking time")
                .accessibilityValue(maxMinutes >= 240 ? "Any" : "\(Int(maxMinutes)) minutes")
            }

            if activeFilterCount > 0 {
                Button {
                    course = nil
                    cuisine = nil
                    dietTags = []
                    maxMinutes = 240
                    visibleCount = Self.pageSize
                } label: {
                    Text("Clear filters")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.danger)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Color.surface)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.borderColor, lineWidth: 1))
    }

    private func filterSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.textTertiary)
                .tracking(1)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { content() }
                    .padding(.vertical, 1)
            }
        }
    }

    private func chip(
        _ title: String,
        icon: String? = nil,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                }
                Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            }
            .foregroundColor(selected ? .white : .textSecondary)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(selected ? Color.ember : Color.surfaceElevated)
            .cornerRadius(20)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "fork.knife.circle")
                .font(.system(size: 40))
                .foregroundColor(.textTertiary)
            Text("Nothing matches those filters")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.textSecondary)
            Text("Try widening the time limit or clearing a diet filter.")
                .font(.system(size: 13))
                .foregroundColor(.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }
}

// MARK: - Row

private struct MealRowCard: View {
    let meal: HomeMeal

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Text(meal.cuisine.emoji).font(.system(size: 24))
                VStack(alignment: .leading, spacing: 3) {
                    Text(meal.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(meal.subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(meal.calories)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.textPrimary)
                    Text("kcal").font(.system(size: 10)).foregroundColor(.textTertiary)
                }
            }

            HStack(spacing: 6) {
                macroChip("P", meal.protein, .ember)
                macroChip("C", meal.carbs, .steel)
                macroChip("F", meal.fat, .warning)
                Spacer(minLength: 0)
                if meal.tags.contains(.highProtein) {
                    tagPill("High protein", .success)
                } else if meal.tags.contains(.vegan) {
                    tagPill("Vegan", .success)
                } else if meal.tags.contains(.quick) {
                    tagPill("Quick", .steel)
                }
            }
        }
        .padding(14)
        .background(Color.surface)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.borderColor.opacity(0.6), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(meal.name). \(meal.calories) calories, \(meal.protein) grams protein, \(meal.minutes) minutes.")
    }

    private func macroChip(_ letter: String, _ grams: Int, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Text(letter).font(.system(size: 10, weight: .bold)).foregroundColor(color)
            Text("\(grams)g").font(.system(size: 11, weight: .medium)).foregroundColor(.textSecondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(color.opacity(0.12))
        .cornerRadius(8)
    }

    private func tagPill(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.12))
            .cornerRadius(8)
    }
}

// MARK: - Detail

private struct MealDetailSheet: View {
    let meal: HomeMeal
    @ObservedObject var vm: LifestyleViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var logged = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    macroBar
                    section("Ingredients", icon: "basket.fill") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(meal.components) { component in
                                HStack(alignment: .top, spacing: 8) {
                                    Circle().fill(Color.ember).frame(width: 5, height: 5).padding(.top, 7)
                                    Text(component.displayLine)
                                        .font(.system(size: 13))
                                        .foregroundColor(.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    section("Method", icon: "list.number") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(meal.steps.enumerated()), id: \.offset) { index, step in
                                HStack(alignment: .top, spacing: 10) {
                                    Text("\(index + 1)")
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundColor(.ember)
                                        .frame(width: 24, height: 24)
                                        .background(Color.ember.opacity(0.14))
                                        .clipShape(Circle())
                                    Text(step)
                                        .font(.system(size: 13))
                                        .foregroundColor(.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    if !meal.tags.isEmpty {
                        section("Suits", icon: "checkmark.seal.fill") {
                            FlowLayout(spacing: 8) {
                                ForEach(Array(meal.tags).sorted(by: { $0.label < $1.label })) { tag in
                                    HStack(spacing: 4) {
                                        Image(systemName: tag.icon).font(.system(size: 9, weight: .semibold))
                                        Text(tag.label).font(.system(size: 11, weight: .medium))
                                    }
                                    .foregroundColor(.success)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(Color.success.opacity(0.12))
                                    .cornerRadius(100)
                                }
                            }
                        }
                    }
                    Text("Macros are calculated from the ingredient amounts above, per serving (makes \(meal.servings)). Swapping ingredients changes them.")
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                    logButton
                }
                .padding(20)
            }
            .background(Color.background.ignoresSafeArea())
            .navigationTitle("Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundColor(.ember)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(meal.cuisine.emoji).font(.system(size: 40))
            Text(meal.name)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                metaItem("timer", "\(meal.minutes) min")
                metaItem(meal.method.icon, meal.method.label)
                metaItem("person.2.fill", "Serves \(meal.servings)")
            }
        }
    }

    private func metaItem(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10))
            Text(text).font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(.textTertiary)
    }

    private var macroBar: some View {
        HStack(spacing: 10) {
            macroTile("Calories", "\(meal.calories)", .textPrimary)
            macroTile("Protein", "\(meal.protein)g", .ember)
            macroTile("Carbs", "\(meal.carbs)g", .steel)
            macroTile("Fat", "\(meal.fat)g", .warning)
        }
    }

    private func macroTile(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label).font(.system(size: 10)).foregroundColor(.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.surface)
        .cornerRadius(12)
    }

    private func section<Content: View>(
        _ title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12)).foregroundColor(.ember)
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.textTertiary)
                    .tracking(1)
            }
            content()
        }
    }

    private var logButton: some View {
        Button {
            guard !logged else { return }
            logged = true
            FDS.notificationHaptic(.success)
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
        } label: {
            HStack(spacing: 8) {
                Image(systemName: logged ? "checkmark.circle.fill" : "plus.circle.fill")
                Text(logged ? "Logged to today" : "Log this meal")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(logged ? Color.success : Color.ember)
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
        .disabled(logged)
    }
}
