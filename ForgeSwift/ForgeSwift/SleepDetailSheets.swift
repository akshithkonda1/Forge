import SwiftUI

struct SleepPersonalizationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var hkService: HealthKitSleepService
    @EnvironmentObject var store: AppStore
    @State private var draft = UserSleepProfile()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Your chronotype shapes scoring, goals, sunrise, and smart wake.")
                            .font(.system(size: 14))
                            .foregroundColor(.textSecondary)
                            .lineSpacing(4)

                        VStack(spacing: 10) {
                            ForEach(Chronotype.allCases) { type in
                                Button {
                                    draft.chronotype = type
                                    UISelectionFeedbackGenerator().selectionChanged()
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: type.icon)
                                            .font(.system(size: 18))
                                            .foregroundColor(draft.chronotype == type ? .white : .steel)
                                            .frame(width: 40, height: 40)
                                            .background(draft.chronotype == type ? Color.steel : Color.surfaceElevated)
                                            .cornerRadius(12)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(type.displayName)
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundColor(.textPrimary)
                                            Text(type.tagline)
                                                .font(.system(size: 12))
                                                .foregroundColor(.textTertiary)
                                        }
                                        Spacer()
                                        if draft.chronotype == type {
                                            Image(systemName: "checkmark.circle.fill").foregroundColor(.steel)
                                        }
                                    }
                                    .padding(14)
                                    .background(Color.surface)
                                    .cornerRadius(14)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(draft.chronotype == type ? Color.steel.opacity(0.5) : Color.borderColor.opacity(0.4), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Coaching personality")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.textSecondary)
                            TextField("e.g. direct, encouraging, data-focused", text: $draft.personality)
                                .padding(12)
                                .background(Color.surfaceElevated)
                                .cornerRadius(12)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Lifestyle notes")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.textSecondary)
                            TextEditor(text: $draft.notes)
                                .frame(minHeight: 90)
                                .padding(8)
                                .background(Color.surfaceElevated)
                                .cornerRadius(12)
                                .scrollContentBackground(.hidden)
                        }
                    }
                    .padding(16)
                }
            }
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
