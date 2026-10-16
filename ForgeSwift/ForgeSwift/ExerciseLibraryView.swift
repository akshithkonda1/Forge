import SwiftUI
import ForgeCore

struct ExerciseLibraryView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var muscle: TargetMuscle? = nil
    @State private var equipment: GearType? = nil
    @State private var pattern: MovementPattern? = nil
    @State private var organize: ExerciseLibrary.OrganizeBy = .style
    @State private var collapsed: Set<String> = []
    @State private var selected: ExerciseDefinition? = nil

    private var sections: [ExerciseLibrary.Section] {
        ExerciseLibrary.grouped(query: query, muscle: muscle, equipment: equipment, pattern: pattern, by: organize)
    }

    private var resultCount: Int { sections.reduce(0) { $0 + $1.items.count } }

    private var hasActiveFilters: Bool { muscle != nil || equipment != nil || pattern != nil }

    private func clearFilters() {
        muscle = nil
        equipment = nil
        pattern = nil
    }

    var body: some View {
        NavigationStack {
            libraryScroll
                .forgeScreenBackground(accent: .ember)
                .navigationTitle("Exercise Library")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { AriaTrainMuteButton() }
                    ToolbarItem(placement: .topBarTrailing) { groupMenu }
                    ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.foregroundColor(.ember).fontWeight(.semibold) }
                }
                .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "A move, a muscle, calisthenics, or a sport")
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .forgeHaptic(.selection, trigger: organize)
                .sheet(item: $selected) { def in ExerciseDetailSheet(def: def) }
        }
    }

    // MARK: Scroll content

    private var libraryScroll: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: ForgeLayout.sectionGap) {
                introBlock
                if sections.isEmpty {
                    emptyBlock
                } else {
                    resultsHeader
                    ForEach(sections) { section in
                        librarySection(section)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .forgeScreenInsets(top: ForgeLayout.screenTop)
        }
    }

    private var introBlock: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text(ExerciseLibrary.welcomeSubtitle)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
                if organize == .style {
                    Text("Calisthenics and sports sit up front. Ask ARIA to log a match.")
                        .font(HomeType.body)
                        .foregroundStyle(Color.textTertiary)
                        .forgeWrapping()
                }
            }
            filterChips
        }
    }

    private var groupMenu: some View {
        Menu {
            Picker("Group by", selection: $organize) {
                ForEach(ExerciseLibrary.OrganizeBy.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
        } label: {
            Image(systemName: "square.grid.2x2")
                .foregroundStyle(Color.ember)
        }
        .accessibilityLabel("Group by")
        .accessibilityValue(organize.label)
    }

    private var filterChips: some View {
        ForgeFlowLayout(spacing: ForgeLayout.chipGap, lineSpacing: ForgeLayout.interactiveChipLineGap) {
            Menu {
                Button("All muscles") { muscle = nil }
                ForEach(TargetMuscle.allCases) { m in Button(m.label) { muscle = m } }
            } label: {
                filterChip(muscle?.label ?? "Muscle", icon: "figure.strengthtraining.traditional", active: muscle != nil, color: muscle?.accent ?? .steel)
            }
            .accessibilityLabel("Muscle filter")
            .accessibilityValue(muscle?.label ?? "All")

            Menu {
                Button("All equipment") { equipment = nil }
                ForEach(GearType.allCases) { e in Button(e.label) { equipment = e } }
            } label: {
                filterChip(equipment?.label ?? "Equipment", icon: "dumbbell.fill", active: equipment != nil, color: .ember)
            }
            .accessibilityLabel("Equipment filter")
            .accessibilityValue(equipment?.label ?? "All")

            Menu {
                Button("All patterns") { pattern = nil }
                ForEach(MovementPattern.allCases) { p in Button(p.label) { pattern = p } }
            } label: {
                filterChip(pattern?.label ?? "Pattern", icon: "arrow.triangle.swap", active: pattern != nil, color: Color.aurora)
            }
            .accessibilityLabel("Pattern filter")
            .accessibilityValue(pattern?.label ?? "All")

            if hasActiveFilters {
                ForgeChipButton(label: "Clear", icon: "xmark") {
                    clearFilters()
                }
            }
        }
    }

    private func filterChip(_ text: String, icon: String, active: Bool, color: Color) -> some View {
        ForgeChip(label: text, icon: icon, energy: color, selected: active)
            .forgeTapOutset(vertical: ForgeLayout.chipTapOutset)
    }

    private var resultsHeader: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            Text("\(resultCount) moves ready · \(sections.count) groups")
                .forgeSectionLabel(tint: .textTertiary)
                .forgeWrapping()
                .accessibilityAddTraits(.isHeader)
            if organize == .style || muscle != nil {
                VStack(spacing: ForgeLayout.tileGap) {
                    if organize == .style {
                        ForgeSecondaryButton(title: "Build calisthenics", icon: "figure.strengthtraining.functional", accent: .ember) {
                            store.adoptCalisthenicsSession()
                            dismiss()
                        }
                    }
                    if let muscle {
                        ForgeSecondaryButton(title: "Build session", icon: "figure.strengthtraining.traditional", accent: .ember) {
                            store.adoptLibrarySession(for: muscle)
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var emptyBlock: some View {
        if hasActiveFilters {
            ForgeEmptyStateCard(
                icon: "figure.gymnastics",
                title: "Nothing in this corner yet",
                message: "Try Calisthenics or Sports, search a muscle, or clear a filter.",
                accent: .ember,
                cta: "Clear filters",
                action: { clearFilters() }
            )
        } else {
            ForgeEmptyStateCard(
                icon: "figure.gymnastics",
                title: "Nothing in this corner yet",
                message: "Try Calisthenics or Sports, search a muscle, or clear a filter.",
                accent: .ember
            )
        }
    }

    // MARK: Sections and rows

    private func librarySection(_ section: ExerciseLibrary.Section) -> some View {
        let open = !collapsed.contains(section.id)
        return VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            sectionHeader(section, open: open)

            if open, let blurb = section.blurb {
                Text(blurb)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textTertiary)
                    .forgeWrapping()
            }

            if open {
                VStack(alignment: .leading, spacing: ForgeLayout.tileGap) {
                    ForEach(section.items) { def in
                        libraryCard(def)
                    }
                }
            }
        }
    }

    private func sectionHeader(_ section: ExerciseLibrary.Section, open: Bool) -> some View {
        Button {
            ForgeHaptics.play(.selection)
            if open { collapsed.insert(section.id) } else { collapsed.remove(section.id) }
        } label: {
            HStack(spacing: ForgeLayout.rowGap) {
                Circle()
                    .fill(section.accent)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(section.title)
                    .font(HomeType.status)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(section.items.count)")
                    .font(HomeType.micro)
                    .monospacedDigit()
                    .foregroundStyle(Color.textTertiary)
                    .padding(.horizontal, FDS.Spacing.sm)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
                Spacer(minLength: 0)
                Image(systemName: open ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textMuted)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: ForgeUX.minTap, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("\(section.title), \(section.items.count) movements")
        .accessibilityValue(open ? "Expanded" : "Collapsed")
        .accessibilityHint(open ? "Collapse" : "Expand")
    }

    private func libraryCard(_ def: ExerciseDefinition) -> some View {
        HStack(spacing: ForgeLayout.rowGap) {
            Button {
                selected = def
            } label: {
                HStack(spacing: ForgeLayout.rowGap) {
                    ForgeIconWell(systemImage: def.icon, tint: def.accent)
                    VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                        Text(def.name)
                            .font(HomeType.status)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(def.muscleSummary)
                            .font(HomeType.micro)
                            .foregroundStyle(Color.textTertiary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        repChip(def.repRangeLabel)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(def.name), \(def.repRangeLabel) reps, \(def.muscleSummary)")
            .accessibilityHint("Opens the movement details")

            howButton(def)
        }
        .forgeWell()
    }

    private func repChip(_ text: String) -> some View {
        HStack(spacing: FDS.Spacing.xs) {
            Image(systemName: "repeat")
                .font(.system(size: 9, weight: .semibold))
                .accessibilityHidden(true)
            Text(text)
                .font(HomeType.micro)
                .monospacedDigit()
                .lineLimit(1)
        }
        .foregroundStyle(Color.textSecondary)
        .padding(.horizontal, FDS.Spacing.sm)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.white.opacity(0.08)))
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: ForgeUX.hairline))
    }

    private func howButton(_ def: ExerciseDefinition) -> some View {
        Button {
            selected = def
            AriaTrainVoice.speakHowTo(def)
        } label: {
            ARIAIdentityMark(state: .idle, mood: .energized, size: 22, amplitude: 0.22)
                .environment(\.forgeMinimalAnimation, true)
                .frame(width: ForgeUX.minTap, height: ForgeUX.minTap)
                .background(Color.ember.opacity(0.12))
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.ember.opacity(0.28), lineWidth: ForgeUX.hairline))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("ARIA, show me how to do \(def.name)")
        .accessibilityHint("ARIA explains the movement out loud")
    }
}

struct ExerciseDetailSheet: View {
    let def: ExerciseDefinition
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var added = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: ForgeLayout.sectionGap) {
                    heroBlock
                    FlowChips(items: specChips)
                    detailCards
                    actionsBlock
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .forgeScreenInsets(top: FDS.Spacing.lg)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { addDock }
            .forgeScreenBackground(accent: .ember)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() }.foregroundColor(.ember).fontWeight(.semibold) } }
            .forgeHaptic(.success, trigger: added)
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: Blocks

    private var heroBlock: some View {
        ForgeAdaptiveStack(spacing: ForgeLayout.rowGap, alignment: .center) {
            ForgeIconWell(systemImage: def.icon, tint: def.accent, diameter: 64)
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text(def.pattern.label)
                    .forgeSectionLabel(tint: def.accent)
                    .forgeWrapping()
                Text(def.name)
                    .font(HomeType.sessionTitle)
                    .foregroundStyle(Color.textPrimary)
                    .forgeWrapping()
                    .accessibilityAddTraits(.isHeader)
                Text(def.muscleSummary)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textTertiary)
                    .forgeWrapping()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var specChips: [(String, String, Color)] {
        [
            ("\(def.defaultSets) × \(def.repRangeLabel)", "repeat", .steel),
            ("\(def.restSeconds)s rest", "clock.fill", .textTertiary),
            ("Tempo \(def.tempo)", "metronome.fill", .ember),
            ("RPE \(def.rpeTarget)", "bolt.fill", Color.amber),
            (def.level.label, "chart.bar.fill", Color.aurora),
            (def.equipment.label, def.equipment.icon, Color.vitality),
        ]
    }

    @ViewBuilder
    private var detailCards: some View {
        if !def.cues.isEmpty { sectionCard("EXECUTION", icon: "checkmark.seal.fill", color: def.accent, lines: def.cues) }
        if !def.faults.isEmpty { sectionCard("COMMON FAULTS", icon: "exclamationmark.triangle.fill", color: .amber, lines: def.faults) }
        if !def.note.isEmpty { noteCard }
        if !def.substitutes.isEmpty { swapsCard }
    }

    private var noteCard: some View {
        HStack(alignment: .top, spacing: ForgeLayout.rowGap) {
            ARIAIdentityMark(state: .idle, mood: .focused, size: 14)
                .environment(\.forgeMinimalAnimation, true)
                .padding(.top, 3)
            Text(def.note)
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
            Spacer(minLength: 0)
        }
        .forgeContentCard(tint: .ember)
    }

    private var swapsCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("ARIA SWAPS")
            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                ForEach(def.substitutes, id: \.self) { s in
                    HStack(alignment: .firstTextBaseline, spacing: ForgeLayout.rowGap) {
                        Image(systemName: "arrow.triangle.swap")
                            .font(HomeType.body)
                            .imageScale(.small)
                            .foregroundStyle(Color.steel)
                            .accessibilityHidden(true)
                        Text(s)
                            .font(HomeType.body)
                            .foregroundStyle(Color.textSecondary)
                            .forgeWrapping()
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .forgeContentCard(tint: .steel)
    }

    private var actionsBlock: some View {
        VStack(spacing: ForgeLayout.rowGap) {
            ForgeSecondaryButton(title: "ARIA, show me how", icon: "speaker.wave.2.fill", accent: .ember) {
                AriaTrainVoice.speakHowTo(def)
            }
            ForgeTextLink(title: "Ask ARIA in chat", accent: .ember) {
                dismiss()
                store.showHowToPerform(def.name, speakLocally: false, openChat: true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var addTitle: String {
        if added { return "Added to today" }
        return store.todayWorkout == nil ? "Start a plan with this" : "Add to today's workout"
    }

    private var addDock: some View {
        ForgePrimaryButton(
            title: addTitle,
            icon: added ? "checkmark.circle.fill" : "plus.circle.fill",
            accent: .ember
        ) {
            addToPlan()
        }
        .disabled(added)
        .padding(.horizontal, ForgeLayout.screenInset)
        .padding(.vertical, FDS.Spacing.sm)
        .frame(maxWidth: .infinity)
        .forgeBarChrome(edge: .bottom)
    }

    private func addToPlan() {
        let ex = Exercise(id: UUID().uuidString, name: def.name, sets: def.defaultSets,
                          reps: def.repRangeLabel.replacingOccurrences(of: "–", with: "-"),
                          weight: def.mechanic == .compound && def.equipment != .bodyweight ? 95 : (def.equipment == .bodyweight ? nil : 25),
                          restSeconds: def.restSeconds, notes: def.cues.first, videoURL: nil, has3DModel: false)
        if store.todayWorkout == nil, let muscle = def.primary.first {
            store.adoptLibrarySession(for: muscle)
            if store.todayWorkout?.exercises.contains(where: { $0.name == def.name }) != true {
                store.todayWorkout?.exercises.insert(ex, at: 0)
            }
        } else if store.todayWorkout == nil {
            store.todayWorkout = WorkoutPlan(id: UUID().uuidString, name: def.name, type: .strength,
                                             duration: 45, intensity: .moderate, exercises: [ex])
        } else {
            store.todayWorkout?.exercises.append(ex)
        }
        if reduceMotion {
            added = true
        } else {
            withAnimation { added = true }
        }
    }

    private func sectionCard(_ title: String, icon: String, color: Color, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader(title)
            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                ForEach(lines, id: \.self) { line in
                    HStack(alignment: .firstTextBaseline, spacing: ForgeLayout.rowGap) {
                        Image(systemName: icon)
                            .font(HomeType.body)
                            .imageScale(.small)
                            .foregroundStyle(color)
                            .accessibilityHidden(true)
                        Text(line)
                            .font(HomeType.body)
                            .foregroundStyle(Color.textSecondary)
                            .forgeWrapping()
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .forgeContentCard(tint: color)
    }
}

/// Wrapping row of neutral context chips (Home chip recipe).
struct FlowChips: View {
    let items: [(String, String, Color)]
    var body: some View {
        ForgeFlowLayout(spacing: ForgeLayout.chipGap, lineSpacing: ForgeLayout.chipGap) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                ForgeChip(label: item.0, icon: item.1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
