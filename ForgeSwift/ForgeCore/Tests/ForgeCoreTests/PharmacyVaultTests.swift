import XCTest
@testable import ForgeCore

final class PharmacyVaultTests: XCTestCase {

    private var suite = ""
    private var defaults: UserDefaults!
    private var store: InMemorySecureStore!

    override func setUp() {
        suite = "forge.pharmacy.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        store = InMemorySecureStore()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private func vault() -> PharmacyVault {
        PharmacyVault(store: store, defaults: defaults)
    }

    func testToggleAddsAndRemovesByStableId() {
        let vault = vault()
        XCTAssertEqual(vault.toggle(id: "ndc-lipitor", name: "Lipitor"), .added)
        XCTAssertEqual(vault.savedNames(), ["Lipitor"])
        XCTAssertTrue(vault.contains(id: "ndc-lipitor", name: "Lipitor 10 mg"))
        XCTAssertEqual(vault.toggle(id: "ndc-lipitor", name: "Lipitor 20 mg"), .removed)
        XCTAssertTrue(vault.load().items.isEmpty)
    }

    func testCapRefusesTheFortyFirstAndKeepsOldest() {
        let vault = vault()
        for i in 1...PharmacyVault.cap {
            XCTAssertEqual(vault.ensure(id: "id-\(i)", name: "Med \(i)"), .added)
        }
        XCTAssertEqual(vault.load().items.count, PharmacyVault.cap)
        XCTAssertEqual(vault.ensure(id: "id-overflow", name: "Overflow"), .atCap)
        XCTAssertEqual(vault.load().items.count, PharmacyVault.cap)
        XCTAssertFalse(vault.contains(id: "id-overflow", name: "Overflow"))
        XCTAssertTrue(vault.contains(id: "id-1", name: "Med 1"))
    }

    func testMigratesLegacyUserDefaultsNamesThenDeletesThem() {
        defaults.set(["Xcopri", "Lipitor"], forKey: PharmacyVault.legacySavedKey)
        let vault = vault()
        let state = vault.load()
        XCTAssertEqual(state.items.map(\.name), ["Xcopri", "Lipitor"])
        XCTAssertEqual(state.items.map(\.id), ["xcopri", "lipitor"])
        XCTAssertFalse(state.shareWithAria)
        XCTAssertNil(defaults.stringArray(forKey: PharmacyVault.legacySavedKey))
        XCTAssertNotNil(try store.data(forKey: PharmacyVault.storageKey))
    }

    func testShareWithAriaDefaultsOffAndPersists() {
        let first = vault()
        XCTAssertFalse(first.load().shareWithAria)
        first.setShareWithAria(true)
        let second = PharmacyVault(store: store, defaults: defaults)
        XCTAssertTrue(second.load().shareWithAria)
    }

    func testRefreshFailurePersistsForOfflineNote() {
        let vault = vault()
        vault.setRefreshOutcome(failed: true)
        XCTAssertTrue(vault.load().lastRefreshFailed)
        vault.setRefreshOutcome(failed: false)
        XCTAssertFalse(vault.load().lastRefreshFailed)
        XCTAssertNotNil(vault.load().lastRefreshAt)
    }

    func testWipeClearsSecureCopyAndLegacyKey() {
        defaults.set(["Xcopri"], forKey: PharmacyVault.legacySavedKey)
        let vault = vault()
        _ = vault.ensure(id: "xcopri", name: "Xcopri")
        vault.wipe()
        XCTAssertTrue(vault.load().items.isEmpty)
        XCTAssertNil(defaults.object(forKey: PharmacyVault.legacySavedKey))
        XCTAssertNil(try store.data(forKey: PharmacyVault.storageKey))
    }

    func testFailedSecureWriteDoesNotRestorePlaintextDefaults() {
        defaults.set(["Xcopri"], forKey: PharmacyVault.legacySavedKey)
        let vault = vault()
        _ = vault.load()
        store.failNextWrite = .encodingFailed
        _ = vault.toggle(id: "lipitor", name: "Lipitor")
        XCTAssertNil(defaults.stringArray(forKey: PharmacyVault.legacySavedKey))
    }
}
