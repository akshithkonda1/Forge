import Foundation

/// Single config for a production Kokoro-82M download origin.
///
/// Unset by default. When this is nil and no local runtime is present,
/// ARIA stays silent and the text stays on screen. Debug / TestFlight
/// still use the consented Hugging Face hydrate. App Store Release does
/// not fetch Hugging Face.
public enum AriaKokoroHostedOrigin: Sendable {
    public static let infoDictionaryKey = "ARIA_KOKORO_HOSTED_ORIGIN"

    /// TODO(aws): set `ARIA_KOKORO_HOSTED_ORIGIN` to the CloudFront / S3
    /// HTTPS URL of the pinned starter bundle. Do not put credentials here.
    public static func url(infoDictionary: [String: Any] = [:]) -> URL? {
        guard let raw = infoDictionary[infoDictionaryKey] as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              (url.scheme ?? "").lowercased() == "https"
        else { return nil }
        return url
    }

    public static func isConfigured(infoDictionary: [String: Any] = [:]) -> Bool {
        url(infoDictionary: infoDictionary) != nil
    }

    /// Bundle-backed lookup. Empty / missing / non-https → nil.
    public static var currentURL: URL? {
        url(infoDictionary: Bundle.main.infoDictionary ?? [:])
    }

    /// Debug and TestFlight may hydrate from Hugging Face after consent.
    /// App Store Release may not.
    public static var allowsConsentedHuggingFaceHydrate: Bool {
        #if DEBUG
        true
        #else
        // TODO(aws): remove this TestFlight exception once the hosted origin is set.
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }
}
