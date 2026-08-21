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
    }

    func continueAsTester() throws -> ForgeAuthSession {
        guard canUseDevOverride else { throw ForgeAuthError.overrideDisabled }
        let minted = DevAuthOverride.session()
        try persist(minted)
        return minted
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

    func signOut() {
        session = nil
        try? store.remove(Self.sessionKey)
        try? store.remove("forge.aria.authToken")
    }

    func authorizationHeader() -> String? {
        session.map(\.authorizationHeader)
    }

    private func persist(_ session: ForgeAuthSession) throws {
        self.session = session
        try store.setValue(session, forKey: Self.sessionKey)
        try store.set(session.accessToken, forKey: "forge.aria.authToken")
        AriaContextStore.shared.configure(userId: session.userId)
    }
}
