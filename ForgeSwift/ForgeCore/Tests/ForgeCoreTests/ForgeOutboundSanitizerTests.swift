import XCTest
@testable import ForgeCore

final class ForgeOutboundSanitizerTests: XCTestCase {

    func testStripsHealthKeysAndCanariesFromJSON() throws {
        let payload: [String: Any] = [
            "message": "how should I train",
            "user_id": "u1",
            "samples": [["metric": "hrv", "value": ForgeOutboundSanitizer.Canary.hrv]],
            "hrv": ForgeOutboundSanitizer.Canary.hrv,
            "email": ForgeOutboundSanitizer.Canary.email,
            "firstName": ForgeOutboundSanitizer.Canary.name,
            "context": [
                "sleep": ["durationMinutes": ForgeOutboundSanitizer.Canary.sleepMinutes],
                "profile": ["coachingStyle": "steady"],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        var request = URLRequest(url: URL(string: "https://api.forge.app/ai/chat?hrv=188")!)
        request.httpMethod = "POST"
        request.setValue(ForgeOutboundSanitizer.Canary.name, forHTTPHeaderField: "X-User")
        request.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
        request.httpBody = data

        let clean = ForgeOutboundSanitizer.sanitize(request)
        XCTAssertTrue(ForgeOutboundSanitizer.leakFindings(in: clean).isEmpty, "\(ForgeOutboundSanitizer.leakFindings(in: clean))")
        XCTAssertEqual(clean.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
        XCTAssertFalse(clean.url?.absoluteString.contains("188") == true)

        let body = try JSONSerialization.jsonObject(with: clean.httpBody ?? Data()) as? [String: Any]
        XCTAssertNil(body?["samples"])
        XCTAssertNil(body?["hrv"])
        XCTAssertNil(body?["email"])
        XCTAssertNil(body?["firstName"])
        XCTAssertEqual(body?["message"] as? String, "how should I train")
        let context = body?["context"] as? [String: Any]
        XCTAssertNil(context?["sleep"])
        XCTAssertEqual((context?["profile"] as? [String: Any])?["coachingStyle"] as? String, "steady")
    }

    func testAuthPathMayKeepEmail() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "email": "real.user@example.com",
            "password": "not-a-canary",
            "hrv": ForgeOutboundSanitizer.Canary.hrv,
        ])
        var request = URLRequest(url: URL(string: "https://cognito.example/oauth2/token")!)
        request.httpBody = data
        let clean = ForgeOutboundSanitizer.sanitize(request)
        let body = try JSONSerialization.jsonObject(with: clean.httpBody ?? Data()) as? [String: Any]
        XCTAssertEqual(body?["email"] as? String, "real.user@example.com")
        XCTAssertNil(body?["hrv"])
        XCTAssertTrue(ForgeOutboundSanitizer.leakFindings(in: clean).isEmpty)
    }

    func testLogRedactionDropsCanaries() {
        let line = ForgeOutboundSanitizer.redactLog(
            "user \(ForgeOutboundSanitizer.Canary.name) hrv=\(ForgeOutboundSanitizer.Canary.hrv) \(ForgeOutboundSanitizer.Canary.email)"
        )
        XCTAssertTrue(ForgeOutboundSanitizer.leakFindings(in: line).isEmpty, line)
    }

    func testPrivacySentenceIsExact() {
        XCTAssertEqual(
            ForgePrivacyCopy.healthStaysOnDevice,
            "Health data always stays on device, never goes to a server."
        )
    }
}
