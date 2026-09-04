import Foundation
import SwiftUI

/// Overall feel of this period — noninvasive, personalization only.
enum PeriodSeverity: String, Codable, CaseIterable, Identifiable {
    case mild, moderate, severe
    var id: String { rawValue }

    var label: String {
        switch self {
        case .mild: return "Mild"
        case .moderate: return "Moderate"
        case .severe: return "Hard"
        }
    }

    var icon: String {
        switch self {
        case .mild: return "leaf.fill"
        case .moderate: return "drop.fill"
        case .severe: return "bolt.heart.fill"
        }
    }
}

enum PeriodEnergyLevel: String, Codable, CaseIterable, Identifiable {
    case low, okay, high
    var id: String { rawValue }

    var label: String {
        switch self {
        case .low: return "Low energy"
        case .okay: return "Okay"
        case .high: return "Still solid"
        }
    }
}

/// Length relative to what feels normal for this person (not a medical measure).
enum PeriodLengthFeel: String, Codable, CaseIterable, Identifiable {
    case shorter, typical, longer
    var id: String { rawValue }

    var label: String {
        switch self {
        case .shorter: return "Shorter"
        case .typical: return "Typical"
        case .longer: return "Longer"
        }
    }
}

/// Overall flow heaviness feel for the episode.
enum PeriodFlowFeel: String, Codable, CaseIterable, Identifiable {
    case lighter, typical, heavier
    var id: String { rawValue }

    var label: String {
        switch self {
        case .lighter: return "Lighter"
        case .typical: return "Typical"
        case .heavier: return "Heavier"
        }
    }
}

enum PeriodSleepQuality: String, Codable, CaseIterable, Identifiable {
    case poor, okay, good
    var id: String { rawValue }

    var label: String {
        switch self {
        case .poor: return "Rough sleep"
        case .okay: return "Okay"
        case .good: return "Slept well"
        }
    }

    var icon: String {
        switch self {
        case .poor: return "moon.zzz"
        case .okay: return "moon"
        case .good: return "moon.stars.fill"
        }
    }
}

enum PeriodMoodOverall: String, Codable, CaseIterable, Identifiable {
    case rough, mixed, steady
    var id: String { rawValue }

    var label: String {
        switch self {
        case .rough: return "Rough"
        case .mixed: return "Mixed"
        case .steady: return "Steady"
        }
    }

    var icon: String {
        switch self {
        case .rough: return "cloud.rain.fill"
        case .mixed: return "cloud.sun.fill"
        case .steady: return "sun.max.fill"
        }
    }
}

/// How much the period disrupted training / work / daily life.
enum PeriodLifeImpact: String, Codable, CaseIterable, Identifiable {
    case low, medium, high
    var id: String { rawValue }

    var label: String {
        switch self {
        case .low: return "Barely"
        case .medium: return "Some"
        case .high: return "Limited me"
        }
    }
}

/// Self-reported stress during this cycle — lifestyle context only.
enum PeriodStressLevel: String, Codable, CaseIterable, Identifiable {
    case low, medium, high
    var id: String { rawValue }

    var label: String {
        switch self {
        case .low: return "Low stress"
        case .medium: return "Medium"
        case .high: return "High stress"
        }
    }
}

enum CoachingHelpfulness: String, Codable, CaseIterable, Identifiable {
    case notHelpful, somewhat, very
    var id: String { rawValue }

    var label: String {
        switch self {
        case .notHelpful: return "Not helpful"
        case .somewhat: return "Somewhat"
        case .very: return "Very helpful"
        }
    }

    var score: Double {
        switch self {
        case .notHelpful: return 0
        case .somewhat: return 0.5
        case .very: return 1
        }
    }
}

enum PeriodCoachingTopic: String, Codable, CaseIterable, Identifiable {
    case rest, lighterTraining, heat, hydration, sleep, nutrition, empathy, mobility
    var id: String { rawValue }

    var label: String {
        switch self {
        case .rest: return "Rest / recovery"
        case .lighterTraining: return "Lighter training"
        case .heat: return "Heat / comfort"
        case .hydration: return "Hydration"
        case .sleep: return "Sleep"
        case .nutrition: return "Food / iron / mag"
        case .empathy: return "Softer tone"
        case .mobility: return "Mobility / yoga"
        }
    }

    var icon: String {
        switch self {
        case .rest: return "bed.double.fill"
        case .lighterTraining: return "figure.walk"
        case .heat: return "thermometer.sun.fill"
        case .hydration: return "drop.fill"
        case .sleep: return "moon.zzz.fill"
        case .nutrition: return "fork.knife"
        case .empathy: return "heart.fill"
        case .mobility: return "figure.flexibility"
        }
    }
}

/// Captured when the user marks period finished — on-device coaching personalization only.
struct PeriodEndFeedback: Codable, Equatable, Identifiable {
    var id: String { startDayKey + "|" + endDayKey }
    var startDayKey: String
    var endDayKey: String
    var dayCount: Int
    /// How was your period overall?
    var severity: PeriodSeverity
    /// 0–10 peak pain this episode.
    var peakPain: Int
    var energy: PeriodEnergyLevel
    /// Optional lifestyle context (all skippable / default-safe).
    var lengthFeel: PeriodLengthFeel?
    var flowFeel: PeriodFlowFeel?
    var sleepQuality: PeriodSleepQuality?
    var moodOverall: PeriodMoodOverall?
    var lifeImpact: PeriodLifeImpact?
    var stressLevel: PeriodStressLevel?
    var coachingHelpfulness: CoachingHelpfulness
    var whatHelped: [PeriodCoachingTopic]
    var whatDidntHelp: [PeriodCoachingTopic]
    var wantMore: [PeriodCoachingTopic]
    var wantLess: [PeriodCoachingTopic]
    var notes: String?
    var recordedAt: Date

    enum CodingKeys: String, CodingKey {
        case startDayKey, endDayKey, dayCount, severity, peakPain, energy
        case lengthFeel, flowFeel, sleepQuality, moodOverall, lifeImpact, stressLevel
        case coachingHelpfulness, whatHelped, whatDidntHelp, wantMore, wantLess, notes, recordedAt
    }

    init(
        startDayKey: String,
        endDayKey: String,
        dayCount: Int,
        severity: PeriodSeverity,
        peakPain: Int,
        energy: PeriodEnergyLevel,
        lengthFeel: PeriodLengthFeel? = nil,
        flowFeel: PeriodFlowFeel? = nil,
        sleepQuality: PeriodSleepQuality? = nil,
        moodOverall: PeriodMoodOverall? = nil,
        lifeImpact: PeriodLifeImpact? = nil,
        stressLevel: PeriodStressLevel? = nil,
        coachingHelpfulness: CoachingHelpfulness,
        whatHelped: [PeriodCoachingTopic],
        whatDidntHelp: [PeriodCoachingTopic],
        wantMore: [PeriodCoachingTopic],
        wantLess: [PeriodCoachingTopic],
        notes: String?,
        recordedAt: Date
    ) {
        self.startDayKey = startDayKey
        self.endDayKey = endDayKey
        self.dayCount = dayCount
        self.severity = severity
        self.peakPain = peakPain
        self.energy = energy
        self.lengthFeel = lengthFeel
        self.flowFeel = flowFeel
        self.sleepQuality = sleepQuality
        self.moodOverall = moodOverall
        self.lifeImpact = lifeImpact
        self.stressLevel = stressLevel
        self.coachingHelpfulness = coachingHelpfulness
        self.whatHelped = whatHelped
        self.whatDidntHelp = whatDidntHelp
        self.wantMore = wantMore
        self.wantLess = wantLess
        self.notes = notes
        self.recordedAt = recordedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startDayKey = try c.decode(String.self, forKey: .startDayKey)
        endDayKey = try c.decode(String.self, forKey: .endDayKey)
        dayCount = try c.decode(Int.self, forKey: .dayCount)
        severity = try c.decode(PeriodSeverity.self, forKey: .severity)
        peakPain = try c.decode(Int.self, forKey: .peakPain)
        energy = try c.decode(PeriodEnergyLevel.self, forKey: .energy)
        lengthFeel = try c.decodeIfPresent(PeriodLengthFeel.self, forKey: .lengthFeel)
        flowFeel = try c.decodeIfPresent(PeriodFlowFeel.self, forKey: .flowFeel)
        sleepQuality = try c.decodeIfPresent(PeriodSleepQuality.self, forKey: .sleepQuality)
        moodOverall = try c.decodeIfPresent(PeriodMoodOverall.self, forKey: .moodOverall)
        lifeImpact = try c.decodeIfPresent(PeriodLifeImpact.self, forKey: .lifeImpact)
        stressLevel = try c.decodeIfPresent(PeriodStressLevel.self, forKey: .stressLevel)
        coachingHelpfulness = try c.decode(CoachingHelpfulness.self, forKey: .coachingHelpfulness)
        whatHelped = try c.decodeIfPresent([PeriodCoachingTopic].self, forKey: .whatHelped) ?? []
        whatDidntHelp = try c.decodeIfPresent([PeriodCoachingTopic].self, forKey: .whatDidntHelp) ?? []
        wantMore = try c.decodeIfPresent([PeriodCoachingTopic].self, forKey: .wantMore) ?? []
        wantLess = try c.decodeIfPresent([PeriodCoachingTopic].self, forKey: .wantLess) ?? []
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        recordedAt = try c.decodeIfPresent(Date.self, forKey: .recordedAt) ?? Date()
    }
}
