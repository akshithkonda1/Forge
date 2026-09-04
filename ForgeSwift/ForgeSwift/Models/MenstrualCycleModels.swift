import Foundation
import SwiftUI

enum MenstrualFlowLevel: String, Codable, CaseIterable, Identifiable {
    case unspecified, none, spotting, light, medium, heavy
    var id: String { rawValue }

    var label: String {
        switch self {
        case .unspecified: return "Unspecified"
        case .none: return "None"
        case .spotting: return "Spotting"
        case .light: return "Light"
        case .medium: return "Medium"
        case .heavy: return "Heavy"
        }
    }

    var isBleeding: Bool {
        switch self {
        case .spotting, .light, .medium, .heavy: return true
        default: return false
        }
    }

    var sortWeight: Int {
        switch self {
        case .none: return 0
        case .unspecified: return 1
        case .spotting: return 2
        case .light: return 3
        case .medium: return 4
        case .heavy: return 5
        }
    }

    static func fromHealthKitLabel(_ raw: String) -> MenstrualFlowLevel {
        let l = raw.lowercased()
        if l.contains("heavy") { return .heavy }
        if l.contains("medium") { return .medium }
        if l.contains("light") { return .light }
        if l.contains("spot") { return .spotting }
        if l.contains("none") { return .none }
        return .unspecified
    }
}

enum OvulationTestResult: String, Codable, CaseIterable {
    case negative, lhSurge, estrogenSurge, positive, indeterminate, unknown

    var indicatesNearOvulation: Bool {
        self == .lhSurge || self == .positive || self == .estrogenSurge
    }

    var label: String {
        switch self {
        case .negative: return "Negative"
        case .lhSurge: return "LH surge"
        case .estrogenSurge: return "Estrogen surge"
        case .positive: return "Positive"
        case .indeterminate: return "Indeterminate"
        case .unknown: return "Unknown"
        }
    }
}

enum CervicalMucusQuality: String, Codable, CaseIterable {
    case dry, sticky, creamy, watery, eggWhite, unknown

    /// Higher = more fertile-type mucus (Billings / standard FAM).
    var fertilityScore: Int {
        switch self {
        case .eggWhite: return 5
        case .watery: return 4
        case .creamy: return 2
        case .sticky: return 1
        case .dry, .unknown: return 0
        }
    }

    var label: String {
        switch self {
        case .dry: return "Dry"
        case .sticky: return "Sticky"
        case .creamy: return "Creamy"
        case .watery: return "Watery"
        case .eggWhite: return "Egg white"
        case .unknown: return "Unknown"
        }
    }
}

enum CycleSymptom: String, Codable, CaseIterable, Identifiable {
    case cramps, headache, bloating, fatigue, moodLow, moodHigh
    case breastTenderness, backache, acne, cravings, insomnia, nausea
    case energyHigh, libidoHigh, brainFog
    // Extended symptom set
    case hotFlash, nightSweats, anxietyHigh, spotting, libidoLow
    case pelvicPain, constipation, diarrhea, appetiteUp, appetiteDown, vaginalDryness

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cramps: return "Cramps"
        case .headache: return "Headache"
        case .bloating: return "Bloating"
        case .fatigue: return "Fatigue"
        case .moodLow: return "Low mood"
        case .moodHigh: return "High mood"
        case .breastTenderness: return "Breast tenderness"
        case .backache: return "Backache"
        case .acne: return "Acne"
        case .cravings: return "Cravings"
        case .insomnia: return "Insomnia"
        case .nausea: return "Nausea"
        case .energyHigh: return "High energy"
        case .libidoHigh: return "Higher libido"
        case .brainFog: return "Brain fog"
        case .hotFlash: return "Hot flash"
        case .nightSweats: return "Night sweats"
        case .anxietyHigh: return "Anxiety"
        case .spotting: return "Spotting"
        case .libidoLow: return "Lower libido"
        case .pelvicPain: return "Pelvic pain"
        case .constipation: return "Constipation"
        case .diarrhea: return "Diarrhea"
        case .appetiteUp: return "Increased appetite"
        case .appetiteDown: return "Decreased appetite"
        case .vaginalDryness: return "Vaginal dryness"
        }
    }

    var icon: String {
        switch self {
        case .cramps: return "bolt.heart.fill"
        case .headache: return "brain.head.profile"
        case .bloating: return "circle.hexagongrid.fill"
        case .fatigue: return "battery.25"
        case .moodLow: return "cloud.rain.fill"
        case .moodHigh: return "sun.max.fill"
        case .breastTenderness: return "heart.fill"
        case .backache: return "figure.stand"
        case .acne: return "face.dashed"
        case .cravings: return "fork.knife"
        case .insomnia: return "moon.zzz.fill"
        case .nausea: return "cross.case.fill"
        case .energyHigh: return "bolt.fill"
        case .libidoHigh: return "flame.fill"
        case .brainFog: return "aqi.medium"
        case .hotFlash: return "thermometer.sun.fill"
        case .nightSweats: return "thermometer.medium"
        case .anxietyHigh: return "waveform.path.ecg.rectangle"
        case .spotting: return "drop"
        case .libidoLow: return "flame"
        case .pelvicPain: return "bolt.heart"
        case .constipation: return "arrow.down.circle"
        case .diarrhea: return "arrow.up.circle"
        case .appetiteUp: return "plus.circle.fill"
        case .appetiteDown: return "minus.circle.fill"
        case .vaginalDryness: return "humidity"
        }
    }
}

struct CycleDayLog: Identifiable, Codable, Equatable, Hashable {
    var id: String { dayKey }
    /// yyyy-MM-dd in local calendar
    var dayKey: String
    var flow: MenstrualFlowLevel
    var symptoms: [CycleSymptom]
    var bbtCelsius: Double?
    var ovulationTest: OvulationTestResult?
    var mucus: CervicalMucusQuality?
    var notes: String?
    var source: String // "manual" | "healthkit" | "merged"
    var updatedAt: Date
    /// 0–10 pain intensity scale, used for endometriosis / pelvic pain tracking.
    var painScale: Int?

    init(
        dayKey: String,
        flow: MenstrualFlowLevel = .none,
        symptoms: [CycleSymptom] = [],
        bbtCelsius: Double? = nil,
        ovulationTest: OvulationTestResult? = nil,
        mucus: CervicalMucusQuality? = nil,
        notes: String? = nil,
        source: String = "manual",
        updatedAt: Date = Date(),
        painScale: Int? = nil
    ) {
        self.dayKey = dayKey
        self.flow = flow
        self.symptoms = symptoms
        self.bbtCelsius = bbtCelsius
        self.ovulationTest = ovulationTest
        self.mucus = mucus
        self.notes = notes
        self.source = source
        self.updatedAt = updatedAt
        self.painScale = painScale
    }

    enum CodingKeys: String, CodingKey {
        case dayKey, flow, symptoms, bbtCelsius, ovulationTest, mucus, notes, source, updatedAt, painScale
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dayKey = try c.decode(String.self, forKey: .dayKey)
        flow = try c.decodeIfPresent(MenstrualFlowLevel.self, forKey: .flow) ?? .none
        symptoms = try c.decodeIfPresent([CycleSymptom].self, forKey: .symptoms) ?? []
        bbtCelsius = try c.decodeIfPresent(Double.self, forKey: .bbtCelsius)
        ovulationTest = try c.decodeIfPresent(OvulationTestResult.self, forKey: .ovulationTest)
        mucus = try c.decodeIfPresent(CervicalMucusQuality.self, forKey: .mucus)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? "manual"
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        painScale = try c.decodeIfPresent(Int.self, forKey: .painScale)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(dayKey, forKey: .dayKey)
        try c.encode(flow, forKey: .flow)
        try c.encode(symptoms, forKey: .symptoms)
        try c.encodeIfPresent(bbtCelsius, forKey: .bbtCelsius)
        try c.encodeIfPresent(ovulationTest, forKey: .ovulationTest)
        try c.encodeIfPresent(mucus, forKey: .mucus)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encode(source, forKey: .source)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encodeIfPresent(painScale, forKey: .painScale)
    }
}

struct PeriodEpisode: Identifiable, Codable, Equatable {
    var id: String
    var startDayKey: String
    var endDayKey: String
    var peakFlow: MenstrualFlowLevel
    var dayCount: Int
    /// True when the user explicitly tapped "Period finished" for this episode, rather
    /// than the engine inferring the end from where bleeding logs stopped.
    var isConfirmedComplete: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, startDayKey, endDayKey, peakFlow, dayCount, isConfirmedComplete
    }

    init(
        id: String,
        startDayKey: String,
        endDayKey: String,
        peakFlow: MenstrualFlowLevel,
        dayCount: Int,
        isConfirmedComplete: Bool = false
    ) {
        self.id = id
        self.startDayKey = startDayKey
        self.endDayKey = endDayKey
        self.peakFlow = peakFlow
        self.dayCount = dayCount
        self.isConfirmedComplete = isConfirmedComplete
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        startDayKey = try c.decode(String.self, forKey: .startDayKey)
        endDayKey = try c.decode(String.self, forKey: .endDayKey)
        peakFlow = try c.decodeIfPresent(MenstrualFlowLevel.self, forKey: .peakFlow) ?? .medium
        dayCount = try c.decodeIfPresent(Int.self, forKey: .dayCount) ?? 1
        isConfirmedComplete = try c.decodeIfPresent(Bool.self, forKey: .isConfirmedComplete) ?? false
    }
}

enum CycleDayKey {
    /// Day keys are pure `yyyy-MM-dd` calendar labels. They are built from calendar
    /// components rather than a cached `DateFormatter` so a timezone change mid-session
    /// (travel, DST) can never emit a key for the wrong local day.
    static func key(for date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard let y = c.year, let m = c.month, let d = c.day else { return "" }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    /// Local **noon** of the given day. Noon (not midnight) keeps day arithmetic exact
    /// across DST transitions, including zones where 00:00 does not exist on some dates.
    static func date(from key: String) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        var comps = DateComponents()
        comps.year = y
        comps.month = m
        comps.day = d
        comps.hour = 12
        guard let date = Calendar.current.date(from: comps) else { return nil }
        // Reject non-existent dates that the calendar rolled over (e.g. 2026-02-31).
        let round = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard round.year == y, round.month == m, round.day == d else { return nil }
        return date
    }

    /// Midnight of the given day — for anything that needs a day *boundary* rather than
    /// a stable anchor (HealthKit sample windows, calendar comparisons).
    static func startOfDay(from key: String) -> Date? {
        date(from: key).map { Calendar.current.startOfDay(for: $0) }
    }

    static func addDays(_ key: String, _ days: Int) -> String? {
        guard let d = date(from: key),
              let next = Calendar.current.date(byAdding: .day, value: days, to: d) else { return nil }
        return self.key(for: next)
    }

    static func daysBetween(_ a: String, _ b: String) -> Int? {
        guard let da = date(from: a), let db = date(from: b) else { return nil }
        return Calendar.current.dateComponents([.day], from: da, to: db).day
    }

    /// Whole days from today to `key` (negative = in the past).
    static func daysFromToday(to key: String) -> Int? {
        daysBetween(self.key(), key)
    }

    /// Short, locale-aware display form ("Aug 3"). Falls back to the raw key.
    static func shortDisplay(_ key: String) -> String {
        guard let d = date(from: key) else { return key }
        return d.formatted(.dateTime.month(.abbreviated).day())
    }
}

/// Local-only cycle history for testers. Never written to HealthKit or a phone pack.
enum FakeCyclePack {
    static let source = "testReady"
    static let cycleLength = 28
    static let periodLength = 5
    static let cycleCount = 4

    /// Day-in-cycle for today, 10...16, so testers land in a named phase instead of bleeding.
    static func currentDayInCycle(seed: Int) -> Int {
        10 + abs(seed % 7)
    }

    static func shouldSeed(testReady: Bool, trackingEnabled: Bool, logsEmpty: Bool, alreadySeeded: Bool) -> Bool {
        testReady && trackingEnabled && logsEmpty && !alreadySeeded
    }

    static func generate(now: Date = Date(), seed: Int) -> [CycleDayLog] {
        let todayKey = CycleDayKey.key(for: now)
        let dayInCycle = currentDayInCycle(seed: seed)
        guard let lastStart = CycleDayKey.addDays(todayKey, -(dayInCycle - 1)) else { return [] }

        var logs: [CycleDayLog] = []
        for cycleIndex in 0..<cycleCount {
            guard let start = CycleDayKey.addDays(lastStart, -cycleIndex * cycleLength) else { continue }
            for day in 0..<periodLength {
                guard let key = CycleDayKey.addDays(start, day) else { continue }
                if let delta = CycleDayKey.daysBetween(key, todayKey), delta < 0 { continue }
                logs.append(
                    CycleDayLog(
                        dayKey: key,
                        flow: flow(onPeriodDay: day),
                        source: source,
                        updatedAt: CycleDayKey.date(from: key) ?? now
                    )
                )
            }
        }
        return logs.sorted { $0.dayKey < $1.dayKey }
    }

    private static func flow(onPeriodDay day: Int) -> MenstrualFlowLevel {
        switch day {
        case 0: return .medium
        case 1: return .heavy
        case 2: return .medium
        case 3: return .light
        default: return .spotting
        }
    }
}
