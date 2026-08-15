import Foundation
import Combine
import ForgeCore

/// Keeps the device shelf current without an App Store release.
///
/// 1. Bundled catalog is instant.
/// 2. `GET /devices/catalog` overlays newer SKUs and retires.
/// 3. HealthKit sources this phone has already seen become rows automatically
///    and are reported so the next fetch can include them for everyone.
@MainActor
final class HealthDeviceCatalogSync: ObservableObject {
    static let shared = HealthDeviceCatalogSync()

    @Published private(set) var revision = 0
    @Published private(set) var lastUpdated: Date?

    private let cacheURL: URL
    private var lastPostedIDs = Set<String>()

    private init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        cacheURL = folder.appendingPathComponent("health-device-catalog.json")
        loadCached()
    }

    func loadCached() {
        guard let data = try? Data(contentsOf: cacheURL),
              let payload = try? HealthDeviceCatalog.decodePayload(data) else { return }
        HealthDeviceCatalog.applyRemote(payload)
        bump()
    }

    func refresh(healthSources: [String] = []) async {
        loadCached()
        if let payload = await fetchRemote() {
            try? HealthDeviceCatalog.encodePayload(payload).write(to: cacheURL, options: .atomic)
            HealthDeviceCatalog.applyRemote(payload)
        }
        let discovered = HealthDeviceCatalog.inferredDevices(fromHealthSources: healthSources)
        HealthDeviceCatalog.applyDiscovered(discovered)
        await reportSeen(discovered)
        lastUpdated = Date()
        bump()
    }

    private func fetchRemote() async -> HealthDeviceCatalogPayload? {
        var request = URLRequest(url: AriaService.shared.baseURL.appendingPathComponent("devices/catalog"))
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else { return nil }
        return try? HealthDeviceCatalog.decodePayload(data)
    }

    private func reportSeen(_ devices: [HealthDevice]) async {
        let fresh = devices.filter { lastPostedIDs.insert($0.id).inserted }
        guard !fresh.isEmpty else { return }
        var request = URLRequest(url: AriaService.shared.baseURL.appendingPathComponent("devices/catalog/seen"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 8
        if let token = UserDefaults.standard.string(forKey: "forge.aria.authToken"), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let payload = HealthDeviceCatalogPayload(devices: fresh)
        request.httpBody = try? HealthDeviceCatalog.encodePayload(payload)
        _ = try? await URLSession.shared.data(for: request)
    }

    private func bump() {
        revision += 1
        NotificationCenter.default.post(name: .healthDeviceCatalogDidChange, object: nil)
    }
}

extension Notification.Name {
    static let healthDeviceCatalogDidChange = Notification.Name("forge.healthDeviceCatalogDidChange")
}
