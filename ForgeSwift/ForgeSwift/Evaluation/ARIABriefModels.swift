import Foundation

enum ARIABriefFocus: String, Codable, Equatable {
    case morning
    case evening
    case postWorkout = "post-workout"
    case midday
    case auto
}

struct ARIABrief: Equatable {
    var focus: ARIABriefFocus
    var title: String
    var headline: String
    var body: String
    var notificationCopy: String
    var trainingDecision: TrainingDecision
    var compoundFlags: [String]
    var generatedAt: Date
}