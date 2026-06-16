import Foundation

/// Living user model ARIA reasons over — mirrors backend `UserContext`.
struct AriaContext: Codable, Equatable {
    var userId: String
    var lifestyleTags: [String]
    var currentGoals: [String]
    var constraints: [String]
    var recentPatterns: [String]
    var lastInsights: [String]
    var relationshipLevel: Int
    var lastUpdated: Date

    init(
        userId: String,
        lifestyleTags: [String] = [],
        currentGoals: [String] = [],
        constraints: [String] = [],
        recentPatterns: [String] = [],
        lastInsights: [String] = [],
        relationshipLevel: Int = 1,
        lastUpdated: Date = Date()
    ) {
        self.userId = userId
        self.lifestyleTags = lifestyleTags
        self.currentGoals = currentGoals
        self.constraints = constraints
        self.recentPatterns = recentPatterns
        self.lastInsights = lastInsights
        self.relationshipLevel = relationshipLevel
        self.lastUpdated = lastUpdated
    }

    var relationshipLabel: String {
        switch relationshipLevel {
        case 8...: return "Trusted Partner"
        case 5...: return "Growing Bond"
        case 3...: return "Getting to Know You"
        default:   return "New Connection"
        }
    }
}

/// Snapshot sent with each chat request.
struct AriaRichContext: Codable, Equatable {
    var userId: String
    var lifestyleTags: [String]
    var goals: [String]
    var constraints: [String]
    var recentPatterns: [String]
    var recentMetrics: [String: Double]
    var relationshipLevel: Int
    var timestamp: String
}