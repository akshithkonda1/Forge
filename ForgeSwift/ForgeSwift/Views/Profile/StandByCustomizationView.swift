import SwiftUI
import ForgeCore

/// Lets the user pick and reorder which rows show on the iPhone StandBy
/// face, with a live preview built from `StandByNestFaceView` — the exact
/// same view WidgetKit renders in real StandBy, so what's shown here is
/// what will actually appear, not an approximation.
struct StandByCustomizationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var metrics: [StandByMetricKind] = StandByMetricsStore.load()
    @State private var previewNightMode = false

    private var snapshot: HomeWidgetSnapshot {
        HomeWidgetSnapshotStore.load() ?? .preview
    }

    private var available: [StandByMetricKind] {
        StandByMetricKind.allCases.filter { !metrics.contains($0) }
    }

    private var rowFill: Color { Color.white.opacity(0.06) }

    var body: some View {
        NavigationStack {
            content
                .scrollContentBackground(.hidden)
                .forgeScreenBackground(accent: .ember)
                .navigationTitle("StandBy")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) { EditButton() }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }

    private var content: some View {
        List {
            previewSection
            onStandBySection
            if !available.isEmpty {
                availableSection
            }
        }
    }

    // MARK: Sections

    private var previewSection: some View {
        Section {
            HStack {
                Spacer()
                StandByNestFaceView(
                    snapshot: snapshot,
                    date: .now,
                    metrics: metrics,
                    nightMode: previewNightMode
                )
                .padding(FDS.Spacing.lg)
                .frame(width: 172, height: 172)
                .background(Color(forgeHex: AriaNestGeometry.StandBy.nightstandBackgroundHex))
                .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.xxl, style: .continuous))
                Spacer()
            }
            .listRowBackground(Color.clear)
            .padding(.vertical, ForgeLayout.rowGap)

            Toggle(isOn: $previewNightMode) {
                Text("Preview night mode")
                    .font(HomeType.status)
                    .foregroundStyle(Color.textPrimary)
            }
            .tint(Color.ember)
            .frame(minHeight: ForgeUX.minTap)
            .listRowBackground(rowFill)
        } header: {
            sectionTitle("Preview")
        } footer: {
            sectionNote("This is the same face WidgetKit renders on your nightstand. Add the widget to StandBy from the widget gallery once, and it stays in sync with what you pick here.")
        }
    }

    private var onStandBySection: some View {
        Section {
            if metrics.isEmpty {
                ForgeEmptyNote(
                    title: "Just Readiness and the clock.",
                    systemImage: "clock"
                )
                .padding(.vertical, ForgeLayout.rowVerticalPadding)
                .listRowBackground(rowFill)
            } else {
                ForEach(metrics) { metric in
                    ForgeListRow(
                        icon: metric.systemImage,
                        iconColor: .ember,
                        title: metric.title
                    )
                    .padding(.vertical, ForgeLayout.rowVerticalPadding)
                    .listRowBackground(rowFill)
                }
                .onMove { indices, newOffset in
                    metrics.move(fromOffsets: indices, toOffset: newOffset)
                    StandByMetricsStore.save(metrics)
                }
                .onDelete { indices in
                    metrics.remove(atOffsets: indices)
                    StandByMetricsStore.save(metrics)
                }
            }
        } header: {
            sectionTitle("On StandBy")
        } footer: {
            sectionNote("Readiness always shows — it's the hero number. Drag to reorder, swipe to remove.")
        }
    }

    private var availableSection: some View {
        Section {
            ForEach(available) { metric in
                Button {
                    FDS.haptic(.press)
                    metrics.append(metric)
                    StandByMetricsStore.save(metrics)
                } label: {
                    availableLabel(metric)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(metric.title)
                .accessibilityHint("Adds it to StandBy")
                .listRowBackground(rowFill)
            }
        } header: {
            sectionTitle("Available")
        }
    }

    private func availableLabel(_ metric: StandByMetricKind) -> some View {
        HStack(spacing: ForgeLayout.rowGap) {
            ForgeIconWell(systemImage: metric.systemImage, tint: .ember)
            Text(metric.title)
                .font(HomeType.status)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)
                .layoutPriority(1)
            Spacer(minLength: FDS.Spacing.xs)
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(Color.ember)
                .accessibilityHidden(true)
        }
        .padding(.vertical, ForgeLayout.rowVerticalPadding)
        .frame(minHeight: ForgeUX.minTap)
        .contentShape(Rectangle())
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .forgeSectionLabel(tint: Color.textTertiary)
    }

    private func sectionNote(_ text: String) -> some View {
        Text(text)
            .font(HomeType.body)
            .foregroundStyle(Color.textSecondary)
            .textCase(nil)
            .forgeWrapping()
            .padding(.top, ForgeLayout.pairGap)
    }
}
