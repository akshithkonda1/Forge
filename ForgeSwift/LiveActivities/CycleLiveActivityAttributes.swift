import Foundation
import ActivityKit

struct CycleLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var phase: String
        var dayInCycle: Int?
        var fertileScore: Int?
        var daysUntilOvulation: Int?
        var isActiveFertileWindow: Bool
        var isCurrentlyBleeding: Bool
    }
}
