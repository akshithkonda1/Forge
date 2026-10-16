import SwiftUI
import ForgeCore

private enum DeviceLibrarySort: String, CaseIterable, Identifiable {
    case newest, company, type, selected
    var id: String { rawValue }
    var title: String {
        switch self {
        case .newest: return "Newest"
        case .company: return "Company"
        case .type: return "Type"
        case .selected: return "Selected"
        }
    }
}

/// Company first, then that company's products. Select as many as you own.
/// Connecting records ownership and re-asks HealthKit so Forge can read
/// what those products already write.
struct ConnectedDevicesLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: AppStore
    @ObservedObject private var liveCatalog = HealthDeviceCatalogSync.shared

    @State private var query = ""
    @State private var typeFilter: HealthDeviceCategory?
    @State private var sort: DeviceLibrarySort = .newest
    @State private var healthSources: [String] = []

    private var connectedIDs: [String] {
        HealthDeviceCatalog.migrateStoredIDs(store.userProfile.connectedDevices)
    }

    private var connected: [HealthDevice] {
        connectedIDs.compactMap { HealthDeviceCatalog.device(matching: $0) }
    }

    private var brands: [HealthDeviceBrand] {
        let found = HealthDeviceCatalog.searchBrands(query, category: typeFilter)
        switch sort {
        case .newest:
            return found.sorted {
                if $0.newestYear != $1.newestYear { return $0.newestYear > $1.newestYear }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .company:
            return found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .type:
            return found.sorted {
                if $0.primaryCategory.title != $1.primaryCategory.title {
                    return $0.primaryCategory.title < $1.primaryCategory.title
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .selected:
            return found.sorted {
                let left = selectedCount($0)
                let right = selectedCount($1)
                if left != right { return left > right }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }

    private func selectedCount(_ brand: HealthDeviceBrand) -> Int {
        HealthDeviceCatalog.devices(fromMaker: brand.name, listedOnly: false)
            .filter { connectedIDs.contains($0.id) }
            .count
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                ForgeScreenStack(top: ForgeLayout.screenTop) {
                    controls
                    if !connected.isEmpty {
                        connectedCard
                    }
                    companiesCard
                }
            }
            .forgeScreenBackground(accent: .steel)
            .navigationTitle("Devices")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                migrateIfNeeded()
                healthSources = await HealthKitManager.shared.knownHealthSources()
                await liveCatalog.refresh(healthSources: healthSources)
            }
        }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchBar
            filterRow
            sortRow
        }
    }

    private var searchBar: some View {
        HStack(spacing: ForgeLayout.rowGap) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.textTertiary)
                .accessibilityHidden(true)
            TextField("Apple, Garmin, LARQ…", text: $query)
                .font(HomeType.body)
                .foregroundStyle(Color.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.textTertiary)
                        .frame(minWidth: ForgeUX.minTap, minHeight: ForgeUX.minTap)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, ForgeLayout.tilePadding)
        .padding(.trailing, query.isEmpty ? ForgeLayout.tilePadding : 0)
        .frame(minHeight: ForgeUX.minTap)
        .forgeInsetTile(radius: FDS.Radius.md)
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ForgeLayout.chipGap) {
                ForgeChipButton(label: "All", energy: .steel, selected: typeFilter == nil) {
                    typeFilter = nil
                }
                ForEach(HealthDeviceCategory.allCases) { category in
                    ForgeChipButton(label: category.title, energy: .steel, selected: typeFilter == category) {
                        typeFilter = category
                    }
                }
            }
            .padding(.horizontal, ForgeLayout.screenInset)
            .padding(.vertical, FDS.Spacing.sm)
        }
        .padding(.horizontal, -ForgeLayout.screenInset)
    }

    private var sortRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ForgeLayout.chipGap) {
                Text("Sort")
                    .font(HomeType.micro)
                    .foregroundStyle(Color.textTertiary)
                    .padding(.trailing, ForgeLayout.pairGap)
                ForEach(DeviceLibrarySort.allCases) { option in
                    ForgeChipButton(label: option.title, energy: .steel, selected: sort == option) {
                        sort = option
                    }
                }
            }
            .padding(.horizontal, ForgeLayout.screenInset)
            .padding(.vertical, FDS.Spacing.sm)
        }
        .padding(.horizontal, -ForgeLayout.screenInset)
    }

    // MARK: Cards

    private var connectedCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("On this iPhone", meta: "\(connected.count)")
            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                ForEach(connected) { device in
                    NavigationLink {
                        CompanyProductsView(
                            maker: device.maker,
                            healthSources: $healthSources
                        )
                    } label: {
                        productSummary(device)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows \(device.maker) products")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeContentCard()
    }

    private var catalogNote: String {
        let lead = sort == .newest ? "Newest first. " : ""
        if liveCatalog.lastUpdated == nil {
            return lead + "New products land from the live shelf and from Apple Health on this iPhone."
        }
        return lead + "Live shelf is current. Older incompatible models fall off after five cycles."
    }

    private var companiesCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader(query.isEmpty ? "Companies" : "Results", meta: "\(brands.count)")
            Text(catalogNote)
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
                .id(liveCatalog.revision)
            if brands.isEmpty {
                ForgeEmptyNote(
                    title: "No matches",
                    message: "Try a different name or clear the filter.",
                    systemImage: "magnifyingglass"
                )
            } else {
                VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                    ForEach(brands) { brand in
                        NavigationLink {
                            CompanyProductsView(
                                maker: brand.name,
                                healthSources: $healthSources
                            )
                        } label: {
                            companyRow(brand)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Shows \(brand.name) products")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeContentCard()
    }

    // MARK: Rows

    private func companyRow(_ brand: HealthDeviceBrand) -> some View {
        let selected = selectedCount(brand)
        return HStack(spacing: ForgeLayout.rowGap) {
            DeviceArtworkStack(devices: brand.previewDevices, size: 48)
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text(brand.name)
                    .font(HomeType.status)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                Text(companySubtitle(brand, selected: selected))
                    .font(HomeType.body)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(2)
            }
            .layoutPriority(1)
            Spacer(minLength: FDS.Spacing.xs)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textMuted)
                .accessibilityHidden(true)
        }
        .padding(.vertical, ForgeLayout.rowVerticalPadding)
        .frame(minHeight: ForgeUX.minTap)
        .contentShape(Rectangle())
    }

    private func companySubtitle(_ brand: HealthDeviceBrand, selected: Int) -> String {
        let products = brand.productCount == 1 ? "1 product" : "\(brand.productCount) products"
        let year = brand.newestYear > 0 ? " · \(brand.newestYear)" : ""
        if selected == 0 { return products + year }
        return "\(products)\(year) · \(selected) selected"
    }

    private func productSummary(_ device: HealthDevice) -> some View {
        HStack(spacing: ForgeLayout.rowGap) {
            DeviceProductImage(device: device, size: 44, cornerRadius: FDS.Radius.sm)
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text(device.name)
                    .font(HomeType.status)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                Text(device.maker)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(2)
            }
            .layoutPriority(1)
            Spacer(minLength: FDS.Spacing.xs)
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.vitality)
                .accessibilityLabel("Selected")
        }
        .padding(.vertical, ForgeLayout.rowVerticalPadding)
        .frame(minHeight: ForgeUX.minTap)
        .contentShape(Rectangle())
    }

    private func migrateIfNeeded() {
        let migrated = HealthDeviceCatalog.migrateStoredIDs(store.userProfile.connectedDevices)
        if migrated != store.userProfile.connectedDevices {
            store.updateProfile(connectedDevices: migrated)
        }
    }
}

// MARK: - Company → products

private struct CompanyProductsView: View {
    let maker: String
    @Binding var healthSources: [String]
    @EnvironmentObject var store: AppStore
    @Environment(\.openURL) private var openURL

    @State private var busyID: String?
    @State private var detail: HealthDevice?

    private var products: [HealthDevice] {
        let listed = HealthDeviceCatalog.devices(fromMaker: maker, listedOnly: true)
        let retiredOwned = HealthDeviceCatalog.devices(fromMaker: maker, listedOnly: false)
            .filter { device in
                connectedIDs.contains(device.id) && !listed.contains { $0.id == device.id }
            }
        return (listed + retiredOwned).sorted {
            if $0.category.title != $1.category.title {
                return $0.category.title < $1.category.title
            }
            if $0.generation != $1.generation {
                return $0.generation > $1.generation
            }
            return $0.releasedYear > $1.releasedYear
        }
    }

    private var groupedProducts: [(title: String, products: [HealthDevice])] {
        Dictionary(grouping: products, by: \.category)
            .map { ($0.key.title, $0.value) }
            .sorted { $0.0 < $1.0 }
    }

    private var connectedIDs: [String] {
        HealthDeviceCatalog.migrateStoredIDs(store.userProfile.connectedDevices)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            ForgeScreenStack(top: ForgeLayout.screenTop) {
                Text("Select every \(maker) product you own. You can pick more than one.")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()

                if groupedProducts.isEmpty {
                    ForgeEmptyNote(
                        title: "Nothing listed yet",
                        message: "New \(maker) products show up here as the live shelf updates.",
                        systemImage: "sensor.tag.radiowaves.forward"
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .forgeContentCard()
                } else {
                    ForEach(groupedProducts, id: \.title) { group in
                        groupCard(group)
                    }
                }
            }
        }
        .forgeScreenBackground(accent: .steel)
        .navigationTitle(maker)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $detail) { device in
            DeviceDetailSheet(
                device: device,
                isConnected: connectedIDs.contains(device.id),
                seenInHealth: isSeenInHealth(device),
                isBusy: busyID == device.id,
                onConnect: { Task { await setConnected(device, true) } },
                onDisconnect: { Task { await setConnected(device, false) } },
                onOpenStore: { openStore(device) }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func groupCard(_ group: (title: String, products: [HealthDevice])) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            if groupedProducts.count > 1 {
                ForgeCardHeader(group.title, meta: "\(group.products.count)")
            }
            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                ForEach(group.products) { device in
                    productRow(device, selected: connectedIDs.contains(device.id))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeContentCard()
    }

    private func productRow(_ device: HealthDevice, selected: Bool) -> some View {
        let busy = busyID == device.id
        return HStack(alignment: .top, spacing: ForgeLayout.rowGap) {
            Button {
                ForgeHaptics.play(.selection)
                Task { await setConnected(device, !selected) }
            } label: {
                selectionGlyph(selected: selected, busy: busy)
                    .frame(minWidth: ForgeUX.minTap, minHeight: ForgeUX.minTap)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(busy)
            .accessibilityLabel(selected ? "Deselect \(device.name)" : "Select \(device.name)")

            Button {
                detail = device
            } label: {
                productDetailLabel(device)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows details")
        }
        .opacity(busy ? 0.55 : 1)
    }

    @ViewBuilder
    private func selectionGlyph(selected: Bool, busy: Bool) -> some View {
        if busy {
            ProgressView().controlSize(.small)
        } else {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(selected ? Color.ember : Color.textTertiary)
        }
    }

    private func productDetailLabel(_ device: HealthDevice) -> some View {
        HStack(alignment: .top, spacing: ForgeLayout.rowGap) {
            DeviceProductImage(device: device, size: 64, cornerRadius: FDS.Radius.md)
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text(device.name)
                    .font(HomeType.status)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                Text(device.summary)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(2)
                Text(metaLine(device))
                    .font(HomeType.micro)
                    .foregroundStyle(Color.textTertiary)
                    .forgeWrapping()
                let tags = tagLabels(device)
                if !tags.isEmpty {
                    ForgeFlowLayout(spacing: ForgeLayout.chipGap, lineSpacing: ForgeLayout.chipGap) {
                        ForEach(tags, id: \.self) { tag in
                            HudVibeChip(label: tag, energy: .ember)
                        }
                    }
                }
            }
        }
    }

    /// Year plus where the product reports from, as one line.
    private func metaLine(_ device: HealthDevice) -> String {
        var parts: [String] = [String(device.releasedYear)]
        if !device.id.hasPrefix("discovered-") {
            if HealthDeviceCatalog.isListed(device) == false {
                parts.append("Past 5 cycles")
            } else if device.writesToAppleHealth {
                parts.append("Apple Health")
            }
        }
        return parts.joined(separator: " · ")
    }

    /// The two highest-priority status labels, shown as tinted chips.
    private func tagLabels(_ device: HealthDevice) -> [String] {
        var tags: [String] = []
        if isSeenInHealth(device) { tags.append("Seen in Health") }
        if device.id.hasPrefix("discovered-") { tags.append("On this iPhone") }
        if device.soldSeparatelyNote != nil { tags.append("Sold separately") }
        return Array(tags.prefix(2))
    }

    private func setConnected(_ device: HealthDevice, _ on: Bool) async {
        busyID = device.id
        defer { busyID = nil }
        if on {
            if device.writesToAppleHealth {
                _ = try? await HealthKitManager.shared.requestAuthorization()
                await store.reconnectHealthKit()
                healthSources = await HealthKitManager.shared.knownHealthSources()
            }
            store.connectHealthDevice(device.id)
        } else {
            store.disconnectHealthDevice(device.id)
        }
    }

    private func isSeenInHealth(_ device: HealthDevice) -> Bool {
        let needles = [device.name, device.maker, device.id].map { $0.lowercased() }
        return healthSources.contains { source in
            let s = source.lowercased()
            return needles.contains { s.contains($0) }
        }
    }

    private func openStore(_ device: HealthDevice) {
        guard let raw = device.appStoreURL, let url = URL(string: raw) else { return }
        openURL(url)
    }
}

private struct DeviceDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let device: HealthDevice
    let isConnected: Bool
    let seenInHealth: Bool
    let isBusy: Bool
    let onConnect: () -> Void
    let onDisconnect: () -> Void
    let onOpenStore: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                ForgeScreenStack(top: ForgeLayout.screenTop) {
                    header
                    Text(device.summary)
                        .font(HomeType.body)
                        .foregroundStyle(Color.textSecondary)
                        .forgeWrapping()
                    if let note = device.soldSeparatelyNote {
                        Text(note)
                            .font(HomeType.body)
                            .foregroundStyle(Color.textSecondary)
                            .forgeWrapping()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .forgeWell()
                            .accessibilityLabel(note)
                    }
                    trackingCard
                    connectCard
                    actions
                }
            }
            .forgeScreenBackground(accent: .steel)
            .navigationTitle(device.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        ForgeAdaptiveStack(spacing: ForgeLayout.rowGap) {
            DeviceProductImage(device: device, size: 84, cornerRadius: FDS.Radius.lg)
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text(device.name)
                    .font(ForgeType.title)
                    .foregroundStyle(Color.textPrimary)
                    .forgeWrapping()
                    .accessibilityAddTraits(.isHeader)
                Text(device.maker + " · " + device.category.title)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var trackingCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("What it tracks")
            ForgeFlowLayout(spacing: ForgeLayout.chipGap, lineSpacing: ForgeLayout.chipGap) {
                ForEach(device.metrics, id: \.self) { metric in
                    ForgeChip(label: metric)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeContentCard()
    }

    private var connectCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("How to connect")
            Text(device.setupHint)
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
            if seenInHealth {
                Text("Apple Health has already seen this source on this iPhone.")
                    .font(HomeType.body)
                    .foregroundStyle(Color.ember)
                    .forgeWrapping()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeContentCard()
    }

    private var actions: some View {
        VStack(spacing: ForgeLayout.tileGap) {
            if !isConnected {
                ForgePrimaryButton(
                    title: isBusy ? "Adding…" : "Add this product",
                    icon: isBusy ? "arrow.triangle.2.circlepath" : "plus",
                    action: onConnect
                )
                .disabled(isBusy)
            }
            if device.appStoreURL != nil {
                ForgeSecondaryButton(
                    title: "Open iOS app",
                    icon: "arrow.up.forward.app",
                    accent: .steel,
                    action: onOpenStore
                )
                .disabled(isBusy)
            }
            if isConnected {
                ForgeSecondaryButton(
                    title: "Remove from Forge",
                    icon: "minus.circle",
                    accent: .danger,
                    action: onDisconnect
                )
            }
        }
    }
}
