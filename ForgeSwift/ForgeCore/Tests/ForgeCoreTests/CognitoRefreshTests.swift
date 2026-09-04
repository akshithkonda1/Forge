import XCTest
@testable import ForgeCore

/// Token refresh is the difference between an app that works and an app that
/// works for an hour. Cognito access tokens expire in sixty minutes by default,
/// and before this existed the refresh token was stored and never used — so
/// every session silently became a 401 machine, and the chat path turned those
/// 401s into plausible rule-based answers.
final class CognitoRefreshTests: XCTestCase {

    private let region = "us-east-1"
    private let clientId = "abc123clientid"

    // MARK: - Request shape

    func testRefreshRequestTargetsInitiateAuthWithTheRefreshFlow() throws {
        let request = try CognitoPasswordAuth.refreshRequest(
            region: region, clientId: clientId, refreshToken: "refresh-me"
        )

        XCTAssertEqual(request.url?.absoluteString, "https://cognito-idp.us-east-1.amazonaws.com/")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Amz-Target"),
                       "AWSCognitoIdentityProviderService.InitiateAuth")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"),
                       "application/x-amz-json-1.1")

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        XCTAssertEqual(json["AuthFlow"] as? String, "REFRESH_TOKEN_AUTH")
        XCTAssertEqual(json["ClientId"] as? String, clientId)
        let params = try XCTUnwrap(json["AuthParameters"] as? [String: String])
        XCTAssertEqual(params["REFRESH_TOKEN"], "refresh-me")
        XCTAssertNil(params["PASSWORD"], "a refresh must never carry the password")
    }

    func testMisconfigurationIsRefusedBeforeAnyNetworkCall() {
        XCTAssertThrowsError(
            try CognitoPasswordAuth.refreshRequest(region: "", clientId: clientId, refreshToken: "r")
        ) { XCTAssertEqual($0 as? ForgeAuthError, .cognitoNotConfigured) }

        XCTAssertThrowsError(
            try CognitoPasswordAuth.refreshRequest(region: region, clientId: "", refreshToken: "r")
        ) { XCTAssertEqual($0 as? ForgeAuthError, .cognitoNotConfigured) }
    }

    func testAnEmptyRefreshTokenIsRejectedRatherThanSent() {
        XCTAssertThrowsError(
            try CognitoPasswordAuth.refreshRequest(region: region, clientId: clientId, refreshToken: "")
        ) { error in
            guard case ForgeAuthError.cognitoRejected = error else {
                return XCTFail("expected a rejection, got \(error)")
            }
        }
    }

    // MARK: - Response parsing

    /// The one that matters. Cognito does **not** return a refresh token on a
    /// refresh — only the new access and id tokens. Treating that absence as
    /// "signed out" logs every user out on their first renewal, an hour in.
    func testRefreshKeepsTheExistingRefreshTokenWhenCognitoOmitsIt() throws {
        let payload = """
        {"AuthenticationResult":{"AccessToken":"new-access","IdToken":"new-id","ExpiresIn":3600}}
        """.data(using: .utf8)!

        let result = try CognitoPasswordAuth.parseRefreshResponse(
            payload, email: "sam@example.com", existingRefreshToken: "the-original"
        )

        XCTAssertEqual(result.accessToken, "new-access")
        XCTAssertEqual(result.idToken, "new-id")
        XCTAssertEqual(result.refreshToken, "the-original",
                       "dropping this signs the user out sixty minutes in")
    }

    func testARotatedRefreshTokenIsAdopted() throws {
        let payload = """
        {"AuthenticationResult":{"AccessToken":"a","IdToken":"b","RefreshToken":"rotated"}}
        """.data(using: .utf8)!

        let result = try CognitoPasswordAuth.parseRefreshResponse(
            payload, email: "sam@example.com", existingRefreshToken: "the-original"
        )
        XCTAssertEqual(result.refreshToken, "rotated")
    }

    func testARevokedRefreshTokenSurfacesAsRejectionNotSuccess() {
        let payload = """
        {"__type":"NotAuthorizedException","message":"Refresh Token has been revoked"}
        """.data(using: .utf8)!

        XCTAssertThrowsError(
            try CognitoPasswordAuth.parseRefreshResponse(
                payload, email: "sam@example.com", existingRefreshToken: "gone"
            )
        ) { error in
            guard case ForgeAuthError.cognitoRejected(let message) = error else {
                return XCTFail("expected cognitoRejected, got \(error)")
            }
            XCTAssertTrue(message.contains("revoked"))
        }
    }

    func testAResponseWithoutTokensIsAnError() {
        let payload = #"{"ChallengeName":"NEW_PASSWORD_REQUIRED"}"#.data(using: .utf8)!
        XCTAssertThrowsError(
            try CognitoPasswordAuth.parseRefreshResponse(
                payload, email: "sam@example.com", existingRefreshToken: "r"
            )
        )
    }

    func testUserIdComesFromTheTokenSubjectNotTheTypedEmail() throws {
        // {"sub":"cognito-sub-42"} as an unsigned JWT payload.
        let claims = Data(#"{"sub":"cognito-sub-42"}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let idToken = "header.\(claims).signature"
        let payload = """
        {"AuthenticationResult":{"AccessToken":"a","IdToken":"\(idToken)"}}
        """.data(using: .utf8)!

        let result = try CognitoPasswordAuth.parseRefreshResponse(
            payload, email: "sam@example.com", existingRefreshToken: "r"
        )
        XCTAssertEqual(result.userId, "cognito-sub-42",
                       "binding to a typed email rather than the token subject is how IDOR starts")
    }
}

final class ForgeAuthErrorTests: XCTestCase {

    /// The distinction the chat fallback depends on: retry-later versus
    /// sign-in-again. Collapsing them means an expired session reads as a
    /// network blip and the user waits for a recovery that never comes.
    func testOnlyNetworkFailuresAreWorthRetrying() {
        XCTAssertTrue(ForgeAuthError.network.isRecoverableByRetry)
        XCTAssertFalse(ForgeAuthError.signedOut.isRecoverableByRetry)
        XCTAssertFalse(ForgeAuthError.cognitoNotConfigured.isRecoverableByRetry)
        XCTAssertFalse(ForgeAuthError.cognitoRejected("no").isRecoverableByRetry)
        XCTAssertFalse(ForgeAuthError.overrideDisabled.isRecoverableByRetry)
    }

    func testEveryErrorSaysSomethingAUserCanActOn() {
        let errors: [ForgeAuthError] = [
            .cognitoNotConfigured, .cognitoRejected("Incorrect username or password."),
            .overrideDisabled, .network, .signedOut,
        ]
        for error in errors {
            XCTAssertFalse(error.userMessage.isEmpty)
            XCTAssertFalse(error.userMessage.contains("Error Domain"),
                           "raw NSError text is not a message for a person")
        }
    }

    func testARejectionCarriesCognitosOwnWording() {
        XCTAssertEqual(
            ForgeAuthError.cognitoRejected("Incorrect username or password.").userMessage,
            "Incorrect username or password."
        )
    }
}
