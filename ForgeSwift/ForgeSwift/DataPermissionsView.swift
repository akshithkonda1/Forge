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
        "aging": ("Training age", "clock.arrow.2.circlepath"),
        "clinical_data": ("Clinical Data (Non PHI)", "pills.fill"),
    ]

    /// Domains grouped for scanning. Any domain the store adds later and this
    /// list does not name lands in the last group, so none is ever hidden.
    private var clusters: [PermissionCluster] {
        let named: [PermissionCluster] = [
            PermissionCluster(
                id: "body",
                title: "Body & recovery",
                tint: .steel,
                domains: ["sleep", "readiness", "chronotype", "body"]
            ),
            PermissionCluster(
                id: "training",
                title: "Training",
                tint: .ember,
                domains: ["training", "progress", "aging"]
            ),
            PermissionCluster(
                id: "lifestyle",
                title: "Lifestyle",
                tint: .vitality,
                domains: ["activity", "nutrition", "lifestyle"]
            ),
            PermissionCluster(
                id: "you",
                title: "You & clinical",
                tint: .indigo,
                domains: ["profile", "clinical_data"]
            ),
        ]
        let known = Set(named.flatMap { $0.domains })
        let extras = DataPermissionsStore.domains.filter { !known.contains($0) }
        let available = Set(DataPermissionsStore.domains)
        var result: [PermissionCluster] = []
        for (index, cluster) in named.enumerated() {
            var domains = cluster.domains.filter { available.contains($0) }
            if index == named.count - 1 {
                domains.append(contentsOf: extras)
            }
            if !domains.isEmpty {
                result.append(
                    PermissionCluster(id: cluster.id, title: cluster.title, tint: cluster.tint, domains: domains)
                )
            }
        }
        return result
    }

    private var allowedCount: Int {
        DataPermissionsStore.domains.filter { permissions.isAllowed($0) }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                ForgeScreenStack(top: FDS.Spacing.sm) {
                    coverageCard

                    ForEach(clusters) { cluster in
                        clusterCard(cluster)
                    }

                    syncSection
                }
            }
            .forgeScreenBackground(accent: .ember)
            .navigationTitle("Data Permissions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundColor(.ember)
                }
            }
        }
    }

    // MARK: Permissions

    /// The intro sentence over a coverage bar: how much of the list is lit.
    private var coverageCard: some View {
        let total = DataPermissionsStore.domains.count
        let allowed = allowedCount
        let fraction = total > 0 ? Double(allowed) / Double(total) : 0
        return VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("What ARIA can see", meta: "\(allowed) of \(total)", metaColor: .textSecondary, tint: .ember)
            Text("ARIA only reasons over the data you allow. Turn a domain off and it's redacted before ARIA ever sees it — never used, never inferred.")
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
            ForgeProgressBar(fraction: fraction, tint: .ember)
                .accessibilityLabel("ARIA can see \(allowed) of \(total) areas")
        }
        .forgeContentCard(accent: .ember)
    }

    private func clusterCard(_ cluster: PermissionCluster) -> some View {
        let allowed = cluster.domains.filter { permissions.isAllowed($0) }.count
        let allOn = allowed == cluster.domains.count
        return VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader(cluster.title, meta: "\(allowed) of \(cluster.domains.count) on", tint: cluster.tint)
            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                ForEach(cluster.domains, id: \.self) { domain in
                    permissionRow(domain, tint: tint(for: domain, fallback: cluster.tint))
                }
            }
            if !allOn {
                ForgeTextLink(title: "Allow all", accent: .ember) {
                    for domain in cluster.domains {
                        permissions.setAllowed(true, for: domain)
                    }
                }
                .accessibilityLabel("Allow all in \(cluster.title)")
            }
        }
        .forgeContentCard(tint: cluster.tint)
    }

    /// Agenda-row anatomy: domain-colored well, label, switch. 44 pt tall.
    private func permissionRow(_ domain: String, tint: Color) -> some View {
        let name = labels[domain]?.0 ?? domain.capitalized
        return HStack(spacing: ForgeLayout.rowGap) {
            ForgeIconWell(systemImage: labels[domain]?.1 ?? "circle.fill", tint: tint)
            Text(name)
                .font(HomeType.status)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)
                .forgeWrapping()
                .frame(maxWidth: .infinity, alignment: .leading)
            ForgeToggle(isOn: allowBinding(for: domain))
                .accessibilityLabel(name)
                .accessibilityValue(permissions.isAllowed(domain) ? "On" : "Off")
        }
        .frame(minHeight: ForgeUX.minTap)
    }

    private func tint(for domain: String, fallback: Color) -> Color {
        domain == "nutrition" ? Color.amber : fallback
    }

    // MARK: Sync

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.sectionGap) {
            ForgePrimaryButton(
                title: isSyncing ? "Syncing body model…" : "Sync body model",
                icon: isSyncing ? nil : "arrow.triangle.2.circlepath"
            ) {
                Task { await sync() }
            }
            .disabled(isSyncing)
            .opacity(isSyncing ? 0.7 : 1)

            if let syncError {
                syncNotice(syncError)
            }

            if let snapshot {
                snapshotCard(snapshot)
            } else if isSyncing {
                syncingCard
            }
        }
    }

    /// A soft network miss is information, not an error: steel, no red.
    private func syncNotice(_ message: String) -> some View {
        HStack(alignment: .top, spacing: ForgeLayout.rowGap) {
            Image(systemName: "info.circle")
                .font(.system(size: ForgeUX.icon, weight: .semibold))
                .foregroundStyle(Color.steel)
                .accessibilityHidden(true)
            Text(message)
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: ForgeUX.minTap)
        .forgeContentCard(tint: .steel, padding: ForgeLayout.compactCardPadding)
        .accessibilityElement(children: .combine)
    }

    private var syncingCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader(title: "Body Model", tint: .steel) {
                ProgressView().controlSize(.mini)
            }
            ForgeSkeletonWell(message: "Syncing body model…")
        }
        .forgeContentCard(tint: .steel)
    }

    private func snapshotCard(_ snap: BodySnapshot) -> some View {
        let estimates = snap.derived.values
            .sorted { $0.name < $1.name }
            .filter { $0.value != nil }
        return VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader(title: "Body Model", tint: .steel) {
                if isSyncing {
                    ProgressView().controlSize(.mini)
                }
            }
            Text("\(snap.observationCount) signals · \(Int(snap.confidence * 100))% confidence")
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()

            VStack(spacing: ForgeLayout.labelValueGap) {
                ForEach(estimates) { estimate in
                    ForgeMetricRow(
                        label: estimate.name.replacingOccurrences(of: "_", with: " ").capitalized,
                        value: String(format: "%.0f", estimate.value ?? 0),
                        tint: .steel,
                        detail: estimate.state
                    )
                }
            }

            if !restricted.isEmpty {
                Text("Off: \(restrictedNames)")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textTertiary)
                    .forgeWrapping()
            }
        }
        .forgeContentCard(tint: .steel)
    }

    /// Plain names for the domains ARIA could not see, not raw keys.
    private var restrictedNames: String {
        restricted.map { labels[$0]?.0 ?? $0.replacingOccurrences(of: "_", with: " ").capitalized }
            .joined(separator: ", ")
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

/// One card of related permission switches.
private struct PermissionCluster: Identifiable {
    let id: String
    let title: String
    let tint: Color
    let domains: [String]
}
