import SwiftUI
import ForgeCore

struct SleepPersonalizationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var hkService: HealthKitSleepService
    @EnvironmentObject var store: AppStore
    @State private var draft = UserSleepProfile()

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: ForgeLayout.sectionGap) {
                    Text("Your chronotype shapes scoring, goals, sunrise, and smart wake.")
                        .font(HomeType.body)
                        .foregroundStyle(Color.textSecondary)
                        .forgeWrapping()

                    chronotypeCard
                    profileFieldsCard
                }
                .forgeScreenInsets(top: FDS.Spacing.lg)
            }
            .forgeScreenBackground(accent: .steel)
            .navigationTitle("Sleep Profile")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { draft = hkService.userProfile }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        hkService.updateProfile(draft)
                        SleepNeedBaselineStore.save(draft.sleepNeedBaselineHours)
                        if !store.sleepData.isEmpty {
                            Task {
                                let rescored = await hkService.fetchRecentSleepData(days: 14)
                                store.mergeSleepDataLocally(rescored)
                            }
                        }
                        dismiss()
                    }
                    .foregroundColor(.steel)
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var chronotypeCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("Chronotype", tint: .steel)
            VStack(spacing: ForgeLayout.tileGap) {
                ForEach(Chronotype.allCases) { type in
                    chronotypeRow(type)
                }
            }
        }
        .forgeContentCard(tint: .steel)
    }

    private func chronotypeRow(_ type: Chronotype) -> some View {
        let isSelected = draft.chronotype == type
        return Button {
            FDS.haptic(.select)
            draft.chronotype = type
        } label: {
            HStack(spacing: ForgeLayout.rowGap) {
                ForgeIconWell(systemImage: type.icon, tint: .steel)
                VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                    Text(type.displayName)
                        .font(HomeType.status)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(2)
                    Text(type.tagline)
                        .font(HomeType.body)
                        .foregroundStyle(Color.textTertiary)
                        .forgeWrapping()
                }
                .layoutPriority(1)
                Spacer(minLength: FDS.Spacing.xs)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.steel)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, FDS.Spacing.sm)
            .padding(.horizontal, FDS.Spacing.md)
            .frame(maxWidth: .infinity, minHeight: ForgeUX.minTap, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: ForgeLayout.innerRadius, style: .continuous)
                    .fill(isSelected ? Color.steel.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ForgeLayout.innerRadius, style: .continuous)
                    .stroke(
                        isSelected ? Color.steel.opacity(0.28) : Color.white.opacity(0.08),
                        lineWidth: ForgeUX.hairline
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("Sets your chronotype")
    }

    private var profileFieldsCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                Text("Your sleep need baseline")
                    .font(HomeType.label)
                    .foregroundStyle(Color.textSecondary)
                    .accessibilityAddTraits(.isHeader)
                Text("Tonight's need is baseline + load + short stretch − naps, kept between 7 and 9 hours. You can override the baseline.")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textTertiary)
                    .forgeWrapping()
                Stepper(
                    value: Binding(
                        get: { draft.sleepNeedBaselineHours ?? 8.0 },
                        set: { draft.sleepNeedBaselineHours = $0 }
                    ),
                    in: SleepNeedParts.clampMin...SleepNeedParts.clampMax,
                    step: 0.25
                ) {
                    Text(String(format: "%.2f hours", draft.sleepNeedBaselineHours ?? 8.0))
                        .font(HomeType.status)
                        .foregroundStyle(Color.textPrimary)
                }
                .frame(minHeight: ForgeUX.minTap)
                Button("Use estimated baseline") {
                    draft.sleepNeedBaselineHours = nil
                }
                .font(HomeType.body)
                .foregroundStyle(Color.steel)
                .frame(minHeight: ForgeUX.minTap, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                Text("Coaching personality")
                    .font(HomeType.label)
                    .foregroundStyle(Color.textSecondary)
                    .accessibilityAddTraits(.isHeader)
                TextField("e.g. direct, encouraging, data-focused", text: $draft.personality)
                    .font(HomeType.body)
                    .frame(minHeight: ForgeUX.minTap - 2 * ForgeLayout.tilePadding)
                    .forgeWell()
            }

            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                Text("Lifestyle notes")
                    .font(HomeType.label)
                    .foregroundStyle(Color.textSecondary)
                    .accessibilityAddTraits(.isHeader)
                TextEditor(text: $draft.notes)
                    .font(HomeType.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 90)
                    .forgeWell()
            }
        }
        .forgeContentCard()
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        FlowResult(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews, spacing: spacing).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (i, sv) in subviews.enumerated() {
            sv.place(at: CGPoint(x: bounds.minX + result.positions[i].x, y: bounds.minY + result.positions[i].y), proposal: .unspecified)
        }
    }
    struct FlowResult {
        var size: CGSize = .zero; var positions: [CGPoint] = []
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0; var y: CGFloat = 0; var lineH: CGFloat = 0
            for sv in subviews {
                let sz = sv.sizeThatFits(.unspecified)
                if x + sz.width > maxWidth && x > 0 { x = 0; y += lineH + spacing; lineH = 0 }
                positions.append(CGPoint(x: x, y: y))
                lineH = max(lineH, sz.height); x += sz.width + spacing
            }
            size = CGSize(width: maxWidth, height: y + lineH)
        }
    }
}
