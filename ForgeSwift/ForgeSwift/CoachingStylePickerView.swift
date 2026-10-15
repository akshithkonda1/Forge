import SwiftUI
import ForgeCore

struct CoachingStylePickerView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var store: AppStore
    @State private var selectedStyle: CoachingStyle = .balanced

    private func save() {
        if selectedStyle != store.userProfile.coachingStyle {
            store.updateProfile(coachingStyle: selectedStyle)
        }
        dismiss()
    }

    private func select(_ style: CoachingStyle) {
        FDS.haptic(.select)
        withAnimation(reduceMotion ? nil : FDS.Spring.snap) {
            selectedStyle = style
        }
    }

    /// Forge-palette tint for each tone. The model's own colors (cyan, green,
    /// purple, orange) are not part of the domain tokens.
    private func tint(for style: CoachingStyle) -> Color {
        switch style {
        case .pushHard:   return Color.ember
        case .balanced:   return Color.steel
        case .patient:    return Color.vitality
        case .dataDriven: return Color.aurora
        case .ultraElite: return Color.amber
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ForgeLayout.sectionGap) {
                    Text("Choose how ARIA talks to you during training and recovery.")
                        .font(HomeType.body)
                        .foregroundStyle(Color.textSecondary)
                        .forgeWrapping()
                        .frame(maxWidth: .infinity, alignment: .leading)

                    stylesCard
                }
                .forgeScreenInsets(top: FDS.Spacing.lg)
            }
            .forgeScreenBackground(accent: .ember)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                saveDock
            }
            .navigationTitle("Coaching Style")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.textSecondary)
                }
            }
            .onAppear { selectedStyle = store.userProfile.coachingStyle }
        }
    }

    private var stylesCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            ForEach(CoachingStyle.allCases, id: \.self) { style in
                styleRow(style)
            }
        }
        .forgeContentCard()
    }

    private var saveDock: some View {
        ForgePrimaryButton(title: "Save", action: save)
            .padding(.horizontal, ForgeLayout.screenInset)
            .padding(.top, FDS.Spacing.sm)
            .padding(.bottom, FDS.Spacing.sm)
            .forgeBarChrome(edge: .bottom)
    }

    private func styleRow(_ style: CoachingStyle) -> some View {
        let selected = selectedStyle == style
        return Button {
            select(style)
        } label: {
            HStack(alignment: .top, spacing: ForgeLayout.rowGap) {
                ForgeIconWell(systemImage: style.icon, tint: tint(for: style))

                VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                    Text(style.label)
                        .font(HomeType.status)
                        .foregroundStyle(Color.textPrimary)
                        .forgeWrapping()
                    Text(style.description)
                        .font(HomeType.body)
                        .foregroundStyle(Color.textTertiary)
                        .forgeWrapping()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: ForgeUX.icon, weight: .semibold))
                    .foregroundStyle(selected ? tint(for: style) : Color.textMuted)
                    .frame(minHeight: ForgeLayout.iconWell)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: ForgeUX.minTap, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
