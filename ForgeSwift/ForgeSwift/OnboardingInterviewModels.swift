import Foundation
import SwiftUI
import ForgeCore

enum HealthKitState: Equatable {
    case unknown, requesting, authorized, denied, unavailable

    var label: String {
        switch self {
        case .unknown:     return "Not connected"
        case .requesting:  return "Connecting…"
        case .authorized:  return "Apple Health live"
        case .denied:      return "Skipped"
        case .unavailable: return "Unavailable"
        }
    }

    var isLive: Bool { self == .authorized }
}

enum AriaInterviewStep: Int, CaseIterable, Hashable {
    case intro = 0
    case name
    case health
    case details
    case goals
    case experience
    case workouts
    case sleep
    case freeTime // now covers interests + training theme + life context in one ask
    case coaching
    case conditions // now optional at the very end, before ready
    case ready
    // Legacy steps kept for migration but no longer in flow
    case trainingTheme
    case lifeContext

    var progressLabel: String {
        switch self {
        case .intro:          return "Hello"
        case .name:           return "Name"
        case .health:         return "Apple Health"
        case .details:        return "Your details"
        case .goals:          return "Goals"
        case .experience:     return "Level"
        case .workouts:       return "Training"
        case .sleep:          return "Sleep"
        case .freeTime:       return "Lifestyle"
        case .trainingTheme:  return "Style"
        case .lifeContext:    return "Context"
        case .conditions:     return "Boundaries"
        case .coaching:       return "Voice"
        case .ready:          return "Ready"
        }
    }

    var graph: OnboardingGraph.Step {
        switch self {
        case .intro: return .intro
        case .name: return .name
        case .health: return .health
        case .details: return .details
        case .goals: return .goals
        case .experience: return .experience
        case .workouts: return .workouts
        case .sleep: return .sleep
        case .freeTime: return .freeTime
        case .coaching: return .coaching
        case .conditions: return .conditions
        case .ready: return .ready
        case .trainingTheme: return .trainingTheme
        case .lifeContext: return .lifeContext
        }
    }

    init(_ graph: OnboardingGraph.Step) {
        switch graph {
        case .intro: self = .intro
        case .name: self = .name
        case .health: self = .health
        case .details: self = .details
        case .goals: self = .goals
        case .experience: self = .experience
        case .workouts: self = .workouts
        case .sleep: self = .sleep
        case .freeTime: self = .freeTime
        case .coaching: self = .coaching
        case .conditions: self = .conditions
        case .ready: self = .ready
        case .trainingTheme: self = .trainingTheme
        case .lifeContext: self = .lifeContext
        }
    }
}

/// Which body-detail fields arrived from Apple Health so the UI can label them.
enum OnboardingHealthSourcedField: String, Hashable {
    case birthday, sex, height, weight
}

enum AriaOnboardingRole: Equatable {
    case aria, user, system
}

struct AriaOnboardingMessage: Identifiable, Equatable {
    let id: String
    let role: AriaOnboardingRole
    let text: String

    init(role: AriaOnboardingRole, text: String) {
        self.id = UUID().uuidString
        self.role = role
        self.text = text
    }
}

enum SleepRhythmBand: String, CaseIterable, Identifiable {
    case earlyBird, average, nightOwl, irregular
    var id: String { rawValue }
    var label: String {
        switch self {
        case .earlyBird: return "Early bird"
        case .average:   return "Average schedule"
        case .nightOwl:  return "Night owl"
        case .irregular: return "Irregular"
        }
    }
    var detail: String {
        switch self {
        case .earlyBird: return "In bed early · up with the morning"
        case .average:   return "Roughly 10–11pm · 6–7am"
        case .nightOwl:  return "Late nights · later mornings"
        case .irregular: return "Shift work or no fixed pattern"
        }
    }
    var tag: String { "sleep:\(rawValue)" }
}

enum LifestyleInterest: String, CaseIterable, Identifiable {
    case outdoors, gaming, reading, social, creative, family, deskWork, travel, music, cooking
    var id: String { rawValue }
    var label: String {
        switch self {
        case .outdoors:  return "Outdoors"
        case .gaming:    return "Gaming"
        case .reading:   return "Reading"
        case .social:    return "Social time"
        case .creative:  return "Creative work"
        case .family:    return "Family"
        case .deskWork:  return "Desk / deep work"
        case .travel:    return "Travel"
        case .music:     return "Music"
        case .cooking:   return "Cooking"
        }
    }
    var tag: String { "interest:\(rawValue)" }
}

enum LifeContextOption: String, CaseIterable, Identifiable {
    case single, partnered, familyHome, roommates, preferNot
    var id: String { rawValue }
    var label: String {
        switch self {
        case .single:      return "On my own"
        case .partnered:   return "Partnered"
        case .familyHome:  return "Family at home"
        case .roommates:   return "Roommates"
        case .preferNot:   return "Prefer not to say"
        }
    }
    var tag: String? {
        self == .preferNot ? nil : "life:\(rawValue)"
    }
}

enum ReportedCondition: String, CaseIterable, Identifiable {
    case adhd, epilepsy, anxietyDepression, injuryRehab, chronicIllness, mobility, sensory, other, none, preferNot
    var id: String { rawValue }
    var label: String {
        switch self {
        case .adhd:              return "ADHD"
        case .epilepsy:          return "Epilepsy"
        case .anxietyDepression: return "Anxiety / depression"
        case .injuryRehab:       return "Injury / rehab"
        case .chronicIllness:    return "Chronic illness"
        case .mobility:          return "Mobility"
        case .sensory:           return "Sensory"
        case .other:             return "Other"
        case .none:              return "None"
        case .preferNot:         return "Prefer not to say"
        }
    }
    /// True conditions that activate guidance-only coaching.
    var isConstraint: Bool {
        switch self {
        case .none, .preferNot: return false
        default: return true
        }
    }
    var tag: String? {
        isConstraint ? "condition:\(rawValue)" : nil
    }
}

extension OnboardingProfile {
    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedLastName: String { lastName.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// What ARIA says out loud — preferred first name only.
    var firstName: String {
        trimmedName.split(separator: " ").first.map(String.init) ?? trimmedName
    }
    /// Profile display name: preferred + optional last.
    var profileDisplayName: String {
        [trimmedName, trimmedLastName].filter { !$0.isEmpty }.joined(separator: " ")
    }
    var isPreferredNameValid: Bool {
        let n = trimmedName
        return (2...32).contains(n.count)
    }
    var ageYears: Int {
        guard let birthday else { return 0 }
        return Calendar.current.dateComponents([.year], from: birthday, to: Date()).year ?? 0
    }
    var hasBirthday: Bool { birthday != nil }
    var hasConfirmedDetails: Bool {
        hasBirthday && ageYears >= 13 && biologicalSex != nil
    }
    var detailsSummaryLine: String {
        var parts: [String] = []
        if !trimmedName.isEmpty { parts.append(firstName) }
        if hasBirthday { parts.append("\(ageYears)") }
        if let sex = biologicalSex { parts.append(sex.label) }
        if let h = heightCm { parts.append(OnboardingBodyUnits.heightLabel(cm: h, metric: usesMetricUnits)) }
        if let w = weightKg { parts.append(OnboardingBodyUnits.weightLabel(kg: w, metric: usesMetricUnits)) }
        return parts.joined(separator: " · ")
    }
}

enum OnboardingBodyUnits {
    static let lbsPerKg = 2.20462
    static let cmPerInch = 2.54

    static func centimeters(feet: Int, inches: Int) -> Double {
        Double(max(0, feet) * 12 + max(0, inches)) * cmPerInch
    }

    static func feetAndInches(cm: Double) -> (feet: Int, inches: Int) {
        let total = (cm / cmPerInch).rounded()
        var feet = Int(total) / 12
        var inches = Int(total) % 12
        if inches == 12 { feet += 1; inches = 0 }
        return (feet, inches)
    }

    static func pounds(kg: Double) -> Double { kg * lbsPerKg }
    static func kilograms(lbs: Double) -> Double { lbs / lbsPerKg }

    static func heightLabel(cm: Double, metric: Bool) -> String {
        if metric { return "\(Int(cm.rounded())) cm" }
        let pair = feetAndInches(cm: cm)
        return "\(pair.feet)′\(pair.inches)″"
    }

    static func weightLabel(kg: Double, metric: Bool) -> String {
        if metric { return String(format: "%.1f kg", kg) }
        return "\(Int(pounds(kg: kg).rounded())) lb"
    }
}
