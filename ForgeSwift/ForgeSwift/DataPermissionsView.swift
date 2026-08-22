import SwiftUI
import ForgeCore

/// Per-domain control over what ARIA may use, plus a one-tap body-model sync
/// that calls POST /ai/observe and shows the fused result.
struct DataPermissionsView: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject private var permissions = DataPermissionsStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var snapshot: BodySnapshot?
    @State private var restricted: [String] = []
    @State private var isSyncing = false
    @State private var syncError: String?

    private let labels: [String: (String, String)] = [
        "sleep": ("Sleep", "moon.fill"),
        "readiness": ("Readiness & HRV", "bolt.heart.fill"),
        "activity": ("Activity", "figure.walk"),
        "training": ("Training", "dumbbell.fill"),
        "chronotype": ("Sleep Timing", "clock.fill"),
        "body": ("Body Metrics", "scalemass.fill"),
        "nutrition": ("Nutrition", "fork.knife"),
        "profile": ("Goals & Profile", "person.fill"),
        "progress": ("Progress", "chart.line.uptrend.xyaxis"),
        "lifestyle": ("Lifestyle & Patterns", "sparkles"),
        "clinical_data": ("Clinical Data (Non PHI)", "pills.fill"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("ARIA only reasons over the data you allow. Turn a domain off and it's redacted before ARIA ever sees it — never used, never inferred.")
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)
                        .padding(.top, 4)

                    VStack(spacing: 0) {
                        ForEach(Array(DataPermissionsStore.domains.enumerated()), id: \.element) { index, domain in
                            if index > 0 { Divider().background(Color.borderColor) }
                            Toggle(isOn: allowBinding(for: domain)) {
                                HStack(spacing: 12) {
                                    Image(systemName: labels[domain]?.1 ?? "circle.fill")
                                        .font(.system(size: 15))
                                        .foregroundColor(.ember)
                                        .frame(width: 24)
                                    Text(labels[domain]?.0 ?? domain.capitalized)
                                        .font(.system(size: 15))
                                        .foregroundColor(.textPrimary)
                                }
                            }
                            .tint(.ember)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                    }
                    .background(Color.surface)
                    .cornerRadius(16)

                    syncSection
                }
                .padding(16)
            }
            .background(Color.background.ignoresSafeArea())
            .navigationTitle("Data Permissions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundColor(.ember)
                }
            }
        }
    }

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                Task { await sync() }
            } label: {
                HStack(spacing: 8) {
                    if isSyncing { ProgressView().tint(.white) }
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text(isSyncing ? "Syncing body model…" : "Sync body model")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(LinearGradient.emberGradient)
                .cornerRadius(14)
            }
            .disabled(isSyncing)

            if let syncError {
                Text(syncError).font(.system(size: 12)).foregroundColor(.danger)
            }

            if let snapshot {
                snapshotCard(snapshot)
            }
        }
    }

    private func snapshotCard(_ snap: BodySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Body Model")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.textPrimary)
            Text("\(snap.observationCount) signals · \(Int(snap.confidence * 100))% confidence")
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)

            ForEach(snap.derived.values.sorted { $0.name < $1.name }) { estimate in
                if let value = estimate.value {
                    HStack {
                        Text(estimate.name.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.system(size: 13))
                            .foregroundColor(.textSecondary)
                        Spacer()
                        Text("\(value, specifier: "%.0f") · \(estimate.state)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.textPrimary)
                    }
                }
            }

            if !restricted.isEmpty {
                Text("Off: \(restricted.joined(separator: ", "))")
                    .font(.system(size: 11))
                    .foregroundColor(.textTertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface)
        .cornerRadius(16)
    }

    private func allowBinding(for domain: String) -> Binding<Bool> {
        Binding(
            get: { permissions.isAllowed(domain) },
            set: { permissions.setAllowed($0, for: domain) }
        )
    }

    private func sync() async {
        isSyncing = true
        syncError = nil
        defer { isSyncing = false }
        do {
            let response = try await AriaService.shared.observe(store: store)
            snapshot = response.snapshot
            restricted = response.restrictedDomains ?? []
        } catch {
            syncError = "Couldn't reach ARIA — showing local state only."
        }
    }
}
