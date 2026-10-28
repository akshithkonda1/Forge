import Foundation

// MARK: - Reliability records
//
// What Forge measures about itself, on this iPhone, so a phase gate
// ("99.9% with no errors") is a number instead of a feeling.
//
// Privacy rule, same as ForgePerf: outcome metadata only. Nothing in this
// file can hold a message, a health value, a name or an error's text. Every
// field is an enum, a count, a duration, a date, or a numeric code (an HTTP
// status, an NSError code). Error *descriptions* are never stored, because a
// server body or a localized description can echo user text back.
// `ReliabilityPrivacyTests` locks this.

/// Which path answered an ARIA turn.
public enum AriaReliabilityRoute: String, Codable, CaseIterable, Sendable {
    /// Apple's on-device foundation model (local testing on a capable iPhone).
    case onDeviceModel = "on_device_model"
    /// On-device rule engine (no Apple Intelligence, or the Simulator).
    case onDeviceRules = "on_device_rules"
    /// Forge's own backend (Claude / Grok via `/ai/chat`).
    case cloud
    /// Safety triage decided on this iPhone before any coach ran.
    case safety
    /// Deterministic Dummy orchestra (DEBUG only).
    case dummy
    /// Failed before a route was chosen.
    case unknown

    public var label: String {
        switch self {
        case .onDeviceModel: return "On-device model"
        case .onDeviceRules: return "On-device rules"
        case .cloud: return "Cloud"
        case .safety: return "Safety (on device)"
        case .dummy: return "Dummy"
        case .unknown: return "Unknown"
        }
    }
}

/// Which ARIA surface asked.
public enum AriaReliabilitySurface: String, Codable, CaseIterable, Sendable {
    case chat
    case insight
}

/// How an ARIA turn ended.
public enum AriaReliabilityOutcome: String, Codable, CaseIterable, Sendable {
    /// The chosen path answered.
    case success
    /// The chosen path failed and another one answered (cloud → on-device).
    /// The person still got a reply, but the infrastructure failed, so the
    /// phase-gate success rate does not count it as a success.
    case fallback
    /// No reply. The person saw "Forge couldn't complete that request".
    case failure
    /// The turn was cancelled (view dismissed, task torn down). Not a
    /// reliability event; excluded from every rate.
    case cancelled
}

/// A failure, reduced to a category and a number. Never the error's text.
public enum ReliabilityErrorKind: String, Codable, CaseIterable, Sendable {
    case offline
    case timeout
    case unauthorized
    case rateLimited = "rate_limited"
    case serverError = "server_error"
    case clientError = "client_error"
    case ariaPaused = "aria_paused"
    case notConfigured = "not_configured"
    case decoding
    case onDeviceModelUnavailable = "on_device_model_unavailable"
    case onDeviceGuardrail = "on_device_guardrail"
    case onDeviceContextWindow = "on_device_context_window"
    case onDeviceModel = "on_device_model"
    case healthKit = "healthkit"
    case fileSystem = "file_system"
    case encoding
    case cancelled
    case unknown

    public var label: String {
        switch self {
        case .offline: return "Offline"
        case .timeout: return "Timed out"
        case .unauthorized: return "Signed out / refused"
        case .rateLimited: return "Rate limited"
        case .serverError: return "Server error"
        case .clientError: return "Request rejected"
        case .ariaPaused: return "ARIA paused"
        case .notConfigured: return "Not configured"
        case .decoding: return "Bad response"
        case .onDeviceModelUnavailable: return "On-device model unavailable"
        case .onDeviceGuardrail: return "On-device guardrail"
        case .onDeviceContextWindow: return "On-device context too long"
        case .onDeviceModel: return "On-device model error"
        case .healthKit: return "HealthKit"
        case .fileSystem: return "File system"
        case .encoding: return "Encoding"
        case .cancelled: return "Cancelled"
        case .unknown: return "Unknown"
        }
    }
}

/// A classified error: the kind plus at most one number and a system domain.
///
/// `domain` is only ever an error domain constant (`NSURLErrorDomain`,
/// `com.apple.healthkit`, `NSCocoaErrorDomain`) — fixed strings the OS or
/// Forge defines, never anything built from user input.
public struct ReliabilityError: Codable, Equatable, Sendable {
    public var kind: ReliabilityErrorKind
    public var code: Int?
    public var domain: String?

    public init(kind: ReliabilityErrorKind, code: Int? = nil, domain: String? = nil) {
        self.kind = kind
        self.code = code
        self.domain = domain.map(ReliabilityError.sanitizedDomain)
    }

    /// An HTTP status from Forge's backend. The body is deliberately not a
    /// parameter: it can echo the user's message.
    public static func http(status: Int) -> ReliabilityError {
        let kind: ReliabilityErrorKind
        switch status {
        case 401, 403: kind = .unauthorized
        case 408: kind = .timeout
        case 429: kind = .rateLimited
        case 500...599: kind = .serverError
        default: kind = .clientError
        }
        return ReliabilityError(kind: kind, code: status, domain: "http")
    }

    /// Classify any error by type, domain and code. Never reads
    /// `localizedDescription`, `userInfo` or `debugDescription`.
    public static func classify(_ error: Error) -> ReliabilityError {
        if error is CancellationError {
            return ReliabilityError(kind: .cancelled)
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled:
                return ReliabilityError(kind: .cancelled, code: urlError.code.rawValue, domain: NSURLErrorDomain)
            case .timedOut:
                return ReliabilityError(kind: .timeout, code: urlError.code.rawValue, domain: NSURLErrorDomain)
            default:
                return ReliabilityError(kind: .offline, code: urlError.code.rawValue, domain: NSURLErrorDomain)
            }
        }
        if error is DecodingError {
            return ReliabilityError(kind: .decoding)
        }
        if error is EncodingError {
            return ReliabilityError(kind: .encoding)
        }
        let ns = error as NSError
        switch ns.domain {
        case NSURLErrorDomain:
            if ns.code == NSURLErrorCancelled {
                return ReliabilityError(kind: .cancelled, code: ns.code, domain: ns.domain)
            }
            if ns.code == NSURLErrorTimedOut {
                return ReliabilityError(kind: .timeout, code: ns.code, domain: ns.domain)
            }
            return ReliabilityError(kind: .offline, code: ns.code, domain: ns.domain)
        case "com.apple.healthkit":
            return ReliabilityError(kind: .healthKit, code: ns.code, domain: ns.domain)
        case NSCocoaErrorDomain, NSPOSIXErrorDomain:
            return ReliabilityError(kind: .fileSystem, code: ns.code, domain: ns.domain)
        default:
            return ReliabilityError(kind: .unknown, code: ns.code, domain: ns.domain)
        }
    }

    /// Domains are identifiers. Anything that does not look like one (spaces,
    /// punctuation beyond `._-`, or longer than 64) is dropped to "other", so
    /// a custom error type cannot smuggle text in through its domain.
    static func sanitizedDomain(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        guard !raw.isEmpty, raw.count <= 64,
              raw.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return "other"
        }
        return raw
    }
}

/// One ARIA turn: route, outcome, latency. No text of any kind.
public struct AriaTurnRecord: Codable, Equatable, Sendable {
    public var at: Date
    public var route: AriaReliabilityRoute
    public var surface: AriaReliabilitySurface
    public var outcome: AriaReliabilityOutcome
    public var latencyMs: Int
    public var error: ReliabilityError?

    public init(
        at: Date = Date(),
        route: AriaReliabilityRoute,
        surface: AriaReliabilitySurface = .chat,
        outcome: AriaReliabilityOutcome,
        latencyMs: Int,
        error: ReliabilityError? = nil
    ) {
        self.at = at
        self.route = route
        self.surface = surface
        self.outcome = outcome
        self.latencyMs = max(0, latencyMs)
        self.error = error
    }
}

/// Where a non-ARIA critical-path failure happened.
public enum ReliabilityArea: String, Codable, CaseIterable, Sendable {
    case healthKit = "healthkit"
    case persistence
    case aria

    public var label: String {
        switch self {
        case .healthKit: return "HealthKit"
        case .persistence: return "Saving data"
        case .aria: return "ARIA"
        }
    }
}

/// The operation that failed. A closed list, so a call site cannot pass text.
public enum ReliabilityOperation: String, Codable, CaseIterable, Sendable {
    case quantityQuery = "quantity_query"
    case sleepQuery = "sleep_query"
    case healthAuthorization = "health_authorization"
    case chatSessionSave = "chat_session_save"
    case chatSessionRestore = "chat_session_restore"
    case ariaContextSave = "aria_context_save"
    case ariaMemorySave = "aria_memory_save"
    case ariaTurn = "aria_turn"

    public var label: String {
        switch self {
        case .quantityQuery: return "Health sample read"
        case .sleepQuery: return "Sleep read"
        case .healthAuthorization: return "Health permission"
        case .chatSessionSave: return "Chat save"
        case .chatSessionRestore: return "Chat restore"
        case .ariaContextSave: return "ARIA context save"
        case .ariaMemorySave: return "ARIA memory save"
        case .ariaTurn: return "ARIA reply"
        }
    }
}

/// A critical-path failure outside an ARIA turn (HealthKit, persistence).
public struct ReliabilityFailureRecord: Codable, Equatable, Sendable {
    public var at: Date
    public var area: ReliabilityArea
    public var operation: ReliabilityOperation
    public var error: ReliabilityError

    public init(at: Date = Date(), area: ReliabilityArea, operation: ReliabilityOperation, error: ReliabilityError) {
        self.at = at
        self.area = area
        self.operation = operation
        self.error = error
    }
}

/// How a foreground session ended.
public enum ReliabilitySessionEnd: String, Codable, Sendable {
    /// Went to the background (or terminated) normally. A later kill while
    /// suspended is the system reclaiming memory, not a crash.
    case clean
    /// The process died while Forge was on screen: a crash, a watchdog kill,
    /// or a foreground memory kill. All three look like a crash to a user.
    case abnormal
}

/// One foreground session.
public struct ReliabilitySessionRecord: Codable, Equatable, Sendable {
    public var id: UUID
    public var launchID: UUID
    public var startedAt: Date
    public var lastActiveAt: Date
    public var endedAt: Date?
    public var end: ReliabilitySessionEnd?
    /// Started with a debugger attached (an Xcode run). Stopping a run in
    /// Xcode looks exactly like a crash, so these never count toward the rate.
    public var debugger: Bool
    public var appVersion: String?
    /// Set while the session is in the background. Nil means on screen.
    public var backgroundedAt: Date?

    public var isOpen: Bool { end == nil }
    public var isInForeground: Bool { isOpen && backgroundedAt == nil }

    public init(
        id: UUID = UUID(),
        launchID: UUID,
        startedAt: Date,
        debugger: Bool = false,
        appVersion: String? = nil
    ) {
        self.id = id
        self.launchID = launchID
        self.startedAt = startedAt
        self.lastActiveAt = startedAt
        self.debugger = debugger
        self.appVersion = appVersion
    }
}
