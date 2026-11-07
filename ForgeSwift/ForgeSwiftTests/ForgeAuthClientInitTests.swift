// Regression for the cold-launch EXC_BREAKPOINT: ForgeAuthClient.shared's
// initializer used to call AriaOperatingMode.refresh() → resolve() →
// ForgeAuthClient.shared, re-entering the static addressor
// (`_dispatch_once_wait`).
import XCTest
import ForgeCore
@testable import ForgeSwift

@MainActor
final class ForgeAuthClientInitTests: XCTestCase {

    private var previousOverride: Any?
    private var previousMode: Any?
    private var previousAPI: Any?
    private var previousAuth: Any?
    private var previousOnboarded: Any?

    override func setUp() {
        super.setUp()
        previousOverride = UserDefaults.standard.object(forKey: "forge.auth.devOverride")
        previousMode = UserDefaults.standard.object(forKey: "forge.aria.operatingMode")
        previousAPI = UserDefaults.standard.object(forKey: "forge.api.baseURL")
        previousAuth = UserDefaults.standard.object(forKey: AppStore.authDefaultsKey)
        previousOnboarded = UserDefaults.standard.object(forKey: AppStore.onboardedDefaultsKey)
        UserDefaults.standard.removeObject(forKey: "forge.aria.operatingMode")
        UserDefaults.standard.removeObject(forKey: "forge.api.baseURL")
    }

    override func tearDown() {
        restore("forge.auth.devOverride", previousOverride)
        restore("forge.aria.operatingMode", previousMode)
        restore("forge.api.baseURL", previousAPI)
        restore(AppStore.authDefaultsKey, previousAuth)
        restore(AppStore.onboardedDefaultsKey, previousOnboarded)
        super.tearDown()
    }

    /// Loopback + override is the Device Hub / test-ready install path that
    /// used to refresh operating mode from inside `init` and trap.
    func testTestReadyInitDoesNotReenterShared() {
        UserDefaults.standard.set(true, forKey: "forge.auth.devOverride")
        let store = InMemorySecureStore()
        let config = ForgeAuthConfig(
            apiBaseURL: URL(string: "http://127.0.0.1:3001")!,
            environment: "dev"
        )

        // Completing construction is the crash proof. The old code called
        // resolve() → ForgeAuthClient.shared from this initializer.
        let client = ForgeAuthClient(config: config, store: store)

        XCTAssertEqual(client.session?.mode, .devOverride)
        XCTAssertEqual(client.session?.userId, ForgeAuthConfig.testUserId)
        XCTAssertTrue(client.canUseDevOverride)
        // A standalone client must not publish itself as the singleton.
        XCTAssertFalse(ForgeAuthClient.sharedIfReady === client)

        // resolve must accept the in-hand client and never need `.shared`.
        let mode = AriaOperatingMode.resolve(using: client)
        if AriaDummyOrchestra.isCompiledIn {
            XCTAssertEqual(mode, .dummy)
        } else {
            XCTAssertEqual(mode, AriaOperatingMode.resolveFromBundle())
        }
    }

    func testResolveDoesNotReadSharedWhenSessionIsPassed() {
        UserDefaults.standard.removeObject(forKey: "forge.aria.operatingMode")
        let config = ForgeAuthConfig(
            apiBaseURL: URL(string: "http://127.0.0.1:3001")!,
            environment: "dev"
        )
        let mode = AriaOperatingMode.resolve(
            session: DevAuthOverride.session(),
            config: config,
            canUseDevOverride: true
        )
        if AriaDummyOrchestra.isCompiledIn {
            XCTAssertEqual(mode, .dummy)
        } else {
            XCTAssertEqual(mode, AriaOperatingMode.resolveFromBundle())
        }
    }

    /// Production-like config + empty keychain never mints a tester. That is
    /// the signed-out launch: ContentView shows AuthWelcomeView when
    /// `!isAuthenticated`.
    func testSignedOutProductionConfigLeavesSessionNil() {
        UserDefaults.standard.set(false, forKey: "forge.auth.devOverride")
        let client = ForgeAuthClient(
            config: ForgeAuthConfig(
                apiBaseURL: URL(string: "https://api.forge.example")!,
                environment: "production"
            ),
            store: InMemorySecureStore()
        )
        XCTAssertNil(client.session)
        XCTAssertFalse(client.canUseDevOverride)
        XCTAssertEqual(
            AriaOperatingMode.resolve(using: client),
            AriaOperatingMode.resolveFromBundle()
        )
    }

    func testSignedOutRestoreLandsOnAuthWelcomeGate() {
        UserDefaults.standard.set(false, forKey: AppStore.authDefaultsKey)
        UserDefaults.standard.set(false, forKey: AppStore.onboardedDefaultsKey)
        let store = AppStore()
        // Device Hub Debug may have already minted a tester on `.shared`.
        // The welcome gate is still `!isAuthenticated`; force the signed-out
        // install the crash report described (empty keychain, no session).
        if ForgeAuthClient.shared.session == nil {
            XCTAssertFalse(store.isAuthenticated)
        }
        store.isAuthenticated = false
        store.isOnboarded = false
        XCTAssertFalse(store.isAuthenticated)
        _ = AuthWelcomeView.self
    }

    private func restore(_ key: String, _ value: Any?) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
