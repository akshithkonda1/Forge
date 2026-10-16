import SwiftUI
import ForgeCore

struct ChatEmptyStateView: View {
    let mood: ARIAMood
    let onQuickActionTap: (String) -> Void
    var onVoiceTap: (() -> Void)? = nil
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Greeting message varies by mood
    private var greeting: String {
        let first = store.userProfile.name.components(separatedBy: " ").first ?? ""
        let who = first.isEmpty ? "" : ", \(first)"
        switch mood {
        case .energized: return "The window's open\(who).\nWant to step through it?"
        case .focused:   return "I'm already listening\(who).\nYou don't have to know what to ask."
        case .calm:      return "Quiet has a shape tonight\(who).\nWe can stay inside it."
        case .pushed:    return "I felt that.\nWe don't have to name it yet."
        }
    }

    private var subtext: String {
        let life = AriaLifeRead.from(tags: AriaContextStore.shared.context.lifestyleTags)
        if let story = life.story, !story.isEmpty { return story }
        switch mood {
        case .energized: return "You've got a window. We can train if you want."
        case .focused:   return "I'll use last night and today's load — just talk."
        case .calm:      return "Recovery is part of training. We can keep it light."
        case .pushed:    return "We go at your pace. No pressure."
        }
    }

    private var prompts: [(title: String, icon: String)] {[
        ("Who are you?", "person.crop.circle"),
        ("How did I sleep?", "moon.fill"),
        ("What should I train?", "figure.strengthtraining.traditional"),
        ("How do I show up?", "heart.fill"),
    ]}

    var body: some View {
        VStack(spacing: ForgeLayout.sectionGap) {
            heroBlock

            if let onVoiceTap {
                ForgePrimaryButton(title: "Talk to ARIA", icon: "waveform") {
                    onVoiceTap()
                }
            }

            promptsCard
        }
        .padding(.horizontal, ForgeLayout.screenInset)
        .padding(.top, FDS.Spacing.lg)
        .padding(.bottom, ForgeLayout.scrollBottomClearance)
        .frame(maxWidth: .infinity)
    }

    // MARK: Hero

    private var heroBlock: some View {
        VStack(spacing: ForgeLayout.blockGap) {
            orb
            VStack(spacing: ForgeLayout.rowGap) {
                Text(greeting)
                    .font(ForgeType.pageTitle)
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .forgeWrapping()
                    .accessibilityAddTraits(.isHeader)

                Text(subtext)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .forgeWrapping()
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// ARIA's mark: small, flat, no halo. The words below carry the moment.
    private var orb: some View {
        AuroraOrbView(
            state: .idle,
            amplitude: 0.32,
            mood: mood,
            size: 64,
            followPresence: true
        )
        .environment(\.forgeMinimalAnimation, reduceMotion)
        .accessibilityHidden(true)
    }

    // MARK: Prompts

    private var promptsCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader(title: "OR BEGIN HERE") {
                Text(mood.displayName.lowercased())
                    .font(HomeType.micro)
                    .foregroundStyle(mood.accentColor)
                    .lineLimit(1)
            }

            VStack(spacing: ForgeLayout.rowGap) {
                ForEach(Array(prompts.enumerated()), id: \.offset) { _, prompt in
                    promptRow(prompt)
                }
            }
        }
        .forgeContentCard()
    }

    private func promptRow(_ prompt: (title: String, icon: String)) -> some View {
        Button {
            ForgeHaptics.play(.press)
            onQuickActionTap(prompt.title)
        } label: {
            ForgeListRow(
                icon: prompt.icon,
                iconColor: mood.accentColor,
                title: prompt.title,
                showChevron: true
            )
        }
        .buttonStyle(ForgePressStyle())
    }
}
