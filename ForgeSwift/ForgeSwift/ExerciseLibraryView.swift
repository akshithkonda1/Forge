import SwiftUI

struct ExerciseLibraryView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var muscle: TargetMuscle? = nil
    @State private var equipment: GearType? = nil
    @State private var pattern: MovementPattern? = nil
    @State private var organize: ExerciseLibrary.OrganizeBy = .region
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
                    organizeRow
                    filterRow
                    if sections.isEmpty {
                        ContentUnavailableView {
                            Label("No movements match", systemImage: "magnifyingglass")
                        } description: {
                            Text("Try a different search or clear a filter.")
                        }
                        .foregroundStyle(Color.textTertiary)
                    } else {
                        ScrollView(showsIndicators: false) {
                            LazyVStack(alignment: .leading, spacing: 18, pinnedViews: [.sectionHeaders]) {
                                HStack {
                                    Text("\(resultCount) MOVEMENTS · \(sections.count) GROUPS")
                                        .forgeSectionLabel()
                                    Spacer()
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
                                .padding(.horizontal, 4)

                                ForEach(sections) { section in
                                    librarySection(section)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 40)
                        }
                    }
                }
            }
            .navigationTitle("Exercise Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.foregroundColor(.ember).fontWeight(.semibold) } }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Movements, muscles, gear")
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .sensoryFeedback(.selection, trigger: organize)
            .sheet(item: $selected) { def in ExerciseDetailSheet(def: def) }
        }
    }

    private func librarySection(_ section: ExerciseLibrary.Section) -> some View {
        let open = !collapsed.contains(section.id)
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                FDS.selectionHaptic()
                if open { collapsed.insert(section.id) } else { collapsed.remove(section.id) }
            } label: {
                HStack(spacing: 10) {
                    Circle().fill(section.accent).frame(width: 8, height: 8)
                    Text(section.title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text("\(section.items.count)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.textMuted)
                        .padding(.horizontal, 8)
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

            if open {
                ForEach(section.items) { def in
                    libraryCard(def)
                }
            }
        }
    }

    private var organizeRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("GROUP")
                    .forgeSectionLabel()
                ForEach(ExerciseLibrary.OrganizeBy.allCases) { mode in
                    Button {
                        FDS.selectionHaptic()
                        organize = mode
                    } label: {
                        Text(mode.label)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(organize == mode ? .white : .textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(organize == mode ? Color.ember : Color.surface)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
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
                } label: { filterChip(pattern?.label ?? "Pattern", active: pattern != nil, color: Color(hex: "A855F7")) }
                if muscle != nil || equipment != nil || pattern != nil {
                    Button {
                        muscle = nil
                        equipment = nil
                        pattern = nil
                    } label: {
                        HStack(spacing: 4) { Image(systemName: "xmark"); Text("Clear") }
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.danger)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.danger.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    private func filterChip(_ text: String, active: Bool, color: Color) -> some View {
        HStack(spacing: 5) {
            Text(text).font(.system(size: 13, weight: .semibold))
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
        }
        .foregroundColor(active ? .white : .textSecondary)
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(active ? color : Color.surface).cornerRadius(100)
        .overlay(Capsule().stroke(active ? color : Color.borderColor.opacity(0.5), lineWidth: 1))
    }

    private func libraryCard(_ def: ExerciseDefinition) -> some View {
        HStack(spacing: 10) {
            Button {
                FDS.haptic(.light)
                selected = def
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(LinearGradient(colors: [def.accent.opacity(0.2), def.accent.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 46, height: 46)
                        Image(systemName: def.icon).font(.system(size: 18, weight: .semibold)).foregroundColor(def.accent)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(def.name).font(.system(size: 15, weight: .semibold)).foregroundColor(.textPrimary).lineLimit(1)
                        Text(def.muscleSummary).font(.system(size: 12)).foregroundColor(.textTertiary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(def.repRangeLabel).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundColor(.textSecondary)
                        Text(def.equipment.label).font(.system(size: 10, weight: .semibold)).foregroundColor(.textMuted)
                    }
                }
            }
            .buttonStyle(.plain)

            Button {
                FDS.haptic(.medium)
                selected = def
                AriaPresence.shared.speak(ExerciseLibrary.howToScript(for: def))
            } label: {
                VStack(spacing: 4) {
                    ARIAIdentityMark(state: .speaking, mood: .energized, size: 22, amplitude: 0.4)
                    Text("How")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                }
                .foregroundColor(.ember)
                .frame(width: 48)
                .padding(.vertical, 8)
                .background(Color.ember.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("ARIA, show me how to do \(def.name)")
        }
        .padding(12)
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
                    VStack(alignment: .leading, spacing: 20) {
                        // Hero
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(LinearGradient(colors: [def.accent.opacity(0.25), def.accent.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 64, height: 64)
                                Image(systemName: def.icon).font(.system(size: 26, weight: .bold)).foregroundColor(def.accent)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(def.pattern.label.uppercased()).font(.system(size: 10, weight: .black)).tracking(1.5).foregroundColor(def.accent)
                                Text(def.name).font(.system(size: 22, weight: .bold)).foregroundColor(.textPrimary)
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
                            (def.level.label, "chart.bar.fill", Color(hex: "A855F7")),
                            (def.equipment.label, def.equipment.icon, .success),
                        ])
                        // Cues
                        if !def.cues.isEmpty { sectionCard("EXECUTION", icon: "checkmark.seal.fill", color: def.accent, lines: def.cues) }
                        if !def.faults.isEmpty { sectionCard("COMMON FAULTS", icon: "exclamationmark.triangle.fill", color: .warning, lines: def.faults) }
                        if !def.note.isEmpty {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "brain.head.profile").font(.system(size: 14)).foregroundColor(.ember)
                                Text(def.note).font(.system(size: 13, design: .serif).italic()).foregroundColor(.textSecondary).lineSpacing(4)
                            }
                            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.ember.opacity(0.06)).cornerRadius(16)
                        }
                        if !def.substitutes.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("ARIA SWAPS").font(.system(size: 10, weight: .black)).tracking(2).foregroundColor(.textTertiary)
                                ForEach(def.substitutes, id: \.self) { s in
                                    HStack(spacing: 8) {
                                        Image(systemName: "arrow.triangle.swap").font(.system(size: 12)).foregroundColor(.steel)
                                        Text(s).font(.system(size: 13)).foregroundColor(.textSecondary)
                                    }
                                }
                            }
                            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.surface).cornerRadius(16)
                        }
                        Button {
                            FDS.haptic(.medium)
                            AriaPresence.shared.speak(ExerciseLibrary.howToScript(for: def))
                        } label: {
                            HStack(spacing: 10) {
                                ARIAIdentityMark(state: .speaking, mood: .energized, size: 28, amplitude: 0.5)
                                Text("ARIA, show me how")
                                    .font(.system(size: 16, weight: .bold))
                            }
                            .foregroundColor(.white).frame(maxWidth: .infinity).frame(height: 54)
                            .background(Color.ember.opacity(0.85)).cornerRadius(16)
                        }
                        Button {
                            FDS.haptic(.light)
                            dismiss()
                            store.showHowToPerform(def.name, speakLocally: false, openChat: true)
                        } label: {
                            Text("Ask ARIA in chat")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.ember)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        // Add
                        Button {
                            addToPlan()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: added ? "checkmark.circle.fill" : "plus.circle.fill").font(.system(size: 18, weight: .bold))
                                Text(added ? "Added to today" : store.todayWorkout == nil ? "Start a plan with this" : "Add to today's workout").font(.system(size: 16, weight: .bold))
                            }
                            .foregroundColor(.white).frame(maxWidth: .infinity).frame(height: 54)
                            .background(added ? Color.success : def.accent).cornerRadius(16)
                            .shadow(color: (added ? Color.success : def.accent).opacity(0.4), radius: 14, y: 6)
                        }
                        .disabled(added)
                    }
                    .padding(20).padding(.bottom, 40)
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
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 10, weight: .black)).tracking(2).foregroundColor(.textTertiary)
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: icon).font(.system(size: 13)).foregroundColor(color)
                    Text(line).font(.system(size: 13)).foregroundColor(.textSecondary).lineSpacing(4)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface).cornerRadius(16)
    }
}

/// Simple wrapping chip row.
struct FlowChips: View {
    let items: [(String, String, Color)]
    var body: some View {
        let cols = [GridItem(.adaptive(minimum: 110), spacing: 8)]
        LazyVGrid(columns: cols, alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 5) {
                    Image(systemName: item.1).font(.system(size: 10))
                    Text(item.0).font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(item.2).padding(.horizontal, 10).padding(.vertical, 8)
                .background(item.2.opacity(0.1)).cornerRadius(9)
            }
        }
    }
}
