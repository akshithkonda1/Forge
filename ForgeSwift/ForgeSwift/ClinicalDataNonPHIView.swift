import SwiftUI
import ForgeCore

/// Clinical data that is not a chart: Health lists + an on-device FDA pharmacy.
/// Names, dates, and source only — never notes, coverage, or FHIR blobs.
struct ClinicalDataNonPHIView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var health = HealthKitManager.shared
    @State private var loading = false
    @State private var error: String?
    @State private var query = ""
    @State private var results: [FDAMedication] = []
    @State private var catalogCount = 0
    @State private var refreshLabel = MedicationPharmacy.lastRefreshLabel()
    @State private var saved = MedicationPharmacy.savedNames()

    private var summary: ClinicalRecordsSummary? { health.clinicalSummary }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Two steps. Connect Apple Health for the meds and allergies already on this iPhone. Then search the pharmacy — every FDA-approved presentation Forge ships, updated from openFDA when you're online.")
                        .font(.system(size: 14))
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    healthStep
                    pharmacyStep

                    if let error {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundColor(.warning)
                    }
                }
                .padding(20)
                .padding(.bottom, 40)
            }
            .background(Color.background.ignoresSafeArea())
            .navigationTitle("Medicine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                catalogCount = MedicationPharmacy.count
                results = MedicationPharmacy.search(query)
                if health.hasStructuredRecordsAccess {
                    await refreshHealth()
                }
                await MedicationPharmacy.refreshFromOpenFDAIfDue()
                catalogCount = MedicationPharmacy.count
                refreshLabel = MedicationPharmacy.lastRefreshLabel()
                if !query.isEmpty {
                    results = MedicationPharmacy.search(query)
                }
            }
        }
    }

    private var healthStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepHeader(number: "1", title: "Apple Health", subtitle: "Structured records only. Not notes. Not insurance.")

            if !health.hasStructuredRecordsAccess {
                Button {
                    Task { await connect() }
                } label: {
                    Text(loading ? "Asking Health…" : "Allow medications from Apple Health")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.ember)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(loading)
                .accessibilityLabel("Allow medications from Apple Health")
            } else if loading && summary == nil {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else if let summary, summary.hasData {
                ForEach(StructuredHealthKind.allCases) { kind in
                    kindSection(kind, items: summary.items(for: kind))
                }
                Button("Refresh Health lists") {
                    Task { await refreshHealth() }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.ember)
                .disabled(loading)
            } else {
                Text("Health is connected. No allergies, meds, labs, or other structured records on file yet. Search the pharmacy below.")
                    .font(.system(size: 13))
                    .foregroundColor(.textTertiary)
            }
        }
    }

    private var pharmacyStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepHeader(
                number: "2",
                title: "Pharmacy",
                subtitle: "\(catalogCount.formatted()) FDA-approved presentations · \(refreshLabel)"
            )

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.textTertiary)
                TextField("Search any medication", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundColor(.textPrimary)
                    .onChange(of: query) { _, value in
                        results = MedicationPharmacy.search(value)
                    }
            }
            .padding(12)
            .background(Color.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if !saved.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("On your list")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textTertiary)
                    ForEach(saved, id: \.self) { name in
                        Text(name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.textPrimary)
                    }
                }
                .padding(.bottom, 4)
            }

            if results.isEmpty, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("No match in the FDA catalog for “\(query)”. Try the generic or the brand.")
                    .font(.system(size: 13))
                    .foregroundColor(.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(results) { med in
                    pharmacyRow(med)
                }
            }
        }
    }

    private func pharmacyRow(_ med: FDAMedication) -> some View {
        let isSaved = saved.contains { $0.caseInsensitiveCompare(med.name) == .orderedSame }
        return Button {
            MedicationPharmacy.toggleSaved(name: med.name)
            saved = MedicationPharmacy.savedNames()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSaved ? "pills.fill" : "pills")
                    .foregroundColor(.ember)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(med.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text([med.brand, med.therapeuticClass, "FDA"].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                }
                Spacer()
            }
            .padding(12)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(med.name). \(isSaved ? "On your list" : "Add to your list")")
    }

    private func stepHeader(number: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(number)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: 22, height: 22)
                    .background(Color.ember)
                    .clipShape(Circle())
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.textPrimary)
            }
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundColor(.textTertiary)
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
                    ForEach(items) { item in
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
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.borderColor.opacity(0.4), lineWidth: 1))
    }

    private func connect() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            try await health.requestClinicalRecordsAuthorization()
            await refreshHealth()
        } catch {
            self.error = "Couldn't open Apple Health for these records. The pharmacy still works."
        }
    }

    private func refreshHealth() async {
        loading = true
        error = nil
        defer { loading = false }
        _ = await health.fetchClinicalRecordsSummary()
    }
}
