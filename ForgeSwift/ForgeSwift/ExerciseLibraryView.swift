import SwiftUI

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

    var body: some View {
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    welcomeStrip
                    organizeRow
                    filterRow
                    if sections.isEmpty {
                        ContentUnavailableView {
                            Label("Nothing in this corner yet", systemImage: "figure.gymnastics")
                        } description: {
                            Text("Try Calisthenics or Sports, search a muscle, or clear a filter.")
                        }
                        .foregroundStyle(Color.textTertiary)
                    } else {
                        ScrollView(showsIndicators: false) {
                            LazyVStack(alignment: .leading, spacing: FDS.Spacing.lg, pinnedViews: [.sectionHeaders]) {
                                HStack {
                                    Text("\(resultCount) moves ready · \(sections.count) groups")
                                        .forgeSectionLabel()
                                    Spacer()
                                    if organize == .style {
                                        Button("Build calisthenics") {
                                            FDS.haptic(.medium)
                                            store.adoptCalisthenicsSession()
                                            dismiss()
                                        }
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundColor(.ember)
                                    }
                                    if let muscle {
                                        Button("Build session") {
                                            FDS.haptic(.medium)
                                            store.adoptLibrarySession(for: muscle)
                                            dismiss()
                                        }
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundColor(.ember)
                                    }
                                }
                                .padding(.horizontal, FDS.Spacing.xs)

                                ForEach(sections) { section in
                                    librarySection(section)
                                }
                            }
                            .padding(.horizontal, FDS.Spacing.lg)
                            .padding(.bottom, 40)
                        }
                    }
                }
            }
            .navigationTitle("Exercise Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { AriaTrainMuteButton() }
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.foregroundColor(.ember).fontWeight(.semibold) }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "A move, a muscle, calisthenics, or a sport")
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .sensoryFeedback(.selection, trigger: organize)
            .sheet(item: $selected) { def in ExerciseDetailSheet(def: def) }
        }
    }

    private func librarySection(_ section: ExerciseLibrary.Section) -> some View {
        let open = !collapsed.contains(section.id)
        return VStack(alignment: .leading, spacing: FDS.Spacing.sm) {
            Button {
                FDS.selectionHaptic()
                if open { collapsed.insert(section.id) } else { collapsed.remove(section.id) }
            } label: {
                HStack(spacing: FDS.Spacing.md) {
                    Circle().fill(section.accent).frame(width: 8, height: 8)
                    Text(section.title)
                        .font(FDS.TypeScale.Dynamic.body.weight(.semibold))
                        .foregroundColor(.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text("\(section.items.count)")
                        .font(FDS.TypeScale.Dynamic.micro)
                        .foregroundColor(.textMuted)
                        .padding(.horizontal, FDS.Spacing.sm)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())
                    Spacer()
                    Image(systemName: open ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(section.title), \(section.items.count) movements")
            .accessibilityHint(open ? "Collapse" : "Expand")

            if open, let blurb = section.blurb {
                Text(blurb)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.textTertiary)
                    .padding(.leading, FDS.Spacing.lg)
                    .padding(.bottom, FDS.Spacing.xs)
            }

            if open {
                ForEach(section.items) { def in
                    libraryCard(def)
                }
            }
        }
    }

    private var welcomeStrip: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.xs) {
            Text(ExerciseLibrary.welcomeSubtitle)
                .font(FDS.TypeScale.Dynamic.body)
                .foregroundColor(.textSecondary)
            if organize == .style {
                Text("Calisthenics and sports sit up front. Ask ARIA to log a match.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, FDS.Spacing.lg)
        .padding(.bottom, FDS.Spacing.md)
    }

    private var organizeRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: FDS.Spacing.sm) {
                Text("GROUP BY")
                    .forgeSectionLabel()
                ForEach(ExerciseLibrary.OrganizeBy.allCases) { mode in
                    Button {
                        FDS.selectionHaptic()
                        organize = mode
                    } label: {
                        Text(mode.label)
                            .font(FDS.TypeScale.Dynamic.caption)
                            .foregroundColor(organize == mode ? .white : .textSecondary)
                            .padding(.horizontal, FDS.Spacing.md)
                            .padding(.vertical, FDS.Spacing.sm)
                            .background(organize == mode ? Color.ember : Color.surface)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, FDS.Spacing.lg)
            .padding(.bottom, FDS.Spacing.sm)
        }
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: FDS.Spacing.sm) {
                Menu {
                    Button("All muscles") { muscle = nil }
                    ForEach(TargetMuscle.allCases) { m in Button(m.label) { muscle = m } }
                } label: { filterChip(muscle?.label ?? "Muscle", active: muscle != nil, color: muscle?.accent ?? .steel) }
                Menu {
                    Button("All equipment") { equipment = nil }
                    ForEach(GearType.allCases) { e in Button(e.label) { equipment = e } }
                } label: { filterChip(equipment?.label ?? "Equipment", active: equipment != nil, color: .ember) }
                Menu {
                    Button("All patterns") { pattern = nil }
                    ForEach(MovementPattern.allCases) { p in Button(p.label) { pattern = p } }
                } label: { filterChip(pattern?.label ?? "Pattern", active: pattern != nil, color: Color.aurora) }
                if muscle != nil || equipment != nil || pattern != nil {
                    Button {
                        muscle = nil
                        equipment = nil
                        pattern = nil
                    } label: {
                        HStack(spacing: FDS.Spacing.xs) { Image(systemName: "xmark"); Text("Clear") }
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.danger)
                            .padding(.horizontal, FDS.Spacing.md)
                            .padding(.vertical, FDS.Spacing.sm)
                            .background(Color.danger.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, FDS.Spacing.lg)
            .padding(.bottom, FDS.Spacing.md)
        }
    }

    private func filterChip(_ text: String, active: Bool, color: Color) -> some View {
        HStack(spacing: FDS.Spacing.xs) {
            Text(text).font(FDS.TypeScale.Dynamic.caption)
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
        }
        .foregroundColor(active ? .white : .textSecondary)
        .padding(.horizontal, FDS.Spacing.lg).padding(.vertical, FDS.Spacing.sm)
        .background(active ? color : Color.surface).cornerRadius(100)
        .overlay(Capsule().stroke(active ? color : Color.borderColor.opacity(0.5), lineWidth: 1))
    }

    private func libraryCard(_ def: ExerciseDefinition) -> some View {
        HStack(spacing: FDS.Spacing.md) {
            Button {
                FDS.haptic(.light)
                selected = def
            } label: {
                HStack(spacing: FDS.Spacing.lg) {
                    ZStack {
                        RoundedRectangle(cornerRadius: FDS.Radius.md)
                            .fill(LinearGradient(colors: [def.accent.opacity(0.2), def.accent.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 46, height: 46)
                        Image(systemName: def.icon).font(.system(size: 18, weight: .semibold)).foregroundColor(def.accent)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(def.name).font(FDS.TypeScale.Dynamic.body.weight(.semibold)).foregroundColor(.textPrimary).lineLimit(1)
                        Text(def.muscleSummary).font(.system(size: 12)).foregroundColor(.textTertiary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(def.repRangeLabel).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundColor(.textSecondary)
                        Text(def.equipment.label).font(FDS.TypeScale.Dynamic.micro).foregroundColor(.textMuted)
                    }
                }
            }
            .buttonStyle(.plain)

            Button {
                FDS.haptic(.medium)
                selected = def
                AriaTrainVoice.speakHowTo(def)
            } label: {
                VStack(spacing: FDS.Spacing.xs) {
                    ARIAIdentityMark(state: .speaking, mood: .energized, size: 22, amplitude: 0.4)
                    Text("How")
                        .font(FDS.TypeScale.Dynamic.micro)
                }
                .foregroundColor(.ember)
                .frame(width: 48)
                .padding(.vertical, FDS.Spacing.sm)
                .background(Color.ember.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("ARIA, show me how to do \(def.name)")
        }
        .padding(FDS.Spacing.md)
        .background(Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

struct ExerciseDetailSheet: View {
    let def: ExerciseDefinition
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var added = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: FDS.Spacing.lg) {
                        // Hero
                        HStack(spacing: FDS.Spacing.lg) {
                            ZStack {
                                RoundedRectangle(cornerRadius: FDS.Radius.lg)
                                    .fill(LinearGradient(colors: [def.accent.opacity(0.25), def.accent.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 64, height: 64)
                                Image(systemName: def.icon).font(.system(size: 26, weight: .bold)).foregroundColor(def.accent)
                            }
                            VStack(alignment: .leading, spacing: FDS.Spacing.xs) {
                                Text(def.pattern.label.uppercased()).font(FDS.TypeScale.Dynamic.micro).tracking(1.5).foregroundColor(def.accent)
                                Text(def.name).font(FDS.TypeScale.Dynamic.title).foregroundColor(.textPrimary)
                                Text(def.muscleSummary).font(.system(size: 12)).foregroundColor(.textTertiary)
                            }
                            Spacer()
                        }
                        // Spec chips
                        FlowChips(items: [
                            ("\(def.defaultSets) × \(def.repRangeLabel)", "repeat", .steel),
                            ("\(def.restSeconds)s rest", "clock.fill", .textTertiary),
                            ("Tempo \(def.tempo)", "metronome.fill", .ember),
                            ("RPE \(def.rpeTarget)", "bolt.fill", .warning),
                            (def.level.label, "chart.bar.fill", Color.aurora),
                            (def.equipment.label, def.equipment.icon, .success),
                        ])
                        // Cues
                        if !def.cues.isEmpty { sectionCard("EXECUTION", icon: "checkmark.seal.fill", color: def.accent, lines: def.cues) }
                        if !def.faults.isEmpty { sectionCard("COMMON FAULTS", icon: "exclamationmark.triangle.fill", color: .warning, lines: def.faults) }
                        if !def.note.isEmpty {
                            HStack(alignment: .top, spacing: FDS.Spacing.md) {
                                Image(systemName: "brain.head.profile").font(.system(size: 14)).foregroundColor(.ember)
                                Text(def.note).font(.system(size: 13, design: .serif).italic()).foregroundColor(.textSecondary).lineSpacing(4)
                            }
                            .padding(FDS.Spacing.lg).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.ember.opacity(0.06)).cornerRadius(FDS.Radius.lg)
                        }
                        if !def.substitutes.isEmpty {
                            VStack(alignment: .leading, spacing: FDS.Spacing.sm) {
                                Text("ARIA SWAPS").font(FDS.TypeScale.Dynamic.micro).tracking(2).foregroundColor(.textTertiary)
                                ForEach(def.substitutes, id: \.self) { s in
                                    HStack(spacing: FDS.Spacing.sm) {
                                        Image(systemName: "arrow.triangle.swap").font(.system(size: 12)).foregroundColor(.steel)
                                        Text(s).font(.system(size: 13)).foregroundColor(.textSecondary)
                                    }
                                }
                            }
                            .padding(FDS.Spacing.lg).frame(maxWidth: .infinity, alignment: .leading)
                            .forgeGlassCard(cornerRadius: FDS.Radius.lg, accent: .ember)
                        }
                        Button {
                            FDS.haptic(.medium)
                            AriaTrainVoice.speakHowTo(def)
                        } label: {
                            HStack(spacing: FDS.Spacing.md) {
                                ARIAIdentityMark(state: .speaking, mood: .energized, size: 28, amplitude: 0.5)
                                Text("ARIA, show me how")
                                    .font(FDS.TypeScale.Dynamic.headline)
                            }
                            .foregroundColor(.white).frame(maxWidth: .infinity).frame(height: 54)
                            .background(Color.ember.opacity(0.85)).cornerRadius(FDS.Radius.lg)
                        }
                        Button {
                            FDS.haptic(.light)
                            dismiss()
                            store.showHowToPerform(def.name, speakLocally: false, openChat: true)
                        } label: {
                            Text("Ask ARIA in chat")
                                .font(FDS.TypeScale.Dynamic.body.weight(.semibold))
                                .foregroundColor(.ember)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        // Add
                        Button {
                            addToPlan()
                        } label: {
                            HStack(spacing: FDS.Spacing.md) {
                                Image(systemName: added ? "checkmark.circle.fill" : "plus.circle.fill").font(.system(size: 18, weight: .bold))
                                Text(added ? "Added to today" : store.todayWorkout == nil ? "Start a plan with this" : "Add to today's workout").font(FDS.TypeScale.Dynamic.headline)
                            }
                            .foregroundColor(.white).frame(maxWidth: .infinity).frame(height: 54)
                            .background(added ? Color.success : def.accent).cornerRadius(FDS.Radius.lg)
                            .shadow(color: (added ? Color.success : def.accent).opacity(0.4), radius: 14, y: 6)
                        }
                        .disabled(added)
                    }
                    .padding(FDS.Spacing.lg).padding(.bottom, 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() }.foregroundColor(.ember).fontWeight(.semibold) } }
            .sensoryFeedback(.success, trigger: added)
        }
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
        withAnimation { added = true }
    }

    private func sectionCard(_ title: String, icon: String, color: Color, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.md) {
            Text(title).font(FDS.TypeScale.Dynamic.micro).tracking(2).foregroundColor(.textTertiary)
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .top, spacing: FDS.Spacing.md) {
                    Image(systemName: icon).font(.system(size: 13)).foregroundColor(color)
                    Text(line).font(.system(size: 13)).foregroundColor(.textSecondary).lineSpacing(4)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(FDS.Spacing.lg).frame(maxWidth: .infinity, alignment: .leading)
        .forgeGlassCard(cornerRadius: FDS.Radius.lg, accent: .ember)
    }
}

/// Simple wrapping chip row.
struct FlowChips: View {
    let items: [(String, String, Color)]
    var body: some View {
        let cols = [GridItem(.adaptive(minimum: 110), spacing: 8)]
        LazyVGrid(columns: cols, alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: FDS.Spacing.xs) {
                    Image(systemName: item.1).font(.system(size: 10))
                    Text(item.0).font(FDS.TypeScale.Dynamic.caption)
                }
                .foregroundColor(item.2).padding(.horizontal, FDS.Spacing.md).padding(.vertical, FDS.Spacing.sm)
                .background(item.2.opacity(0.1)).cornerRadius(FDS.Radius.sm)
            }
        }
    }
}
