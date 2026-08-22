import SwiftUI
import ForgeCore

/// Usable lists of the six structured Health record types.
/// Names, dates, and source only — never notes, coverage, or FHIR blobs.
struct ClinicalDataNonPHIView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var health = HealthKitManager.shared
    @State private var loading = false
    @State private var error: String?

    private var summary: ClinicalRecordsSummary? { health.clinicalSummary }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Structured lists from Apple Health. Allergies, medications, conditions, immunizations, labs, and procedures. Not notes. Not insurance. Nothing leaves this iPhone.")
                        .font(.system(size: 14))
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !health.hasStructuredRecordsAccess {
                        Button {
                            Task { await connect() }
                        } label: {
                            Text(loading ? "Asking Health…" : "Allow from Apple Health")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.ember)
                                .cornerRadius(14)
                        }
                        .buttonStyle(.plain)
                        .disabled(loading)
                    } else if loading && summary == nil {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    } else if let error {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundColor(.warning)
                    } else if let summary, summary.hasData {
                        ForEach(StructuredHealthKind.allCases) { kind in
                            kindSection(kind, items: summary.items(for: kind))
                        }
                    } else {
                        Text("No allergies, meds, labs, or other structured records in Apple Health yet.")
                            .font(.system(size: 14))
                            .foregroundColor(.textSecondary)
                    }
                }
                .padding(20)
            }
            .background(Color.background.ignoresSafeArea())
            .navigationTitle("Clinical Data (Non PHI)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
                if health.hasStructuredRecordsAccess {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Refresh") {
                            Task { await refresh() }
                        }
                        .disabled(loading)
                    }
                }
            }
            .task {
                if health.hasStructuredRecordsAccess {
                    await refresh()
                }
            }
        }
    }

    private func kindSection(_ kind: StructuredHealthKind, items: [StructuredHealthItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.ember)
                Text(kind.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("\(items.count)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.textTertiary)
            }

            if items.isEmpty {
                Text("None on file")
                    .font(.system(size: 13))
                    .foregroundColor(.textTertiary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider().background(Color.borderColor) }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.textPrimary)
                            Text("\(item.source)  ·  \(item.date.formatted(date: .abbreviated, time: .omitted))")
                                .font(.system(size: 12))
                                .foregroundColor(.textTertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.surface)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.borderColor.opacity(0.4), lineWidth: 1))
    }

    private func connect() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            try await health.requestClinicalRecordsAuthorization()
            await refresh()
        } catch {
            self.error = "Couldn't open Apple Health for these records."
        }
    }

    private func refresh() async {
        loading = true
        error = nil
        defer { loading = false }
        _ = await health.fetchClinicalRecordsSummary()
    }
}
