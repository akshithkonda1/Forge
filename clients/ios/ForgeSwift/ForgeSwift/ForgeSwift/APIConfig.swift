import Foundation

enum APIConfig {
    static var baseURL: URL {
        if let value = Bundle.main.object(forInfoDictionaryKey: "FORGE_API_BASE_URL") as? String,
           let url = URL(string: value) {
            return url
        }
        return URL(string: "http://localhost:3001")!
    }

    static var usesAuth: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "FORGE_USE_AUTH") as? String) != "false"
    }

    static var cognitoRegion: String {
        Bundle.main.object(forInfoDictionaryKey: "FORGE_COGNITO_REGION") as? String ?? "us-east-1"
    }

    static var cognitoClientId: String {
        Bundle.main.object(forInfoDictionaryKey: "FORGE_COGNITO_CLIENT_ID") as? String ?? ""
    }

    static var cognitoEndpoint: URL {
        URL(string: "https://cognito-idp.\(cognitoRegion).amazonaws.com/")!
    }
}
