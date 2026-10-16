import SwiftUI
import PhotosUI
import ForgeCore
#if canImport(UIKit)
import UIKit
#endif

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
    @State private var showCamera = false
    @State private var photoItem: PhotosPickerItem?
    @State private var scanningBottle = false
    @State private var bottleScan: MedicationBottleScan?
    @State private var showHow = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .caption) private var badgeSize: CGFloat = 22

    private var summary: ClinicalRecordsSummary? { health.clinicalSummary }

    /// Health is the one primary action until it is connected; after that the
    /// bottle scan takes over, so the screen never shows two filled buttons.
    private var healthNeedsAllow: Bool {
        health.canRequestStructuredRecords && !health.hasStructuredRecordsAccess
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                ForgeScreenStack(top: FDS.Spacing.sm) {
                    introBlock
                    healthStep
                    pharmacyStep
                }
            }
            .forgeScreenBackground(accent: .steel)
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
            .sheet(isPresented: $showCamera) {
                CameraCaptureView { image in
                    Task { await admitBottle(image) }
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task { await admitPickedPhoto(item) }
            }
        }
    }

    // MARK: Intro

    /// One sentence up front; the rest sits behind "How this works".
    private var introBlock: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeSectionHeader(
                title: "Two steps",
                subtitle: "Allow Apple Health — the same full catalog Forge asks at first connect — so allergies, meds, conditions, shots, labs, procedures, and vitals already on this iPhone land in Forge."
            )
            if showHow {
                Text("Then search every federal-list product by brand or generic, or photograph the bottle. ARIA never names a medicine or a dose for you.")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
                    .forgeTransition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }
            ForgeTextLink(title: "How this works", accent: .steel, expanded: showHow) {
                if reduceMotion {
                    showHow.toggle()
                } else {
                    withForgeMotion(ForgeMotion.smooth) { showHow.toggle() }
                }
            }
        }
    }

    // MARK: Step 1 · Apple Health

    private var healthStep: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.sectionGap) {
            stepHeader(number: "1", title: "Apple Health", subtitle: "Every structured record Forge can read. Not notes. Not insurance.")
            healthContent
            if let error {
                noticeCard(error, systemImage: "exclamationmark.triangle", tint: .warning)
            }
        }
    }

    @ViewBuilder
    private var healthContent: some View {
        if !health.canRequestStructuredRecords {
            noticeCard(
                "Health Records need a real iPhone with Health Records turned on. The Simulator cannot open that sheet — asking anyway used to crash the app. The pharmacy below still works.",
                systemImage: "info.circle",
                tint: .steel
            )
        } else if !health.hasStructuredRecordsAccess {
            ForgePrimaryButton(
                title: healthLoading ? "Asking Health…" : "Allow Apple Health records",
                icon: "heart.text.square"
            ) {
                Task { await connect() }
            }
            .disabled(healthLoading)
            .accessibilityLabel("Allow Apple Health records")
        } else if healthLoading && summary == nil {
            VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
                ForgeCardHeader(title: "Health records", tint: .steel) {
                    ProgressView().controlSize(.mini)
                }
                ForgeSkeletonWell(message: "Asking Health…")
            }
            .forgeContentCard(tint: .steel)
        } else if let summary, summary.hasData {
            recordsCard(summary)
        } else {
            ForgeEmptyNote(
                title: "Health is connected.",
                message: "No allergies, meds, labs, or other structured records on file yet. Search the pharmacy below.",
                systemImage: "heart.text.square",
                tint: .steel
            )
            .forgeContentCard(tint: .steel)
        }
    }

    /// Every kind in one card: kinds with records first, each a header row over
    /// a well of items; kinds with nothing on file close the card as quiet rows.
    private func recordsCard(_ summary: ClinicalRecordsSummary) -> some View {
        let kinds = StructuredHealthKind.allCases
        let filled = kinds.filter { !summary.items(for: $0).isEmpty }
        let empty = kinds.filter { summary.items(for: $0).isEmpty }
        let total = filled.reduce(0) { $0 + summary.items(for: $1).count }
        return VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader(title: "Health records", tint: .steel) {
                if healthLoading {
                    ProgressView().controlSize(.mini)
                } else {
                    ForgeCardMeta(text: "\(total)")
                        .accessibilityLabel("\(total) records")
                }
            }
            VStack(alignment: .leading, spacing: ForgeLayout.groupBreak) {
                ForEach(filled) { kind in
                    kindBlock(kind, items: summary.items(for: kind))
                }
            }
            if !empty.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(empty) { kind in
                        ForgeListRow(
                            icon: kind.symbol,
                            iconColor: .textTertiary,
                            title: kind.title,
                            trailing: "None on file"
                        )
                    }
                }
            }
            ForgeTextLink(title: "Refresh Health lists", accent: .steel) {
                Task { await refreshHealth() }
            }
            .disabled(healthLoading)
        }
        .forgeContentCard(tint: .steel)
    }

    private func kindBlock(_ kind: StructuredHealthKind, items: [StructuredHealthItem]) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            HStack(spacing: ForgeLayout.rowGap) {
                ForgeIconWell(systemImage: kind.symbol, tint: .steel)
                Text(kind.title)
                    .font(HomeType.status)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                    .forgeWrapping()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                ForgeCardMeta(text: "\(items.count)")
                    .accessibilityLabel("\(items.count) records")
            }
            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                        Text(item.name)
                            .font(HomeType.body)
                            .foregroundStyle(Color.textPrimary)
                            .forgeWrapping()
                        Text("\(item.source) · \(item.date.formatted(date: .abbreviated, time: .omitted))")
                            .font(HomeType.micro)
                            .foregroundStyle(Color.textTertiary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .forgeWell()
        }
    }

    // MARK: Step 2 · Pharmacy

    private var pharmacyStep: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.sectionGap) {
            stepHeader(
                number: "2",
                title: "Pharmacy",
                subtitle: catalogLoading
                    ? "Loading the federal catalog…"
                    : "\(catalogCount.formatted()) presentations · \(refreshLabel)"
            )
            searchCard
            if let bottleScan {
                bottleScanCard(bottleScan)
            }
            if !saved.isEmpty {
                savedCard
            }
            resultsContent
        }
    }

    private var searchCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            Text("ARIA never names a medicine or a dose for you. It reads what you already take, files the likely needs, and mutates lifestyle and training for you — not a general-population template.")
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()

            HStack(spacing: ForgeLayout.rowGap) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.textTertiary)
                    .accessibilityHidden(true)
                TextField("Brand, generic, disease, or archetype", text: $query)
                    .font(HomeType.body)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(Color.textPrimary)
                    .onChange(of: query) { _, _ in
                        scheduleSearch()
                    }
            }
            .frame(minHeight: ForgeUX.minTap - 2 * ForgeLayout.tilePadding)
            .forgeWell()

            bottleScanBar
            sortBar
        }
        .forgeContentCard()
    }

    private var bottleScanBar: some View {
        ForgeAdaptiveStack(spacing: ForgeLayout.tileGap) {
            bottleScanButton
            PhotosPicker(selection: $photoItem, matching: .images) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: ForgeUX.icon, weight: .semibold))
                    .foregroundStyle(Color.steel)
                    .frame(minWidth: ForgeUX.minTap + 4, minHeight: ForgeUX.minTap + 8)
                    .background(
                        RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous)
                            .fill(Color.steel.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous)
                            .stroke(Color.steel.opacity(0.28), lineWidth: ForgeUX.hairline)
                    )
            }
            .disabled(scanningBottle || catalogLoading)
            .accessibilityLabel("Choose a bottle photo")
        }
    }

    @ViewBuilder
    private var bottleScanButton: some View {
        let title = scanningBottle ? "Reading label…" : "Photograph the bottle"
        if healthNeedsAllow {
            ForgeSecondaryButton(title: title, icon: "camera.fill", accent: .steel) {
                showCamera = true
            }
            .disabled(scanningBottle || catalogLoading)
            .accessibilityLabel("Photograph the medication bottle to add it instantly")
        } else {
            ForgePrimaryButton(title: title, icon: "camera.fill") {
                showCamera = true
            }
            .disabled(scanningBottle || catalogLoading)
            .accessibilityLabel("Photograph the medication bottle to add it instantly")
        }
    }

    private func bottleScanCard(_ scan: MedicationBottleScan) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            Text(scan.headline)
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
            if scan.admitted == nil, !scan.candidates.isEmpty {
                VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                    ForEach(scan.candidates, id: \.id) { med in
                        pharmacyRow(med)
                    }
                }
            }
        }
        .forgeContentCard(tint: .steel)
    }

    private var savedCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("On your list", meta: "\(saved.count)", tint: .steel)
            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                ForEach(saved, id: \.self) { name in
                    Text(name)
                        .font(HomeType.status)
                        .foregroundStyle(Color.textPrimary)
                        .forgeWrapping()
                        .frame(maxWidth: .infinity, minHeight: ForgeUX.minTap - 2 * ForgeLayout.rowVerticalPadding, alignment: .leading)
                }
            }
        }
        .forgeContentCard(tint: .steel)
    }

    @ViewBuilder
    private var resultsContent: some View {
        if catalogLoading {
            VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
                ForgeCardHeader(title: "Results", tint: .steel) {
                    ProgressView().controlSize(.mini)
                }
                ForgeSkeletonWell(message: "Loading the federal catalog…")
            }
            .forgeContentCard(tint: .steel)
        } else if page.total == 0, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ForgeEmptyNote(
                title: "No match for “\(query)”.",
                message: "Try the brand (Xcopri), the generic (cenobamate), or photograph the bottle.",
                systemImage: "magnifyingglass",
                tint: .steel
            )
            .forgeContentCard(tint: .steel)
        } else {
            Text(resultSummary)
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()

            ForEach(page.groups) { group in
                groupCard(group)
            }

            if page.items.count < page.total {
                showMoreButtons
            }
        }
    }

    private func groupCard(_ group: PharmacyGroup) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader(group.title, meta: "\(group.items.count)", tint: .steel)
            LazyVStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                ForEach(group.items, id: \.id) { med in
                    pharmacyRow(med)
                }
            }
        }
        .forgeContentCard(tint: .steel)
    }

    private var showMoreButtons: some View {
        VStack(spacing: ForgeLayout.tileGap) {
            ForgeSecondaryButton(
                title: "Show more (\(page.items.count.formatted()) of \(page.total.formatted()))",
                accent: .steel
            ) {
                visibleLimit += 40
                applySearch()
            }
            ForgeSecondaryButton(title: "Show all", accent: .steel) {
                visibleLimit = min(page.total, MedicationPharmacy.showAllLimit)
                applySearch()
            }
            .accessibilityLabel("Show all medications")
            .accessibilityHint("Loads the full current list, up to \(MedicationPharmacy.showAllLimit) rows.")
        }
    }

    /// Sort and filter chips on the §2.3 edge-bleed rail: the rail runs to the
    /// card edge, the first chip lines up with the card's content.
    private var sortBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ForgeLayout.chipGap) {
                ForEach(PharmacySort.allCases) { option in
                    ForgeChipButton(label: option.label, selected: sort == option) {
                        sort = option
                        applySearch()
                    }
                }
                if let archetypeFilter {
                    filterChip(archetypeFilter) { self.archetypeFilter = nil; applySearch() }
                }
                if let diseaseFilter {
                    filterChip(diseaseFilter) { self.diseaseFilter = nil; applySearch() }
                }
            }
            .padding(.horizontal, ForgeLayout.cardPadding)
            .padding(.vertical, FDS.Spacing.sm)
        }
        .padding(.horizontal, -ForgeLayout.cardPadding)
    }

    private func filterChip(_ title: String, clear: @escaping () -> Void) -> some View {
        ForgeChipButton(label: title, icon: "xmark", energy: .steel, selected: true, action: clear)
            .accessibilityHint("Clears this filter")
    }

    private var resultSummary: String {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            return "Browse \(page.total.formatted()) medications by \(sort.label.lowercased())."
        }
        return "\(page.total.formatted()) matches for “\(q)” — brand and generic."
    }

    /// Agenda row: well, name over both names over the facts, then a 44 pt
    /// add or check mark. Tapping the row adds or removes it from the list.
    private func pharmacyRow(_ med: FDAMedication) -> some View {
        let isSaved = saved.contains { $0.caseInsensitiveCompare(med.name) == .orderedSame }
        let facts = [med.strength, med.form, med.archetype, med.disease]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        return Button {
            ForgeHaptics.play(.selection)
            MedicationPharmacy.toggleSaved(name: med.name)
            saved = MedicationPharmacy.savedNames()
            AriaContextStore.shared.applyMedicationLayer()
        } label: {
            HStack(alignment: .center, spacing: ForgeLayout.rowGap) {
                ForgeIconWell(systemImage: isSaved ? "pills.fill" : "pills", tint: .steel)
                VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                    Text(med.brandOrGeneric)
                        .font(HomeType.status)
                        .foregroundStyle(Color.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    if med.bothNames != med.brandOrGeneric {
                        Text(med.bothNames)
                            .font(HomeType.body)
                            .foregroundStyle(Color.textSecondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(1)
                    }
                    if !facts.isEmpty {
                        Text(facts)
                            .font(HomeType.micro)
                            .foregroundStyle(Color.textTertiary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
                Image(systemName: isSaved ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isSaved ? Color.vitality : Color.steel)
                    .frame(width: ForgeUX.minTap, height: ForgeUX.minTap)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, ForgeLayout.rowVerticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(med.bothNames). \(med.archetype). \(med.disease). \(isSaved ? "On your list" : "Add to your list")")
        .accessibilityAddTraits(isSaved ? .isSelected : [])
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

    // MARK: Pieces

    /// "1  Apple Health" over its one-line subtitle. The badge scales with
    /// Dynamic Type instead of clipping its digit in a fixed circle.
    private func stepHeader(number: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: ForgeLayout.rowGap) {
            Text(number)
                .font(HomeType.micro)
                .foregroundStyle(Color.steel)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(minWidth: badgeSize, minHeight: badgeSize)
                .background(Circle().fill(Color.steel.opacity(0.16)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text(title)
                    .font(ForgeType.title)
                    .foregroundStyle(Color.textPrimary)
                    .forgeWrapping()
                Text(subtitle)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number), \(title). \(subtitle)")
        .accessibilityAddTraits(.isHeader)
    }

    /// A one-line-or-two notice on the card surface: info in steel, a missing
    /// connection in warning. Never red.
    private func noticeCard(_ message: String, systemImage: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: ForgeLayout.rowGap) {
            Image(systemName: systemImage)
                .font(.system(size: ForgeUX.icon, weight: .semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(message)
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: ForgeUX.minTap)
        .forgeContentCard(tint: tint, padding: ForgeLayout.compactCardPadding)
        .accessibilityElement(children: .combine)
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
            await health.applyConnectedHealthToForge()
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

    private func admitPickedPhoto(_ item: PhotosPickerItem) async {
#if canImport(UIKit)
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            bottleScan = MedicationBottleScan(
                rawText: "",
                tokensUsed: [],
                admitted: nil,
                candidates: []
            )
            return
        }
        await admitBottle(image)
#endif
        photoItem = nil
    }

    private func admitBottle(_ image: UIImage) async {
        scanningBottle = true
        defer { scanningBottle = false }
        await MedicationPharmacy.prepare()
#if canImport(Vision)
        let text = await MedicationBottleScanner.readText(from: image)
#else
        let text = ""
#endif
        let scan = MedicationBottleScanner.match(ocrText: text)
        bottleScan = scan
        if let med = scan.admitted {
            MedicationPharmacy.ensureSaved(name: med.name)
            saved = MedicationPharmacy.savedNames()
            AriaContextStore.shared.applyMedicationLayer()
            query = med.brandOrGeneric
            applySearch()
        } else if let first = scan.tokensUsed.first {
            query = first
            applySearch()
        }
    }
}
