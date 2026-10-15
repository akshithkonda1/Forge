import SwiftUI
import ForgeCore

/// Long-press avatar → what ARIA used, what was redacted, which habit it's on.
/// Grounded transparency, not a debug dump.
struct ContextInspectorSheet: View {
    @ObservedObject var aria = AriaContextStore.shared
    @ObservedObject var permissions = DataPermissionsStore.shared
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                ForgeScreenStack {
                    ForgePageHeader(
                        title: "What ARIA sees",
                        subtitle: "Long-press friendly — what was used, what was off, and which habit ARIA is on.",
                        accent: .steel
                    )

                    usedSection
                    if !permissions.restrictedDomains.isEmpty {
                        redactedSection
                    }
                    habitSection
                    relationshipSection
                }
            }
            .forgeScreenBackground(accent: .steel)
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

    // MARK: Used signals

    private var usedSection: some View {
        InspectorSection(title: "Used", color: .vitality) {
            if aria.context.lifestyleTags.isEmpty && aria.context.recentPatterns.isEmpty {
                ForgeEmptyNote(title: "No strong signals yet — ARIA is asking, not guessing.")
            } else {
                VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                    ForEach(Array(aria.context.lifestyleTags.prefix(6)), id: \.self) { tag in
                        InspectorRow(text: tag, color: .vitality)
                    }
                    ForEach(Array(aria.context.recentPatterns.prefix(4)), id: \.self) { pat in
                        InspectorRow(text: pat, color: .steel)
                    }
                }
            }
        }
    }

    // MARK: Redacted (permissions)

    private var redactedSection: some View {
        InspectorSection(title: "Off — redacted before reasoning", color: .steel) {
            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                ForEach(permissions.restrictedDomains, id: \.self) { domain in
                    InspectorRow(text: "\(domain) is off (permission) — never sent", color: .steel)
                }
                Text("Off ≠ missing. ARIA says so explicitly.")
                    .font(HomeType.body)
                    .foregroundColor(.textTertiary)
                    .forgeWrapping()
            }
        }
    }

    // MARK: Deep habit ARIA is on

    private var habitSection: some View {
        InspectorSection(title: "Habit ARIA is breaking", color: .ember) {
            if let habit = aria.context.deepHabits.first {
                VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                    Text(habit.title)
                        .font(HomeType.status)
                        .foregroundColor(.textPrimary)
                        .forgeWrapping()
                    habitLine(label: "Cue", value: habit.cue)
                    habitLine(label: "Routine", value: habit.routine)
                    habitLine(label: "Cost", value: habit.cost)
                    Text(habit.evidence)
                        .font(HomeType.micro)
                        .foregroundColor(.textTertiary)
                        .forgeWrapping()
                    Text("Breaker: \(habit.breaker)")
                        .font(HomeType.body)
                        .foregroundColor(.ember)
                        .forgeWrapping()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .forgeWell()
                }
            } else {
                ForgeEmptyNote(title: "No strong loop detected — signals look balanced.")
            }
        }
    }

    /// Micro label over a body sentence.
    private func habitLine(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
            Text(label)
                .font(HomeType.micro)
                .foregroundColor(.textTertiary)
                .textCase(.uppercase)
            Text(value)
                .font(HomeType.body)
                .foregroundColor(.textSecondary)
                .forgeWrapping()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Relationship + constraints

    private var relationshipSection: some View {
        InspectorSection(title: "How ARIA knows you", color: .steel) {
            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                InspectorRow(text: "Level \(aria.context.relationshipLevel)/10 — \(aria.context.relationshipLabel)", color: .steel)
                if !aria.context.constraints.isEmpty {
                    ForEach(Array(aria.context.constraints.prefix(4)), id: \.self) { c in
                        InspectorRow(text: c, color: .textTertiary)
                    }
                }
            }
        }
    }
}

/// Standard card: wrapping eyebrow, then the body at the block gap. The card
/// is washed in the section's domain color; there is no halo.
private struct InspectorSection<Content: View>: View {
    let title: String; let color: Color; let content: Content
    init(title: String, color: Color, @ViewBuilder content: () -> Content) {
        self.title = title; self.color = color; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            Text(title)
                .forgeSectionLabel(tint: .textTertiary)
                .forgeWrapping()
                .accessibilityAddTraits(.isHeader)
            content
        }
        .forgeContentCard(tint: color)
    }
}

private struct InspectorRow: View {
    let text: String; let color: Color
    var body: some View {
        ForgeBulletRow(text: text, tint: color)
    }
}
