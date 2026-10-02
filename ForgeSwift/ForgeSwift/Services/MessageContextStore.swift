import Foundation
import Combine
import ForgeCore

/// Owns the Messages pipeline: providers → `MessageContextEngine` → facts.
///
/// Privacy contract
/// ----------------
/// What ARIA sees: `contextBrief()` — "Friday: dinner plan, high confidence;
/// this week: 2 travel mentions, 1 stress signal" — and the matching
/// `life_context:` tags, built fresh for each on-device turn and never written
/// into ARIA's saved context. Only while Settings → Life Context → Messages is
/// on. `AriaOnDeviceHealthPolicy` removes both before any remote (/ai/chat)
/// request: Claude, Grok and the Forge backend never receive them.
/// What stays on-device: the facts. Message text is never stored here — it
/// lives only inside a provider's fetch and the engine's extract call.
///
/// Nothing is remembered unless the user says so, twice:
/// 1. every share ends in a review; facts reach `facts` only on Remember, and
/// 2. they are written down only while "Remember life context" is on — sealed
///    by `LifeContextVault` (AES-256-GCM, Keychain key, this device only, no
///    backups). With it off, confirmed facts live in memory until Forge quits.
/// Delete removes a fact from memory and rewrites the sealed file without it.
/// "Forget all" wipes the file, the keys and any pending share boxes, and
/// reports whether `LifeContextVault.isWiped()` confirmed it.
@MainActor
final class MessageContextStore: ObservableObject {
    static let shared = MessageContextStore()

    /// What Forge knows from shared conversations.
    @Published private(set) var facts: [LifeContextFact] = []
    /// Extracted, not yet confirmed. Memory only; ARIA never reads it.
    @Published private(set) var pendingReview: [LifeContextFact] = []
    @Published private(set) var pendingSourceName: String?
    @Published private(set) var settings: LifeContextSettings
    @Published private(set) var isProcessing = false
    @Published private(set) var lastError: String?
    /// Result of the last "Forget all": true when the wipe was verified.
    @Published private(set) var lastForgetVerified: Bool?

    private let vault: LifeContextVault
    private let defaults: UserDefaults?
    private let containerURL: URL?
    private let calendar: Calendar

    init(
        secureStore: SecureStore = KeychainStore(service: "com.forge.ForgeSwift.lifeContext"),
        rootDirectory: URL = LifeContextVault.defaultRoot(),
        defaults: UserDefaults? = UserDefaults(suiteName: LifeContextSettings.suiteName),
        containerURL: URL? = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: LifeContextSettings.suiteName
        ),
        calendar: Calendar = .current
    ) {
        self.vault = LifeContextVault(secureStore: secureStore, rootDirectory: rootDirectory)
        self.defaults = defaults
        self.containerURL = containerURL
        self.calendar = calendar
        let loaded = LifeContextSettings.load(from: defaults)
        self.settings = loaded
        if loaded.rememberEnabled {
            do {
                facts = try vault.loadFacts()
            } catch {
                lastError = LifeIngestError.explain(error, doing: "Couldn't open saved life context")
            }
        } else if vault.hasStoredFacts {
            // Remember is off, so nothing may be on disk.
            try? vault.removeFacts()
        }
        if loaded.messagesEnabled {
            publishInboxKey()
        }
    }

    // MARK: Switches

    /// Messages on: the Share extension may accept conversations (it gets the
    /// inbox public key) and ARIA may use the facts. Off: the key is withdrawn,
    /// pending review is dropped, and ARIA stops reading facts. Saved facts
    /// stay until the user deletes them or forgets all.
    func setMessagesEnabled(_ enabled: Bool) {
        settings.messagesEnabled = enabled
        persistSettings()
        if enabled {
            publishInboxKey()
        } else {
            LifeContextSettings.setInboxPublicKey(nil, in: defaults)
            discardPending()
        }
    }

    /// On: what the user already confirmed this session is written down now —
    /// turning it on is the instruction to remember. Off: the sealed copy is
    /// deleted; facts stay in memory until Forge quits.
    func setRememberEnabled(_ enabled: Bool) {
        settings.rememberEnabled = enabled
        persistSettings()
        if enabled {
            persistFacts()
        } else {
            do {
                try vault.removeFacts()
            } catch {
                lastError = LifeIngestError.explain(error, doing: "Couldn't delete the saved life context")
            }
        }
    }

    var hasSavedCopy: Bool { vault.hasStoredFacts }

    // MARK: Pipeline

    func hashKey() throws -> LifeContextHashKey {
        try vault.hashKey()
    }

    private func makeEngine() throws -> MessageContextEngine {
        MessageContextEngine(hashKey: try vault.hashKey(), configuration: .init(calendar: calendar))
    }

    /// provider → engine → pending review. Nothing is kept until `rememberPending()`.
    func ingest(from provider: any MessageIngestionProvider, since: Date = .distantPast) async {
        guard settings.messagesEnabled else {
            lastError = "Messages is off in Life Context, so nothing was read."
            return
        }
        isProcessing = true
        defer { isProcessing = false }
        do {
            let engine = try makeEngine()
            let turns = try await provider.fetchTurns(since: since)
            let extracted = await Task.detached(priority: .userInitiated) {
                engine.extract(from: turns)
            }.value
            let known = Set(facts.map(\.sourceHash))
            pendingReview = extracted.filter { !known.contains($0.sourceHash) }
            pendingSourceName = provider.displayName
            lastError = nil
        } catch {
            lastError = LifeIngestError.explain(error, doing: "Couldn't read that conversation")
        }
    }

    /// The user tapped Remember.
    func rememberPending() {
        guard !pendingReview.isEmpty else { return }
        facts = MessageContextEngine.merge(pendingReview, into: facts)
        discardPending()
        persistFacts()
    }

    func discardPending() {
        pendingReview = []
        pendingSourceName = nil
    }

    /// Gone from memory, and — when saved — from the sealed file, which is
    /// rewritten without it (or removed when it was the last one).
    func delete(_ fact: LifeContextFact) {
        facts.removeAll { $0.sourceHash == fact.sourceHash }
        persistFacts()
    }

    /// Wipe everything and verify it. Returns true only when the vault reports
    /// its directory and keys gone and no share boxes are left.
    @discardableResult
    func forgetAll() -> Bool {
        facts = []
        discardPending()
        var succeeded = true
        do {
            try vault.wipe()
        } catch {
            succeeded = false
            lastError = LifeIngestError.explain(error, doing: "Couldn't erase life context")
        }
        LifeContextSettings.setInboxPublicKey(nil, in: defaults)
        if let containerURL {
            do {
                try LifeContextInbox.purge(in: containerURL)
            } catch {
                succeeded = false
                lastError = LifeIngestError.explain(error, doing: "Couldn't erase pending shares")
            }
        }
        let inboxEmpty = containerURL.map { LifeContextInbox.pendingBoxes(in: $0).isEmpty } ?? true
        let verified = succeeded && vault.isWiped() && inboxEmpty
        lastForgetVerified = verified
        if verified { lastError = nil }
        // A fresh key, so new shares still work — and nothing sealed before
        // the wipe can ever be opened.
        if settings.messagesEnabled {
            publishInboxKey()
        }
        return verified
    }

    /// Facts the Share extension sealed for the app. Every box is deleted once
    /// read — or unread, when Messages has since been turned off.
    func drainShareInbox() {
        guard let containerURL else { return }
        let boxes = LifeContextInbox.pendingBoxes(in: containerURL)
        guard !boxes.isEmpty else { return }
        var incoming: [LifeContextFact] = []
        for url in boxes {
            if settings.messagesEnabled,
               let data = try? Data(contentsOf: url),
               let opened = try? vault.openInbox(data) {
                incoming.append(contentsOf: opened)
            }
            try? FileManager.default.removeItem(at: url)
        }
        guard !incoming.isEmpty else { return }
        facts = MessageContextEngine.merge(incoming, into: facts)
        persistFacts()
    }

    // MARK: ARIA (on-device only)

    /// Facts ARIA may use: none while Messages is off.
    var activeFacts: [LifeContextFact] {
        settings.messagesEnabled ? facts : []
    }

    /// The Scout-style handoff for on-device ARIA.
    func contextBrief(now: Date = Date()) -> String? {
        LifeContextBrief.render(activeFacts, now: now, calendar: calendar)
    }

    func ariaTags(now: Date = Date()) -> [String] {
        LifeContextBrief.ariaTags(activeFacts, now: now, calendar: calendar)
    }

    // MARK: Persistence

    private func persistFacts() {
        guard settings.rememberEnabled else { return }
        do {
            try vault.saveFacts(facts)
        } catch {
            lastError = LifeIngestError.explain(error, doing: "Couldn't save life context")
        }
    }

    /// Read-modify-write, so the Reminders switch (owned by RemindersManager)
    /// is never overwritten from here.
    private func persistSettings() {
        var stored = LifeContextSettings.load(from: defaults)
        stored.messagesEnabled = settings.messagesEnabled
        stored.rememberEnabled = settings.rememberEnabled
        stored.save(to: defaults)
        settings.remindersEnabled = stored.remindersEnabled
    }

    private func publishInboxKey() {
        do {
            LifeContextSettings.setInboxPublicKey(try vault.inboxPublicKey(), in: defaults)
        } catch {
            lastError = LifeIngestError.explain(error, doing: "Couldn't prepare the Share Sheet inbox")
        }
    }
}
