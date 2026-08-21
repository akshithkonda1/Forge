import XCTest
@testable import ForgeCore

/// The migration exists to remove plaintext, not to copy it. Most of these tests
/// are about the delete rather than the write, because a migration that writes
/// to the Keychain and leaves the original behind has accomplished nothing while
/// looking like it worked.
final class SecureStoreMigrationTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!
    private var store: InMemorySecureStore!

    override func setUp() {
        super.setUp()
        suiteName = "forge.securestore.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = InMemorySecureStore()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        store = nil
        super.tearDown()
    }

    // MARK: - The point of the exercise

    func testMigrationRemovesTheUserDefaultsCopy() throws {
        defaults.set("eyJhbGciOi.tokenish.value", forKey: "forge.aria.authToken")

        let report = SecureStoreMigration.run(keys: ["forge.aria.authToken"],
                                              from: defaults, to: store)

        XCTAssertEqual(report.migrated, ["forge.aria.authToken"])
        XCTAssertNil(defaults.object(forKey: "forge.aria.authToken"),
                     "the plaintext is still in the plist, so nothing was actually fixed")
        XCTAssertEqual(try store.string(forKey: "forge.aria.authToken"),
                       "eyJhbGciOi.tokenish.value")
    }

    func testEveryDeclaredSensitiveKeyIsMovedAndCleared() throws {
        for (index, key) in SecureStoreMigration.sensitiveKeys.enumerated() {
            defaults.set("value-\(index)", forKey: key)
        }

        let report = SecureStoreMigration.run(from: defaults, to: store)

        XCTAssertEqual(report.migrated.count, SecureStoreMigration.sensitiveKeys.count)
        XCTAssertTrue(report.failed.isEmpty)
        for key in SecureStoreMigration.sensitiveKeys {
            XCTAssertNil(defaults.object(forKey: key), "\(key) left behind in UserDefaults")
        }
    }

    /// The cycle digest is the one with a legal dimension rather than only a
    /// security one, so it gets its own assertion.
    func testCycleDigestDoesNotSurviveInPlaintext() throws {
        defaults.set(#"{"phase":"luteal","dayOfCycle":19}"#, forKey: "forge.cycle.sharing.digest")

        SecureStoreMigration.run(from: defaults, to: store)

        XCTAssertNil(defaults.object(forKey: "forge.cycle.sharing.digest"))
        XCTAssertNotNil(try store.data(forKey: "forge.cycle.sharing.digest"))
    }

    // MARK: - Failure has to be safe

    func testAFailedWriteLeavesTheOriginalAlone() throws {
        defaults.set("still-needed", forKey: "forge.aria.authToken")
        store.failNextWrite = .keychain(status: -34018)   // errSecMissingEntitlement

        let report = SecureStoreMigration.run(keys: ["forge.aria.authToken"],
                                              from: defaults, to: store)

        XCTAssertEqual(report.failed, ["forge.aria.authToken"])
        XCTAssertEqual(defaults.string(forKey: "forge.aria.authToken"), "still-needed",
                       "destroying the only copy after a failed write loses the session")
    }

    func testAFailedRunRetriesOnTheNextLaunch() throws {
        defaults.set("retry-me", forKey: "forge.aria.authToken")
        store.failNextWrite = .keychain(status: -25308)   // errSecInteractionNotAllowed

        _ = SecureStoreMigration.run(keys: ["forge.aria.authToken"], from: defaults, to: store)
        let second = SecureStoreMigration.run(keys: ["forge.aria.authToken"], from: defaults, to: store)

        XCTAssertEqual(second.migrated, ["forge.aria.authToken"])
        XCTAssertNil(defaults.object(forKey: "forge.aria.authToken"))
    }

    // MARK: - Idempotence

    func testRunningTwiceIsSafe() throws {
        defaults.set("once", forKey: "forge.aria.authToken")

        let first = SecureStoreMigration.run(keys: ["forge.aria.authToken"], from: defaults, to: store)
        let second = SecureStoreMigration.run(keys: ["forge.aria.authToken"], from: defaults, to: store)

        XCTAssertTrue(first.didChangeAnything)
        XCTAssertFalse(second.didChangeAnything)
        XCTAssertEqual(second.absent, ["forge.aria.authToken"])
        XCTAssertEqual(try store.string(forKey: "forge.aria.authToken"), "once")
    }

    /// A build that already migrated holds the newer value. A stale plist copy
    /// reappearing — a restored backup, a downgrade — must not overwrite it.
    func testAnExistingSecureValueWins() throws {
        try store.set("current", forKey: "forge.aria.authToken")
        defaults.set("stale-from-a-restored-backup", forKey: "forge.aria.authToken")

        SecureStoreMigration.run(keys: ["forge.aria.authToken"], from: defaults, to: store)

        XCTAssertEqual(try store.string(forKey: "forge.aria.authToken"), "current")
        XCTAssertNil(defaults.object(forKey: "forge.aria.authToken"),
                     "the stale copy should still be cleared out")
    }

    func testNothingToMigrateOnAFreshInstall() {
        let report = SecureStoreMigration.run(from: defaults, to: store)
        XCTAssertTrue(report.migrated.isEmpty)
        XCTAssertTrue(report.failed.isEmpty)
        XCTAssertEqual(report.absent.count, SecureStoreMigration.sensitiveKeys.count)
    }

    // MARK: - Value shapes

    /// Location arrives as a Double, profiles as dictionaries, tokens as strings.
    /// All of them have to survive the round trip.
    func testNonStringValuesSurvive() throws {
        defaults.set(37.7749, forKey: "forge.lifestyle.lastLat")
        defaults.set(["name": "Sam", "goal": "build-muscle"], forKey: "forge.user.profile.v1")

        SecureStoreMigration.run(from: defaults, to: store)

        let lat = try XCTUnwrap(try store.data(forKey: "forge.lifestyle.lastLat"))
        XCTAssertEqual(SecureStoreMigration.decodeDouble(lat) ?? 0, 37.7749, accuracy: 0.00001)

        let profile = try XCTUnwrap(try store.data(forKey: "forge.user.profile.v1"))
        let decoded = try PropertyListSerialization.propertyList(
            from: profile, options: [], format: nil
        ) as? [String: String]
        XCTAssertEqual(decoded?["name"], "Sam")
    }

    func testOrdinaryPreferencesAreLeftAlone() {
        defaults.set(2, forKey: "forge.ui.selectedTab")
        defaults.set(true, forKey: "forge.notif.cycle.period")

        SecureStoreMigration.run(from: defaults, to: store)

        XCTAssertEqual(defaults.integer(forKey: "forge.ui.selectedTab"), 2,
                       "sweeping every forge.* key into the Keychain would make it the settings store")
        XCTAssertTrue(defaults.bool(forKey: "forge.notif.cycle.period"))
    }
}

final class SecureStoreTests: XCTestCase {

    func testRoundTripsStringsAndCodableValues() throws {
        let store = InMemorySecureStore()

        try store.set("hello", forKey: "greeting")
        XCTAssertEqual(try store.string(forKey: "greeting"), "hello")

        struct Token: Codable, Equatable { let access: String; let expires: Int }
        try store.setValue(Token(access: "abc", expires: 3600), forKey: "token")
        XCTAssertEqual(try store.value(Token.self, forKey: "token"),
                       Token(access: "abc", expires: 3600))
    }

    func testWritingNilRemovesTheKey() throws {
        let store = InMemorySecureStore()
        try store.set("x", forKey: "k")
        try store.remove("k")
        XCTAssertNil(try store.data(forKey: "k"))
        XCTAssertFalse(store.keys.contains("k"))
    }

    func testMissingKeyIsNilRatherThanAnError() throws {
        XCTAssertNil(try InMemorySecureStore().data(forKey: "never-written"))
    }

    func testRemoveAllClearsEverything() throws {
        let store = InMemorySecureStore()
        try store.set("a", forKey: "one")
        try store.set("b", forKey: "two")
        try store.removeAll()
        XCTAssertTrue(store.keys.isEmpty)
    }
}
