import Foundation
import ForgeCore

/// Live cycle state sealed in Cycle Vault. One box, not a pile of plists.
struct CycleVaultLiveState: Codable, Equatable {
    var settings: MenstrualTrackingSettings
    var logs: [CycleDayLog]
    var people: [SupportedPerson]
    var selectedPersonId: String?
    var predictionFeedback: [CyclePredictionFeedback]
    var forecastArchive: [CycleForecastRecord]
    var periodEndFeedbacks: [PeriodEndFeedback]
    var coachingPreferences: PeriodCoachingPreferences
    var lastAdvertisedNextPeriodMedian: String?
}

enum CycleMonthlyDigestFactory {

    static func make(
        monthKey: String,
        logs: [CycleDayLog],
        snapshot: MenstrualCycleSnapshot,
        settings: MenstrualTrackingSettings
    ) -> CycleMonthlyDigest {
        let inMonth = logs.filter { $0.dayKey.hasPrefix(monthKey) }
        let bleedingDays = inMonth.filter { $0.flow.isBleeding }.count
        let episodes = MenstrualCycleEngine.buildPeriodEpisodes(from: logs)
        let starts = episodes.filter { $0.startDayKey.hasPrefix(monthKey) }.count
        let lengths = interStartLengths(episodes)
        let periodLengths = episodes.map(\.dayCount)
        let pains = inMonth.compactMap(\.painScale)
        var symptoms: [String: Int] = [:]
        for log in inMonth {
            for s in log.symptoms {
                symptoms[s.label, default: 0] += 1
            }
        }
        return CycleMonthlyDigest(
            monthKey: monthKey,
            daysLogged: inMonth.count,
            bleedingDays: bleedingDays,
            cycleStarts: starts,
            medianCycleDays: lengths.isEmpty ? snapshot.cycleLengthMedian : median(lengths.map(Double.init)),
            medianPeriodDays: periodLengths.isEmpty ? snapshot.periodLengthMedian : median(periodLengths.map(Double.init)),
            cycleLengthMin: lengths.min(),
            cycleLengthMax: lengths.max(),
            averagePain: pains.isEmpty ? nil : Double(pains.reduce(0, +)) / Double(pains.count),
            painDays: pains.count,
            symptomCounts: symptoms,
            predictionMAE: snapshot.accuracyMAE,
            predictionSamples: snapshot.accuracySampleCount,
            highAccuracyMode: settings.highAccuracyMode,
            lifestyleGoal: settings.lifestyleGoal == .none ? nil : settings.lifestyleGoal.rawValue
        )
    }

    private static func interStartLengths(_ episodes: [PeriodEpisode]) -> [Int] {
        guard episodes.count >= 2 else { return [] }
        var out: [Int] = []
        for i in 1..<episodes.count {
            if let days = CycleDayKey.daysBetween(episodes[i - 1].startDayKey, episodes[i].startDayKey),
               days >= 14, days <= 90 {
                out.append(days)
            }
        }
        return out
    }

    private static func median(_ values: [Double]) -> Double {
        let s = values.sorted()
        guard !s.isEmpty else { return 0 }
        let m = s.count / 2
        if s.count % 2 == 0 { return (s[m - 1] + s[m]) / 2 }
        return s[m]
    }
}
