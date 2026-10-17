import SwiftUI
import ForgeCore

/// Teaching personality — mindset only. Reuses the working coaching-style
/// picker layout so typography and chrome stay put.
struct CoachingPersonalityPickerView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var store: AppStore
    @State private var selected: ForgeCoachingPersonality.Preset = .steadyBuilder
    @State private var freeText = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ForgeLayout.sectionGap) {
                    Text("How ARIA talks. Never the session plan. Pillar Training never pushes past comfort or safety, and it names real progress.")
                        .font(HomeType.body)
                        .foregroundStyle(Color.textSecondary)
                        .forgeWrapping()

                    VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                        ForEach(ForgeCoachingPersonality.Preset.allCases, id: \.self) { preset in
                            Button {
                                ForgeHaptics.play(.selection)
                                withAnimation(reduceMotion ? nil : ForgeMotion.snappy) {
                                    selected = preset
                                }
                            } label: {
                                HStack(alignment: .top, spacing: ForgeLayout.rowGap) {
                                    VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                                        Text(preset.label)
                                            .font(HomeType.status)
                                            .foregroundStyle(Color.textPrimary)
                                        Text(preset.summary)
                                            .font(HomeType.body)
                                            .foregroundStyle(Color.textTertiary)
                                            .forgeWrapping()
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: selected == preset ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selected == preset ? Color.ember : Color.textMuted)
                                }
                                .frame(maxWidth: .infinity, minHeight: ForgeUX.minTap, alignment: .topLeading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selected == preset ? .isSelected : [])
                        }
                    }
                    .forgeContentCard()

                    TextField("Describe your own style (optional)", text: $freeText, axis: .vertical)
                        .font(HomeType.body)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(3...6)
                }
                .forgeScreenInsets(top: FDS.Spacing.lg)
            }
            .forgeScreenBackground(accent: .ember)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ForgePrimaryButton(title: "Save") {
                    store.updateProfile(
                        coachingPersonality: .init(preset: selected, freeText: freeText)
                    )
                    dismiss()
                }
                .padding(.horizontal, ForgeLayout.screenInset)
                .padding(.top, FDS.Spacing.sm)
                .padding(.bottom, FDS.Spacing.sm)
                .forgeBarChrome(edge: .bottom)
            }
            .navigationTitle("Teaching personality")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.textSecondary)
                }
            }
            .onAppear {
                selected = store.userProfile.coachingPersonality.preset ?? .steadyBuilder
                freeText = store.userProfile.coachingPersonality.freeText
            }
        }
    }
}
