import SwiftUI
import ForgeCore

/// 12-month Cycle Vault report — on-device, clinician-shareable, no fertility.
struct CycleRhythmReportView: View {
    @ObservedObject var cycleStore: MenstrualHealthStore
    @Environment(\.dismiss) private var dismiss

    private var months: [CycleMonthlyDigest] {
        cycleStore.loadRecentMonthlyDigests()
    }

    private var report: String {
        cycleStore.clinicianRhythmReportText()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Rhythm report")
                            .font(FDS.TypeScale.title(22))
                            .foregroundColor(.textPrimary)
                        Text("Sealed in Cycle Vault on this iPhone. Hand this to a gynecologist — not a social feed. Fertile windows and private notes stay out.")
                            .font(FDS.TypeScale.body(14))
                            .foregroundColor(.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    overviewChips

                    if months.isEmpty {
                        Text("Keep logging. Each month writes an encrypted archive. After a few cycles this becomes a 12-month evidence pack.")
                            .font(FDS.TypeScale.body(14))
                            .foregroundColor(.textSecondary)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("MONTHLY ARCHIVES").forgeSectionLabel()
                            ForEach(months) { month in
                                monthRow(month)
                            }
                        }
                    }

                    Text(report)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundColor(.textSecondary)
                        .textSelection(.enabled)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    ShareLink(item: report) {
                        Label("Share with my clinician", systemImage: "square.and.arrow.up")
                            .font(FDS.TypeScale.label(15))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.ember)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .accessibilityHint("Opens the system share sheet. You choose who receives this report.")
                }
                .padding(20)
            }
            .background(Color.background.ignoresSafeArea())
            .navigationTitle("Cycle Vault")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var overviewChips: some View {
        let snap = cycleStore.snapshot
        return HStack(spacing: 8) {
            chip("\(Int(snap.cycleLengthMedian.rounded()))d cycle", Color.ember)
            chip("\(Int(snap.periodLengthMedian.rounded()))d bleed", Color(hex: "EF4444"))
            if let mae = cycleStore.accuracyReport.maeDays {
                chip(String(format: "MAE %.1fd", mae), Color(hex: "22C55E"))
            }
            chip("Vault", Color.vitality)
            Spacer(minLength: 0)
        }
    }

    private func monthRow(_ month: CycleMonthlyDigest) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(month.monthKey)
                    .font(FDS.TypeScale.label(15))
                    .foregroundColor(.textPrimary)
                Text("\(month.daysLogged) days logged · \(month.bleedingDays) bleeding · \(month.cycleStarts) starts")
                    .font(FDS.TypeScale.body(12))
                    .foregroundColor(.textTertiary)
            }
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 11))
                .foregroundStyle(Color.vitality)
        }
        .padding(14)
        .background(Color.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func chip(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(FDS.TypeScale.micro(10))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

struct CycleTrainingPrescriptionCard: View {
    let prescription: CycleTrainingPrescription
    var onAskARIA: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TODAY'S TRAINING").forgeSectionLabel()
            Text(prescription.headline)
                .font(FDS.TypeScale.title(17))
                .foregroundColor(.textPrimary)
            Text(prescription.volumeLine)
                .font(FDS.TypeScale.body(14))
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(prescription.intensityLine)
                .font(FDS.TypeScale.body(13))
                .foregroundColor(.textSecondary)
            Text(prescription.returnLine)
                .font(FDS.TypeScale.body(13))
                .foregroundColor(.textTertiary)
            Button(action: onAskARIA) {
                Label("Ask ARIA to shape this", systemImage: "sparkles")
                    .font(FDS.TypeScale.label(13))
            }
            .buttonStyle(.bordered)
            .tint(.ember)
            Text(prescription.disclaimer)
                .font(FDS.TypeScale.body(11))
                .foregroundColor(.textTertiary)
        }
        .padding(18)
        .forgeGlassCard(accent: .ember)
    }
}
