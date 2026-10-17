import SwiftUI
import ForgeCore

/// Adaptive training model — the person's own words. Optional speaking-tone
/// chips stay secondary. Reuses the working picker layout so typography and
/// chrome stay put.
struct CoachingPersonalityPickerView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var store: AppStore
    @State private var selected: ForgeCoachingPersonality.Preset?
    @State private var freeText = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ForgeLayout.sectionGap) {
                    Text("Describe your training style in your own words. ARIA coaches against that — mindset and method only, never exercise form, never past comfort or safety. Progress is named when it is real.")
                        .font(HomeType.body)
                        .foregroundStyle(Color.textSecondary)
                        .forgeWrapping()

                    TextField(ForgeCoachingPersonality.modelPlaceholder, text: $freeText, axis: .vertical)
                        .font(HomeType.body)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(3...8)
                        .accessibilityLabel("Describe your training style")
                        .accessibilityHint("This is the adaptive training model. Optional example mentions Hashira as a reference for intensity, not a preset.")

                    Text("Speaking tone (optional)")
                        .font(HomeType.micro)
                        .foregroundStyle(Color.textTertiary)

                    VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                        ForEach(ForgeCoachingPersonality.Preset.allCases, id: \.self) { preset in
                            Button {
                                ForgeHaptics.play(.selection)
                                withAnimation(reduceMotion ? nil : ForgeMotion.snappy) {
                                    selected = selected == preset ? nil : preset
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
            .navigationTitle("Training style")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.textSecondary)
                }
            }
            .onAppear {
                selected = store.userProfile.coachingPersonality.preset
                freeText = store.userProfile.coachingPersonality.freeText
            }
        }
    }
}
