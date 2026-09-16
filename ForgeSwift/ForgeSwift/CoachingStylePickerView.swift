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
                VStack(spacing: 16) {
                    Text("Choose how ARIA talks to you during training and recovery.")
                        .font(.system(size: 14))
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .padding(.top, 8)

                    VStack(spacing: 12) {
                        ForEach(CoachingStyle.allCases, id: \.self) { style in
                            Button(action: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    selectedStyle = style
                                }
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: style.icon)
                                        .font(.system(size: 18))
                                        .foregroundColor(style.color)
                                        .frame(width: 28)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(style.label)
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.textPrimary)
                                        Text(style.description)
                                            .font(.system(size: 13))
                                            .foregroundColor(.textSecondary)
                                            .lineLimit(3)
                                    }
                                    Spacer()

                                    ZStack {
                                        Circle()
                                            .stroke(selectedStyle == style ? Color(hex: "F7F4F0") : Color.borderColor, lineWidth: 2)
                                            .frame(width: 24, height: 24)
                                        if selectedStyle == style {
                                            Circle()
                                                .fill(Color(hex: "F7F4F0"))
                                                .frame(width: 14, height: 14)
                                        }
                                    }
                                }
                                .padding(16)
                                .background(Color.white.opacity(selectedStyle == style ? 0.06 : 0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color.white.opacity(selectedStyle == style ? 0.18 : 0.08), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)

                    PremiumPrimaryButton(title: "Save", icon: nil, action: save)
                        .padding(.horizontal)
                        .padding(.top, 12)
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
