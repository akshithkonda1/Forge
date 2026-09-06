import SwiftUI
import ForgeCore

/// Clinical data that is not a chart: Health lists + an on-device federal pharmacy.
/// Names, dates, and source only — never notes, coverage, or FHIR blobs.
struct ClinicalDataNonPHIView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var health = HealthKitManager.shared
    @State private var healthLoading = false
    @State private var catalogLoading = true
    @State private var error: String?
    @State private var query = ""
    @State private var page = PharmacySearchPage(items: [], total: 0, groups: [])
    @State private var catalogCount = 0
    @State private var refreshLabel = MedicationPharmacy.lastRefreshLabel()
    @State private var saved = MedicationPharmacy.savedNames()
    @State private var sort: PharmacySort = .archetype
    @State private var archetypeFilter: String?
    @State private var diseaseFilter: String?
    @State private var visibleLimit = 40
    @State private var searchTask: Task<Void, Never>?

    private var summary: ClinicalRecordsSummary? { health.clinicalSummary }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 22) {
                    Text("Two steps. Connect Apple Health for the meds already on this iPhone. Then search every federal-list product by brand or generic — every body-system archetype and disease. ARIA reads this as its medication context layer and can pull from here.")
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
                await bootCatalog()
                if health.hasStructuredRecordsAccess {
                    await refreshHealth()
                }
                await MedicationPharmacy.refreshFromOpenFDAIfDue()
                catalogCount = MedicationPharmacy.count
                refreshLabel = MedicationPharmacy.lastRefreshLabel()
                applySearch()
            }
            .onDisappear {
                searchTask?.cancel()
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
                    Text(healthLoading ? "Asking Health…" : "Allow medications from Apple Health")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.ember)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(healthLoading)
                .accessibilityLabel("Allow medications from Apple Health")
            } else if healthLoading && summary == nil {
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
                .disabled(healthLoading)
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
                subtitle: catalogLoading
                    ? "Loading the federal catalog…"
                    : "\(catalogCount.formatted()) presentations · \(refreshLabel)"
            )

            Text("ARIA never prescribes and never names a dose. It reads what you already take, files the likely needs, and mutates lifestyle and training for you — not a general-population template.")
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.textTertiary)
                TextField("Brand, generic, disease, or archetype", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundColor(.textPrimary)
                    .onChange(of: query) { _, _ in
                        scheduleSearch()
                    }
            }
            .padding(12)
            .background(Color.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            sortBar

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
            }

            if catalogLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else if page.total == 0, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("No match for “\(query)”. Try the brand (Xcopri) or the generic (cenobamate).")
                    .font(.system(size: 13))
                    .foregroundColor(.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(resultSummary)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.textTertiary)

                ForEach(page.groups) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.ember)
                        ForEach(group.items, id: \.id) { med in
                            pharmacyRow(med)
                        }
                    }
                }

                if page.items.count < page.total {
                    Button("Show more (\(page.items.count.formatted()) of \(page.total.formatted()))") {
                        visibleLimit += 40
                        applySearch()
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.ember)
                }
            }
        }
    }

    private var sortBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PharmacySort.allCases) { option in
                    Button {
                        sort = option
                        applySearch()
                    } label: {
                        Text(option.label)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(sort == option ? .white : .textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(sort == option ? Color.ember : Color.surfaceElevated)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                if let archetypeFilter {
                    filterChip(archetypeFilter) { self.archetypeFilter = nil; applySearch() }
                }
                if let diseaseFilter {
                    filterChip(diseaseFilter) { self.diseaseFilter = nil; applySearch() }
                }
            }
        }
    }

    private func filterChip(_ title: String, clear: @escaping () -> Void) -> some View {
        Button(action: clear) {
            HStack(spacing: 4) {
                Text(title)
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.ember.opacity(0.8))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var resultSummary: String {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            return "Browse \(page.total.formatted()) medications by \(sort.label.lowercased())."
        }
        return "\(page.total.formatted()) matches for “\(q)” — brand and generic."
    }

    private func pharmacyRow(_ med: FDAMedication) -> some View {
        let isSaved = saved.contains { $0.caseInsensitiveCompare(med.name) == .orderedSame }
        return Button {
            MedicationPharmacy.toggleSaved(name: med.name)
            saved = MedicationPharmacy.savedNames()
            AriaContextStore.shared.applyMedicationLayer()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSaved ? "pills.fill" : "pills")
                    .foregroundColor(.ember)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(med.brandOrGeneric)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text(med.bothNames)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textSecondary)
                    Text([med.strength, med.form, med.archetype, med.disease].filter { !$0.isEmpty }.joined(separator: " · "))
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
        .accessibilityLabel("\(med.bothNames). \(med.archetype). \(med.disease). \(isSaved ? "On your list" : "Add to your list")")
        .contextMenu {
            Button("Only \(med.archetype)") {
                archetypeFilter = med.archetype
                applySearch()
            }
            Button("Only \(med.disease)") {
                diseaseFilter = med.disease
                applySearch()
            }
        }
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

    private func bootCatalog() async {
        catalogLoading = true
        await MedicationPharmacy.prepare()
        catalogCount = MedicationPharmacy.count
        refreshLabel = MedicationPharmacy.lastRefreshLabel()
        applySearch()
        catalogLoading = false
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            visibleLimit = 40
            applySearch()
        }
    }

    private func applySearch() {
        page = MedicationPharmacy.search(
            query,
            sort: sort,
            limit: visibleLimit,
            archetype: archetypeFilter,
            disease: diseaseFilter
        )
    }

    private func connect() async {
        healthLoading = true
        error = nil
        defer { healthLoading = false }
        do {
            try await health.requestClinicalRecordsAuthorization()
            await refreshHealth()
        } catch {
            self.error = "Couldn't open Apple Health for these records. The pharmacy still works."
        }
    }

    private func refreshHealth() async {
        healthLoading = true
        error = nil
        defer { healthLoading = false }
        _ = await health.fetchClinicalRecordsSummary()
        AriaContextStore.shared.applyMedicationLayer()
    }
}
