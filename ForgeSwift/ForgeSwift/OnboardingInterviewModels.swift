import Foundation
import SwiftUI

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
    case age
    case name
    case health
    case goals
    case biologicalSex
    case experience
    case workouts
    case sleep
    case freeTime
    case trainingTheme
    case lifeContext
    case conditions
    case coaching
    case ready

    var progressLabel: String {
        switch self {
        case .intro:          return "Hello"
        case .age:            return "Safety"
        case .name:           return "Identity"
        case .health:         return "Signals"
        case .goals:          return "Goals"
        case .biologicalSex:  return "Biology"
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
    var ageYears: Int {
        Calendar.current.dateComponents([.year], from: birthday, to: Date()).year ?? 0
    }
    var firstName: String {
        trimmedName.split(separator: " ").first.map(String.init) ?? trimmedName
    }
}
