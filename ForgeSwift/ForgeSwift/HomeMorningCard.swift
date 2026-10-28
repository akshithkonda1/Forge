import SwiftUI
import ForgeCore

/// One morning card on Home: the day's call, 1–3 actions, a short reason.
struct HomeMorningCard: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject private var patterns = AriaPersonalPatternStore.shared

    private var card: AriaMorningCardBuilder.Card {
        patterns.lastCard ?? AriaMorningCardBuilder.build(
            .init(
                numbers: .init(
                    sleepHours: SleepData.lastNight(in: store.sleepData)?.totalHours,
                    readiness: store.readiness.hasScore ? store.readiness.overall : nil
                ),
                gymLabel: AriaPersonalPatternStore.gymLabel(store.userProfile.trainingEquipment),
                hasLifeSignal: store.hasMeaningfulLifeSignal
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("Today", meta: AriaPersonalPatternStore.gymLabel(store.userProfile.trainingEquipment))

            if card.empty {
                ForgeEmptyState(
                    icon: "sun.haze",
                    title: card.call,
                    message: card.reason
                )
            } else {
                Text(card.call)
                    .font(HomeType.sessionTitle)
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                    ForEach(Array(card.actions.enumerated()), id: \.offset) { index, line in
                        HStack(alignment: .top, spacing: FDS.Spacing.sm) {
                            Text("\(index + 1)")
                                .font(HomeType.micro)
                                .foregroundStyle(Color.textTertiary)
                                .frame(width: 16, alignment: .leading)
                            Text(line)
                                .font(HomeType.body)
                                .foregroundStyle(Color.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }

                Text(card.reason)
                    .font(HomeType.status)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !card.patternLine.isEmpty {
                    Text(card.patternLine)
                        .font(HomeType.micro)
                        .foregroundStyle(Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !card.ruleLine.isEmpty {
                    Text(card.ruleLine)
                        .font(HomeType.micro)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .forgeContentCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(card.voiceOverLabel)
    }
}
