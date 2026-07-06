import SwiftUI

// MARK: - Sleep models (platform-free, fully testable)
//
// `SleepNight` replaces the HealthKit-coupled aggregate summary: it is
// built purely from stage segments, so aggregation and night-grouping
// logic can be unit tested without HealthKit, and the watch timeline
// visual renders straight from `segments`.

public enum SleepStage: String, Codable, CaseIterable, Sendable {
    case deep
    case rem
    case core
    case awake

    public var displayName: String {
        switch self {
        case .deep:  return "Deep"
        case .rem:   return "REM"
        case .core:  return "Core"
        case .awake: return "Awake"
        }
    }

    /// Calm palette: sleep depth in blues/violets, wake in soft amber.
    public var color: Color {
        switch self {
        case .deep:  return ForgePalette.indigo
        case .rem:   return ForgePalette.violet
        case .core:  return ForgePalette.steel
        case .awake: return ForgePalette.amber
        }
    }
}

public struct SleepStageSegment: Codable, Sendable, Equatable {
    public var start: Date
    public var end: Date
    public var stage: SleepStage

    public init(start: Date, end: Date, stage: SleepStage) {
        self.start = start
        self.end = end
        self.stage = stage
    }

    public var minutes: Double {
        max(0, end.timeIntervalSince(start) / 60)
    }
}

public struct SleepNight: Codable, Sendable, Equatable {
    public var segments: [SleepStageSegment]
    public var totalMinutes: Double
    public var deepMinutes: Double
    public var remMinutes: Double
    public var coreMinutes: Double
    public var awakeMinutes: Double
    public var start: Date?
    public var end: Date?

    /// Aggregates are derived from segments — one source of truth.
    /// Awake time does not count toward `totalMinutes` (asleep time).
    public init(segments: [SleepStageSegment]) {
        let sorted = segments.sorted { $0.start < $1.start }
        self.segments = sorted
        var deep = 0.0, rem = 0.0, core = 0.0, awake = 0.0
        for segment in sorted {
            switch segment.stage {
            case .deep:  deep += segment.minutes
            case .rem:   rem += segment.minutes
            case .core:  core += segment.minutes
            case .awake: awake += segment.minutes
            }
        }
        deepMinutes = deep
        remMinutes = rem
        coreMinutes = core
        awakeMinutes = awake
        totalMinutes = deep + rem + core
        start = sorted.first?.start
        end = sorted.last?.end
    }

    public var durationLabel: String {
        "\(Int(totalMinutes) / 60)h \(Int(totalMinutes) % 60)m"
    }

    /// Groups a flat, multi-day list of segments into nights. A segment
    /// belongs to the "night of" the day containing its start shifted
    /// back 12 hours — so 23:40 and 02:10 land in the same night.
    public static func groupIntoNights(
        segments: [SleepStageSegment],
        calendar: Calendar = .current
    ) -> [SleepNight] {
        var buckets: [Date: [SleepStageSegment]] = [:]
        for segment in segments {
            let shifted = segment.start.addingTimeInterval(-12 * 3600)
            let key = calendar.startOfDay(for: shifted)
            buckets[key, default: []].append(segment)
        }
        return buckets.keys.sorted().map { SleepNight(segments: buckets[$0] ?? []) }
    }
}

// MARK: - Sleep factors (one-tap chips)
//
// Zero-judgment logging of things that shaped the night. Each factor
// carries the note ARIA uses to contextualize — observational, never
// scolding.

public enum SleepFactor: String, Codable, CaseIterable, Identifiable, Sendable {
    case lateCaffeine
    case stress
    case lateWorkout
    case screens
    case alcohol

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .lateCaffeine: return "Late caffeine"
        case .stress:       return "Stressful day"
        case .lateWorkout:  return "Late workout"
        case .screens:      return "Screens late"
        case .alcohol:      return "Alcohol"
        }
    }

    public var symbolName: String {
        switch self {
        case .lateCaffeine: return "cup.and.saucer.fill"
        case .stress:       return "brain.head.profile"
        case .lateWorkout:  return "dumbbell.fill"
        case .screens:      return "iphone"
        case .alcohol:      return "wineglass"
        }
    }

    public var ariaNote: String {
        switch self {
        case .lateCaffeine: return "Caffeine after mid-afternoon tends to trim deep sleep — useful to know, not a verdict."
        case .stress:       return "A loaded day often shows up as lighter sleep. Naming it already helps."
        case .lateWorkout:  return "Late training runs the engine warm at lights-out. Worth pairing with a longer wind-down."
        case .screens:      return "Late screens push the body clock a little later. Small shifts add up."
        case .alcohol:      return "Alcohol usually costs some REM later in the night. Good context for today's energy."
        }
    }
}
