import SwiftUI

/// ARIA's daily story: a short cross-source narrative plus the actionable
/// insights it was built from. Backed by `AriaContextStore.lastDailyStory`,
/// which `/ai/observe` refreshes on its own 18-24h cadence — this view just
/// renders whatever is currently cached and stays hidden until a first one
/// exists.
struct TodaysStoryCard: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject private var ariaContext = AriaContextStore.shared

    var body: some View {
        if let story = ariaContext.lastDailyStory {
            content(for: story)
        }
    }

    private func content(for story: DailyStoryPayload) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            HStack(spacing: FDS.Spacing.sm) {
                Image(systemName: "book.pages.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.aurora)
                    .accessibilityHidden(true)
                Text("TODAY'S STORY")
                    .forgeSectionLabel(tint: Color.aurora)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }

            Text(story.narrative)
                .font(HomeType.body)
                .foregroundColor(.textPrimary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            if !story.insights.isEmpty {
                VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                    ForEach(Array(story.insights.enumerated()), id: \.offset) { _, insight in
                        insightRow(insight)
                    }
                }
            }

            if !story.sources.isEmpty {
                Text("From " + story.sources.map(sourceLabel).joined(separator: ", "))
                    .font(HomeType.micro)
                    .foregroundColor(.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(HomeMetrics.cardPadding)
        .forgeGlassCard(accent: Color.aurora)
    }

    private func insightRow(_ insight: DailyStoryInsight) -> some View {
        Button {
            FDS.haptic(.press)
            HomeInsightFlow.open(insight.text, store: store)
        } label: {
            HStack(spacing: ForgeLayout.rowGap) {
                ForgeIconWell(systemImage: domainIcon(insight.domain), tint: Color.aurora, diameter: 28)
                Text(insight.text)
                    .font(HomeType.body)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textMuted)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, ForgeLayout.rowVerticalPadding)
            .frame(minHeight: ForgeUX.minTap)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(insight.text)
        .accessibilityHint("Opens the related screen")
    }

    private func domainIcon(_ domain: String) -> String {
        switch domain {
        case "aging": return "hourglass"
        case "readiness": return "waveform.path.ecg"
        case "activity": return "figure.walk"
        case "sleep": return "moon.stars.fill"
        default: return "sparkles"
        }
    }

    private func sourceLabel(_ source: String) -> String {
        switch source {
        case "apple-health": return "Apple Health"
        default: return source.prefix(1).uppercased() + source.dropFirst()
        }
    }
}
