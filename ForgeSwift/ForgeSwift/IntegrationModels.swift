import Foundation

enum IntegrationProvider: String, Codable, CaseIterable {
    case appleHealth = "apple-health"
    case oura = "oura"
    case whoop = "whoop"
    case garmin = "garmin"
    case strava = "strava"
    case manual = "manual"

    var displayName: String {
        switch self {
        case .appleHealth: return "Apple Health"
        case .oura: return "Oura Ring"
        case .whoop: return "Whoop"
        case .garmin: return "Garmin"
        case .strava: return "Strava"
        case .manual: return "Manual"
        }
    }

    var icon: String {
        switch self {
        case .appleHealth: return "heart.text.square.fill"
        case .oura: return "circle.circle.fill"
        case .whoop: return "bolt.heart.fill"
        case .garmin: return "location.fill"
        case .strava: return "figure.run"
        case .manual: return "plus.circle.fill"
        }
    }
}

enum IntegrationStatus: String, Codable {
    case connected
    case needsAuth = "needs-auth"
    case syncing
    case error
}

struct IntegrationConnection: Identifiable, Codable, Equatable {
    var id: String { provider.rawValue + displayName }
    let provider: IntegrationProvider
    let displayName: String
    let status: IntegrationStatus
    let lastSyncedAt: String?
    let errorMessage: String?

    init(
        provider: IntegrationProvider,
        displayName: String,
        status: IntegrationStatus,
        lastSyncedAt: String? = nil,
        errorMessage: String? = nil
    ) {
        self.provider = provider
        self.displayName = displayName
        self.status = status
        self.lastSyncedAt = lastSyncedAt
        self.errorMessage = errorMessage
    }

    init(apiConnection: APIIntegrationConnection) {
        provider = IntegrationProvider(rawValue: apiConnection.provider) ?? .manual
        displayName = apiConnection.displayName
        status = IntegrationStatus(rawValue: apiConnection.status) ?? .needsAuth
        lastSyncedAt = apiConnection.lastSyncedAt
        errorMessage = apiConnection.errorMessage
    }
}

struct APIIntegrationConnection: Decodable {
    let provider: String
    let displayName: String
    let status: String
    let lastSyncedAt: String?
    let errorMessage: String?
}

struct DeviceServiceStatus: Decodable {
    let configured: Bool
    let connected: Bool
    let provider: String?
}

struct WidgetSessionResponse: Decodable {
    let referenceId: String
    let sessionId: String?
    let url: String?
    let expiresAt: String?
    let status: String
}

struct IntegrationSyncResponse: Decodable {
    let provider: String
    let jobId: String
    let status: String
}

struct ARIAInsightsResponse: Decodable {
    let insights: [[String: AnyDecodable]]
    let count: Int
    let periodDays: Int
}

struct AnyDecodable: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else {
            value = ""
        }
    }
}

struct WearableDevice: Identifiable {
    let id: String
    let name: String
    let provider: IntegrationProvider

    static let catalog: [WearableDevice] = [
        WearableDevice(id: "apple-watch", name: "Apple Watch", provider: .appleHealth),
        WearableDevice(id: "garmin", name: "Garmin", provider: .garmin),
        WearableDevice(id: "oura-ring", name: "Oura Ring", provider: .oura),
        WearableDevice(id: "whoop", name: "Whoop", provider: .whoop),
        WearableDevice(id: "strava", name: "Strava", provider: .strava),
    ]
}

struct CoachingInsight: Identifiable, Equatable {
    let id: String
    let type: String
    let priority: String
    let title: String
    let observation: String
    let recommendation: String
    let metric: String?

    init?(dictionary: [String: Any]) {
        guard
            let title = dictionary["title"] as? String,
            let observation = dictionary["observation"] as? String,
            let recommendation = dictionary["recommendation"] as? String
        else { return nil }

        id = (dictionary["insightId"] as? String) ?? UUID().uuidString
        type = dictionary["type"] as? String ?? "training"
        priority = dictionary["priority"] as? String ?? "medium"
        self.title = title
        self.observation = observation
        self.recommendation = recommendation
        metric = dictionary["metric"] as? String
    }
}