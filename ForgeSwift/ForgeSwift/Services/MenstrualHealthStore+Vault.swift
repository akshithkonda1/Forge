import Foundation
import ForgeCore

extension MenstrualHealthStore {

    static let vaultUserDefaultsKeys: [String] = [
        "forge.menstrual.settings.v1",
        "forge.menstrual.logs.v1",
        "forge.menstrual.partner.settings.v1",
        "forge.menstrual.partner.logs.v1",
        "forge.menstrual.people.v2",
        "forge.menstrual.selectedPerson.v2",
        "forge.menstrual.prediction.feedback.v1",
        "forge.menstrual.forecast.archive.v1",
        "forge.menstrual.advertised.next.v1",
        "forge.menstrual.period.end.feedback.v1",
        "forge.menstrual.coaching.prefs.v1",
    ]

    static func makeVault() -> CycleVault {
        let tests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let store: SecureStore = tests
            ? InMemorySecureStore()
            : KeychainStore(service: "com.forge.ForgeSwift.cycleVault")
        let root: URL = {
            if tests {
                return FileManager.default.temporaryDirectory
                    .appendingPathComponent("ForgeCycleVault-test-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
            }
            return CycleVault.defaultRoot()
        }()
        return CycleVault(secureStore: store, rootDirectory: root)
    }

    var liveVaultState: CycleVaultLiveState {
        CycleVaultLiveState(
            settings: settings,
            logs: logs,
            people: supportedPeople,
            selectedPersonId: selectedPersonId,
            predictionFeedback: predictionFeedback,
            forecastArchive: forecastArchive,
            periodEndFeedbacks: periodEndFeedbacks,
            coachingPreferences: coachingPreferences,
            lastAdvertisedNextPeriodMedian: lastAdvertisedNextPeriodMedian
        )
    }

    func applyVaultState(_ state: CycleVaultLiveState) {
        settings = state.settings
        logs = state.logs
        supportedPeople = state.people
        selectedPersonId = state.selectedPersonId
        predictionFeedback = state.predictionFeedback
        forecastArchive = state.forecastArchive
        periodEndFeedbacks = state.periodEndFeedbacks
        coachingPreferences = state.coachingPreferences
        lastAdvertisedNextPeriodMedian = state.lastAdvertisedNextPeriodMedian
        syncSelectedProjection()
    }

    func loadFromVaultOrLegacy() {
        if let data = try? cycleVault.readLive(),
           let state = try? JSONDecoder().decode(CycleVaultLiveState.self, from: data) {
            applyVaultState(state)
            clearLegacyUserDefaults()
            return
        }
        loadLegacyUserDefaults()
        persistVault()
    }

    func persistVault() {
        do {
            let data = try JSONEncoder().encode(liveVaultState)
            try cycleVault.writeLive(data)
            let monthKey = CycleVault.monthKey()
            let digest = CycleMonthlyDigestFactory.make(
                monthKey: monthKey,
                logs: logs,
                snapshot: snapshot,
                settings: settings
            )
            try cycleVault.writeMonth(monthKey, plaintext: try JSONEncoder().encode(digest))
            clearLegacyUserDefaults()
            vaultSaveError = nil
        } catch {
            vaultSaveError = error.localizedDescription
            if !cycleVault.hasLiveBox {
                writeLegacyUserDefaults()
            }
        }
    }

    func loadRecentMonthlyDigests() -> [CycleMonthlyDigest] {
        let pairs = (try? cycleVault.readRecentMonths()) ?? []
        return pairs.compactMap { try? JSONDecoder().decode(CycleMonthlyDigest.self, from: $1) }
    }

    func clinicianRhythmReportText() -> String {
        CycleRhythmReport.clinicianText(
            months: loadRecentMonthlyDigests(),
            generatedDayKey: CycleDayKey.key(),
            typicalCycle: snapshot.cycleLengthMedian,
            typicalPeriod: snapshot.periodLengthMedian,
            mae: accuracyReport.maeDays,
            maeSamples: accuracyReport.sampleCount
        )
    }

    func wipeVaultArchives() {
        try? cycleVault.wipe()
        cycleVault = Self.makeVault()
    }

    func clearLegacyUserDefaults() {
        for key in Self.vaultUserDefaultsKeys {
            defaults.removeObject(forKey: key)
        }
    }

    func loadLegacyUserDefaults() {
        if let data = defaults.data(forKey: settingsKey),
           let s = try? JSONDecoder().decode(MenstrualTrackingSettings.self, from: data) {
            settings = s
        }
        if let data = defaults.data(forKey: logsKey),
           let l = try? JSONDecoder().decode([CycleDayLog].self, from: data) {
            logs = l
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
        syncSelectedProjection()
    }

    func writeLegacyUserDefaults() {
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: settingsKey) }
        if let data = try? JSONEncoder().encode(logs) { defaults.set(data, forKey: logsKey) }
        if let data = try? JSONEncoder().encode(supportedPeople) { defaults.set(data, forKey: peopleKey) }
        persistSelectedPerson()
        if let data = try? JSONEncoder().encode(predictionFeedback) { defaults.set(data, forKey: feedbackKey) }
        if let data = try? JSONEncoder().encode(forecastArchive) { defaults.set(data, forKey: forecastKey) }
        if let data = try? JSONEncoder().encode(periodEndFeedbacks) { defaults.set(data, forKey: periodEndFeedbackKey) }
        if let data = try? JSONEncoder().encode(coachingPreferences) { defaults.set(data, forKey: coachingPrefsKey) }
        if let median = lastAdvertisedNextPeriodMedian {
            defaults.set(median, forKey: advertisedKey)
        }
    }
}
