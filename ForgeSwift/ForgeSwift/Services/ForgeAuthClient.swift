import Foundation
import ForgeCore

/// Phone-side auth. Cognito for real accounts; a DEBUG tester session so
/// device work does not depend on AWS secrets.
@MainActor
final class ForgeAuthClient: ObservableObject {
    static let shared = ForgeAuthClient()

    @Published private(set) var session: ForgeAuthSession?

    var config: ForgeAuthConfig

    /// User-facing switch. Ignored in Release and when the API environment is prod.
    var devOverrideEnabled: Bool {
        didSet { UserDefaults.standard.set(devOverrideEnabled, forKey: Self.overrideKey) }
    }

    var canUseDevOverride: Bool {
        ForgeAuthPolicy.devOverrideAllowed(userEnabled: devOverrideEnabled, config: config)
    }

    private static let overrideKey = "forge.auth.devOverride"
    private static let sessionKey = "forge.aria.authSession"
    private let store: SecureStore

    init(
        config: ForgeAuthConfig = ForgeAuthConfig.fromInfoDictionary(Bundle.main.infoDictionary ?? [:]),
        store: SecureStore = KeychainStore()
    ) {
        self.config = config
        self.store = store
        #if DEBUG
        if UserDefaults.standard.object(forKey: Self.overrideKey) == nil {
            UserDefaults.standard.set(true, forKey: Self.overrideKey)
        }
        #endif
        self.devOverrideEnabled = UserDefaults.standard.bool(forKey: Self.overrideKey)
        self.session = try? store.value(ForgeAuthSession.self, forKey: Self.sessionKey)
        if config.apiBaseURL.host != nil, UserDefaults.standard.string(forKey: "forge.api.baseURL") == nil {
            UserDefaults.standard.set(config.apiBaseURL.absoluteString, forKey: "forge.api.baseURL")
        }
        installTestReadySessionIfNeeded()
    }

    /// Xcode Device Hub (simulator or a plugged-in phone) and loopback API
    /// builds get a tester session so ARIA is Test-Ready on-device. Never
    /// clobbers a real Cognito session unless the API URL cannot work from
    /// the phone (`127.0.0.1`).
    @discardableResult
    func installTestReadySessionIfNeeded() -> ForgeAuthSession? {
        let allowed = ForgeAuthPolicy.devOverrideAllowed(
            userEnabled: devOverrideEnabled,
            config: config
        )
        let auto = ForgeAuthPolicy.shouldAutoInstallTester(
            allowed: allowed,
            xcodeLaunch: ForgeAuthPolicy.isXcodeDeviceHubLaunch,
            apiIsLoopback: config.apiIsLoopback
        )
        guard auto else { return session }
        if let current = session, current.mode == .cognito, !config.apiIsLoopback {
            return current
        }
        if session?.mode == .devOverride { return session }
        let minted = DevAuthOverride.session()
        try? persist(minted)
        return minted
    }

    func continueAsTester() throws -> ForgeAuthSession {
        guard canUseDevOverride else { throw ForgeAuthError.overrideDisabled }
        let minted = DevAuthOverride.session()
        try persist(minted)
        return minted
    }

    func signUp(email: String, password: String, displayName: String) async throws -> CognitoPasswordAuth.SignUpResult {
        let request = try CognitoPasswordAuth.signUpRequest(
            region: config.cognitoRegion,
            clientId: config.cognitoClientId,
            username: email,
            password: password,
            name: displayName
        )
        let data: Data
        do {
            let (body, _) = try await URLSession.shared.data(for: request)
            data = body
        } catch {
            throw ForgeAuthError.network
        }
        return try CognitoPasswordAuth.parseSignUpResponse(data)
    }

    func confirmSignUp(email: String, code: String) async throws {
        let request = try CognitoPasswordAuth.confirmSignUpRequest(
            region: config.cognitoRegion,
            clientId: config.cognitoClientId,
            username: email,
            code: code
        )
        let data: Data
        do {
            let (body, _) = try await URLSession.shared.data(for: request)
            data = body
        } catch {
            throw ForgeAuthError.network
        }
        try CognitoPasswordAuth.parseConfirmSignUpResponse(data)
    }

    func signIn(email: String, password: String) async throws -> ForgeAuthSession {
        let request = try CognitoPasswordAuth.initiateAuthRequest(
            region: config.cognitoRegion,
            clientId: config.cognitoClientId,
            username: email,
            password: password
        )
        let data: Data
        do {
            let (body, _) = try await URLSession.shared.data(for: request)
            data = body
        } catch {
            throw ForgeAuthError.network
        }
        let result = try CognitoPasswordAuth.parseAuthResponse(data, email: email)
        let local = email.split(separator: "@").first.map(String.init) ?? "Athlete"
        let session = ForgeAuthSession(
            userId: result.userId,
            email: result.email,
            displayName: local.capitalized,
            provider: "email",
            accessToken: result.accessToken,
            idToken: result.idToken,
            refreshToken: result.refreshToken,
            mode: .cognito
        )
        try persist(session)
        return session
    }

    /// Renew the access token, once, without racing.
    ///
    /// Six services can hit a 401 at the same moment. Without a shared in-flight
    /// task each would start its own refresh, and Cognito would rotate the token
    /// out from under the others — so the first caller does the work and the rest
    /// await the same result.
    private var refreshTask: Task<ForgeAuthSession, Error>?

    @discardableResult
    func refreshSession() async throws -> ForgeAuthSession {
        if let existing = refreshTask { return try await existing.value }

        guard let current = session else { throw ForgeAuthError.signedOut }
        // A tester session has no Cognito behind it; renewing is a no-op rather
        // than an error, so DEBUG device work keeps running.
        guard current.mode == .cognito else { return current }
        guard let refreshToken = current.refreshToken, !refreshToken.isEmpty else {
            signOut()
            throw ForgeAuthError.signedOut
        }

        let task = Task<ForgeAuthSession, Error> { [config] in
            let request = try CognitoPasswordAuth.refreshRequest(
                region: config.cognitoRegion,
                clientId: config.cognitoClientId,
                refreshToken: refreshToken
            )
            let data: Data
            do {
                let (body, _) = try await URLSession.shared.data(for: request)
                data = body
            } catch {
                throw ForgeAuthError.network
            }
            let result = try CognitoPasswordAuth.parseRefreshResponse(
                data, email: current.email, existingRefreshToken: refreshToken
            )
            var renewed = current
            renewed.accessToken = result.accessToken
            renewed.idToken = result.idToken
            renewed.refreshToken = result.refreshToken
            return renewed
        }
        refreshTask = task
        defer { refreshTask = nil }

        do {
            let renewed = try await task.value
            try persist(renewed)
            return renewed
        } catch {
            // A refresh token Cognito refuses is not a transient failure — it is
            // revoked or expired, and the only honest response is to sign out
            // rather than retry forever.
            if let authError = error as? ForgeAuthError,
               case .cognitoRejected = authError {
                signOut()
            }
            throw error
        }
    }

    func signOut() {
        session = nil
        try? store.remove(Self.sessionKey)
        try? store.remove("forge.aria.authToken")
        // Topic affinity, familiarity and remembered facts are this session's,
        // not this device's. Carrying them across a sign-out would have ARIA
        // greeting the next person with the last one's bad knee.
        LocalTestingOrchestrator.shared.resetForNewSession()
    }

    func authorizationHeader() -> String? {
        session.map(\.authorizationHeader)
    }

    private func persist(_ session: ForgeAuthSession) throws {
        self.session = session
        try store.setValue(session, forKey: Self.sessionKey)
        try store.set(session.accessToken, forKey: "forge.aria.authToken")
        AriaContextStore.shared.configure(userId: session.userId)
        // Fresh session, fresh local state and a fresh phrasing seed, so a
        // tester who signs in twice does not get a transcript they have already
        // read.
        LocalTestingOrchestrator.shared.resetForNewSession()
    }
}
