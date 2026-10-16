import SwiftUI
import ForgeCore

/// Dedicated page for “conceiving is taking longer” — options and specialists,
/// not a chat dump and not a clinic.
struct DifficultyConceivingGuideView: View {
    var onAskARIA: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .subheadline) private var stepBadgeSize: CGFloat = 22

    private var stepBadgeDiameter: CGFloat {
        ForgeLayout.scaledCap(stepBadgeSize, base: 22)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ForgeLayout.sectionGap) {
                    intro
                    stepsCard
                    specialistsCard
                    ForgePrimaryButton(
                        title: "Ask ARIA to walk this with me",
                        icon: "heart.text.square",
                        accent: .ember,
                        action: onAskARIA
                    )
                    Text(SexualHealthCurriculum.medicalDisclaimer)
                        .font(HomeType.micro)
                        .foregroundStyle(Color.textTertiary)
                        .forgeWrapping()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .forgeScreenInsets(top: FDS.Spacing.lg)
            }
            .background(Color.background.ignoresSafeArea())
            .navigationTitle("Taking longer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Intro

    private var intro: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
            Text("If conceiving is taking longer")
                .font(ForgeType.title)
                .foregroundStyle(Color.textPrimary)
                .forgeWrapping()
                .accessibilityAddTraits(.isHeader)
            Text("Literacy, not a diagnosis. Forge is not a fertility clinic and cannot run labs. You leave with a list you can take to a human.")
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
        }
    }

    // MARK: - Steps

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("THINGS YOU CAN DO")
            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                ForEach(Array(DifficultyConceivingGuide.steps.enumerated()), id: \.offset) { index, step in
                    stepRow(number: index + 1, text: step)
                }
            }
        }
        .forgeContentCard()
    }

    private func stepRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: ForgeLayout.rowGap) {
            Text("\(number)")
                .font(HomeType.label)
                .monospacedDigit()
                .foregroundStyle(Color.ember)
                .hudInArcText()
                .frame(width: stepBadgeDiameter, height: stepBadgeDiameter)
                .background(Circle().fill(Color.ember.opacity(0.16)))
                .accessibilityHidden(true)
            Text(text)
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number). \(text)")
    }

    // MARK: - Specialists

    private var specialistsCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("SPECIALISTS TO KNOW")
            VStack(alignment: .leading, spacing: ForgeLayout.tileGap) {
                ForEach(DifficultyConceivingGuide.specialists) { person in
                    specialistTile(title: person.title, when: person.when)
                }
            }
        }
        .forgeContentCard()
    }

    private func specialistTile(title: String, when: String) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
            Text(title)
                .font(HomeType.status)
                .foregroundStyle(Color.textPrimary)
                .forgeWrapping()
            Text(when)
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeWell()
        .accessibilityElement(children: .combine)
    }
}
