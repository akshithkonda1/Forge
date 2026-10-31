import Foundation
import ForgeCore
import os
#if canImport(System)
import System
#endif

#if canImport(KokoroTTS)
import KokoroTTS
#endif
#if canImport(BackgroundAssets)
import BackgroundAssets
#endif
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Finds, verifies, and (after consent) hydrates the Kokoro-82M starter runtime.
///
/// Search order: Apple-hosted Background Assets pack, `Bundle.main`, then
/// Application Support. Speak never calls this downloader. On-Demand Resources
/// are not used.
@MainActor
final class AriaKokoroModelStore {
    static let shared = AriaKokoroModelStore()
    static let logger = Logger(subsystem: "com.forge.aria", category: "kokoro.model")

    private(set) var isDownloading = false
    private(set) var lastError: String?
    private var hydrateTask: Task<Bool, Never>?
    private var cachedPackRoot: URL?

    private init() {}

    var applicationSupportRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return AriaKokoroDelivery.applicationSupportRoot(base: base)
    }

    var compiledModelsDirectory: URL {
        applicationSupportRoot.appendingPathComponent("compiled", isDirectory: true)
    }

    var hasVerifiedRuntime: Bool {
        resolvedRuntimeURL() != nil
    }

    func resolvedRuntimeURL() -> URL? {
        locator.resolvedRoot { url in
            FileManager.default.fileExists(atPath: url.path)
        }
    }

    var locator: AriaKokoroRuntimeLocator {
        var roots: [URL] = []
        if let cachedPackRoot { roots.append(cachedPackRoot) }
        if let bundled = bundledRuntimeURL() { roots.append(bundled) }
        roots.append(applicationSupportRoot)
        return AriaKokoroRuntimeLocator(roots: roots)
    }

    func bundledRuntimeURL() -> URL? {
        if let url = Bundle.main.url(
            forResource: AriaKokoroDelivery.bundleResourceName,
            withExtension: AriaKokoroDelivery.bundleResourceExtension
        ) {
            return url
        }
        if let manifest = Bundle.main.url(
            forResource: "KokoroRuntimeManifest",
            withExtension: "json"
        ) {
            return manifest.deletingLastPathComponent()
        }
        return nil
    }

    func discover() async {
        cachedPackRoot = await backgroundAssetRoot()
        if hasVerifiedRuntime {
            AriaKokoroEngine.noteRuntimeBecameAvailable()
        }
    }

    /// Hydrate the pinned Hugging Face starter bundle into Application Support.
    /// Refuses unless a local copy is already present or the user consented.
    func prefetchIfAllowed(defaults: UserDefaults = .standard) async -> Bool {
        if hasVerifiedRuntime { return true }
        let consented = defaults.bool(forKey: AriaKokoroDelivery.consentKey)
        guard AriaKokoroDelivery.allowsPrefetch(hasLocalModel: false, consented: consented) else {
            return false
        }
        return await downloadPinnedBundle()
    }

    func downloadPinnedBundle() async -> Bool {
        if let existing = hydrateTask {
            return await existing.value
        }
        let task = Task { () -> Bool in
            await self.performDownload()
        }
        hydrateTask = task
        let ok = await task.value
        hydrateTask = nil
        return ok
    }

    func resetForTests() {
        hydrateTask?.cancel()
        hydrateTask = nil
        isDownloading = false
        lastError = nil
        cachedPackRoot = nil
    }

    private func performDownload() async -> Bool {
        #if canImport(KokoroTTS)
        guard AriaKokoroDelivery.isPinnedRevision(AriaKokoroVoice.hostedRevision) else {
            lastError = "Unpinned hosted revision."
            return false
        }
        isDownloading = true
        lastError = nil
        defer { isDownloading = false }
        do {
            try FileManager.default.createDirectory(at: applicationSupportRoot, withIntermediateDirectories: true)
            _ = try await KokoroResourceProvider.huggingFace(cacheDirectory: applicationSupportRoot)
            guard hasVerifiedRuntime else {
                lastError = "Download finished without a verified runtime."
                return false
            }
            guard verifyHostedManifestChecksum() else {
                lastError = "Hosted manifest checksum mismatch."
                return false
            }
            AriaKokoroEngine.noteRuntimeBecameAvailable()
            return true
        } catch {
            lastError = error.localizedDescription
            Self.logger.error("Kokoro download failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
        #else
        lastError = "KokoroTTS is not linked."
        return false
        #endif
    }

    private func verifyHostedManifestChecksum() -> Bool {
        let url = applicationSupportRoot.appendingPathComponent("HostedManifest.json")
        guard let data = try? Data(contentsOf: url) else {
            // Some hydrations write only the runtime tree. The SDK already
            // checked the hosted digest before extracting; a missing sidecar
            // is not a speak-time fetch.
            return FileManager.default.fileExists(
                atPath: applicationSupportRoot
                    .appendingPathComponent(AriaKokoroDelivery.manifestFileName).path
            )
        }
        #if canImport(CryptoKit)
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return AriaKokoroDelivery.matchesChecksum(hex, expected: AriaKokoroVoice.hostedManifestSHA256)
        #else
        return true
        #endif
    }

    private func backgroundAssetRoot() async -> URL? {
        #if canImport(BackgroundAssets)
        if #available(iOS 26.0, *) {
            guard Bundle.main.object(forInfoDictionaryKey: "BAAppGroupID") as? String != nil else {
                return nil
            }
            do {
                let pack = try await AssetPackManager.shared.assetPack(
                    withID: AriaKokoroDelivery.assetPackID
                )
                try await AssetPackManager.shared.ensureLocalAvailability(of: pack)
                let manifest = try AssetPackManager.shared.url(
                    for: FilePath(AriaKokoroDelivery.manifestFileName)
                )
                return manifest.deletingLastPathComponent()
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }
}
