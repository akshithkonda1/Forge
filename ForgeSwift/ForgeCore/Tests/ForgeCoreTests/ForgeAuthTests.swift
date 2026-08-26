import XCTest
@testable import ForgeCore

final class ForgeAuthTests: XCTestCase {

    func testDevOverrideIsForbiddenInReleaseAndInProduction() {
        let prod = ForgeAuthConfig(
            apiBaseURL: ForgeAuthConfig.defaultLocalAPI,
            environment: "production"
        )
        let dev = ForgeAuthConfig(
            apiBaseURL: ForgeAuthConfig.defaultLocalAPI,
            environment: "dev"
        )

        XCTAssertFalse(ForgeAuthPolicy.devOverrideAllowed(userEnabled: true, config: prod, debugBuild: true))
        XCTAssertFalse(ForgeAuthPolicy.devOverrideAllowed(userEnabled: true, config: dev, debugBuild: false))
        XCTAssertFalse(ForgeAuthPolicy.devOverrideAllowed(userEnabled: false, config: dev, debugBuild: true))
        XCTAssertTrue(ForgeAuthPolicy.devOverrideAllowed(userEnabled: true, config: dev, debugBuild: true))
    }

    func testXcodeDeviceHubLaunchDetectsXcodeEnv() {
        XCTAssertTrue(
            ForgeAuthPolicy.isXcodeDeviceHubLaunch(
                environment: ["OS_ACTIVITY_DT_MODE": "enable"],
                debugBuild: true
            )
        )
        XCTAssertTrue(
            ForgeAuthPolicy.isXcodeDeviceHubLaunch(
                environment: ["SIMULATOR_DEVICE_NAME": "iPhone 17 Pro"],
                debugBuild: true
            )
        )
        XCTAssertFalse(
            ForgeAuthPolicy.isXcodeDeviceHubLaunch(
                environment: ["OS_ACTIVITY_DT_MODE": "enable"],
                debugBuild: false
            )
        )
        XCTAssertFalse(
            ForgeAuthPolicy.isXcodeDeviceHubLaunch(
                environment: [:],
                debugBuild: true
            )
        )
    }

    func testLoopbackAPIAndXcodeLaunchAutoInstallTester() {
        let loopback = ForgeAuthConfig(
            apiBaseURL: URL(string: "http://127.0.0.1:3001")!,
            environment: "dev"
        )
        XCTAssertTrue(loopback.apiIsLoopback)
        XCTAssertTrue(
            ForgeAuthPolicy.shouldAutoInstallTester(
                allowed: true,
                xcodeLaunch: true,
                apiIsLoopback: false
            )
        )
        XCTAssertTrue(
            ForgeAuthPolicy.shouldAutoInstallTester(
                allowed: true,
                xcodeLaunch: false,
                apiIsLoopback: true
            )
        )
        XCTAssertFalse(
            ForgeAuthPolicy.shouldAutoInstallTester(
                allowed: false,
                xcodeLaunch: true,
                apiIsLoopback: true
            )
        )
    }

    func testTesterSessionMatchesBackendTestUser() {
        let session = DevAuthOverride.session()
        XCTAssertEqual(session.userId, "test-user-00000000")
        XCTAssertEqual(session.email, "tester@forge.dev")
        XCTAssertEqual(session.mode, .devOverride)
        XCTAssertEqual(session.provider, "dev-override")
        XCTAssertTrue(session.authorizationHeader.hasPrefix("Bearer "))
    }

    func testUnsignedTokenIsThreePartsAndCarriesSub() {
        let token = DevAuthOverride.unsignedAccessToken(sub: "test-user-00000000", email: "tester@forge.dev")
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        XCTAssertEqual(parts.count, 3, "Lambda decode requires header.payload.signature")
        XCTAssertEqual(CognitoPasswordAuth.jwtSubject(token), "test-user-00000000")
    }

    func testCognitoRequestIsPasswordAuthAgainstTheIdp() throws {
        let request = try CognitoPasswordAuth.initiateAuthRequest(
            region: "us-east-1",
            clientId: "ios-client",
            username: "ada@forge.dev",
            password: "hunter2-HUNTER"
        )
        XCTAssertEqual(request.url?.host, "cognito-idp.us-east-1.amazonaws.com")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Amz-Target"), "AWSCognitoIdentityProviderService.InitiateAuth")
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        XCTAssertEqual(body["AuthFlow"] as? String, "USER_PASSWORD_AUTH")
        XCTAssertEqual(body["ClientId"] as? String, "ios-client")
        let params = body["AuthParameters"] as! [String: String]
        XCTAssertEqual(params["USERNAME"], "ada@forge.dev")
        XCTAssertEqual(params["PASSWORD"], "hunter2-HUNTER")
    }

    func testCognitoRequestRefusesAnEmptyClient() {
        XCTAssertThrowsError(
            try CognitoPasswordAuth.initiateAuthRequest(
                region: "",
                clientId: "",
                username: "a@b.c",
                password: "x"
            )
        ) { error in
            XCTAssertEqual(error as? ForgeAuthError, .cognitoNotConfigured)
        }
    }

    func testCognitoParseReadsTokensAndSubject() throws {
        let payload = #"{"sub":"abc-123","email":"ada@forge.dev"}"#
        let idToken = "hdr.\(base64URL(payload)).sig"
        let json = """
        {"AuthenticationResult":{"AccessToken":"access-token","IdToken":"\(idToken)","RefreshToken":"refresh"}}
        """
        let result = try CognitoPasswordAuth.parseAuthResponse(
            Data(json.utf8),
            email: "ada@forge.dev"
        )
        XCTAssertEqual(result.accessToken, "access-token")
        XCTAssertEqual(result.userId, "abc-123")
        XCTAssertEqual(result.refreshToken, "refresh")
    }

    func testCognitoParseSurfacesPoolErrors() {
        let json = #"{"__type":"NotAuthorizedException","message":"Incorrect username or password."}"#
        XCTAssertThrowsError(
            try CognitoPasswordAuth.parseAuthResponse(Data(json.utf8), email: "ada@forge.dev")
        ) { error in
            XCTAssertEqual(
                error as? ForgeAuthError,
                .cognitoRejected("Incorrect username or password.")
            )
        }
    }

    func testConfigFromPlist() {
        let config = ForgeAuthConfig.fromInfoDictionary([
            "FORGEAPIBaseURL": "https://api.forge.example",
            "FORGECognitoRegion": "us-east-1",
            "FORGECognitoClientId": "abc",
            "FORGECognitoUserPoolId": "us-east-1_xyz",
            "FORGEEnvironment": "production",
        ])
        XCTAssertTrue(config.cognitoConfigured)
        XCTAssertTrue(config.isProductionLike)
        XCTAssertEqual(config.apiBaseURL.host, "api.forge.example")
    }

    private func base64URL(_ string: String) -> String {
        Data(string.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
