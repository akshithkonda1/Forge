import SwiftUI
import ForgeCore

/// Browse, connect and disconnect wearables and health tools that speak iOS
/// and Apple Health. Connecting does not invent a vendor API — it records
/// that you own the device and, where relevant, re-asks HealthKit so Forge
/// can read what that device already writes.
struct ConnectedDevicesLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject var store: AppStore

    @State private var query = ""
    @State private var category: HealthDeviceCategory?
    @State private var selected: HealthDevice?
    @State private var healthSources: [String] = []
    @State private var busyID: String?

    private var connectedIDs: [String] {
        HealthDeviceCatalog.migrateStoredIDs(store.userProfile.connectedDevices)
    }

    private var connected: [HealthDevice] {
        connectedIDs.compactMap { HealthDeviceCatalog.device(matching: $0) }
    }

    private var library: [HealthDevice] {
        let base = HealthDeviceCatalog.search(query)
        if let category { return base.filter { $0.category == category } }
        return base
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    searchBar
                    categoryPills
                    if !connected.isEmpty {
                        sectionTitle("On this iPhone")
                        ForEach(connected) { device in
                            deviceRow(device, connected: true)
                        }
                    }
                    sectionTitle(query.isEmpty ? "Compatible library" : "Results")
                    Text("Every tool here has an iOS app. Most write sleep, water, heart or workouts into Apple Health — the same ledger Forge already reads.")
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)
                    ForEach(library) { device in
                        deviceRow(device, connected: connectedIDs.contains(device.id))
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .background(Color.background)
            .navigationTitle("Devices & tools")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                migrateIfNeeded()
                healthSources = await HealthKitManager.shared.knownHealthSources()
            }
            .sheet(item: $selected) { device in
                DeviceDetailSheet(
                    device: device,
                    isConnected: connectedIDs.contains(device.id),
                    seenInHealth: isSeenInHealth(device),
                    isBusy: busyID == device.id,
                    onConnect: { Task { await connect(device) } },
                    onDisconnect: { disconnect(device) },
                    onOpenStore: { openStore(device) }
                )
                .presentationDetents([.medium, .large])
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundColor(.textTertiary)
            TextField("Search LARQ, Oura, Garmin…", text: $query)
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

    private var categoryPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                pill("All", selected: category == nil) { category = nil }
                ForEach(HealthDeviceCategory.allCases) { cat in
                    pill(cat.title, selected: category == cat) { category = cat }
                }
            }
        }
    }

    private func pill(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(selected ? .white : .textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(selected ? Color.ember : Color.surface)
                .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .black))
            .tracking(1.2)
            .foregroundColor(.textTertiary)
    }

    private func deviceRow(_ device: HealthDevice, connected: Bool) -> some View {
        Button { selected = device } label: {
            HStack(spacing: 12) {
                Image(systemName: device.symbolName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(connected ? .ember : .steel)
                    .frame(width: 36, height: 36)
                    .background((connected ? Color.ember : Color.steel).opacity(0.14))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(device.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Text(device.maker + " · " + device.category.title)
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)
                    HStack(spacing: 6) {
                        if device.writesToAppleHealth {
                            badge("Apple Health", color: .vitality)
                        }
                        if device.hasIOSApp {
                            badge("iOS", color: .steel)
                        }
                        if isSeenInHealth(device) {
                            badge("Seen in Health", color: .ember)
                        }
                    }
                }
                Spacer(minLength: 0)
                if connected {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.vitality)
                } else {
                    Image(systemName: "plus.circle").foregroundColor(.textTertiary)
                }
            }
            .padding(12)
            .background(Color.surface)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.borderColor.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.14))
            .cornerRadius(6)
    }

    private func isSeenInHealth(_ device: HealthDevice) -> Bool {
        let needles = [device.name, device.maker, device.id]
            .map { $0.lowercased() }
        return healthSources.contains { source in
            let s = source.lowercased()
            return needles.contains { s.contains($0) }
        }
    }

    private func connect(_ device: HealthDevice) async {
        busyID = device.id
        defer { busyID = nil }
        if device.writesToAppleHealth {
            _ = try? await HealthKitManager.shared.requestAuthorization()
            await store.reconnectHealthKit()
            healthSources = await HealthKitManager.shared.knownHealthSources()
        }
        store.connectHealthDevice(device.id)
        selected = nil
    }

    private func disconnect(_ device: HealthDevice) {
        store.disconnectHealthDevice(device.id)
        selected = nil
    }

    private func openStore(_ device: HealthDevice) {
        guard let raw = device.appStoreURL, let url = URL(string: raw) else { return }
        openURL(url)
    }

    private func migrateIfNeeded() {
        let migrated = HealthDeviceCatalog.migrateStoredIDs(store.userProfile.connectedDevices)
        if migrated != store.userProfile.connectedDevices {
            store.updateProfile(connectedDevices: migrated)
        }
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
                    HStack(spacing: 12) {
                        Image(systemName: device.symbolName)
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(.ember)
                            .frame(width: 56, height: 56)
                            .background(Color.ember.opacity(0.14))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(device.name)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.textPrimary)
                            Text(device.maker)
                                .font(.system(size: 14))
                                .foregroundColor(.textSecondary)
                        }
                    }

                    Text(device.summary)
                        .font(.system(size: 14))
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        if device.writesToAppleHealth { chip("Apple Health") }
                        if device.hasIOSApp { chip("iOS app") }
                        if device.worksWithAppleWatch { chip("Apple Watch") }
                        if seenInHealth { chip("Seen in Health") }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("What it tracks")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.textPrimary)
                        FlowLayout(spacing: 8) {
                            ForEach(device.metrics, id: \.self) { metric in
                                Text(metric)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.textSecondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.surfaceElevated)
                                    .cornerRadius(100)
                            }
                        }
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

                    if device.appStoreURL != nil {
                        Button(action: onOpenStore) {
                            label(isBusy ? "Opening…" : "Open iOS app", icon: "arrow.up.forward.app.fill")
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
                            label(isBusy ? "Connecting…" : "Add to Forge", icon: "plus.circle.fill")
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

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.ember)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.ember.opacity(0.12))
            .cornerRadius(8)
    }

    private func label(_ title: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
            Text(title)
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.ember)
        .cornerRadius(12)
    }
}
