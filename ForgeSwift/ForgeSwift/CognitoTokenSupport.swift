import Foundation

enum CognitoTokenSupport {
    static let defaultRefreshLeadTime: TimeInterval = 5 * 60

    static func expirationDate(forJWT jwt: String) -> Date? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder > 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }

        guard
            let data = Data(base64Encoded: payload),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let exp = json["exp"] as? TimeInterval
        else {
            return nil
        }

        return Date(timeIntervalSince1970: exp)
    }

    static func shouldRefresh(
        idToken: String,
        now: Date = Date(),
        within leadTime: TimeInterval = defaultRefreshLeadTime
    ) -> Bool {
        guard let expiration = expirationDate(forJWT: idToken) else { return true }
        return expiration.timeIntervalSince(now) <= leadTime
    }

    static func refreshAuthPayload(clientId: String, refreshToken: String) -> [String: Any] {
        [
            "AuthFlow": "REFRESH_TOKEN_AUTH",
            "ClientId": clientId,
            "AuthParameters": [
                "REFRESH_TOKEN": refreshToken,
            ],
        ]
    }
}