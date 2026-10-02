import CryptoKit
import Foundation

// ============================================================
// MARK: - Life Context models
// ============================================================
//
// Privacy contract
// ----------------
// What ARIA sees: `LifeContextFact` only — a kind, a one-line summary Forge
// wrote from its own fixed vocabulary, a date, a confidence, and a keyed hash.
// Never a quote, a name, a phone number, or a place. On-device ARIA only;
// `AriaOnDeviceHealthPolicy` removes every `life_context:` tag and brief
// before a remote (/ai/chat) request.
// What stays on-device: `MessageTurn`, in memory, for as long as one
// extraction runs. It is deliberately not `Codable` — there is no supported
// way to write one down — and its `description` never prints the text.
// Phone numbers and email addresses are removed from the text in its
// initializer, so the engine never sees them. Contacts are a keyed HMAC
// (`ContactID`), never a name or a number; the key lives in the Keychain
// (this device only) and is destroyed by "Forget all".
// Persisted: facts only, and only when the user turned "Remember life
// context" on and tapped Remember — sealed by `LifeContextVault`.

// ------------------------------------------------------------
// MARK: Keyed hashing
// ------------------------------------------------------------

/// The secret behind every hash the Life Context pipeline makes. Without it a
/// `sourceHash` or `ContactID` cannot be tested against a guess, so a short
/// message ("see you friday") or a phone number cannot be recovered from its
/// hash by trying candidates.
public struct LifeContextHashKey: Sendable, Equatable {
    public static let byteCount = 32

    public let bytes: Data

    public init?(bytes: Data) {
        guard bytes.count == Self.byteCount else { return nil }
        self.bytes = bytes
    }

    private init(validated bytes: Data) {
        self.bytes = bytes
    }

    public static func generate() -> LifeContextHashKey {
        let key = SymmetricKey(size: .bits256)
        return LifeContextHashKey(validated: key.withUnsafeBytes { Data($0) })
    }

    /// Load the key from `store`, creating and saving one the first time.
    public static func loadOrCreate(in store: SecureStore, account: String) throws -> LifeContextHashKey {
        if let existing = try store.data(forKey: account), let key = LifeContextHashKey(bytes: existing) {
            return key
        }
        let fresh = generate()
        try store.set(fresh.bytes, forKey: account)
        return fresh
    }

    /// Lowercase hex of HMAC-SHA256(domain ‖ 0x1F ‖ value), truncated to
    /// `byteLength` bytes. `domain` keeps a contact hash and a fact hash of the
    /// same string from ever colliding.
    public func digest(_ value: String, domain: String, byteLength: Int = 16) -> String {
        let message = Data((domain + "\u{1F}" + value).utf8)
        let mac = HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: bytes))
        let macBytes = mac.withUnsafeBytes { Array($0) }
        return macBytes.prefix(max(1, byteLength)).map { String(format: "%02x", $0) }.joined()
    }
}

/// A conversation partner, as a keyed hash. The only initializer hashes, so a
/// name or a phone number cannot be passed through as an id.
public struct ContactID: Hashable, Sendable {
    public let value: String

    public init(hashing handle: String, key: LifeContextHashKey) {
        let normalized = ContactID.normalize(handle)
        value = "c_" + key.digest(normalized, domain: "forge.lifeContext.contact.v1", byteLength: 8)
    }

    /// "+1 (555) 010-2000" and "15550102000" are the same person; so are
    /// "Sam" and " sam ".
    static func normalize(_ handle: String) -> String {
        let trimmed = handle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let digits = trimmed.filter(\.isNumber)
        let letters = trimmed.filter(\.isLetter)
        if letters.isEmpty, digits.count >= 7 { return digits }
        return trimmed.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

// ------------------------------------------------------------
// MARK: Input
// ------------------------------------------------------------

/// One message handed to `MessageContextEngine`. In memory only.
public struct MessageTurn: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {

    public enum Sender: Sendable, Hashable {
        case me
        case them(ContactID)
    }

    public let sender: Sender
    /// The message with phone numbers and email addresses already removed.
    public let text: String
    public let timestamp: Date

    public init(sender: Sender, text: String, timestamp: Date) {
        self.sender = sender
        self.text = MessageTextRedactor.redact(text)
        self.timestamp = timestamp
    }

    public var isFromMe: Bool {
        if case .me = sender { return true }
        return false
    }

    /// Never the text — a turn that reaches a log line says only how long it was.
    public var description: String {
        let who: String
        switch sender {
        case .me: who = "me"
        case .them(let id): who = id.value
        }
        return "MessageTurn(\(who), \(text.count) chars redacted)"
    }

    public var debugDescription: String { description }
}

/// Removes what the engine must never see: phone numbers, email addresses, and
/// long digit runs (account numbers, codes).
public enum MessageTextRedactor {

    public static let numberPlaceholder = "[number]"
    public static let emailPlaceholder = "[email]"

    private static let email = try? NSRegularExpression(
        pattern: #"[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}"#,
        options: [.caseInsensitive]
    )
    /// Nine or more digits, optionally space-separated: card, account and
    /// order numbers. Dashed and dotted dates ("2026-10-12") are left alone;
    /// dashed phone numbers are the detector's job.
    private static let digitRun = try? NSRegularExpression(pattern: #"\b(?:\d ?){8,}\d\b"#)
    /// North American numbers written with separators — a backstop for the
    /// detector, which depends on the device's region.
    private static let nanpPhone = try? NSRegularExpression(
        pattern: #"(?:\+?1[\s.\-]?)?\(?\b\d{3}\)?[\s.\-]\d{3}[\s.\-]\d{4}\b"#
    )
    private static let phoneDetector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue
    )

    public static func redact(_ text: String) -> String {
        var out = text
        if let detector = phoneDetector {
            out = replace(detector, in: out, with: numberPlaceholder)
        }
        if let regex = nanpPhone {
            out = replace(regex, in: out, with: numberPlaceholder)
        }
        if let regex = email {
            out = replace(regex, in: out, with: emailPlaceholder)
        }
        if let regex = digitRun {
            out = replace(regex, in: out, with: numberPlaceholder)
        }
        return out
    }

    private static func replace(_ regex: NSRegularExpression, in text: String, with placeholder: String) -> String {
        let full = NSRange(location: 0, length: (text as NSString).length)
        let matches = regex.matches(in: text, options: [], range: full)
        guard !matches.isEmpty else { return text }
        let mutable = NSMutableString(string: text)
        for match in matches.reversed() {
            mutable.replaceCharacters(in: match.range, with: placeholder)
        }
        return mutable as String
    }
}

// ------------------------------------------------------------
// MARK: Output
// ------------------------------------------------------------

/// A structured life fact. Everything in it was written by Forge: no field
/// carries message text.
public struct LifeContextFact: Sendable, Codable, Identifiable, Hashable {

    public enum Kind: String, Codable, Sendable, CaseIterable {
        case plan, event, travel, commitment, healthSignal, stressSignal, relationship

        /// Lowercase noun for briefs: "plan", "travel mention", "stress signal".
        public func briefNoun(count: Int) -> String {
            let plural = count != 1
            switch self {
            case .plan: return plural ? "plans" : "plan"
            case .event: return plural ? "event mentions" : "event mention"
            case .travel: return plural ? "travel mentions" : "travel mention"
            case .commitment: return plural ? "commitments" : "commitment"
            case .healthSignal: return plural ? "health signals" : "health signal"
            case .stressSignal: return plural ? "stress signals" : "stress signal"
            case .relationship: return plural ? "relationship signals" : "relationship signal"
            }
        }

        /// Title-case label for the "what Forge knows" viewer.
        public var displayName: String {
            switch self {
            case .plan: return "Plan"
            case .event: return "Event"
            case .travel: return "Travel"
            case .commitment: return "Commitment"
            case .healthSignal: return "Health signal"
            case .stressSignal: return "Stress signal"
            case .relationship: return "Relationship"
            }
        }
    }

    public enum ConfidenceBand: String, Sendable {
        case high, medium, low
    }

    public let kind: Kind
    /// Forge's fixed-vocabulary topic ("dinner", "flight", "wedding",
    /// "stress"). Never a word chosen from the message.
    public let label: String
    /// One short sentence, no quotes: "Dinner with a friend Friday 7pm".
    public let summary: String
    public let date: Date?
    public let confidence: Double
    /// Keyed hash of the source turn(s), for dedup. Not reversible without the
    /// device's Keychain key, and not reversible with it either — it is a MAC.
    public let sourceHash: String
    /// When the source message was sent (or shared). Drives oldest-first eviction.
    public let observedAt: Date

    public var id: String { sourceHash }

    public init(
        kind: Kind,
        label: String,
        summary: String,
        date: Date?,
        confidence: Double,
        sourceHash: String,
        observedAt: Date
    ) {
        self.kind = kind
        self.label = label
        self.summary = summary
        self.date = date
        self.confidence = confidence
        self.sourceHash = sourceHash
        self.observedAt = observedAt
    }

    public var confidenceBand: ConfidenceBand {
        if confidence >= 0.85 { return .high }
        if confidence >= 0.7 { return .medium }
        return .low
    }
}

// ------------------------------------------------------------
// MARK: Settings (shared with the Share extension)
// ------------------------------------------------------------

/// The Life Context switches. All three default to off. They live in the app
/// group's defaults so the Share extension can honor them without the app
/// running; they are booleans and a public key, never content.
public struct LifeContextSettings: Sendable, Equatable {
    public static let suiteName = WatchSnapshotStore.appGroupID

    static let remindersKey = "forge.lifeContext.remindersEnabled.v1"
    static let messagesKey = "forge.lifeContext.messagesEnabled.v1"
    static let rememberKey = "forge.lifeContext.rememberEnabled.v1"
    static let inboxPublicKeyKey = "forge.lifeContext.inboxPublicKey.v1"

    /// Read Reminders and turn them into workload counts.
    public var remindersEnabled: Bool
    /// Accept conversations from the Share Sheet and let ARIA use the facts.
    public var messagesEnabled: Bool
    /// Keep facts after the app closes (encrypted). Off: facts live in memory
    /// for this session only, and the Share Sheet keeps nothing.
    public var rememberEnabled: Bool

    public init(remindersEnabled: Bool = false, messagesEnabled: Bool = false, rememberEnabled: Bool = false) {
        self.remindersEnabled = remindersEnabled
        self.messagesEnabled = messagesEnabled
        self.rememberEnabled = rememberEnabled
    }

    public static func load(from defaults: UserDefaults?) -> LifeContextSettings {
        guard let defaults else { return LifeContextSettings() }
        return LifeContextSettings(
            remindersEnabled: defaults.bool(forKey: remindersKey),
            messagesEnabled: defaults.bool(forKey: messagesKey),
            rememberEnabled: defaults.bool(forKey: rememberKey)
        )
    }

    public func save(to defaults: UserDefaults?) {
        guard let defaults else { return }
        defaults.set(remindersEnabled, forKey: Self.remindersKey)
        defaults.set(messagesEnabled, forKey: Self.messagesKey)
        defaults.set(rememberEnabled, forKey: Self.rememberKey)
    }

    /// The app's inbox public key (Curve25519, raw). The Share extension can
    /// seal facts to it but cannot open what it sealed.
    public static func inboxPublicKey(in defaults: UserDefaults?) -> Data? {
        defaults?.data(forKey: inboxPublicKeyKey)
    }

    public static func setInboxPublicKey(_ key: Data?, in defaults: UserDefaults?) {
        guard let defaults else { return }
        if let key {
            defaults.set(key, forKey: inboxPublicKeyKey)
        } else {
            defaults.removeObject(forKey: inboxPublicKeyKey)
        }
    }
}
