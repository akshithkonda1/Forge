import SwiftUI
import ForgeCore

// MARK: - Fitness Goals Editor

struct FitnessGoalsEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @State private var selected: Set<UserFitnessGoal> = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(UserFitnessGoal.allCases) { goal in
                    Button {
                        toggle(goal)
                    } label: {
                        HStack {
                            Text(goal.label)
                                .foregroundColor(.textPrimary)
                            Spacer()
                            if selected.contains(goal) {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(.ember)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Training Goals")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.updateProfile(fitnessGoals: Array(selected))
                        dismiss()
                    }
                    .foregroundColor(.ember)
                }
            }
            .onAppear { selected = Set(store.userProfile.fitnessGoals) }
        }
    }

    private func toggle(_ goal: UserFitnessGoal) {
        if selected.contains(goal) { selected.remove(goal) } else { selected.insert(goal) }
    }
}

// MARK: - Training Schedule Editor

struct TrainingScheduleEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @State private var mode: SchedulePlanningMode = .rotate
    @State private var split: [WeeklySplitSlot] = WeeklySplitSlot.defaultWeek

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("The week walks day by day. Rotate lets ARIA assign the library; pick days to lock Tuesday legs, Wednesday chest and abs, or whatever you want. You can still replay yesterday from Train.")
                        .font(.system(size: 14))
                        .foregroundColor(.textSecondary)

                    HStack(spacing: 8) {
                        ForEach(SchedulePlanningMode.allCases) { option in
                            Button {
                                mode = option
                            } label: {
                                Text(option.label)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(mode == option ? .white : .textSecondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(mode == option ? Color.ember : Color.surfaceElevated)
                                    .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    ForEach($split) { $slot in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(WeeklySplit.dayNames[slot.weekday])
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.textPrimary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(WeeklySplit.focusChoices, id: \.label) { choice in
                                        let on = slot.primary == choice.id && slot.extra == choice.extra
                                        Button {
                                            slot.primary = choice.id
                                            slot.extra = choice.extra
                                            if choice.id == "rest" { slot.exerciseCount = 0 }
                                            else if slot.exerciseCount == 0 { slot.exerciseCount = 5 }
                                            mode = .fixed
                                        } label: {
                                            Text(choice.label)
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundColor(on ? .white : .textSecondary)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 7)
                                                .background(on ? Color.ember : Color.surface)
                                                .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            if !slot.isRest {
                                Stepper("\(slot.exerciseCount) exercises", value: $slot.exerciseCount, in: 3...8)
                                    .font(.system(size: 13))
                                    .foregroundColor(.textSecondary)
                            }
                        }
                        .padding(12)
                        .background(Color.surfaceElevated)
                        .cornerRadius(12)
                    }
                }
                .padding(16)
            }
            .background(Color.background.ignoresSafeArea())
            .navigationTitle("Training Schedule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let week = WeeklySplit.normalized(split)
                        store.updateProfile(
                            weeklySchedule: WeeklySplit.trainingDays(in: week),
                            schedulePlanningMode: mode,
                            weeklySplit: week
                        )
                        store.rebuildTodayPlanFromLife()
                        dismiss()
                    }
                    .foregroundColor(.ember)
                }
            }
            .onAppear {
                mode = store.userProfile.schedulePlanningMode
                split = WeeklySplit.normalized(store.userProfile.weeklySplit)
            }
        }
    }
}

// MARK: - Training Theme Picker

struct TrainingThemePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @State private var selection: AriaTrainingTheme = .classic

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("ARIA builds real sessions in the language of the world you pick — readiness still decides intensity.")
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)
                        .listRowBackground(Color.clear)
                }

                ForEach(AriaTrainingTheme.allCases) { theme in
                    Button {
                        selection = theme
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: theme.icon)
                                .font(.system(size: 18))
                                .foregroundColor(Color(hex: theme.accentHex))
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(theme.label)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.textPrimary)
                                Text(theme.tagline)
                                    .font(.system(size: 12))
                                    .foregroundColor(.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            if selection == theme {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(Color(hex: theme.accentHex))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Training Theme")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.setTrainingTheme(selection, source: "settings")
                        dismiss()
                    }
                    .foregroundColor(.ember)
                }
            }
            .onAppear { selection = store.userProfile.trainingTheme }
        }
    }
}

// MARK: - Equipment Picker

struct EquipmentPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @State private var selection: TrainingEquipment = .commercialGym

    var body: some View {
        NavigationStack {
            List {
                ForEach(TrainingEquipment.allCases) { equipment in
                    Button {
                        selection = equipment
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: equipment.icon).foregroundColor(.ember)
                            Text(equipment.rawValue).foregroundColor(.textPrimary)
                            Spacer()
                            if selection == equipment {
                                Image(systemName: "checkmark").foregroundColor(.ember)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Equipment")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.updateProfile(trainingEquipment: selection)
                        dismiss()
                    }
                    .foregroundColor(.ember)
                }
            }
            .onAppear { selection = store.userProfile.trainingEquipment }
        }
    }
}

// MARK: - Preferred Workouts Editor

struct PreferredWorkoutsEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @State private var selected: Set<WorkoutType> = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(WorkoutType.allCases) { type in
                    Button { toggle(type) } label: {
                        HStack {
                            Circle().fill(type.color).frame(width: 8, height: 8)
                            Text(type.label).foregroundColor(.textPrimary)
                            Spacer()
                            if selected.contains(type) {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(.ember)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Preferred Workouts")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.updateProfile(preferredWorkouts: Array(selected))
                        dismiss()
                    }
                    .foregroundColor(.ember)
                }
            }
            .onAppear { selected = Set(store.userProfile.preferredWorkouts) }
        }
    }

    private func toggle(_ type: WorkoutType) {
        if selected.contains(type) { selected.remove(type) } else { selected.insert(type) }
    }
}

// MARK: - Nutrition Targets Editor

struct NutritionTargetsEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore

    @State private var useCustom = false
    @State private var protein = ""
    @State private var calories = ""
    @State private var steps = ""
    @State private var sleepHours = ""
    @State private var water = ""

    private var computed: LifestyleTargets {
        LifestyleTargets.resolve(profile: store.userProfile, overrides: nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Use custom targets", isOn: $useCustom)
                }

                Section("Recommended (from your profile)") {
                    targetRow("Protein", value: "\(computed.proteinGrams)g")
                    targetRow("Calories", value: "\(computed.calorieTarget) kcal")
                    targetRow("Steps", value: "\(computed.stepTarget.formatted())")
                    targetRow("Sleep", value: String(format: "%.1fh", computed.sleepHoursTarget))
                    targetRow("Water", value: "\(computed.waterGlassesTarget) glasses")
                }

                if useCustom {
                    Section("Custom overrides") {
                        TextField("Protein (g)", text: $protein).keyboardType(.numberPad)
                        TextField("Calories", text: $calories).keyboardType(.numberPad)
                        TextField("Steps", text: $steps).keyboardType(.numberPad)
                        TextField("Sleep hours", text: $sleepHours).keyboardType(.decimalPad)
                        TextField("Water glasses", text: $water).keyboardType(.numberPad)
                    }
                    Section {
                        Text("Hydration also has its own goal editor. A millilitre goal set there wins over glasses here.")
                            .font(.footnote)
                            .foregroundColor(.textSecondary)
                    }
                }
            }
            .navigationTitle("Nutrition Targets")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(); dismiss() }.foregroundColor(.ember)
                }
            }
            .onAppear { load() }
        }
    }

    private func targetRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundColor(.textSecondary)
        }
    }

    private func load() {
        let prefs = store.nutritionPreferences
        useCustom = prefs.proteinGrams != nil || prefs.calorieTarget != nil
            || prefs.stepTarget != nil || prefs.waterGlassesTarget != nil
            || prefs.hydrationTargetMl != nil
        protein = prefs.proteinGrams.map(String.init) ?? ""
        calories = prefs.calorieTarget.map(String.init) ?? ""
        steps = prefs.stepTarget.map(String.init) ?? ""
        sleepHours = prefs.sleepHoursTarget.map { String(format: "%.1f", $0) } ?? ""
        if let ml = prefs.hydrationTargetMl {
            water = String(max(4, Int(HydrationEngine.glasses(fromMilliliters: ml).rounded())))
        } else {
            water = prefs.waterGlassesTarget.map(String.init) ?? ""
        }
    }

    private func save() {
        guard useCustom else {
            store.updateNutritionPreferences(NutritionPreferences())
            return
        }
        let glasses = Int(water)
        store.updateNutritionPreferences(NutritionPreferences(
            proteinGrams: Int(protein),
            calorieTarget: Int(calories),
            stepTarget: Int(steps),
            sleepHoursTarget: Double(sleepHours),
            waterGlassesTarget: glasses,
            hydrationTargetMl: glasses.map { HydrationEngine.milliliters(fromGlasses: Double($0)) },
            activeCalorieTarget: nil
        ))
    }
}