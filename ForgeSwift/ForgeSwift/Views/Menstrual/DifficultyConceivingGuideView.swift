import SwiftUI
import ForgeCore

/// Dedicated page for “conceiving is taking longer” — options and specialists,
/// not a chat dump and not a clinic.
struct DifficultyConceivingGuideView: View {
    var onAskARIA: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("If conceiving is taking longer")
                            .font(FDS.TypeScale.title(22))
                            .foregroundColor(.textPrimary)
                        Text("Literacy, not a diagnosis. Forge is not a fertility clinic and cannot run labs. You leave with a list you can take to a human.")
                            .font(FDS.TypeScale.body(14))
                            .foregroundColor(.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("THINGS YOU CAN DO").forgeSectionLabel()
                        ForEach(Array(DifficultyConceivingGuide.steps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(index + 1)")
                                    .font(FDS.TypeScale.label(12))
                                    .foregroundStyle(Color.ember)
                                    .frame(width: 22, height: 22)
                                    .background(Color.ember.opacity(0.15))
                                    .clipShape(Circle())
                                Text(step)
                                    .font(FDS.TypeScale.body(14))
                                    .foregroundColor(.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(16)
                    .forgeGlassCard(accent: Color(hex: "EC4899"))

                    VStack(alignment: .leading, spacing: 10) {
                        Text("SPECIALISTS TO KNOW").forgeSectionLabel()
                        ForEach(DifficultyConceivingGuide.specialists) { person in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(person.title)
                                    .font(FDS.TypeScale.label(15))
                                    .foregroundColor(.textPrimary)
                                Text(person.when)
                                    .font(FDS.TypeScale.body(13))
                                    .foregroundColor(.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }

                    Button(action: onAskARIA) {
                        Label("Ask ARIA to walk this with me", systemImage: "sparkles")
                            .font(FDS.TypeScale.label(15))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.ember)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Text(SexualHealthCurriculum.medicalDisclaimer)
                        .font(FDS.TypeScale.body(11))
                        .foregroundColor(.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
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
}
