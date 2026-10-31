import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - AriaReliabilityClassifier
//
// App- and system-level errors reduced to `ReliabilityError`: a kind, a
// status or code, a system domain. Never a server body, a localized
// description, or reply text. Lives in ForgeCore so the on-device privacy
// contract is testable without the app target (`AriaReliabilityClassifierPrivacyTests`).

public enum AriaReliabilityClassifier {

    /// Classify any error. Never reads an error's description, its
    /// user-info dictionary, or a response payload. An HTTP payload that
    /// happens to be wrapped in an app-side `Failure` must be discarded
    /// by the caller before this (see `classifyHTTP`).
    public static func classify(_ error: Error) -> ReliabilityError {
        #if canImport(FoundationModels)
        if let generation = error as? LanguageModelSession.GenerationError {
            return classify(generation)
        }
        #endif
        let ns = error as NSError
        if ns.domain == "Forge.FoundationModels" {
            return ReliabilityError(kind: .onDeviceModelUnavailable, code: ns.code)
        }
        return ReliabilityError.classify(error)
    }

    /// An HTTP status from Forge's backend. The response payload is
    /// deliberately not a parameter: it can echo the user's message or a
    /// health value.
    public static func classifyHTTP(status: Int, isAriaPaused: Bool = false) -> ReliabilityError {
        if isAriaPaused {
            return ReliabilityError(kind: .ariaPaused, code: status, domain: "http")
        }
        return .http(status: status)
    }

    /// A transport failure (offline, timeout, cancelled). Delegates to
    /// `ReliabilityError.classify` and remaps a leftover `.unknown` to
    /// `.offline` so a generic `URLError` still counts as infrastructure.
    public static func classifyTransport(_ error: Error) -> ReliabilityError {
        let classified = ReliabilityError.classify(error)
        return classified.kind == .unknown
            ? ReliabilityError(kind: .offline, code: classified.code, domain: classified.domain)
            : classified
    }

    public static func classifyAuth() -> ReliabilityError {
        ReliabilityError(kind: .unauthorized, domain: "auth")
    }

    public static func classifyNotConfigured() -> ReliabilityError {
        ReliabilityError(kind: .notConfigured)
    }

    #if canImport(FoundationModels)
    public static func classify(_ error: LanguageModelSession.GenerationError) -> ReliabilityError {
        switch error {
        case .guardrailViolation:
            return ReliabilityError(kind: .onDeviceGuardrail, domain: "foundation_models")
        case .exceededContextWindowSize:
            return ReliabilityError(kind: .onDeviceContextWindow, domain: "foundation_models")
        case .assetsUnavailable:
            return ReliabilityError(kind: .onDeviceModelUnavailable, domain: "foundation_models")
        case .rateLimited:
            return ReliabilityError(kind: .rateLimited, domain: "foundation_models")
        default:
            return ReliabilityError(kind: .onDeviceModel, domain: "foundation_models")
        }
    }
    #endif
}
