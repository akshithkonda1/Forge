import SwiftUI

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
    @State private var selectedDays: Set<Int> = []

    private let labels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Select the days you typically train. Workout reminders align to this schedule.")
                    .font(.system(size: 14))
                    .foregroundColor(.textSecondary)
                    .padding(.horizontal, 16)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
                    ForEach(0..<7, id: \.self) { day in
                        Button {
                            if selectedDays.contains(day) { selectedDays.remove(day) } else { selectedDays.insert(day) }
                        } label: {
                            Text(labels[day])
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(selectedDays.contains(day) ? .white : .textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(selectedDays.contains(day) ? Color.ember : Color.surfaceElevated)
                                .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)

                Spacer()
            }
            .padding(.top, 12)
            .background(Color.background.ignoresSafeArea())
            .navigationTitle("Training Schedule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.updateProfile(weeklySchedule: Array(selectedDays).sorted())
                        dismiss()
                    }
                    .foregroundColor(.ember)
                }
            }
            .onAppear { selectedDays = Set(store.userProfile.weeklySchedule) }
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
        useCustom = prefs.proteinGrams != nil || prefs.calorieTarget != nil || prefs.stepTarget != nil
        protein = prefs.proteinGrams.map(String.init) ?? ""
        calories = prefs.calorieTarget.map(String.init) ?? ""
        steps = prefs.stepTarget.map(String.init) ?? ""
        sleepHours = prefs.sleepHoursTarget.map { String(format: "%.1f", $0) } ?? ""
        water = prefs.waterGlassesTarget.map(String.init) ?? ""
    }

    private func save() {
        guard useCustom else {
            store.updateNutritionPreferences(NutritionPreferences())
            return
        }
        store.updateNutritionPreferences(NutritionPreferences(
            proteinGrams: Int(protein),
            calorieTarget: Int(calories),
            stepTarget: Int(steps),
            sleepHoursTarget: Double(sleepHours),
            waterGlassesTarget: Int(water),
            activeCalorieTarget: nil
        ))
    }
}