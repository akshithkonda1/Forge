import Foundation

/// Data domains ARIA can reason over — mirrors `AriaDataDomain` in api-contracts.
enum AriaDataDomain: String, CaseIterable, Codable, Identifiable {
    case sleep, readiness, activity, training, chronotype, body, nutrition, profile, progress, lifestyle
    case clinicalData = "clinical_data"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sleep: return "Sleep"
        case .readiness: return "Readiness"
        case .activity: return "Activity"
        case .training: return "Training"
        case .chronotype: return "Chronotype"
        case .body: return "Body"
        case .nutrition: return "Nutrition"
        case .profile: return "Profile"
        case .progress: return "Progress"
        case .lifestyle: return "Lifestyle"
        case .clinicalData: return "Clinical Data (Non PHI)"
        }
    }
}

/// Per-domain grants persisted locally and sent with each ARIA request.
struct AriaPermissionsStore: Codable, Equatable {
    var grants: [String: Bool]

    static var allowAll: AriaPermissionsStore {
        var grants: [String: Bool] = [:]
        for domain in AriaDataDomain.allCases {
            grants[domain.rawValue] = true
        }
        return AriaPermissionsStore(grants: grants)
    }

    func isAllowed(_ domain: AriaDataDomain) -> Bool {
        grants[domain.rawValue] ?? true
    }

    mutating func setAllowed(_ domain: AriaDataDomain, _ allowed: Bool) {
        grants[domain.rawValue] = allowed
    }

    var payload: [String: Bool] { grants }
}