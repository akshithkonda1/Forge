import Foundation

/// Where the Kokoro-82M starter runtime may live, and when we are allowed
/// to fetch it. Speak never opens a socket; this type is network-free.
public enum AriaKokoroDelivery: Sendable {
    public static let consentKey = "aria.kokoro.modelDownloadConsent"
    public static let declinedKey = "aria.kokoro.modelDownloadDeclined"
    public static let assetPackID = "forge.aria.kokoro-82m-starter"
    public static let bundleResourceName = "kokoro-82m-starter"
    public static let bundleResourceExtension = "bundle"
    public static let applicationSupportFolder = "Kokoro82M"
    public static let manifestFileName = "KokoroRuntimeManifest.json"
    /// Sentence-sized chunks keep peak RAM off the 1 GB 30 s path.
    public static let maxChunkCharacters = 220
    public static let maxChunkSeconds = 6.0

    public static let promptTitle = "ARIA's voice"
    public static let promptBody =
        "ARIA speaks with an on-device Kokoro voice. That needs a 210 MB download, once. Nothing you say, and no health data, goes with it. Until it finishes, replies stay on screen."
    public static let promptDownloadTitle = "Download 210 MB"
    public static let promptLaterTitle = "Not now"

    /// Guideline 4.2.3(ii): if the model is not already on device, tell them
    /// the size and ask before any download.
    public static func shouldAskToDownload(
        hasLocalModel: Bool,
        alreadyConsented: Bool,
        declined: Bool
    ) -> Bool {
        !hasLocalModel && !alreadyConsented && !declined
    }

    /// Prefetch is allowed only after they said yes, or when a pack/bundle is
    /// already present. Speak still refuses to hit the network.
    public static func allowsPrefetch(hasLocalModel: Bool, consented: Bool) -> Bool {
        hasLocalModel || consented
    }

    public static func hostedManifestURL(
        repo: String = AriaKokoroVoice.hostedModelRepo,
        revision: String = AriaKokoroVoice.hostedRevision
    ) -> URL? {
        URL(string: "https://huggingface.co/\(repo)/resolve/\(revision)/HostedManifest.json")
    }

    public static func isPinnedRevision(_ revision: String) -> Bool {
        revision.count == 40 && revision.allSatisfy(\.isHexDigit)
    }

    public static func matchesChecksum(_ hex: String, expected: String) -> Bool {
        hex.lowercased() == expected.lowercased()
    }

    public static func applicationSupportRoot(
        base: URL
    ) -> URL {
        base.appendingPathComponent(applicationSupportFolder, isDirectory: true)
    }
}

/// Ordered search: Apple-hosted pack, then the app bundle, then Application
/// Support. First root that contains the runtime manifest wins.
public struct AriaKokoroRuntimeLocator: Equatable, Sendable {
    public var roots: [URL]

    public init(roots: [URL]) {
        self.roots = roots
    }

    public func resolvedRoot(fileExists: (URL) -> Bool) -> URL? {
        roots.first { fileExists($0.appendingPathComponent(AriaKokoroDelivery.manifestFileName)) }
    }

    public var hasVerifiedRuntime: Bool {
        resolvedRoot { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        } != nil
    }
}

/// Missing model is not a permanent failure. After a consented download (or a
/// Background Assets pack) lands, `allowRetryAfterLoad` grants **exactly one**
/// additional load. A second grant after that retry fails is a no-op.
public struct AriaKokoroLoadState: Equatable, Sendable {
    public static let retryLimit = 1

    public private(set) var engineLoaded = false
    public private(set) var hardFailure = false
    public private(set) var missingModel = false
    public private(set) var loadAttempts = 0
    public private(set) var retriesUsed = 0
    public private(set) var pendingRetry = false

    public init() {}

    public var isReady: Bool { engineLoaded }

    /// `true` when the next prepare should actually open the runtime.
    public func shouldLoad(modelPresent: Bool) -> Bool {
        if engineLoaded { return false }
        guard modelPresent else { return false }
        if loadAttempts == 0 { return true }
        return pendingRetry && retriesUsed < Self.retryLimit
    }

    public mutating func markLoaded() {
        recordAttempt()
        engineLoaded = true
        hardFailure = false
        missingModel = false
    }

    public mutating func markMissing() {
        engineLoaded = false
        hardFailure = false
        missingModel = true
        pendingRetry = false
    }

    public mutating func markHardFailure() {
        recordAttempt()
        engineLoaded = false
        hardFailure = true
        missingModel = false
    }

    /// Call when a download or asset pack finishes so a previous miss/failure
    /// can retry once. Does not grant a second retry after that budget is used,
    /// and does not unload an engine that already loaded.
    public mutating func allowRetryAfterLoad() {
        if engineLoaded { return }
        guard retriesUsed < Self.retryLimit else { return }
        hardFailure = false
        missingModel = false
        pendingRetry = true
    }

    private mutating func recordAttempt() {
        if loadAttempts > 0 && pendingRetry {
            retriesUsed += 1
        }
        pendingRetry = false
        loadAttempts += 1
    }
}
