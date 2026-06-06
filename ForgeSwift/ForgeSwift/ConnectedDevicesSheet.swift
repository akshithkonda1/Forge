import SwiftUI

struct ConnectedDevicesSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var deviceManager = DeviceConnectManager.shared
    @State private var errorMessage: String?
    @State private var syncingProvider: IntegrationProvider?

    var body: some View {
        NavigationStack {
            List {
                if let service = store.deviceServiceStatus {
                    Section {
                        HStack {
                            Circle()
                                .fill(service.configured ? Color.success : Color.warning)
                                .frame(width: 8, height: 8)
                            Text(service.configured ? "Wearable linking is available" : "Wearable linking is not configured on this backend")
                                .font(.system(size: 13))
                                .foregroundColor(.textSecondary)
                        }
                    }
                }

                Section("Your Devices") {
                    ForEach(WearableDevice.catalog) { device in
                        deviceRow(device)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .foregroundColor(.danger)
                    }
                }
            }
            .navigationTitle("Connect Devices")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.ember)
                }
            }
        }
    }

    @ViewBuilder
    private func deviceRow(_ device: WearableDevice) -> some View {
        let connection = store.connections.first { $0.provider == device.provider }
        let isConnected = connection?.status == .connected || connection?.status == .syncing
        let isBusy = deviceManager.connectingProvider == device.provider || syncingProvider == device.provider

        Button {
            Task { await handleDeviceTap(device, connection: connection) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: device.provider.icon)
                    .font(.system(size: 18))
                    .foregroundColor(.steel)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.textPrimary)
                    Text(statusLabel(connection: connection, isConnected: isConnected))
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                }

                Spacer()

                if isBusy {
                    ProgressView().scaleEffect(0.8)
                } else if isConnected {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 14))
                        .foregroundColor(.ember)
                } else {
                    Text("Connect")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.ember)
                }
            }
        }
        .disabled(isBusy || (device.provider != .appleHealth && store.deviceServiceStatus?.configured == false))
    }

    private func statusLabel(connection: IntegrationConnection?, isConnected: Bool) -> String {
        guard let connection else { return "Not connected" }
        switch connection.status {
        case .connected: return "Connected"
        case .syncing: return "Syncing"
        case .needsAuth: return "Needs authorization"
        case .error: return connection.errorMessage ?? "Connection error"
        }
    }

    private func handleDeviceTap(_ device: WearableDevice, connection: IntegrationConnection?) async {
        errorMessage = nil

        if device.provider == .appleHealth {
            await store.connectAppleHealth()
            return
        }

        if connection?.status == .connected || connection?.status == .syncing {
            syncingProvider = device.provider
            defer { syncingProvider = nil }
            do {
                try await deviceManager.syncProvider(device.provider)
                await store.refreshConnections()
                await store.loadDashboardFromAPI()
            } catch {
                errorMessage = error.localizedDescription
            }
            return
        }

        do {
            try await deviceManager.connectWearable(device) {
                Task {
                    if device.provider != .manual {
                        try? await deviceManager.syncProvider(device.provider)
                    }
                    await store.refreshConnections()
                    await store.loadDashboardFromAPI()
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}