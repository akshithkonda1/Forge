import SwiftUI
import UIKit

struct ExerciseLibraryView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var muscle: TargetMuscle? = nil
    @State private var equipment: GearType? = nil
    @State private var selected: ExerciseDefinition? = nil

    private var results: [ExerciseDefinition] {
        ExerciseLibrary.filter(query: query, muscle: muscle, equipment: equipment, pattern: nil)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    searchBar
                    filterRow
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            ExerciseBodyMapView(selected: $muscle)
                            movementsHeader
                            if results.isEmpty {
                                VStack(spacing: 10) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 28))
                                        .foregroundColor(.textMuted)
                                    Text("No movements match")
                                        .font(.system(size: 15, weight: .medium, design: .rounded))
                                        .foregroundColor(.textTertiary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 36)
                            } else {
                                LazyVStack(spacing: 8) {
                                    ForEach(results) { def in
                                        libraryCard(def)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("Exercise Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.foregroundColor(.ember).fontWeight(.semibold) } }
            .sheet(item: $selected) { def in ExerciseDetailSheet(def: def) }
        }
    }

    private var movementsHeader: some View {
        HStack {
            Text(muscle.map { "\($0.label.uppercased()) · \(results.count)" } ?? "\(results.count) MOVEMENTS")
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
                Button("All muscles") {
                    FDS.haptic(.light)
                    self.muscle = nil
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.textTertiary)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 15)).foregroundColor(.textMuted)
            TextField("Search or tap a muscle…", text: $query)
                .font(.system(size: 15)).foregroundColor(.textPrimary).tint(.ember)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 15)).foregroundColor(.textMuted) }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Color.surface).cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.borderColor.opacity(0.5), lineWidth: 1))
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Button("All equipment") { equipment = nil }
                    ForEach(GearType.allCases) { e in Button(e.label) { equipment = e } }
                } label: { filterChip(equipment?.label ?? "Equipment", active: equipment != nil, color: .ember) }
                if muscle != nil || equipment != nil {
                    Button {
                        muscle = nil
                        equipment = nil
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
        Button { UIImpactFeedbackGenerator(style: .light).impactOccurred(); selected = def } label: {
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
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(def.repRangeLabel).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundColor(.textSecondary)
                    Text(def.equipment.label).font(.system(size: 10, weight: .semibold)).foregroundColor(.textMuted)
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Body map

struct ExerciseBodyMapView: View {
    @Binding var selected: TargetMuscle?
    @State private var face: BodyMapHotspot.BodyMapFace = .front

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("BODY MAP")
                        .forgeSectionLabel()
                    Text(selected?.label ?? "Tap a muscle")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(selected?.accent ?? .textPrimary)
                }
                Spacer()
                facePicker
            }

            ZStack {
                BodySilhouette(face: face)
                GeometryReader { geo in
                    ForEach(BodyMapHotspot.spots(on: face)) { spot in
                        hotspot(spot, in: geo.size)
                    }
                }
            }
            .frame(height: 340)
            .frame(maxWidth: .infinity)
            .animation(FDS.Spring.standard, value: face)
            .animation(FDS.Spring.snap, value: selected)

            extraChips
        }
        .padding(16)
        .forgeGlassCard(accent: selected?.accent)
    }

    private var facePicker: some View {
        HStack(spacing: 0) {
            ForEach(BodyMapHotspot.BodyMapFace.allCases, id: \.self) { side in
                Button {
                    FDS.selectionHaptic()
                    face = side
                } label: {
                    Text(side.label)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(face == side ? .white : .textTertiary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background {
                            if face == side {
                                Capsule().fill(FDS.Gradient.ember)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.05))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
    }

    /// One button per hotspot, sized to the capsule so a bicep tap cannot
    /// steal the calf hit target (a wrapping GeometryReader would).
    private func hotspot(_ spot: BodyMapHotspot, in size: CGSize) -> some View {
        let box = CGRect(
            x: (spot.x - spot.w / 2) * size.width,
            y: (spot.y - spot.h / 2) * size.height,
            width: spot.w * size.width,
            height: spot.h * size.height
        )
        let w = max(36, box.width)
        let h = max(28, box.height)
        return Button {
            FDS.haptic(.light)
            selected = selected == spot.muscle ? nil : spot.muscle
        } label: {
            Capsule()
                .fill(spot.muscle.accent.opacity(selected == spot.muscle ? 0.72 : 0.22))
                .overlay(
                    Capsule()
                        .stroke(
                            spot.muscle.accent.opacity(selected == spot.muscle ? 0.95 : 0.35),
                            lineWidth: selected == spot.muscle ? 1.6 : 1
                        )
                )
                .shadow(
                    color: selected == spot.muscle ? spot.muscle.accent.opacity(0.45) : .clear,
                    radius: 8,
                    y: 2
                )
        }
        .buttonStyle(.plain)
        .frame(width: w, height: h)
        .contentShape(Capsule())
        .position(x: box.midX, y: box.midY)
        .accessibilityLabel(spot.muscle.label)
        .accessibilityValue("\(ExerciseLibrary.count(matching: spot.muscle)) movements")
        .accessibilityAddTraits(selected == spot.muscle ? .isSelected : [])
        .accessibilityHint("Filters the library to this muscle")
    }

    private var extraChips: some View {
        HStack(spacing: 8) {
            ForEach(BodyMapHotspot.extraChips) { muscle in
                Button {
                    FDS.haptic(.light)
                    selected = selected == muscle ? nil : muscle
                } label: {
                    Text(muscle.label)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(selected == muscle ? .white : .textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(selected == muscle ? muscle.accent : Color.white.opacity(0.05))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(muscle.accent.opacity(selected == muscle ? 0.0 : 0.28), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct BodySilhouette: View {
    let face: BodyMapHotspot.BodyMapFace

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let cx = w * 0.5
            let fill = Color.white.opacity(0.06)
            let line = Color.white.opacity(0.10)

            ZStack {
                Capsule()
                    .fill(fill)
                    .overlay(Capsule().stroke(line, lineWidth: 1))
                    .frame(width: w * 0.16, height: h * 0.10)
                    .position(x: cx, y: h * 0.07)

                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(fill)
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(line, lineWidth: 1))
                    .frame(width: w * 0.34, height: h * 0.30)
                    .position(x: cx, y: h * 0.30)

                Capsule()
                    .fill(fill)
                    .frame(width: w * 0.12, height: h * 0.28)
                    .rotationEffect(.degrees(-18))
                    .position(x: w * 0.22, y: h * 0.32)
                Capsule()
                    .fill(fill)
                    .frame(width: w * 0.12, height: h * 0.28)
                    .rotationEffect(.degrees(18))
                    .position(x: w * 0.78, y: h * 0.32)

                Capsule()
                    .fill(fill)
                    .frame(width: w * 0.14, height: h * 0.36)
                    .position(x: w * 0.40, y: h * 0.68)
                Capsule()
                    .fill(fill)
                    .frame(width: w * 0.14, height: h * 0.36)
                    .position(x: w * 0.60, y: h * 0.68)

                if face == .back {
                    Capsule()
                        .fill(Color.white.opacity(0.04))
                        .frame(width: 3, height: h * 0.22)
                        .position(x: cx, y: h * 0.32)
                }
            }
        }
        .allowsHitTesting(false)
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
        }
    }

    private func addToPlan() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
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
