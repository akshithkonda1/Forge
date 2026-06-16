import SwiftUI

/// Debug / power-user sheet — shows the living context ARIA reasons over.
struct ContextInspectorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var contextStore: AriaContextStore
    let richContext: AriaRichContext

    var body: some View {
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        relationshipCard
                        tagSection(title: "Goals", items: richContext.goals, icon: "target")
                        tagSection(title: "Lifestyle", items: richContext.lifestyleTags, icon: "leaf.fill")
                        tagSection(title: "Constraints", items: richContext.constraints, icon: "exclamationmark.shield.fill")
                        tagSection(title: "Patterns", items: richContext.recentPatterns, icon: "waveform.path.ecg")
                        insightsSection
                        metricsSection
                    }
                    .padding(16)
                }
            }
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

    private var relationshipCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Relationship")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.textSecondary)
            HStack {
                Text("Level \(contextStore.context.relationshipLevel)/10")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.steel)
                Spacer()
                Text(contextStore.context.relationshipLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textTertiary)
            }
            ProgressView(value: Double(contextStore.context.relationshipLevel), total: 10)
                .tint(.steel)
        }
        .padding(16)
        .background(Color.surface)
        .cornerRadius(16)
    }

    private func tagSection(title: String, items: [String], icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.textPrimary)
            if items.isEmpty {
                Text("None yet — ARIA learns as you interact.")
                    .font(.system(size: 12))
                    .foregroundColor(.textTertiary)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(items, id: \.self) { item in
                        Text(item)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.surfaceElevated)
                            .cornerRadius(10)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.surface)
        .cornerRadius(16)
    }

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Recent Insights", systemImage: "lightbulb.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.textPrimary)
            if contextStore.context.lastInsights.isEmpty {
                Text("No insights stored yet.")
                    .font(.system(size: 12))
                    .foregroundColor(.textTertiary)
            } else {
                ForEach(contextStore.context.lastInsights.prefix(5), id: \.self) { insight in
                    Text(insight)
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)
                        .padding(.vertical, 4)
                }
            }
        }
        .padding(16)
        .background(Color.surface)
        .cornerRadius(16)
    }

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Live Metrics", systemImage: "heart.text.square.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.textPrimary)
            ForEach(richContext.recentMetrics.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                HStack {
                    Text(key.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                    Spacer()
                    Text(String(format: "%.0f", value))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.textPrimary)
                }
            }
            Text("Updated \(richContext.timestamp)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.textTertiary)
                .padding(.top, 4)
        }
        .padding(16)
        .background(Color.surface)
        .cornerRadius(16)
    }
}