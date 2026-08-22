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
                    Text("Choose how Forge AI interacts with you during workouts and provides feedback.")
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
                                            .stroke(selectedStyle == style ? Color.ember : Color.borderColor, lineWidth: 2)
                                            .frame(width: 24, height: 24)
                                        if selectedStyle == style {
                                            Circle()
                                                .fill(Color.ember)
                                                .frame(width: 14, height: 14)
                                        }
                                    }
                                }
                                .padding(16)
                                .background(Color.surface)
                                .cornerRadius(14)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(selectedStyle == style ? Color.ember : Color.borderColor, lineWidth: selectedStyle == style ? 2 : 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)

                    Button(action: save) {
                        Text("Save Selection")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.ember)
                            .cornerRadius(14)
                    }
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
