import SwiftUI
import UIKit
import ForgeCore

// MARK: - Shared editor scaffolding
//
// The settings editors are Forge sheets, not stock Lists and Forms: a screen
// background, one 16 pt inset, cards at 20 pt, 44 pt option rows and a single
// selection indicator.

/// The scrolling body of an editor sheet: 16 pt side inset, 16 pt between
/// cards, the sheet top inset, and a domain-washed Forge background.
private struct EditorSheetScroll<Content: View>: View {
    var accent: Color = .ember
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ForgeLayout.sectionGap) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .forgeScreenInsets(top: FDS.Spacing.lg)
        }
        .scrollDismissesKeyboard(.interactively)
        .forgeScreenBackground(accent: accent)
    }
}

/// A neutral content card for a group of rows. Rows sit at the row gap, with
/// no dividers between them.
private struct EditorCard<Content: View>: View {
    var spacing: CGFloat = ForgeLayout.rowGap
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content()
        }
        .forgeContentCard()
    }
}

/// One selectable option: optional icon well or color dot, a status title, an
/// optional subtitle, and the shared check indicator. The whole row is the
/// 44 pt target and carries the selected trait.
private struct EditorOptionRow: View {
    var title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var dot: Color? = nil
    var tint: Color = .ember
    var selected: Bool
    var action: () -> Void

    @ViewBuilder
    private var leading: some View {
        if let icon {
            ForgeIconWell(systemImage: icon, tint: tint)
        } else if let dot {
            Circle()
                .fill(dot)
                .frame(width: 10, height: 10)
                .frame(width: ForgeLayout.iconWell)
                .accessibilityHidden(true)
        }
    }

    private var indicator: some View {
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(selected ? tint : Color.textMuted)
            .accessibilityHidden(true)
    }

    var body: some View {
        Button {
            ForgeHaptics.play(.selection)
            action()
        } label: {
            HStack(spacing: ForgeLayout.rowGap) {
                leading
                VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                    Text(title)
                        .font(HomeType.status)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(2)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(HomeType.body)
                            .foregroundStyle(Color.textSecondary)
                            .forgeWrapping()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                indicator
            }
            .padding(.vertical, ForgeLayout.rowVerticalPadding)
            .frame(minHeight: ForgeUX.minTap)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Fitness Goals Editor

struct FitnessGoalsEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @State private var selected: Set<UserFitnessGoal> = []

    var body: some View {
        NavigationStack {
            EditorSheetScroll(accent: .ember) {
                EditorCard {
                    ForEach(UserFitnessGoal.allCases) { goal in
                        EditorOptionRow(
                            title: goal.label,
                            selected: selected.contains(goal)
                        ) {
                            toggle(goal)
                        }
                    }
                }
            }
            .navigationTitle("Training Goals")
            .navigationBarTitleDisplayMode(.inline)
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
        .presentationDragIndicator(.visible)
    }

    private func toggle(_ goal: UserFitnessGoal) {
        if selected.contains(goal) { selected.remove(goal) } else { selected.insert(goal) }
    }
}

// MARK: - Training Schedule Editor

/// A pill that opens a menu: the current value and a chevron, drawn like a
/// chip (30 pt) with a 44 pt tap area.
private struct ScheduleMenuPill: View {
    var title: String

    var body: some View {
        HStack(spacing: FDS.Spacing.xs) {
            Text(title)
                .font(HomeType.label)
                .foregroundStyle(Color.textPrimary)
                .forgeSingleLine(minScale: ForgeLayout.labelMinScale)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, FDS.Spacing.sm)
        .padding(.vertical, FDS.Spacing.sm)
        .frame(minHeight: 30)
        .background(Color.white.opacity(0.08))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: ForgeUX.hairline))
        .forgeTapOutset(vertical: ForgeLayout.chipTapOutset)
    }
}

/// One weekday: `Mon | Legs v | 5 exercises v`. Picking a focus keeps the
/// editor's behaviour (a rest day clears the count, a training day with none
/// gets 5, and the plan switches to "pick the days").
private struct ScheduleDayRow: View {
    @Binding var slot: WeeklySplitSlot
    var onFocusPicked: () -> Void

    private typealias FocusChoice = (id: String, extra: String?, label: String)

    private var dayName: String { WeeklySplit.dayNames[slot.weekday] }
    private var dayShort: String { WeeklySplit.dayLabels[slot.weekday] }

    private var focusTitle: String {
        let match = WeeklySplit.focusChoices.first { $0.id == slot.primary && $0.extra == slot.extra }
        return match?.label ?? slot.title
    }

    private var countTitle: String { "\(slot.exerciseCount) exercises" }

    private func isCurrent(_ choice: FocusChoice) -> Bool {
        choice.id == slot.primary && choice.extra == slot.extra
    }

    private func pick(_ choice: FocusChoice) {
        slot.primary = choice.id
        slot.extra = choice.extra
        if choice.id == "rest" { slot.exerciseCount = 0 }
        else if slot.exerciseCount == 0 { slot.exerciseCount = 5 }
        onFocusPicked()
    }

    @ViewBuilder
    private func focusOption(_ choice: FocusChoice) -> some View {
        if isCurrent(choice) {
            Label(choice.label, systemImage: "checkmark")
        } else {
            Text(choice.label)
        }
    }

    @ViewBuilder
    private func countOption(_ count: Int) -> some View {
        if count == slot.exerciseCount {
            Label("\(count) exercises", systemImage: "checkmark")
        } else {
            Text("\(count) exercises")
        }
    }

    private var focusMenu: some View {
        Menu {
            ForEach(WeeklySplit.focusChoices, id: \.label) { choice in
                Button {
                    pick(choice)
                } label: {
                    focusOption(choice)
                }
            }
        } label: {
            ScheduleMenuPill(title: focusTitle)
        }
        .accessibilityLabel("\(dayName) focus")
        .accessibilityValue(focusTitle)
    }

    private var countMenu: some View {
        Menu {
            ForEach(3...8, id: \.self) { count in
                Button {
                    slot.exerciseCount = count
                } label: {
                    countOption(count)
                }
            }
        } label: {
            ScheduleMenuPill(title: countTitle)
        }
        .accessibilityLabel("\(dayName) exercises")
        .accessibilityValue(countTitle)
    }

    var body: some View {
        ForgeAdaptiveStack(spacing: ForgeLayout.rowGap) {
            Text(dayShort)
                .font(HomeType.status)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(dayName)
                .accessibilityAddTraits(.isHeader)
            focusMenu
            if !slot.isRest {
                countMenu
            }
        }
        .frame(minHeight: ForgeUX.minTap)
        .accessibilityElement(children: .contain)
    }
}

struct TrainingScheduleEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @State private var mode: SchedulePlanningMode = .rotate
    @State private var split: [WeeklySplitSlot] = WeeklySplitSlot.defaultWeek

    private var modeOptions: [ForgeSegmentOption<SchedulePlanningMode>] {
        SchedulePlanningMode.allCases.map { option in
            ForgeSegmentOption(value: option, title: option.label)
        }
    }

    private var modeCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            Text("The week walks day by day. Rotate lets ARIA assign the library; pick days to lock Tuesday legs, Wednesday chest and abs, or whatever you want. You can still replay yesterday from Train.")
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
            ForgeSegmentedControl(
                modeOptions,
                selection: $mode,
                accent: .ember,
                bleed: ForgeLayout.cardPadding
            )
            Text(mode.detail)
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
        }
        .forgeContentCard()
    }

    private var weekCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            ForEach($split) { $slot in
                ScheduleDayRow(slot: $slot) {
                    mode = .fixed
                }
            }
        }
        .forgeContentCard()
    }

    var body: some View {
        NavigationStack {
            EditorSheetScroll(accent: .ember) {
                modeCard
                weekCard
            }
            .navigationTitle("Training Schedule")
            .navigationBarTitleDisplayMode(.inline)
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
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Training Theme Picker

struct TrainingThemePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @State private var selection: AriaTrainingTheme = .classic

    var body: some View {
        NavigationStack {
            EditorSheetScroll(accent: .aurora) {
                Text("ARIA builds real sessions in the language of the world you pick — readiness still decides intensity.")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
                EditorCard {
                    ForEach(AriaTrainingTheme.allCases) { theme in
                        EditorOptionRow(
                            title: theme.label,
                            subtitle: theme.tagline,
                            icon: theme.icon,
                            tint: Color(hex: theme.accentHex),
                            selected: selection == theme
                        ) {
                            selection = theme
                        }
                    }
                }
            }
            .navigationTitle("Training Theme")
            .navigationBarTitleDisplayMode(.inline)
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
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Equipment Picker

struct EquipmentPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @State private var selection: TrainingEquipment = .commercialGym
    @State private var notes: String = ""

    var body: some View {
        NavigationStack {
            EditorSheetScroll(accent: .steel) {
                EditorCard {
                    ForEach(TrainingEquipment.allCases) { equipment in
                        EditorOptionRow(
                            title: equipment.rawValue,
                            icon: equipment.icon,
                            tint: .steel,
                            selected: selection == equipment
                        ) {
                            selection = equipment
                        }
                    }
                }
                EditorCard {
                    Text("Exact gear (optional)")
                        .font(HomeType.body)
                        .foregroundStyle(Color.textSecondary)
                    TextField("dumbbells, rack, bike…", text: $notes, axis: .vertical)
                        .font(HomeType.body)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("Gym and equipment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.updateProfile(trainingEquipment: selection, equipmentNotes: notes)
                        dismiss()
                    }
                    .foregroundColor(.ember)
                }
            }
            .onAppear {
                selection = store.userProfile.trainingEquipment
                notes = store.userProfile.equipmentNotes
            }
        }
        .presentationDragIndicator(.visible)
    }
}

struct AriaSoulPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var soul = AriaSoulStore.shared

    var body: some View {
        NavigationStack {
            EditorSheetScroll(accent: .ember) {
                EditorCard {
                    ForEach(AriaSoul.Personality.allCases, id: \.self) { personality in
                        EditorOptionRow(
                            title: personality.label,
                            subtitle: personality.flavor,
                            icon: "text.bubble",
                            tint: .ember,
                            selected: soul.config.blend.anchor == personality
                        ) {
                            soul.setPersonality(personality)
                        }
                    }
                }
                Text("Takes effect on the next reply — no restart. If you don't pick, ARIA blends from experience, goals, and how you respond. Same rails for every blend: coach, not doctor; never shame, diagnose, push past comfort, or say recovery.")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
            }
            .navigationTitle("ARIA personality")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.ember)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}

struct AriaVoicePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var voices = AriaVoiceProfileStore.shared
    @State private var previewing = false

    var body: some View {
        NavigationStack {
            EditorSheetScroll(accent: .ember) {
                EditorCard {
                    ForEach(voices.featured) { profile in
                        EditorOptionRow(
                            title: profile.label,
                            subtitle: profile.description,
                            icon: "waveform",
                            tint: .ember,
                            selected: voices.selection.profileID == profile.id
                        ) {
                            voices.select(profile)
                        }
                    }
                }
                if let more = voices.catalog?.voices, !more.isEmpty {
                    ForgeCardHeader("Kokoro presets", meta: "On this iPhone")
                    EditorCard {
                        ForEach(more.prefix(12), id: \.id) { voice in
                            EditorOptionRow(
                                title: voice.title,
                                subtitle: voice.description,
                                icon: "speaker.wave.2",
                                tint: .ember,
                                selected: voices.selection.voiceID == voice.id && voices.selection.profileID == nil
                            ) {
                                voices.select(voice: voice)
                            }
                        }
                    }
                }
                Button {
                    previewing = true
                    AriaPresence.shared.speak(AriaVoiceCatalog.previewText)
                    previewing = false
                } label: {
                    Text(previewing ? "Playing sample" : "Play a short sample")
                        .font(HomeType.status)
                        .foregroundStyle(Color.ember)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, ForgeLayout.rowVerticalPadding)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play a short sample of the selected voice")
                Text("Takes effect on the next spoken reply — no restart. Independent of Coach, Friend, or Drill Sergeant. Same rails either way.")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                if voices.lastBusy {
                    Text(AriaKokoroVoice.loadFailedMessage)
                        .font(HomeType.body)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .navigationTitle("ARIA voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.ember)
                }
            }
            .task { await voices.refreshCatalog() }
        }
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Preferred Workouts Editor

struct PreferredWorkoutsEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @State private var selected: Set<WorkoutType> = []

    var body: some View {
        NavigationStack {
            EditorSheetScroll(accent: .ember) {
                EditorCard {
                    ForEach(WorkoutType.allCases) { type in
                        EditorOptionRow(
                            title: type.label,
                            dot: type.color,
                            selected: selected.contains(type)
                        ) {
                            toggle(type)
                        }
                    }
                }
            }
            .navigationTitle("Preferred Workouts")
            .navigationBarTitleDisplayMode(.inline)
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
        .presentationDragIndicator(.visible)
    }

    private func toggle(_ type: WorkoutType) {
        if selected.contains(type) { selected.remove(type) } else { selected.insert(type) }
    }
}

// MARK: - Nutrition Targets Editor

/// A labelled number field in a well. The label stays visible once a value is
/// typed, and stacks above the field at accessibility sizes.
private struct TargetFieldRow: View {
    var label: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .numberPad

    var body: some View {
        ForgeAdaptiveStack(spacing: ForgeLayout.rowGap) {
            Text(label)
                .font(HomeType.status)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)
            TextField("—", text: $text)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .font(HomeType.metric)
                .foregroundStyle(Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityLabel(label)
        }
        .frame(minHeight: ForgeUX.minTap - 2 * ForgeLayout.tilePadding)
        .forgeWell()
    }
}

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

    private var customToggleCard: some View {
        Toggle(isOn: $useCustom) {
            Text("Use custom targets")
                .font(HomeType.status)
                .foregroundStyle(Color.textPrimary)
        }
        .tint(.ember)
        .frame(minHeight: ForgeUX.minTap)
        .forgeContentCard()
    }

    private var recommendedCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.labelValueGap) {
            targetRow("Protein", value: "\(computed.proteinGrams)", unit: "g", tint: .amber)
            targetRow("Calories", value: "\(computed.calorieTarget)", unit: "kcal", tint: .amber)
            targetRow("Steps", value: "\(computed.stepTarget.formatted())", unit: nil, tint: .vitality)
            targetRow("Sleep", value: String(format: "%.1f", computed.sleepHoursTarget), unit: "h", tint: .steel)
            targetRow("Water", value: "\(computed.waterGlassesTarget)", unit: "glasses", tint: .steel)
        }
        .forgeContentCard()
    }

    private var overridesCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.tileGap) {
            TargetFieldRow(label: "Protein (g)", text: $protein)
            TargetFieldRow(label: "Calories", text: $calories)
            TargetFieldRow(label: "Steps", text: $steps)
            TargetFieldRow(label: "Sleep hours", text: $sleepHours, keyboard: .decimalPad)
            TargetFieldRow(label: "Water glasses", text: $water)
            Text("Hydration also has its own goal editor. A millilitre goal set there wins over glasses here.")
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
                .padding(.top, ForgeLayout.pairGap)
        }
        .forgeContentCard()
    }

    var body: some View {
        NavigationStack {
            EditorSheetScroll(accent: .amber) {
                customToggleCard

                ForgeSectionHeader(title: "Recommended (from your profile)")
                recommendedCard

                if useCustom {
                    ForgeSectionHeader(title: "Custom overrides")
                    overridesCard
                }
            }
            .navigationTitle("Nutrition Targets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(); dismiss() }.foregroundColor(.ember)
                }
            }
            .onAppear { load() }
        }
        .presentationDragIndicator(.visible)
    }

    private func targetRow(_ label: String, value: String, unit: String?, tint: Color) -> some View {
        ForgeMetricRow(label: label, value: value, unit: unit, tint: tint)
            .padding(.vertical, ForgeLayout.rowVerticalPadding)
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
