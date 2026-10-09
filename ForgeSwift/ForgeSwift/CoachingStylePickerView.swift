import SwiftUI
import ForgeCore

struct CoachingStylePickerView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var store: AppStore
    @State private var selectedStyle: CoachingStyle = .balanced

    private func save() {
        if selectedStyle != store.userProfile.coachingStyle {
            store.updateProfile(coachingStyle: selectedStyle)
        }
        dismiss()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: FDS.Spacing.lg) {
                    Text("Choose how ARIA talks to you during training and recovery.")
                        .font(.system(size: 14))
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .padding(.top, FDS.Spacing.sm)

                    VStack(spacing: FDS.Spacing.md) {
                        ForEach(CoachingStyle.allCases, id: \.self) { style in
                            Button(action: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    selectedStyle = style
                                }
                            }) {
                                HStack(spacing: FDS.Spacing.md) {
                                    Image(systemName: style.icon)
                                        .font(.system(size: 18))
                                        .foregroundColor(style.color)
                                        .frame(width: 28)

                                    VStack(alignment: .leading, spacing: FDS.Spacing.xs) {
                                        Text(style.label)
                                            .font(FDS.TypeScale.Dynamic.headline)
                                            .foregroundColor(.textPrimary)
                                        Text(style.description)
                                            .font(.system(size: 13))
                                            .foregroundColor(.textSecondary)
                                            .lineLimit(3)
                                    }
                                    Spacer()

                                    ZStack {
                                        Circle()
                                            .stroke(selectedStyle == style ? Color.paper : Color.borderColor, lineWidth: 2)
                                            .frame(width: 24, height: 24)
                                        if selectedStyle == style {
                                            Circle()
                                                .fill(Color.paper)
                                                .frame(width: 14, height: 14)
                                        }
                                    }
                                }
                                .padding(FDS.Spacing.lg)
                                .background(Color.white.opacity(selectedStyle == style ? 0.06 : 0.04))
                                .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous)
                                        .stroke(Color.white.opacity(selectedStyle == style ? 0.18 : 0.08), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)

                    PremiumPrimaryButton(title: "Save", icon: nil, action: save)
                        .padding(.horizontal)
                        .padding(.top, FDS.Spacing.md)
                }
                .padding(.bottom, 32)
            }
            .background(Color.background.ignoresSafeArea())
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
}
