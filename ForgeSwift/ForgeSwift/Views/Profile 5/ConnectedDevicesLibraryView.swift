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
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    searchBar
                    filterRow
                    sortRow

                    if !connected.isEmpty {
                        Text("On this iPhone")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.textTertiary)
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
                        }
                    }

                    Text(query.isEmpty ? "Companies" : "Results")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.textTertiary)
                    Text(liveCatalog.lastUpdated == nil
                         ? "Newest first. New products land from the live shelf and from Apple Health on this iPhone."
                         : "Newest first. Live shelf is current. Older incompatible models fall off after five cycles.")
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)
                        .id(liveCatalog.revision)

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
                    }
                }
                .padding(20)
                .padding(.bottom, 24)
            }
            .background(Color.background)
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

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundColor(.textTertiary)
            TextField("Apple, Garmin, LARQ…", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.textMuted)
                }
            }
        }
        .padding(12)
        .background(Color.surface)
        .cornerRadius(12)
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip("All", selected: typeFilter == nil) { typeFilter = nil }
                ForEach(HealthDeviceCategory.allCases) { category in
                    filterChip(category.title, selected: typeFilter == category) {
                        typeFilter = category
                    }
                }
            }
        }
    }

    private var sortRow: some View {
        HStack(spacing: 8) {
            Text("Sort")
                .font(.system(size: 12))
                .foregroundColor(.textTertiary)
            ForEach(DeviceLibrarySort.allCases) { option in
                Button {
                    sort = option
                } label: {
                    Text(option.title)
                        .font(.system(size: 12, weight: sort == option ? .semibold : .medium))
                        .foregroundColor(sort == option ? .textPrimary : .textTertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(sort == option ? Color.white.opacity(0.08) : Color.clear)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private func filterChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(selected ? .background : .textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(selected ? Color.textPrimary : Color.surface)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func companyRow(_ brand: HealthDeviceBrand) -> some View {
        let selected = selectedCount(brand)
        return HStack(spacing: 12) {
            DeviceArtworkStack(devices: brand.previewDevices, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(brand.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Text(companySubtitle(brand, selected: selected))
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.textMuted)
        }
        .padding(.vertical, 10)
    }

    private func companySubtitle(_ brand: HealthDeviceBrand, selected: Int) -> String {
        let products = brand.productCount == 1 ? "1 product" : "\(brand.productCount) products"
        let year = brand.newestYear > 0 ? " · \(brand.newestYear)" : ""
        if selected == 0 { return products + year }
        return "\(products)\(year) · \(selected) selected"
    }

    private func productSummary(_ device: HealthDevice) -> some View {
        HStack(spacing: 12) {
            DeviceProductImage(device: device, size: 44, cornerRadius: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Text(device.maker)
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
            }
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.vitality)
        }
        .padding(.vertical, 6)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Select every \(maker) product you own. You can pick more than one.")
                    .font(.system(size: 14))
                    .foregroundColor(.textSecondary)
                    .padding(.bottom, 8)

                ForEach(groupedProducts, id: \.title) { group in
                    if groupedProducts.count > 1 {
                        Text(group.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.textTertiary)
                            .padding(.top, 10)
                    }
                    ForEach(group.products) { device in
                        productRow(device, selected: connectedIDs.contains(device.id))
                    }
                }
            }
            .padding(20)
        }
        .background(Color.background)
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
        }
    }

    private func productRow(_ device: HealthDevice, selected: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                Task { await setConnected(device, !selected) }
            } label: {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(selected ? .ember : .textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(selected ? "Deselect \(device.name)" : "Select \(device.name)")

            Button { detail = device } label: {
                HStack(alignment: .top, spacing: 12) {
                    DeviceProductImage(device: device, size: 64, cornerRadius: 12)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(device.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.textPrimary)
                        Text(device.summary)
                            .font(.system(size: 12))
                            .foregroundColor(.textSecondary)
                            .lineLimit(2)
                        HStack(spacing: 8) {
                            Text(String(device.releasedYear))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.textTertiary)
                            if device.id.hasPrefix("discovered-") {
                                Text("On this iPhone")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.ember)
                            } else if HealthDeviceCatalog.isListed(device) == false {
                                Text("Past 5 cycles")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.textMuted)
                            } else if device.writesToAppleHealth {
                                Text("Apple Health")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.textTertiary)
                            }
                            if isSeenInHealth(device) {
                                Text("Seen in Health")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.ember)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
        .opacity(busyID == device.id ? 0.55 : 1)
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
    let device: HealthDevice
    let isConnected: Bool
    let seenInHealth: Bool
    let isBusy: Bool
    let onConnect: () -> Void
    let onDisconnect: () -> Void
    let onOpenStore: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .center, spacing: 14) {
                        DeviceProductImage(device: device, size: 84, cornerRadius: 16)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(device.name)
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(.textPrimary)
                            Text(device.maker + " · " + device.category.title)
                                .font(.system(size: 14))
                                .foregroundColor(.textSecondary)
                        }
                    }

                    Text(device.summary)
                        .font(.system(size: 14))
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("What it tracks")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.textPrimary)
                        Text(device.metrics.joined(separator: " · "))
                            .font(.system(size: 13))
                            .foregroundColor(.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("How to connect")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.textPrimary)
                        Text(device.setupHint)
                            .font(.system(size: 13))
                            .foregroundColor(.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if seenInHealth {
                        Text("Apple Health has already seen this source on this iPhone.")
                            .font(.system(size: 12))
                            .foregroundColor(.ember)
                    }

                    if device.appStoreURL != nil {
                        Button(action: onOpenStore) {
                            Text("Open iOS app")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.surfaceElevated)
                                .cornerRadius(12)
                        }
                        .disabled(isBusy)
                    }

                    if isConnected {
                        Button(action: onDisconnect) {
                            Text("Remove from Forge")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.danger)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.surfaceElevated)
                                .cornerRadius(12)
                        }
                    } else {
                        Button(action: onConnect) {
                            Text(isBusy ? "Adding…" : "Add this product")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.ember)
                                .cornerRadius(12)
                        }
                        .disabled(isBusy)
                    }
                }
                .padding(20)
            }
            .background(Color.background)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
