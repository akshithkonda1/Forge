import Foundation
import SafariServices
import SwiftUI

@MainActor
final class DeviceConnectManager: NSObject, ObservableObject {
    static let shared = DeviceConnectManager()

    @Published private(set) var isPresentingSafari = false
    @Published private(set) var connectingProvider: IntegrationProvider?

    private var safariController: SFSafariViewController?
    private var onComplete: (() -> Void)?

    private override init() {}

    func connectWearable(_ device: WearableDevice, onComplete: @escaping () -> Void) async throws {
        if device.provider == .appleHealth {
            onComplete()
            return
        }

        connectingProvider = device.provider
        let callbacks = DeviceConnectManager.widgetCallbackURLs()

        let session = try await ForgeAPIClient.shared.createWearableWidgetSession(
            successRedirectUrl: callbacks.success,
            failureRedirectUrl: callbacks.failure,
            language: "en"
        )

        guard let urlString = session.url, let url = URL(string: urlString) else {
            connectingProvider = nil
            throw ForgeAPIError.server(502, "Device connection session did not return a URL.")
        }

        self.onComplete = onComplete
        presentSafari(url: url)
    }

    func syncProvider(_ provider: IntegrationProvider) async throws {
        _ = try await ForgeAPIClient.shared.syncIntegration(provider: provider.rawValue)
    }

    private func presentSafari(url: URL) {
        let controller = SFSafariViewController(url: url)
        controller.delegate = self
        controller.preferredControlTintColor = UIColor(Color.ember)
        safariController = controller
        isPresentingSafari = true

        guard
            let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController
        else {
            connectingProvider = nil
            isPresentingSafari = false
            return
        }

        var presenter = root
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        presenter.present(controller, animated: true)
    }

    static func widgetCallbackURLs() -> (success: String, failure: String) {
        if let base = Bundle.main.object(forInfoDictionaryKey: "FORGE_WEB_CALLBACK_BASE_URL") as? String,
           !base.isEmpty {
            if base.hasPrefix("forge://") {
                let trimmed = base.hasSuffix("/") ? String(base.dropLast()) : base
                return (
                    success: "\(trimmed)/success",
                    failure: "\(trimmed)/failure"
                )
            }
            let trimmed = base.hasSuffix("/") ? String(base.dropLast()) : base
            return (
                success: "\(trimmed)/integrations/terra/callback/success",
                failure: "\(trimmed)/integrations/terra/callback/failure"
            )
        }
        return (
            success: "forge://device-connected/success",
            failure: "forge://device-connected/failure"
        )
    }
}

extension DeviceConnectManager: SFSafariViewControllerDelegate {
    nonisolated func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        Task { @MainActor in
            isPresentingSafari = false
            connectingProvider = nil
            let completion = onComplete
            onComplete = nil
            completion?()
        }
    }
}