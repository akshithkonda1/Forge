import Foundation
import Combine
import HealthKit
import ActivityKit
import ForgeCore

/// Persists cycle logs, syncs HealthKit menstrual signals, exposes engine snapshot.
/// Also holds **people you support** (partner, daughter, family) — never written
/// to the user's HealthKit. Incoming CloudKit shares bind to these rows by
/// owner id, not by “whatever is first.”
@MainActor
final class MenstrualHealthStore: ObservableObject {
    static let shared = MenstrualHealthStore()

    @Published var settings: MenstrualTrackingSettings
    @Published var logs: [CycleDayLog]
    @Published var snapshot: MenstrualCycleSnapshot

    /// Every person this user supports. First-class — partner and daughter
    /// are separate rows, not a costume on one slot.
    @Published var supportedPeople: [SupportedPerson]
    @Published var selectedPersonId: String?
    @Published var personSnapshots: [String: MenstrualCycleSnapshot]
    @Published var personBriefs: [String: PartnerSupportBrief]

    /// Selected person, mirrored so existing UI and ARIA call sites keep working.
    @Published private(set) var partnerSettings: PartnerCycleSettings
    @Published private(set) var partnerLogs: [CycleDayLog]
    @Published private(set) var partnerSnapshot: MenstrualCycleSnapshot
    @Published private(set) var partnerSupportBrief: PartnerSupportBrief?

    @Published var lastSyncAt: Date?
    @Published var isSyncing = false
    @Published var accuracyReport: CycleAccuracyReport = .empty
    @Published var predictionFeedback: [CyclePredictionFeedback] = []
    /// Frozen forecasts scored on actual starts (honest MAE).
    @Published var forecastArchive: [CycleForecastRecord] = []
    @Published var lastEvaluation: CycleDataEvaluation = .empty
    @Published var lastAriaBrief: CycleAriaAnalyst.Brief?
    @Published var lastTeachingMessage: String?
    /// Last live next-period median we advertised (cache; archive is source of truth).
    @Published var lastAdvertisedNextPeriodMedian: String?
    /// Short toast after model auto-corrects (cleared by UI).
    @Published var lastModelUpdateMessage: String?
    /// Period-end feedback history + continuously learned coaching preferences.
    @Published var periodEndFeedbacks: [PeriodEndFeedback] = []
    @Published var coachingPreferences: PeriodCoachingPreferences = .neutral
    /// Pending episode metadata after logPeriodEnd — UI presents feedback sheet.
    @Published var pendingPeriodEndEpisode: PeriodEpisode?
    /// True when the user's biological sex makes the cycle surface relevant, so the UI
    /// can open straight to it. Set during onboarding.
    @Published private(set) var cycleSurfaceRelevant = false

    /// ~24 months of daily logs.
    static let maxRetainedLogs = 800

    // MARK: - Persistence surface
    //
    // Everything from here to `persistCoachingPrefs` is internal rather than
    // private, and that is a language constraint rather than a preference:
    // `private` in Swift means "this file", and the store's behaviour no longer
    // lives in one file. Swift has no access level between `private` and
    // module-wide, so splitting a class across files necessarily widens whatever
    // its parts share. Nothing outside this store should call any of it.
    let defaults = UserDefaults.standard
    let settingsKey = "forge.menstrual.settings.v1"
    let logsKey = "forge.menstrual.logs.v1"
    let partnerSettingsKey = "forge.menstrual.partner.settings.v1"
    let partnerLogsKey = "forge.menstrual.partner.logs.v1"
    let peopleKey = "forge.menstrual.people.v2"
    let selectedPersonKey = "forge.menstrual.selectedPerson.v2"
    let feedbackKey = "forge.menstrual.prediction.feedback.v1"
    let forecastKey = "forge.menstrual.forecast.archive.v1"
    let advertisedKey = "forge.menstrual.advertised.next.v1"
    let quietSyncKey = "forge.menstrual.quiet.sync.at"
    let periodEndFeedbackKey = "forge.menstrual.period.end.feedback.v1"
    let coachingPrefsKey = "forge.menstrual.coaching.prefs.v1"
    let cycleRelevantKey = "forge.menstrual.surface.relevant.v1"
    /// Stops a wipe from being immediately overwritten by the tester seed.
    let testReadySeededKey = "forge.menstrual.testReady.seeded.v1"

    private init() {
        if let data = defaults.data(forKey: settingsKey),
           let s = try? JSONDecoder().decode(MenstrualTrackingSettings.self, from: data) {
            settings = s
        } else {
            settings = .default
        }
        if let data = defaults.data(forKey: logsKey),
           let l = try? JSONDecoder().decode([CycleDayLog].self, from: data) {
            logs = l
        } else {
            logs = []
        }
        let migrated = Self.loadPeople(
            defaults: defaults,
            peopleKey: peopleKey,
            selectedPersonKey: selectedPersonKey,
            partnerSettingsKey: partnerSettingsKey,
            partnerLogsKey: partnerLogsKey
        )
        supportedPeople = migrated.people
        selectedPersonId = migrated.selectedId
        partnerSettings = migrated.people.first(where: { $0.id == migrated.selectedId })?.settings
            ?? migrated.people.first?.settings
            ?? .default
        partnerLogs = migrated.people.first(where: { $0.id == migrated.selectedId })?.logs
            ?? migrated.people.first?.logs
            ?? []
        personSnapshots = [:]
        personBriefs = [:]
        if let data = defaults.data(forKey: feedbackKey),
           let f = try? JSONDecoder().decode([CyclePredictionFeedback].self, from: data) {
            predictionFeedback = f
        }
        if let data = defaults.data(forKey: forecastKey),
           let f = try? JSONDecoder().decode([CycleForecastRecord].self, from: data) {
            forecastArchive = f
        }
        if let data = defaults.data(forKey: periodEndFeedbackKey),
           let f = try? JSONDecoder().decode([PeriodEndFeedback].self, from: data) {
            periodEndFeedbacks = f
        }
        if let data = defaults.data(forKey: coachingPrefsKey),
           let p = try? JSONDecoder().decode(PeriodCoachingPreferences.self, from: data) {
            coachingPreferences = p
        }
        lastAdvertisedNextPeriodMedian = defaults.string(forKey: advertisedKey)
        cycleSurfaceRelevant = defaults.bool(forKey: cycleRelevantKey)
        snapshot = .empty
        partnerSnapshot = .empty
        partnerSupportBrief = nil
        recompute()
        recomputePartner()
    }

    // MARK: Settings

    func persistSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: settingsKey)
        }
    }

    func persistLogs() {
        if let data = try? JSONEncoder().encode(logs) {
            defaults.set(data, forKey: logsKey)
        }
    }

    func persistPeople() {
        if let data = try? JSONEncoder().encode(supportedPeople) {
            defaults.set(data, forKey: peopleKey)
        }
        persistSelectedPerson()
        // v1 projection of the selected person so a rollback still has one slot.
        let projection = selectedPerson
        if let data = try? JSONEncoder().encode(projection?.settings ?? PartnerCycleSettings.default) {
            defaults.set(data, forKey: partnerSettingsKey)
        }
        if let data = try? JSONEncoder().encode(projection?.logs ?? []) {
            defaults.set(data, forKey: partnerLogsKey)
        }
    }

    func persistSelectedPerson() {
        if let selectedPersonId {
            defaults.set(selectedPersonId, forKey: selectedPersonKey)
        } else {
            defaults.removeObject(forKey: selectedPersonKey)
        }
    }

    func syncSelectedProjection() {
        if let person = selectedPerson {
            partnerSettings = person.settings
            partnerLogs = person.logs
            partnerSnapshot = personSnapshots[person.id] ?? .empty
            partnerSupportBrief = personBriefs[person.id]
        } else {
            partnerSettings = .default
            partnerLogs = []
            partnerSnapshot = .empty
            partnerSupportBrief = nil
        }
    }

    static func loadPeople(
        defaults: UserDefaults,
        peopleKey: String,
        selectedPersonKey: String,
        partnerSettingsKey: String,
        partnerLogsKey: String
    ) -> (people: [SupportedPerson], selectedId: String?) {
        if let data = defaults.data(forKey: peopleKey),
           let decoded = try? JSONDecoder().decode([SupportedPerson].self, from: data),
           !decoded.isEmpty {
            let selected = defaults.string(forKey: selectedPersonKey)
            let valid = selected.flatMap { id in decoded.contains(where: { $0.id == id }) ? id : nil }
            return (decoded, valid ?? decoded[0].id)
        }

        var v1Settings = PartnerCycleSettings.default
        var v1Logs: [CycleDayLog] = []
        if let data = defaults.data(forKey: partnerSettingsKey),
           let s = try? JSONDecoder().decode(PartnerCycleSettings.self, from: data) {
            v1Settings = s
        }
        if let data = defaults.data(forKey: partnerLogsKey),
           let l = try? JSONDecoder().decode([CycleDayLog].self, from: data) {
            v1Logs = l
        }
        let hasLegacy = v1Settings.enabled
            || v1Settings.consentAcknowledged
            || !v1Settings.partnerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !v1Logs.isEmpty
            || v1Settings.relationshipLabel != "partner"
        guard hasLegacy else { return ([], nil) }
        let person = SupportedPerson.make(settings: v1Settings, logs: v1Logs)
        if let data = try? JSONEncoder().encode([person]) {
            defaults.set(data, forKey: peopleKey)
            defaults.set(person.id, forKey: selectedPersonKey)
        }
        return ([person], person.id)
    }

    func persistFeedback() {
        if let data = try? JSONEncoder().encode(predictionFeedback) {
            defaults.set(data, forKey: feedbackKey)
        }
    }

    func persistForecasts() {
        if let data = try? JSONEncoder().encode(forecastArchive) {
            defaults.set(data, forKey: forecastKey)
        }
    }

    func persistPeriodEndFeedback() {
        if let data = try? JSONEncoder().encode(periodEndFeedbacks) {
            defaults.set(data, forKey: periodEndFeedbackKey)
        }
    }

    func persistCoachingPrefs() {
        if let data = try? JSONEncoder().encode(coachingPreferences) {
            defaults.set(data, forKey: coachingPrefsKey)
        }
    }

}

// MARK: - HealthKit DTO

struct MenstrualHealthKitBundle {
    var flowSamples: [(date: Date, flow: MenstrualFlowLevel)]
    var bbtSamples: [(date: Date, celsius: Double)]
    var ovulationTests: [(date: Date, result: OvulationTestResult)]
    var mucusSamples: [(date: Date, quality: CervicalMucusQuality)]
}
