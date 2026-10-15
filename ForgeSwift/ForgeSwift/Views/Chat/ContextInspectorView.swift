import SwiftUI

/// Debug / power-user sheet — shows the living context ARIA reasons over.
struct ContextInspectorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var contextStore: AriaContextStore
    let richContext: AriaRichContext

    private static let levelCount = 10

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: ForgeLayout.sectionGap) {
                    relationshipCard
                    chipSection(title: "Goals", items: richContext.goals)
                    chipSection(title: "Lifestyle", items: richContext.lifestyleTags)
                    chipSection(title: "Constraints", items: richContext.constraints)
                    listSection(title: "Patterns", items: richContext.recentPatterns)
                    listSection(
                        title: "Clinical Data (Non PHI)",
                        items: HealthKitManager.shared.clinicalSummary?.ariaConstraintLines() ?? []
                    )
                    insightsSection
                    metricsSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .forgeScreenInsets(top: FDS.Spacing.lg)
            }
            .forgeScreenBackground(accent: .steel)
            .navigationTitle("ARIA Context")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.steel)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: Relationship

    private var level: Int {
        min(max(contextStore.context.relationshipLevel, 0), Self.levelCount)
    }

    private var relationshipCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader(
                "Relationship",
                meta: contextStore.context.relationshipLabel,
                metaColor: .textTertiary
            )
            HStack(alignment: .firstTextBaseline, spacing: ForgeLayout.pairGap) {
                Text("Level \(level)")
                    .font(HomeType.metric)
                    .foregroundColor(.textPrimary)
                    .forgeSingleLine()
                Text("/\(Self.levelCount)")
                    .font(HomeType.label)
                    .foregroundColor(.textTertiary)
                    .forgeSingleLine()
            }
            levelBar
        }
        .forgeContentCard(accent: .steel)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Relationship, level \(level) of \(Self.levelCount), \(contextStore.context.relationshipLabel)")
    }

    /// Ten capsules, one per level, filled up to the current one.
    private var levelBar: some View {
        HStack(spacing: ForgeLayout.pairGap) {
            ForEach(0..<Self.levelCount, id: \.self) { index in
                Capsule()
                    .fill(index < level ? Color.steel : Color.white.opacity(0.08))
                    .frame(height: 6)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Tag sections

    private var emptyTagsNote: some View {
        ForgeEmptyNote(title: "None yet — ARIA learns as you interact.")
    }

    /// Short labels read best as chips.
    private func chipSection(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader(title)
            if items.isEmpty {
                emptyTagsNote
            } else {
                ForgeFlowLayout {
                    ForEach(items, id: \.self) { item in
                        ForgeChip(label: item)
                    }
                }
            }
        }
        .forgeContentCard(tint: .steel)
    }

    /// Longer lines wrap as rows instead of truncating inside a chip.
    private func listSection(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader(title)
            if items.isEmpty {
                emptyTagsNote
            } else {
                VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                    ForEach(items, id: \.self) { item in
                        ForgeBulletRow(text: item, tint: .steel)
                    }
                }
            }
        }
        .forgeContentCard(tint: .steel)
    }

    // MARK: Insights + metrics

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("Recent Insights")
            if contextStore.context.lastInsights.isEmpty {
                ForgeEmptyNote(title: "No insights stored yet.")
            } else {
                VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                    ForEach(contextStore.context.lastInsights.prefix(5), id: \.self) { insight in
                        ForgeBulletRow(text: insight, tint: .steel)
                    }
                }
            }
        }
        .forgeContentCard(tint: .steel)
    }

    private var sortedMetrics: [(key: String, value: Double)] {
        richContext.recentMetrics.sorted(by: { $0.key < $1.key }).map { (key: $0.key, value: $0.value) }
    }

    /// Whole numbers stay whole; fractions (7.5 hours of sleep) keep one place.
    private func formattedMetric(_ value: Double) -> String {
        value.rounded() == value ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("Live Metrics")
            VStack(alignment: .leading, spacing: ForgeLayout.labelValueGap) {
                ForEach(sortedMetrics, id: \.key) { metric in
                    ForgeMetricRow(
                        label: metric.key.replacingOccurrences(of: "_", with: " ").capitalized,
                        value: formattedMetric(metric.value)
                    )
                }
            }
            Text("Updated \(richContext.timestamp)")
                .font(HomeType.micro)
                .foregroundColor(.textTertiary)
                .forgeWrapping()
        }
        .forgeContentCard(tint: .steel)
    }
}
