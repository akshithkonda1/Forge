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

    var body: some View {
        NavigationStack {
            content
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
            Section {
                HStack {
                    Spacer()
                    StandByNestFaceView(
                        snapshot: snapshot,
                        date: .now,
                        metrics: metrics,
                        nightMode: previewNightMode
                    )
                    .padding(20)
                    .frame(width: 172, height: 172)
                    .background(Color(forgeHex: AriaNestGeometry.StandBy.nightstandBackgroundHex))
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    Spacer()
                }
                .listRowBackground(Color.clear)
                .padding(.vertical, 8)

                Toggle("Preview night mode", isOn: $previewNightMode)
                    .font(.system(size: 14))
            } header: {
                Text("Preview")
            } footer: {
                Text("This is the same face WidgetKit renders on your nightstand. Add the widget to StandBy from the widget gallery once, and it stays in sync with what you pick here.")
            }

            Section {
                if metrics.isEmpty {
                    Text("Just Readiness and the clock.")
                        .font(.system(size: 14))
                        .foregroundColor(.textSecondary)
                } else {
                    ForEach(metrics) { metric in
                        Label(metric.title, systemImage: metric.systemImage)
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
                Text("On StandBy")
            } footer: {
                Text("Readiness always shows — it's the hero number. Drag to reorder, swipe to remove.")
            }

            if !available.isEmpty {
                Section("Available") {
                    ForEach(available) { metric in
                        Button {
                            metrics.append(metric)
                            StandByMetricsStore.save(metrics)
                        } label: {
                            Label(metric.title, systemImage: metric.systemImage)
                        }
                    }
                }
            }
        }
    }
}
