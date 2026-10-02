import XCTest
@testable import ForgeCore

final class LifeContextVaultTests: XCTestCase {

    private var store: InMemorySecureStore!
    private var root: URL!
    private var container: URL!
    private var vault: LifeContextVault!

    override func setUp() {
        super.setUp()
        store = InMemorySecureStore()
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ForgeLifeContext-tests-\(UUID().uuidString)", isDirectory: true)
        root = base.appendingPathComponent("vault", isDirectory: true)
        container = base.appendingPathComponent("group", isDirectory: true)
        vault = LifeContextVault(secureStore: store, rootDirectory: root)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
        store = nil
        vault = nil
        super.tearDown()
    }

    private func fact(_ summary: String, hash: String, minute: Int = 0) -> LifeContextFact {
        LifeContextFact(
            kind: .plan, label: "dinner", summary: summary, date: Date(timeIntervalSince1970: 1_790_000_000),
            confidence: 0.9, sourceHash: hash, observedAt: Date(timeIntervalSince1970: 1_789_000_000 + Double(minute * 60))
        )
    }

    // MARK: Vault

    func testRoundTripIsEncryptedAtRest() throws {
        let facts = [fact("Dinner with a friend Friday 7pm", hash: "a1"), fact("Coffee with a colleague Monday", hash: "b2")]
        try vault.saveFacts(facts)
        XCTAssertTrue(vault.hasStoredFacts)
        XCTAssertEqual(try vault.loadFacts(), facts)
        let onDisk = try Data(contentsOf: vault.factsURL)
        XCTAssertNil(onDisk.range(of: Data("Dinner".utf8)), "ciphertext must not contain the plaintext")
        XCTAssertTrue(store.keys.contains(LifeContextVault.wrappingKeyAccount))
    }

    func testWrongKeyCannotOpen() throws {
        try vault.saveFacts([fact("Dinner with a friend", hash: "a1")])
        let attacker = LifeContextVault(secureStore: InMemorySecureStore(), rootDirectory: root)
        XCTAssertThrowsError(try attacker.loadFacts())
    }

    func testTamperedBoxIsRejected() throws {
        try vault.saveFacts([fact("Dinner with a friend", hash: "a1")])
        var bytes = [UInt8](try Data(contentsOf: vault.factsURL))
        bytes[bytes.count - 1] ^= 0xFF
        try Data(bytes).write(to: vault.factsURL)
        XCTAssertThrowsError(try vault.loadFacts()) { error in
            XCTAssertEqual(error as? LifeContextVaultError, .cryptoFailed)
        }
    }

    func testSavingNothingRemovesTheFile() throws {
        try vault.saveFacts([fact("Dinner with a friend", hash: "a1")])
        try vault.saveFacts([])
        XCTAssertFalse(vault.hasStoredFacts)
        XCTAssertEqual(try vault.loadFacts(), [])
    }

    func testWipeActuallyDeletes() throws {
        try vault.saveFacts([fact("Dinner with a friend", hash: "a1")])
        _ = try vault.hashKey()
        _ = try vault.inboxPublicKey()
        XCTAssertFalse(vault.isWiped())

        try vault.wipe()

        XCTAssertTrue(vault.isWiped())
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        XCTAssertFalse(store.keys.contains(LifeContextVault.wrappingKeyAccount))
        XCTAssertFalse(store.keys.contains(LifeContextVault.hashKeyAccount))
        XCTAssertFalse(store.keys.contains(LifeContextVault.inboxPrivateKeyAccount))
        XCTAssertEqual(try vault.loadFacts(), [])
    }

    func testHashKeyIsStableUntilWiped() throws {
        let first = try vault.hashKey()
        XCTAssertEqual(try vault.hashKey(), first)
        try vault.wipe()
        XCTAssertNotEqual(try vault.hashKey(), first, "forget all rotates the hash key")
    }

    // MARK: Share inbox

    func testInboxRoundTrip() throws {
        let publicKey = try vault.inboxPublicKey()
        let facts = [fact("Flight Thursday 6pm", hash: "c3")]
        let url = try LifeContextInbox.deposit(facts, toPublicKey: publicKey, container: container)
        // Compare names: the directory listing resolves /var → /private/var on macOS.
        XCTAssertEqual(LifeContextInbox.pendingBoxes(in: container).map(\.lastPathComponent), [url.lastPathComponent])
        let boxed = try Data(contentsOf: url)
        XCTAssertNil(boxed.range(of: Data("Flight".utf8)))
        XCTAssertEqual(try vault.openInbox(boxed), facts)
    }

    func testOnlyTheAppCanOpenTheInbox() throws {
        let boxed = try LifeContextInbox.seal([fact("Flight Thursday 6pm", hash: "c3")], toPublicKey: try vault.inboxPublicKey())
        let other = LifeContextVault(secureStore: InMemorySecureStore(), rootDirectory: root)
        XCTAssertThrowsError(try other.openInbox(boxed))
    }

    func testSealingTwiceGivesDifferentCiphertext() throws {
        let publicKey = try vault.inboxPublicKey()
        let facts = [fact("Flight Thursday 6pm", hash: "c3")]
        XCTAssertNotEqual(try LifeContextInbox.seal(facts, toPublicKey: publicKey),
                          try LifeContextInbox.seal(facts, toPublicKey: publicKey))
    }

    func testInvalidPublicKeyIsRefused() {
        XCTAssertThrowsError(try LifeContextInbox.seal([], toPublicKey: Data([1, 2, 3]))) { error in
            XCTAssertEqual(error as? LifeContextVaultError, .invalidPublicKey)
        }
    }

    func testPurgeRemovesPendingBoxes() throws {
        let publicKey = try vault.inboxPublicKey()
        try LifeContextInbox.deposit([fact("Trip", hash: "d4")], toPublicKey: publicKey, container: container,
                                     now: Date(timeIntervalSince1970: 1_790_000_000))
        try LifeContextInbox.deposit([fact("Trip", hash: "e5")], toPublicKey: publicKey, container: container,
                                     now: Date(timeIntervalSince1970: 1_790_000_100))
        let pending = LifeContextInbox.pendingBoxes(in: container)
        XCTAssertEqual(pending.count, 2)
        XCTAssertLessThan(pending[0].lastPathComponent, pending[1].lastPathComponent, "oldest first")
        try LifeContextInbox.purge(in: container)
        XCTAssertTrue(LifeContextInbox.pendingBoxes(in: container).isEmpty)
    }

    func testWipeRotatesTheInboxKey() throws {
        let before = try vault.inboxPublicKey()
        let boxed = try LifeContextInbox.seal([fact("Trip", hash: "f6")], toPublicKey: before)
        try vault.wipe()
        XCTAssertNotEqual(try vault.inboxPublicKey(), before)
        XCTAssertThrowsError(try vault.openInbox(boxed), "a box sealed before forget-all can no longer be opened")
    }

    // MARK: Settings

    func testSettingsDefaultToOffAndRoundTrip() {
        let suite = "forge.lifeContext.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)
        defer { defaults?.removePersistentDomain(forName: suite) }
        XCTAssertEqual(LifeContextSettings.load(from: defaults), LifeContextSettings())
        XCTAssertFalse(LifeContextSettings().remindersEnabled)
        XCTAssertFalse(LifeContextSettings().messagesEnabled)
        XCTAssertFalse(LifeContextSettings().rememberEnabled)

        let on = LifeContextSettings(remindersEnabled: true, messagesEnabled: true, rememberEnabled: false)
        on.save(to: defaults)
        XCTAssertEqual(LifeContextSettings.load(from: defaults), on)

        LifeContextSettings.setInboxPublicKey(Data([9]), in: defaults)
        XCTAssertEqual(LifeContextSettings.inboxPublicKey(in: defaults), Data([9]))
        LifeContextSettings.setInboxPublicKey(nil, in: defaults)
        XCTAssertNil(LifeContextSettings.inboxPublicKey(in: defaults))
    }
}
