import SwiftUI
import ForgeCore

// ============================================================
// MARK: - Home widget board
// ============================================================

/// The cards a user can pin on Forge Home. Separate from the iOS Home
/// Screen widgets, but they show the same numbers so pinning one here
/// and adding the matching widget outside the app never disagree.
struct HomeWidgetBoard: View {
    @EnvironmentObject var store: AppStore
    @State private var pins: [HomePinnedWidgetKind] = HomeWidgetBoardStore.load()
    @State private var editing = false

    private var snapshot: HomeWidgetSnapshot {
        HomeWidgetSnapshotStore.load() ?? .preview
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("WIDGETS")
                    .forgeSectionLabel()
                Spacer()
                if !HomeWidgetBoardStore.availableToAdd(from: pins).isEmpty {
                    Menu {
                        ForEach(HomeWidgetBoardStore.availableToAdd(from: pins)) { kind in
                            Button {
                                HomeWidgetBoardStore.add(kind)
                                pins = HomeWidgetBoardStore.load()
                                FDS.haptic(.light)
                            } label: {
                                Label(kind.title, systemImage: kind.systemImage)
                            }
                        }
                    } label: {
                        Label("Add", systemImage: "plus")
                            .font(FDS.TypeScale.label(12))
                            .foregroundStyle(Color.ember)
                    }
                    .accessibilityLabel("Add a widget to Home")
                }
                Button(editing ? "Done" : "Edit") {
                    withAnimation(FDS.Spring.standard) { editing.toggle() }
                }
                .font(FDS.TypeScale.label(12))
                .foregroundStyle(Color.textSecondary)
            }

            if pins.isEmpty {
                empty
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(pins) { kind in
                        HomePinnedWidgetCard(kind: kind, snapshot: snapshot, editing: editing) {
                            HomeWidgetBoardStore.remove(kind)
                            pins = HomeWidgetBoardStore.load()
                        }
                    }
                }
            }
        }
        .onAppear { pins = HomeWidgetBoardStore.load() }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No widgets on this page")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.textPrimary)
            Text("Add Hydration, Sleep, Cycle, Workout or Lifestyle. The same cards can live on your iPhone Home Screen.")
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)
        }
        .padding(HomeMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeGlassCard(accent: Color.steel.opacity(0.4))
    }
}

private struct HomePinnedWidgetCard: View {
    @EnvironmentObject var store: AppStore
    let kind: HomePinnedWidgetKind
    let snapshot: HomeWidgetSnapshot
    let editing: Bool
    let onRemove: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: kind.systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accent)
                    Text(kind.title.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.5)
                        .foregroundColor(.textTertiary)
                    Spacer(minLength: 0)
                    if editing {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(Color.alert)
                            .onTapGesture(perform: onRemove)
                    }
                }
                content
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .forgeGlassCard(accent: accent.opacity(0.55))
        }
        .buttonStyle(.plain)
        .accessibilityHint(editing ? "Remove from Home" : "Opens \(kind.title)")
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .hydration:
            Text(formatMl(snapshot.hydrationMl))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.textPrimary)
            Text("\(Int((snapshot.hydrationFraction * 100).rounded()))% of need")
                .font(.system(size: 11))
                .foregroundColor(.textSecondary)
        case .sleep:
            Text(String(format: "%.1f h", snapshot.sleepHours))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.textPrimary)
            Text(snapshot.sleepWindowTitle ?? "Last night")
                .font(.system(size: 11))
                .foregroundColor(.textSecondary)
                .lineLimit(1)
        case .cycle:
            Text(snapshot.cyclePhase?.capitalized ?? "—")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.textPrimary)
            if let day = snapshot.cycleDay {
                Text("Day \(day)")
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
            }
        case .workout:
            Text(snapshot.workoutName ?? "No session yet")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.textPrimary)
                .lineLimit(2)
            Text(snapshot.workoutName == nil ? "Ask ARIA to build one" : "Ready when you are")
                .font(.system(size: 11))
                .foregroundColor(.textSecondary)
        case .lifestyle:
            Text("\(snapshot.qol)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.textPrimary)
            Text(snapshot.topRecommendation ?? "QOL")
                .font(.system(size: 11))
                .foregroundColor(.textSecondary)
                .lineLimit(2)
        }
    }

    private var accent: Color {
        switch kind {
        case .hydration: return Color(hex: "4A9EFF")
        case .sleep:     return .aurora
        case .cycle:     return Color(hex: "EC4899")
        case .workout:   return .ember
        case .lifestyle: return .vitality
        }
    }

    private func open() {
        guard !editing else { onRemove(); return }
        FDS.haptic(.light)
        switch kind {
        case .hydration: store.openHydration()
        case .sleep:     store.activeTab = .sleep
        case .cycle:     store.openCycleHealth(pane: "me")
        case .workout:   store.activeTab = .workout
        case .lifestyle: store.activeTab = .lifestyle
        }
    }

    private func formatMl(_ ml: Double) -> String {
        ml >= 1_000 ? String(format: "%.2f L", ml / 1_000) : "\(Int(ml.rounded())) ml"
    }
}
