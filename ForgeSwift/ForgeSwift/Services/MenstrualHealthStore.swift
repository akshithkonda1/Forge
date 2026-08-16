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

    @Published private(set) var settings: MenstrualTrackingSettings
    @Published private(set) var logs: [CycleDayLog]
    @Published private(set) var snapshot: MenstrualCycleSnapshot

    /// Every person this user supports. First-class — partner and daughter
    /// are separate rows, not a costume on one slot.
    @Published private(set) var supportedPeople: [SupportedPerson]
    @Published private(set) var selectedPersonId: String?
    @Published private(set) var personSnapshots: [String: MenstrualCycleSnapshot]
    @Published private(set) var personBriefs: [String: PartnerSupportBrief]

    /// Selected person, mirrored so existing UI and ARIA call sites keep working.
    @Published private(set) var partnerSettings: PartnerCycleSettings
    @Published private(set) var partnerLogs: [CycleDayLog]
    @Published private(set) var partnerSnapshot: MenstrualCycleSnapshot
    @Published private(set) var partnerSupportBrief: PartnerSupportBrief?

    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var isSyncing = false
    @Published private(set) var accuracyReport: CycleAccuracyReport = .empty
    @Published private(set) var predictionFeedback: [CyclePredictionFeedback] = []
    /// Frozen forecasts scored on actual starts (honest MAE).
    @Published private(set) var forecastArchive: [CycleForecastRecord] = []
    @Published private(set) var lastEvaluation: CycleDataEvaluation = .empty
    @Published private(set) var lastAriaBrief: CycleAriaAnalyst.Brief?
    @Published private(set) var lastTeachingMessage: String?
    /// Last live next-period median we advertised (cache; archive is source of truth).
    @Published private(set) var lastAdvertisedNextPeriodMedian: String?
    /// Short toast after model auto-corrects (cleared by UI).
    @Published var lastModelUpdateMessage: String?
    /// Period-end feedback history + continuously learned coaching preferences.
    @Published private(set) var periodEndFeedbacks: [PeriodEndFeedback] = []
    @Published private(set) var coachingPreferences: PeriodCoachingPreferences = .neutral
    /// Pending episode metadata after logPeriodEnd — UI presents feedback sheet.
    @Published var pendingPeriodEndEpisode: PeriodEpisode?
    /// True when the user's biological sex makes the cycle surface relevant, so the UI
    /// can open straight to it. Set during onboarding.
    @Published private(set) var cycleSurfaceRelevant = false

    /// ~24 months of daily logs.
    static let maxRetainedLogs = 800

    private let defaults = UserDefaults.standard
    private let settingsKey = "forge.menstrual.settings.v1"
    private let logsKey = "forge.menstrual.logs.v1"
    private let partnerSettingsKey = "forge.menstrual.partner.settings.v1"
    private let partnerLogsKey = "forge.menstrual.partner.logs.v1"
    private let peopleKey = "forge.menstrual.people.v2"
    private let selectedPersonKey = "forge.menstrual.selectedPerson.v2"
    private let feedbackKey = "forge.menstrual.prediction.feedback.v1"
    private let forecastKey = "forge.menstrual.forecast.archive.v1"
    private let advertisedKey = "forge.menstrual.advertised.next.v1"
    private let quietSyncKey = "forge.menstrual.quiet.sync.at"
    private let periodEndFeedbackKey = "forge.menstrual.period.end.feedback.v1"
    private let coachingPrefsKey = "forge.menstrual.coaching.prefs.v1"
    private let cycleRelevantKey = "forge.menstrual.surface.relevant.v1"

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

    func updateSettings(_ mutate: (inout MenstrualTrackingSettings) -> Void) {
        var s = settings
        mutate(&s)
        settings = s
        persistSettings()
        recompute()
        pushAriaTags()
        Task { await ForgeNotificationScheduler.syncCycleNotifications(settings: settings, snapshot: snapshot) }
    }

    func updateCondition(_ condition: CycleCondition) {
        updateSettings { $0.condition = condition }
    }

    func updatePartnerSettings(_ mutate: (inout PartnerCycleSettings) -> Void) {
        updatePersonSettings(selectedPersonId, mutate)
    }

    /// Mutate one supported person. `nil` id uses (or creates) the selected row.
    func updatePersonSettings(_ personId: String?, _ mutate: (inout PartnerCycleSettings) -> Void) {
        if supportedPeople.isEmpty {
            var s = PartnerCycleSettings.default
            mutate(&s)
            let person = SupportedPerson.make(settings: s)
            supportedPeople = [person]
            selectedPersonId = person.id
        } else {
            let id = personId ?? selectedPersonId ?? supportedPeople[0].id
            guard let idx = supportedPeople.firstIndex(where: { $0.id == id }) else { return }
            mutate(&supportedPeople[idx].settings)
            supportedPeople[idx].updatedAt = Date()
        }
        persistPeople()
        syncSelectedProjection()
        recomputePartner()
        pushAriaTags()
    }

    /// Surfaces the cycle surface for female profiles, but never *behind the user's back*:
    /// tracking only auto-enables once the privacy contract has been acknowledged.
    /// Previously this flipped `enabled` on without `privacyAcknowledged`, which skipped
    /// the consent card entirely and left the acknowledgement flag permanently false.
    func enableForFemaleProfileIfNeeded(gender: Gender) {
        guard gender == .female, !settings.enabled, settings.privacyAcknowledged else { return }
        updateSettings {
            $0.enabled = true
            $0.shareWithAria = true
        }
    }

    /// Auto-enable cycle tracking for female/intersex biological sex captured during onboarding.
    func enableForBiologicalSexIfNeeded(_ sex: BiologicalSex) {
        guard sex.cycleAutoEnabled, !settings.enabled else { return }
        updateSettings {
            $0.enabled = true
            $0.privacyAcknowledged = true
            $0.shareWithAria = true
        }
    }

    /// Surface partner tracking for users who may support a female partner (any gender).
    func enablePartnerTrackingIfAppropriate(gender: Gender) {
        // Soft suggest only — do not auto-enable without consent flag.
        _ = gender
    }

    func updateCycleGoal(_ goal: CycleGoal) {
        updateSettings { $0.cycleGoal = goal }
    }

    // MARK: Logging

    /// Upsert a day log.
    ///
    /// `fieldsAreAuthoritative` distinguishes a *patch* (only non-nil fields overwrite —
    /// how HealthKit-adjacent partial updates behave) from a full *replacement* from the
    /// day editor, where clearing a field must actually clear it. Without this, deleting
    /// a note or a BBT reading in the editor silently kept the old value forever.
    func upsertLog(_ log: CycleDayLog, fieldsAreAuthoritative: Bool = false) {
        if let idx = logs.firstIndex(where: { $0.dayKey == log.dayKey }) {
            var merged = logs[idx]
            merged.flow = log.flow
            merged.symptoms = log.symptoms
            if fieldsAreAuthoritative {
                merged.bbtCelsius = log.bbtCelsius
                merged.ovulationTest = log.ovulationTest
                merged.mucus = log.mucus
                merged.notes = log.notes
                merged.painScale = log.painScale
            } else {
                if let bbt = log.bbtCelsius { merged.bbtCelsius = bbt }
                if let o = log.ovulationTest { merged.ovulationTest = o }
                if let m = log.mucus { merged.mucus = m }
                if let n = log.notes { merged.notes = n }
                if let p = log.painScale { merged.painScale = p }
            }
            merged.source = log.source
            merged.updatedAt = Date()
            logs[idx] = merged
        } else {
            logs.append(log)
        }
        logs.sort { $0.dayKey < $1.dayKey }
        // Cap retention ~24 months of daily logs
        if logs.count > Self.maxRetainedLogs {
            logs = Array(logs.suffix(Self.maxRetainedLogs))
        }
        retireConfirmedEndIfBleedingResumed(on: log)
        persistLogs()
        recompute()
        pushAriaTags()
        Task { await writeFlowToHealthKitIfNeeded(log) }
    }

    /// If bleeding is logged on or after a confirmed end day, the bleed evidently is not
    /// over and the confirmation has to stand down — otherwise the app would insist the
    /// period had finished while the user was actively logging flow.
    private func retireConfirmedEndIfBleedingResumed(on log: CycleDayLog) {
        guard log.flow.isBleeding,
              let confirmed = settings.confirmedPeriodEndDayKey,
              let delta = CycleDayKey.daysBetween(confirmed, log.dayKey),
              delta > 0 else { return }
        var s = settings
        s.confirmedPeriodEndDayKey = nil
        settings = s
        persistSettings()
    }

    /// Apply several day edits as one transaction — one persist, one recompute, one
    /// ARIA push — instead of paying the full pipeline per day.
    private func applyLogBatch(_ updates: [CycleDayLog], fieldsAreAuthoritative: Bool = false) {
        guard !updates.isEmpty else { return }
        for log in updates {
            if let idx = logs.firstIndex(where: { $0.dayKey == log.dayKey }) {
                var merged = logs[idx]
                merged.flow = log.flow
                merged.symptoms = log.symptoms
                if fieldsAreAuthoritative {
                    merged.bbtCelsius = log.bbtCelsius
                    merged.ovulationTest = log.ovulationTest
                    merged.mucus = log.mucus
                    merged.notes = log.notes
                } else {
                    if let bbt = log.bbtCelsius { merged.bbtCelsius = bbt }
                    if let o = log.ovulationTest { merged.ovulationTest = o }
                    if let m = log.mucus { merged.mucus = m }
                    if let n = log.notes { merged.notes = n }
                }
                merged.source = log.source
                merged.updatedAt = Date()
                logs[idx] = merged
            } else {
                logs.append(log)
            }
        }
        logs.sort { $0.dayKey < $1.dayKey }
        if logs.count > Self.maxRetainedLogs {
            logs = Array(logs.suffix(Self.maxRetainedLogs))
        }
        persistLogs()
        recompute()
        pushAriaTags()
        let bleeding = updates.filter(\.flow.isBleeding)
        Task {
            for log in bleeding {
                await writeFlowToHealthKitIfNeeded(log)
            }
        }
    }

    func logPeriodStart(on dayKey: String = CycleDayKey.key(), flow: MenstrualFlowLevel = .medium) {
        // Capture feedback vs advertised prediction before logs change the engine state.
        recordPredictionFeedbackIfNeeded(actualStartDayKey: dayKey)
        // A new bleed reopens the cycle: the previous episode's "finished" confirmation
        // belongs to that episode and must not suppress this one.
        if settings.confirmedPeriodEndDayKey != nil {
            var s = settings
            s.confirmedPeriodEndDayKey = nil
            settings = s
            persistSettings()
        }
        upsertLog(CycleDayLog(dayKey: dayKey, flow: flow, source: "manual"))
    }

    /// Marks `dayKey` as the **last bleeding day** of the current episode.
    /// Clears any bleeding logged after that day, learns period length, and queues end feedback.
    @discardableResult
    func logPeriodEnd(on dayKey: String = CycleDayKey.key()) -> PeriodEpisode? {
        let episodesBefore = MenstrualCycleEngine.buildPeriodEpisodes(from: logs)
        let startKey = episodesBefore.last?.startDayKey
            ?? snapshot.lastPeriodStartDayKey
            ?? dayKey

        // All of the day mutations below land as one transaction — the previous version
        // ran a full persist + recompute + HealthKit write per day, so ending a 7-day
        // period fired the whole pipeline a dozen times and republished mid-edit state.
        var batch: [CycleDayLog] = []

        // Ensure the end day counts as bleeding (last flow day).
        var endLog = logs.first(where: { $0.dayKey == dayKey }) ?? CycleDayLog(dayKey: dayKey)
        if !endLog.flow.isBleeding {
            endLog.flow = .light
        }
        endLog.source = "manual"
        endLog.updatedAt = Date()
        batch.append(endLog)

        // Clear bleeding after the declared end so the episode closes cleanly.
        let today = CycleDayKey.key()
        if let afterEnd = CycleDayKey.daysBetween(dayKey, today), afterEnd > 0 {
            for offset in 1...afterEnd {
                guard let key = CycleDayKey.addDays(dayKey, offset),
                      let existing = logs.first(where: { $0.dayKey == key }),
                      existing.flow.isBleeding else { continue }
                var cleared = existing
                cleared.flow = .none
                cleared.source = "manual"
                cleared.updatedAt = Date()
                batch.append(cleared)
            }
        }

        // Fill unlogged days inside the episode with light flow so the run is contiguous.
        // Bounded to a plausible period length — a stale start key must not backfill weeks.
        if let gap = CycleDayKey.daysBetween(startKey, dayKey), gap >= 1, gap <= 10 {
            for offset in 0...gap {
                guard let key = CycleDayKey.addDays(startKey, offset),
                      !logs.contains(where: { $0.dayKey == key }),
                      !batch.contains(where: { $0.dayKey == key }) else { continue }
                batch.append(CycleDayLog(dayKey: key, flow: .light, source: "manual"))
            }
        }

        // Record the confirmation *before* recomputing so the very next snapshot already
        // reports the period as finished — this is what flips both the user's coaching and
        // the partner support brief out of period mode on the same tap.
        var confirmed = settings
        confirmed.confirmedPeriodEndDayKey = dayKey
        confirmed.overdueWidenDays = 0
        settings = confirmed
        persistSettings()

        applyLogBatch(batch)

        let episodes = MenstrualCycleEngine.buildPeriodEpisodes(from: logs)
        var episode = episodes.last(where: { $0.endDayKey == dayKey || $0.startDayKey == startKey })
            ?? episodes.last
            ?? PeriodEpisode(
                id: startKey,
                startDayKey: startKey,
                endDayKey: dayKey,
                peakFlow: endLog.flow,
                dayCount: max(1, (CycleDayKey.daysBetween(startKey, dayKey) ?? 0) + 1)
            )
        episode.isConfirmedComplete = true

        learnPeriodLength(from: episode)
        pendingPeriodEndEpisode = episode
        let msg = "Period finished · \(episode.dayCount) day\(episode.dayCount == 1 ? "" : "s") · how was it?"
        lastModelUpdateMessage = msg
        refreshAnalyst(lastAction: "period_ended")
        Task {
            await PartnerCycleSharing.shared.publishNow(supporterDigest)
            PartnerCycleSharing.shared.stageSupportUpdateForMessages()
        }
        return episode
    }

    /// Convenience: end period today (last bleeding day = today if bleeding, else yesterday if it bled).
    @discardableResult
    func confirmPeriodEndedToday() -> String {
        let today = CycleDayKey.key()
        let todayBleeding = logs.first(where: { $0.dayKey == today })?.flow.isBleeding == true
            || snapshot.isCurrentlyBleeding
        let endKey: String
        if todayBleeding {
            endKey = today
        } else if let y = CycleDayKey.addDays(today, -1),
                  logs.first(where: { $0.dayKey == y })?.flow.isBleeding == true {
            endKey = y
        } else {
            endKey = today
        }
        _ = logPeriodEnd(on: endKey)
        return lastModelUpdateMessage ?? "Period finished · model refreshed"
    }

    /// Submit ending-screen feedback and continuously update coaching preferences.
    @discardableResult
    func submitPeriodEndFeedback(_ feedback: PeriodEndFeedback) -> String {
        if let idx = periodEndFeedbacks.firstIndex(where: { $0.id == feedback.id }) {
            periodEndFeedbacks[idx] = feedback
        } else {
            periodEndFeedbacks.append(feedback)
        }
        if periodEndFeedbacks.count > 36 {
            periodEndFeedbacks = Array(periodEndFeedbacks.suffix(36))
        }
        persistPeriodEndFeedback()

        var prefs = coachingPreferences
        prefs.learn(from: feedback)
        coachingPreferences = prefs
        persistCoachingPrefs()

        // Soft-learn average period length toward this episode.
        if CycleBiology.periodDayRange.contains(feedback.dayCount) {
            updateSettings {
                let prior = Double($0.averagePeriodOverride ?? Int(snapshot.periodLengthMedian.rounded()))
                let blended = prior * 0.55 + Double(feedback.dayCount) * 0.45
                $0.averagePeriodOverride = CycleBiology.clampPeriodDays(Int(blended.rounded()))
            }
        }

        pendingPeriodEndEpisode = nil
        pushAriaTags()
        refreshAnalyst(lastAction: "period_end_feedback")

        let summary = prefs.lastLearnedSummary ?? "Thanks — coaching updated"
        lastModelUpdateMessage = summary
        lastTeachingMessage = summary
        AriaContextStore.shared.addInsight("Period feedback: \(summary)")
        return summary
    }

    func dismissPeriodEndFeedback() {
        pendingPeriodEndEpisode = nil
    }

    private func learnPeriodLength(from episode: PeriodEpisode) {
        // Outside 3–7 days this is not a normal bleed and should not move the model.
        guard CycleBiology.periodDayRange.contains(episode.dayCount) else { return }
        var s = settings
        let prior = Double(s.averagePeriodOverride ?? Int(snapshot.periodLengthMedian.rounded()))
        let blended = prior * 0.6 + Double(episode.dayCount) * 0.4
        let learned = CycleBiology.clampPeriodDays(Int(blended.rounded()))
        guard learned != s.averagePeriodOverride else { return }
        s.averagePeriodOverride = learned
        settings = s
        persistSettings()
        // The learned length feeds phase resolution — republish rather than leaving the
        // snapshot describing the pre-learning model until some later action recomputes.
        recompute()
    }

    /// Delete a single day log (day edit wipe).
    func deleteLog(dayKey: String) {
        logs.removeAll { $0.dayKey == dayKey }
        persistLogs()
        recompute()
        pushAriaTags()
    }

    /// Wipe self cycle logs (and optionally settings). Keeps partner logs by design.
    func wipeSelfCycleData(includingSettings: Bool = false) {
        logs = []
        predictionFeedback = []
        periodEndFeedbacks = []
        // The forecast archive survived a wipe, so the very next logged start was scored
        // against a prediction made for deleted history — poisoning MAE and the
        // calibration offset with an error the user had already erased.
        forecastArchive = []
        coachingPreferences = .neutral
        pendingPeriodEndEpisode = nil
        lastAdvertisedNextPeriodMedian = nil
        lastAriaBrief = nil
        lastTeachingMessage = nil
        lastEvaluation = .empty
        accuracyReport = .empty
        defaults.removeObject(forKey: feedbackKey)
        defaults.removeObject(forKey: forecastKey)
        defaults.removeObject(forKey: advertisedKey)
        defaults.removeObject(forKey: periodEndFeedbackKey)
        defaults.removeObject(forKey: coachingPrefsKey)
        persistLogs()
        // A wipe must also reset the learned bias — it was derived from the deleted data.
        var s = settings
        s.calibrationOffsetDays = 0
        s.learnedLutealDays = nil
        s.overdueWidenDays = 0
        s.averagePeriodOverride = nil
        s.confirmedPeriodEndDayKey = nil
        settings = includingSettings ? .default : s
        persistSettings()
        recompute()
        pushAriaTags()
    }

    func logToday(
        flow: MenstrualFlowLevel? = nil,
        symptoms: [CycleSymptom]? = nil,
        bbtCelsius: Double? = nil,
        ovulationTest: OvulationTestResult? = nil,
        mucus: CervicalMucusQuality? = nil,
        notes: String? = nil
    ) {
        let key = CycleDayKey.key()
        var existing = logs.first(where: { $0.dayKey == key }) ?? CycleDayLog(dayKey: key)
        if let flow { existing.flow = flow }
        if let symptoms { existing.symptoms = symptoms }
        if let bbtCelsius { existing.bbtCelsius = bbtCelsius }
        if let ovulationTest { existing.ovulationTest = ovulationTest }
        if let mucus { existing.mucus = mucus }
        if let notes { existing.notes = notes }
        existing.source = "manual"
        existing.updatedAt = Date()
        upsertLog(existing)
    }

    // MARK: People you support

    var selectedPerson: SupportedPerson? {
        if let selectedPersonId,
           let person = supportedPeople.first(where: { $0.id == selectedPersonId }) {
            return person
        }
        return supportedPeople.first
    }

    var consentedPeople: [SupportedPerson] {
        supportedPeople.filter { $0.settings.enabled && $0.settings.consentAcknowledged }
    }

    /// Period / luteal first, then the selected consented person.
    var mostTimelyPerson: SupportedPerson? {
        let live = consentedPeople
        if let bleeding = live.first(where: { (personSnapshots[$0.id] ?? .empty).stage == .period }) {
            return bleeding
        }
        if let luteal = live.first(where: { (personSnapshots[$0.id] ?? .empty).phase == .luteal }) {
            return luteal
        }
        if let selected = selectedPerson, live.contains(where: { $0.id == selected.id }) {
            return selected
        }
        return live.first
    }

    func selectPerson(_ id: String) {
        guard supportedPeople.contains(where: { $0.id == id }) else { return }
        selectedPersonId = id
        persistSelectedPerson()
        syncSelectedProjection()
        pushAriaTags()
    }

    @discardableResult
    func addSupportedPerson(
        name: String,
        role: CycleSupportRole,
        relationshipLabel: String? = nil,
        consentAcknowledged: Bool = false,
        cloudKitOwnerID: String? = nil
    ) -> SupportedPerson {
        var settings = PartnerCycleSettings.default
        settings.enabled = true
        settings.partnerName = name
        settings.supportRole = role
        settings.relationshipLabel = relationshipLabel
            ?? role.suggestedLabels.first
            ?? role.shortLabel.lowercased()
        settings.shareWithAria = true
        settings.consentAcknowledged = consentAcknowledged
        let person = SupportedPerson.make(settings: settings, cloudKitOwnerID: cloudKitOwnerID)
        supportedPeople.append(person)
        selectedPersonId = person.id
        persistPeople()
        persistSelectedPerson()
        syncSelectedProjection()
        recomputePartner()
        pushAriaTags()
        return person
    }

    func removeSupportedPerson(_ id: String) {
        supportedPeople.removeAll { $0.id == id }
        personSnapshots[id] = nil
        personBriefs[id] = nil
        if selectedPersonId == id {
            selectedPersonId = supportedPeople.first?.id
        }
        persistPeople()
        persistSelectedPerson()
        syncSelectedProjection()
        recomputePartner()
        pushAriaTags()
    }

    /// Select an existing row, or add one. Never overwrite a partner into a daughter.
    func activateOrCreatePerson(name: String, label: String, role: CycleSupportRole) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = supportedPeople.first(where: { person in
            if !trimmed.isEmpty {
                return person.settings.partnerName.lowercased() == trimmed.lowercased()
                    || person.displayName.lowercased() == trimmed.lowercased()
            }
            return person.settings.resolvedRole == role
                && person.settings.relationshipLabel.lowercased() == label.lowercased()
        }) {
            if !trimmed.isEmpty, existing.settings.partnerName.isEmpty {
                updatePersonSettings(existing.id) { $0.partnerName = trimmed }
            }
            selectPerson(existing.id)
            return
        }
        _ = addSupportedPerson(
            name: trimmed,
            role: role,
            relationshipLabel: label,
            consentAcknowledged: false
        )
    }

    func personBound(to cloudKitOwnerID: String) -> SupportedPerson? {
        supportedPeople.first { $0.cloudKitOwnerID == cloudKitOwnerID }
    }

    /// Bind incoming CloudKit shares to local people. Creates a row when the
    /// share does not match anyone — never dumps a daughter onto the partner.
    func adoptReceivedDigests(_ incoming: [PartnerCycleSharing.ReceivedDigest]) {
        var changed = false
        for received in incoming {
            let records = supportedPeople.map {
                SupportedPersonMatch.Record(
                    name: $0.settings.partnerName.isEmpty ? $0.displayName : $0.settings.partnerName,
                    role: $0.settings.resolvedRole.rawValue,
                    cloudID: $0.cloudKitOwnerID
                )
            }
            if let idx = SupportedPersonMatch.bindIndex(
                people: records,
                incomingName: received.ownerName,
                incomingRole: received.role.rawValue,
                incomingCloudID: received.id
            ) {
                if supportedPeople[idx].cloudKitOwnerID != received.id {
                    supportedPeople[idx].cloudKitOwnerID = received.id
                    supportedPeople[idx].updatedAt = Date()
                    changed = true
                }
                if supportedPeople[idx].settings.partnerName.isEmpty {
                    supportedPeople[idx].settings.partnerName = received.ownerName
                    changed = true
                }
                continue
            }
            var s = PartnerCycleSettings.default
            s.enabled = true
            s.consentAcknowledged = true
            s.partnerName = received.ownerName
            s.supportRole = received.role
            s.relationshipLabel = received.role.suggestedLabels.first
                ?? received.role.shortLabel.lowercased()
            s.shareWithAria = true
            if received.digest.periodFinished {
                s.confirmedPeriodEndDayKey = received.digest.periodFinishedDayKey
            }
            let person = SupportedPerson.make(settings: s, cloudKitOwnerID: received.id)
            supportedPeople.append(person)
            if selectedPersonId == nil { selectedPersonId = person.id }
            changed = true
        }
        guard changed else { return }
        persistPeople()
        persistSelectedPerson()
        syncSelectedProjection()
        recomputePartner()
        pushAriaTags()
    }

    // MARK: Partner logging (never HealthKit — the supported person is not the device owner)

    func upsertPartnerLog(_ log: CycleDayLog, personId: String? = nil) {
        let id = resolvedPersonId(personId)
        guard let id, let pidx = supportedPeople.firstIndex(where: { $0.id == id }) else {
            var s = PartnerCycleSettings.default
            s.enabled = true
            let person = SupportedPerson.make(settings: s, logs: [sanitizedPartnerLog(log)])
            supportedPeople = [person]
            selectedPersonId = person.id
            persistPeople()
            persistSelectedPerson()
            syncSelectedProjection()
            recomputePartner()
            pushAriaTags()
            return
        }
        var entry = sanitizedPartnerLog(log)
        if let idx = supportedPeople[pidx].logs.firstIndex(where: { $0.dayKey == entry.dayKey }) {
            var merged = supportedPeople[pidx].logs[idx]
            merged.flow = entry.flow
            merged.symptoms = entry.symptoms
            if let n = entry.notes { merged.notes = n }
            merged.source = "manual"
            merged.updatedAt = Date()
            supportedPeople[pidx].logs[idx] = merged
        } else {
            supportedPeople[pidx].logs.append(entry)
        }
        supportedPeople[pidx].logs.sort { $0.dayKey < $1.dayKey }
        if supportedPeople[pidx].logs.count > 800 {
            supportedPeople[pidx].logs = Array(supportedPeople[pidx].logs.suffix(800))
        }
        supportedPeople[pidx].updatedAt = Date()
        persistPeople()
        syncSelectedProjection()
        recomputePartner()
        pushAriaTags()
    }

    func logPartnerPeriodStart(
        on dayKey: String = CycleDayKey.key(),
        flow: MenstrualFlowLevel = .medium,
        personId: String? = nil
    ) {
        let id = resolvedPersonId(personId)
        let snap = id.flatMap { personSnapshots[$0] } ?? partnerSnapshot
        if let predicted = snap.nextPeriod?.medianDayKey,
           let err = CycleDayKey.daysBetween(predicted, dayKey),
           abs(err) <= 21 {
            lastModelUpdateMessage = "Support model updated · error \(err >= 0 ? "+" : "")\(err) days"
        }
        if let id, let idx = supportedPeople.firstIndex(where: { $0.id == id }),
           supportedPeople[idx].settings.confirmedPeriodEndDayKey != nil {
            supportedPeople[idx].settings.confirmedPeriodEndDayKey = nil
            supportedPeople[idx].updatedAt = Date()
            persistPeople()
        }
        upsertPartnerLog(CycleDayLog(dayKey: dayKey, flow: flow, source: "manual"), personId: id)
    }

    /// The supported person's period is over. Closes the episode and returns the support
    /// brief from period-care coaching to everyday support on the same tap.
    @discardableResult
    func logPartnerPeriodEnd(
        on dayKey: String = CycleDayKey.key(),
        propagate: Bool = true,
        personId: String? = nil
    ) -> String {
        let id = resolvedPersonId(personId)
        guard let id, let idx = supportedPeople.firstIndex(where: { $0.id == id }) else {
            return "No one selected"
        }
        var person = supportedPeople[idx]
        let snap = personSnapshots[id] ?? partnerSnapshot
        let episodes = MenstrualCycleEngine.buildPeriodEpisodes(from: person.logs)
        let startKey = episodes.last?.startDayKey ?? snap.lastPeriodStartDayKey ?? dayKey

        var endLog = person.logs.first(where: { $0.dayKey == dayKey }) ?? CycleDayLog(dayKey: dayKey)
        if !endLog.flow.isBleeding { endLog.flow = .light }
        endLog.source = "manual"
        endLog.updatedAt = Date()

        person.settings.confirmedPeriodEndDayKey = dayKey
        person.updatedAt = Date()
        supportedPeople[idx] = person
        persistPeople()
        upsertPartnerLog(endLog, personId: id)

        let days = (CycleDayKey.daysBetween(startKey, dayKey) ?? 0) + 1
        let name = person.displayName
        let msg = "\(name)'s period finished · \(max(1, days)) day\(days == 1 ? "" : "s") · back to everyday support"
        lastModelUpdateMessage = msg
        if selectedPersonId == id {
            refreshAnalyst(lastAction: "partner_period_ended", isPartner: true)
        }
        if propagate {
            let ownerID = person.cloudKitOwnerID ?? ""
            Task {
                _ = await PartnerCycleSharing.shared.reportPeriodFinishedFromSupport(
                    ownerID: ownerID,
                    dayKey: dayKey
                )
                PartnerCycleSharing.shared.stageSupportUpdateForMessages()
            }
        }
        return msg
    }

    /// Pull CloudKit. If they marked finished, both sides show it — per person.
    func syncSharedPeriodFinished() async {
        let incoming = await PartnerCycleSharing.shared.fetchSharedDigest()
        adoptReceivedDigests(incoming)
        for received in incoming where received.digest.periodFinished {
            guard let person = personBound(to: received.id) else { continue }
            let snap = personSnapshots[person.id] ?? .empty
            if person.settings.enabled,
               person.settings.confirmedPeriodEndDayKey == nil || snap.stage == .period {
                _ = logPartnerPeriodEnd(
                    on: received.digest.periodFinishedDayKey ?? CycleDayKey.key(),
                    propagate: false,
                    personId: person.id
                )
            }
        }
        if settings.enabled, !snapshot.periodEndConfirmed || snapshot.isCurrentlyBleeding {
            if let dayKey = await PartnerCycleSharing.shared.applyRemotePeriodFinishedIfNeeded() {
                _ = logPeriodEnd(on: dayKey)
            }
        }
    }

    private func resolvedPersonId(_ personId: String?) -> String? {
        if let personId, supportedPeople.contains(where: { $0.id == personId }) {
            return personId
        }
        return selectedPerson?.id
    }

    private func sanitizedPartnerLog(_ log: CycleDayLog) -> CycleDayLog {
        var entry = log
        entry.source = entry.source == "healthkit" ? "manual" : entry.source
        return entry
    }

    /// User says period started today (feedback + log).
    @discardableResult
    func confirmPeriodStartedToday(flow: MenstrualFlowLevel = .medium) -> String {
        let key = CycleDayKey.key()
        logPeriodStart(on: key, flow: flow)
        updateSettings { $0.overdueWidenDays = 0 }
        let msg = lastModelUpdateMessage ?? "Period logged · model refreshed"
        return msg
    }

    /// Manual early/late correction: period came `days` before (negative) or after (positive) prediction.
    @discardableResult
    func confirmPeriodOffsetFromPrediction(daysFromPredicted: Int, flow: MenstrualFlowLevel = .medium) -> String {
        guard let predicted = lastAdvertisedNextPeriodMedian ?? snapshot.nextPeriod?.medianDayKey,
              let actual = CycleDayKey.addDays(predicted, daysFromPredicted) else {
            let key = CycleDayKey.key()
            logPeriodStart(on: key, flow: flow)
            return lastModelUpdateMessage ?? "Period logged"
        }
        logPeriodStart(on: actual, flow: flow)
        updateSettings { $0.overdueWidenDays = 0 }
        return lastModelUpdateMessage ?? "Model updated · error \(daysFromPredicted >= 0 ? "+" : "")\(daysFromPredicted) days"
    }

    /// Still no period past window — widen forecast, lower certainty, keep history.
    @discardableResult
    func reportStillNoPeriod() -> String {
        updateSettings {
            $0.overdueWidenDays = min(10, $0.overdueWidenDays + 2)
        }
        recompute()
        let msg = "Window widened · still waiting (confidence tempered)"
        lastModelUpdateMessage = msg
        return msg
    }

    func logPartnerToday(
        flow: MenstrualFlowLevel? = nil,
        symptoms: [CycleSymptom]? = nil,
        notes: String? = nil,
        personId: String? = nil
    ) {
        let id = resolvedPersonId(personId)
        let key = CycleDayKey.key()
        let existingLogs = id.flatMap { pid in supportedPeople.first(where: { $0.id == pid })?.logs } ?? partnerLogs
        var existing = existingLogs.first(where: { $0.dayKey == key }) ?? CycleDayLog(dayKey: key)
        if let flow { existing.flow = flow }
        if let symptoms { existing.symptoms = symptoms }
        if let notes { existing.notes = notes }
        existing.source = "manual"
        existing.updatedAt = Date()
        upsertPartnerLog(existing, personId: id)
    }

    // MARK: Engine

    func recompute(readinessHRV: Int? = nil, baselineHRV: Int? = nil, restingHR: Int? = nil) {
        var snap = MenstrualCycleEngine.evaluate(
            logs: logs,
            settings: settings,
            recentHRV: readinessHRV,
            baselineHRV: baselineHRV,
            restingHR: restingHR
        )
        let report = CycleAccuracyReport.compute(
            from: predictionFeedback,
            calibrationOffset: settings.calibrationOffsetDays
        )
        snap.accuracyMAE = report.maeDays
        snap.accuracySampleCount = report.sampleCount
        snap.accuracyGrade = report.gradeLabel
        snap.calibrationOffsetDays = settings.calibrationOffsetDays
        if report.sampleCount > 0, let mae = report.maeDays {
            snap.insights.insert(
                "Personal timing MAE: \(String(format: "%.1f", mae)) days over \(report.sampleCount) confirms (\(report.gradeLabel.replacingOccurrences(of: "_", with: " "))).",
                at: 0
            )
        }
        // TTC mode: attach goal + two-week wait progress to the snapshot.
        snap.cycleGoal = settings.cycleGoal
        if snap.phase == .luteal,
           let dayInCycle = snap.dayInCycle,
           let ovulationDay = snap.ovulationDayInCycle,
           snap.ovulationMethod != nil {
            let elapsed = dayInCycle - ovulationDay
            if elapsed > 0 && elapsed <= 14 {
                snap.twwDaysElapsed = elapsed
            }
        }

        // Defer @Published mutations to avoid publishing during a view update.
        Task { @MainActor in
            accuracyReport = report
            snapshot = snap
            archiveOpenForecastIfNeeded(from: snap)
            lastEvaluation = CycleDataEvaluator.evaluate(
                snapshot: snap,
                settings: settings,
                logs: logs,
                feedback: predictionFeedback
            )
            lastAriaBrief = CycleAriaAnalyst.localBrief(
                evaluation: lastEvaluation,
                snapshot: snap
            )
            // Remember what we currently advertise so the next real start can score us.
            if let median = snap.nextPeriod?.medianDayKey {
                lastAdvertisedNextPeriodMedian = median
                defaults.set(median, forKey: advertisedKey)
            }
            await ForgeNotificationScheduler.syncCycleNotifications(settings: settings, snapshot: snapshot)

            // Keep anyone the user shares with current. This is the only place
            // the shared digest is refreshed, and it is deliberately here rather
            // than at invite time: publishing once when the invite is created
            // leaves a supporter reading a snapshot frozen at the moment they
            // were invited, for as long as the share lasts.
            //
            // `publishIfChanged` no-ops when nobody has been invited and when the
            // redacted digest has not moved, so the cost on the common path — a
            // recompute that changes nothing a supporter can see — is one
            // equality check.
            await PartnerCycleSharing.shared.publishIfChanged(supporterDigest)

            // Sync cycle data to WatchSnapshot (drives complications + lockscreen widget).
            if snap.trackingEnabled {
                WatchSnapshotStore.update(reloadWidgets: false) { ws in
                    ws.cyclePhase = snap.phase.rawValue
                    ws.cycleDayInCycle = snap.dayInCycle
                    ws.cycleFertileWindowOpen = (snap.phase == .fertileWindow || snap.phase == .ovulation)
                    ws.cycleFertileScore = snap.fertileScore
                    if let nextPeriod = snap.nextPeriod,
                       let nextDate = CycleDayKey.date(from: nextPeriod.medianDayKey) {
                        ws.cycleNextPeriodDaysAway = Calendar.current.dateComponents([.day], from: Date(), to: nextDate).day
                    } else {
                        ws.cycleNextPeriodDaysAway = nil
                    }
                }
            }

            // Manage cycle Live Activity for the fertile window (ActivityContent API —
            // matches WorkoutActivityCoordinator; avoids deprecated contentState:).
            if #available(iOS 16.2, *) {
                let isInFertileWindow = snap.phase == .fertileWindow || snap.phase == .ovulation
                if isInFertileWindow && snap.trackingEnabled {
                    let state = CycleLiveActivityAttributes.ContentState(
                        phase: snap.phase.rawValue,
                        dayInCycle: snap.dayInCycle,
                        fertileScore: snap.fertileScore,
                        daysUntilOvulation: {
                            guard let day = snap.dayInCycle, let ovu = snap.ovulationDayInCycle else { return nil }
                            return max(0, ovu - day)
                        }(),
                        isActiveFertileWindow: true,
                        isCurrentlyBleeding: snap.isCurrentlyBleeding
                    )
                    let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(6 * 3600))
                    if let existing = Activity<CycleLiveActivityAttributes>.activities.first {
                        await existing.update(content)
                    } else if ActivityAuthorizationInfo().areActivitiesEnabled {
                        _ = try? Activity.request(
                            attributes: CycleLiveActivityAttributes(),
                            content: content
                        )
                    }
                } else {
                    for activity in Activity<CycleLiveActivityAttributes>.activities {
                        let final = ActivityContent(state: activity.content.state, staleDate: Date())
                        await activity.end(final, dismissalPolicy: .immediate)
                    }
                }
            }
        }
    }

    /// Freeze one open forecast per anchor period start (honest MAE source).
    private func archiveOpenForecastIfNeeded(from snap: MenstrualCycleSnapshot) {
        guard let next = snap.nextPeriod,
              let anchor = snap.lastPeriodStartDayKey else { return }
        // Update cache
        lastAdvertisedNextPeriodMedian = next.medianDayKey
        defaults.set(next.medianDayKey, forKey: advertisedKey)

        if let idx = forecastArchive.firstIndex(where: { $0.anchorPeriodStartDayKey == anchor && $0.isOpen }) {
            // Refresh open forecast with latest engine view (same cycle)
            var rec = forecastArchive[idx]
            rec.predictedMedianDayKey = next.medianDayKey
            rec.earliestDayKey = next.earliestDayKey
            rec.latestDayKey = next.latestDayKey
            rec.cycleLengthUsed = snap.cycleLengthMedian
            rec.calibrationOffsetUsed = settings.calibrationOffsetDays
            rec.confidence = snap.periodTimingConfidence
            rec.methodSummary = snap.predictionMethodSummary
            rec.asOfDayKey = snap.asOfDayKey
            forecastArchive[idx] = rec
        } else if !forecastArchive.contains(where: { $0.anchorPeriodStartDayKey == anchor }) {
            let rec = CycleForecastRecord(
                id: UUID().uuidString,
                asOfDayKey: snap.asOfDayKey,
                anchorPeriodStartDayKey: anchor,
                predictedMedianDayKey: next.medianDayKey,
                earliestDayKey: next.earliestDayKey,
                latestDayKey: next.latestDayKey,
                cycleLengthUsed: snap.cycleLengthMedian,
                calibrationOffsetUsed: settings.calibrationOffsetDays,
                confidence: snap.periodTimingConfidence,
                methodSummary: snap.predictionMethodSummary,
                createdAt: Date()
            )
            forecastArchive.append(rec)
        }
        if forecastArchive.count > 36 {
            forecastArchive = Array(forecastArchive.suffix(36))
        }
        persistForecasts()
    }

    /// Score actual start against the correct archived forecast; adaptive calibration.
    func recordPredictionFeedbackIfNeeded(actualStartDayKey: String) {
        if predictionFeedback.contains(where: { $0.actualStartDayKey == actualStartDayKey }) {
            return
        }

        // Prefer open forecast whose window is nearest to this actual start.
        let open = forecastArchive.filter(\.isOpen)
        let predicted: String
        var forecastId: String?
        if let best = open.min(by: { a, b in
            abs((CycleDayKey.daysBetween(a.predictedMedianDayKey, actualStartDayKey) ?? 99))
                < abs((CycleDayKey.daysBetween(b.predictedMedianDayKey, actualStartDayKey) ?? 99))
        }), let err0 = CycleDayKey.daysBetween(best.predictedMedianDayKey, actualStartDayKey), abs(err0) <= 21 {
            predicted = best.predictedMedianDayKey
            forecastId = best.id
        } else if let fallback = lastAdvertisedNextPeriodMedian ?? snapshot.nextPeriod?.medianDayKey {
            predicted = fallback
        } else {
            return
        }

        guard let err = CycleDayKey.daysBetween(predicted, actualStartDayKey), abs(err) <= 21 else { return }

        let entry = CyclePredictionFeedback(
            predictedMedianDayKey: predicted,
            actualStartDayKey: actualStartDayKey,
            errorDays: err,
            recordedAt: Date()
        )
        predictionFeedback.append(entry)
        if predictionFeedback.count > 24 {
            predictionFeedback = Array(predictionFeedback.suffix(24))
        }
        persistFeedback()

        if let fid = forecastId, let idx = forecastArchive.firstIndex(where: { $0.id == fid }) {
            forecastArchive[idx].scoredActualStartDayKey = actualStartDayKey
            forecastArchive[idx].scoredErrorDays = err
            persistForecasts()
        }

        // Adaptive EMA: stronger alpha when last 3 errors share a sign.
        let recent = predictionFeedback.suffix(3).map(\.errorDays)
        let sameSign = recent.count >= 3
            && (recent.allSatisfy { $0 > 0 } || recent.allSatisfy { $0 < 0 })
        let alpha = sameSign ? 0.5 : 0.35
        let newOffset = settings.calibrationOffsetDays * (1 - alpha) + Double(err) * alpha

        // Learn luteal when prior cycle had high-signal ovulation
        maybeLearnLuteal(actualStartDayKey: actualStartDayKey)

        // Direct settings mutate without nested recompute storm
        var s = settings
        s.calibrationOffsetDays = max(-5, min(5, newOffset))
        s.overdueWidenDays = 0
        settings = s
        persistSettings()

        lastModelUpdateMessage = "Model updated · last error \(err >= 0 ? "+" : "")\(err) days"
        let eval = CycleDataEvaluator.evaluate(
            snapshot: snapshot,
            settings: settings,
            logs: logs,
            feedback: predictionFeedback,
            lastAction: "period_start_confirmed"
        )
        lastEvaluation = eval
        lastTeachingMessage = CycleAriaAnalyst.teachingAfterFeedback(
            errorDays: err,
            evaluation: eval,
            snapshot: snapshot
        )
        lastAriaBrief = CycleAriaAnalyst.localBrief(
            evaluation: eval,
            snapshot: snapshot,
            lastAction: "period_start_confirmed"
        )
    }

    /// Update learned luteal from LH/BBT-tagged prior ovulation when next start arrives.
    private func maybeLearnLuteal(actualStartDayKey: String) {
        guard let method = snapshot.ovulationMethod,
              method == "lh_surge" || method == "bbt_shift",
              let ovuDay = snapshot.ovulationDayInCycle,
              let lastStart = snapshot.lastPeriodStartDayKey,
              let ovuKey = CycleDayKey.addDays(lastStart, ovuDay - 1),
              let luteal = CycleDayKey.daysBetween(ovuKey, actualStartDayKey),
              luteal >= 10, luteal <= 16
        else { return }

        let prior = settings.learnedLutealDays ?? Double(settings.typicalLutealDays)
        let blended = prior * 0.6 + Double(luteal) * 0.4
        settings.learnedLutealDays = blended
        persistSettings()
    }

    func recomputePartner() {
        var snaps: [String: MenstrualCycleSnapshot] = [:]
        var briefs: [String: PartnerSupportBrief] = [:]
        for person in supportedPeople {
            let engineSettings = MenstrualTrackingSettings(
                enabled: person.settings.enabled && person.settings.consentAcknowledged,
                shareWithAria: person.settings.shareWithAria,
                averageCycleOverride: person.settings.averageCycleOverride,
                averagePeriodOverride: person.settings.averagePeriodOverride,
                typicalLutealDays: person.settings.typicalLutealDays,
                usesHormonalContraception: person.settings.usesHormonalContraception,
                notes: person.settings.notes,
                confirmedPeriodEndDayKey: person.settings.confirmedPeriodEndDayKey
            )
            let snap = MenstrualCycleEngine.evaluate(
                logs: person.logs,
                settings: engineSettings
            )
            snaps[person.id] = snap
            if person.settings.enabled, person.settings.consentAcknowledged {
                briefs[person.id] = PartnerSupportCoach.brief(
                    snapshot: snap,
                    settings: person.settings
                )
            }
        }
        personSnapshots = snaps
        personBriefs = briefs
        syncSelectedProjection()
    }

    // MARK: Sharing

    /// The user's own cycle, reduced to what a supporter is allowed to see.
    ///
    /// Derived on demand rather than stored, so it cannot drift from `snapshot`
    /// and there is no second copy of reproductive state to keep in sync or
    /// forget to clear. `PartnerCycleDigest.init(redacting:)` is the only
    /// crossing point, and this is the only thing that calls it.
    var supporterDigest: PartnerCycleDigest {
        PartnerCycleDigest(redacting: snapshot)
    }

    func refresh(from store: AppStore) {
        recompute(
            readinessHRV: store.dailyMetrics.hrv,
            baselineHRV: max(store.dailyMetrics.hrv, 40),
            restingHR: store.dailyMetrics.restingHR
        )
        recomputePartner()
        pushAriaTags()
    }

    // MARK: HealthKit

    func syncFromHealthKit(days: Int = 400) async {
        // Two concurrent syncs (toolbar tap while the onAppear sync is in flight) both
        // merged into `logs` and both wrote, so the slower one clobbered the newer merge.
        guard settings.enabled, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let bundle = await HealthKitManager.shared.fetchMenstrualHealthBundle(days: days)
        mergeHealthKit(bundle)
        lastSyncAt = Date()
        defaults.set(Date().timeIntervalSince1970, forKey: quietSyncKey)
        recompute()
        pushAriaTags()
    }

    /// Quiet weekly HealthKit menstrual sync. Runs full sync if never run, >7 days, or forced (e.g. HealthKit offline).
    func quietWeeklyHealthKitSync(force: Bool = false) async {
        guard settings.enabled else { return }
        let last = defaults.double(forKey: quietSyncKey)
        let week: TimeInterval = 7 * 24 * 60 * 60
        let stale = last <= 0 || (Date().timeIntervalSince1970 - last) >= week
        guard force || stale || lastSyncAt == nil else {
            // Still refresh engine from local logs.
            recompute()
            return
        }
        await syncFromHealthKit()
    }

    private func mergeHealthKit(_ bundle: MenstrualHealthKitBundle) {
        // `Dictionary(uniqueKeysWithValues:)` traps at runtime on a duplicate key. A single
        // duplicated dayKey — from an interrupted migration, a restored backup, or two
        // writers racing — would crash the app on every HealthKit sync. Keep the newest.
        var byDay = Dictionary(logs.map { ($0.dayKey, $0) }) { older, newer in
            newer.updatedAt >= older.updatedAt ? newer : older
        }

        /// Manual entries are the user's own words about their body — HealthKit never
        /// silently overwrites them, and merging never downgrades a "manual" log to a
        /// weaker precedence tier.
        func mergedSource(_ existing: String) -> String {
            existing == "manual" || existing == "merged" ? "merged" : "healthkit"
        }

        for sample in bundle.flowSamples {
            let key = CycleDayKey.key(for: sample.date)
            var log = byDay[key] ?? CycleDayLog(dayKey: key, flow: .none, source: "healthkit")
            let manualIsAuthoritative = (log.source == "manual" || log.source == "merged")
                && log.updatedAt > sample.date
            if !manualIsAuthoritative {
                log.flow = sample.flow
                log.source = mergedSource(log.source)
                log.updatedAt = max(log.updatedAt, sample.date)
            }
            byDay[key] = log
        }

        for bbt in bundle.bbtSamples {
            let key = CycleDayKey.key(for: bbt.date)
            var log = byDay[key] ?? CycleDayLog(dayKey: key, source: "healthkit")
            if log.bbtCelsius == nil || log.source == "healthkit" {
                log.bbtCelsius = bbt.celsius
                log.source = mergedSource(log.source)
            }
            byDay[key] = log
        }

        for opk in bundle.ovulationTests {
            let key = CycleDayKey.key(for: opk.date)
            var log = byDay[key] ?? CycleDayLog(dayKey: key, source: "healthkit")
            if log.ovulationTest == nil || log.source == "healthkit" {
                log.ovulationTest = opk.result
                log.source = mergedSource(log.source)
            }
            byDay[key] = log
        }

        for mucus in bundle.mucusSamples {
            let key = CycleDayKey.key(for: mucus.date)
            var log = byDay[key] ?? CycleDayLog(dayKey: key, source: "healthkit")
            if log.mucus == nil || log.source == "healthkit" {
                log.mucus = mucus.quality
                log.source = mergedSource(log.source)
            }
            byDay[key] = log
        }

        var merged = byDay.values.sorted { $0.dayKey < $1.dayKey }
        if merged.count > Self.maxRetainedLogs {
            merged = Array(merged.suffix(Self.maxRetainedLogs))
        }
        logs = merged
        persistLogs()
    }

    private func writeFlowToHealthKitIfNeeded(_ log: CycleDayLog) async {
        guard log.flow.isBleeding, log.source == "manual" || log.source == "merged" else { return }
        // Only the first bleeding day of an episode is a cycle *start*. Tagging every
        // bleeding day as a start told Apple Health each day began a new cycle.
        let isEpisodeStart = MenstrualCycleEngine.buildPeriodEpisodes(from: logs)
            .contains { $0.startDayKey == log.dayKey }
        await HealthKitManager.shared.saveMenstrualFlow(
            dayKey: log.dayKey,
            flow: log.flow,
            isCycleStart: isEpisodeStart
        )
    }

    // MARK: ARIA bridge

    func pushAriaTags() {
        if settings.enabled, settings.shareWithAria {
            AriaContextStore.shared.applyCycleSnapshot(snapshot)
            AriaContextStore.shared.applyPeriodCoachingPreferences(coachingPreferences)
        } else {
            AriaContextStore.shared.clearCycleTags()
        }
        let ariaPeople: [(SupportedPerson, MenstrualCycleSnapshot)] = consentedPeople.compactMap { person in
            guard person.settings.shareWithAria else { return nil }
            return (person, personSnapshots[person.id] ?? .empty)
        }
        AriaContextStore.shared.applySupportedPeople(ariaPeople)
    }

    func ariaContextLines() -> [String] {
        var lines: [String] = []
        if settings.enabled, settings.shareWithAria {
            lines.append("Self cycle phase: \(snapshot.phase.label)")
            if let d = snapshot.dayInCycle {
                lines.append("Self day in cycle: \(d)")
            }
            lines.append(snapshot.trainingNote)
            if coachingPreferences.sampleCount > 0 {
                let directive = coachingPreferences.coachingDirective
                if !directive.isEmpty { lines.append(directive) }
            }
        }
        for person in consentedPeople where person.settings.shareWithAria {
            let snap = personSnapshots[person.id] ?? .empty
            let who = person.role.shortLabel
            lines.append("\(who) (\(person.displayName)) phase: \(snap.phase.label)")
            if let d = snap.dayInCycle {
                lines.append("\(who) (\(person.displayName)) day in cycle: \(d)")
            }
            if let brief = personBriefs[person.id] {
                lines.append("\(person.displayName): \(brief.headline)")
                lines.append(brief.communicationTip)
            }
        }
        if consentedPeople.contains(where: { $0.settings.shareWithAria }) {
            lines.append(PartnerSupportBrief.disclaimer)
        }
        return lines
    }

    // MARK: Persist

    private func persistSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: settingsKey)
        }
    }

    private func persistLogs() {
        if let data = try? JSONEncoder().encode(logs) {
            defaults.set(data, forKey: logsKey)
        }
    }

    private func persistPeople() {
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

    private func persistSelectedPerson() {
        if let selectedPersonId {
            defaults.set(selectedPersonId, forKey: selectedPersonKey)
        } else {
            defaults.removeObject(forKey: selectedPersonKey)
        }
    }

    private func syncSelectedProjection() {
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

    private static func loadPeople(
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

    private func persistFeedback() {
        if let data = try? JSONEncoder().encode(predictionFeedback) {
            defaults.set(data, forKey: feedbackKey)
        }
    }

    private func persistForecasts() {
        if let data = try? JSONEncoder().encode(forecastArchive) {
            defaults.set(data, forKey: forecastKey)
        }
    }

    private func persistPeriodEndFeedback() {
        if let data = try? JSONEncoder().encode(periodEndFeedbacks) {
            defaults.set(data, forKey: periodEndFeedbackKey)
        }
    }

    private func persistCoachingPrefs() {
        if let data = try? JSONEncoder().encode(coachingPreferences) {
            defaults.set(data, forKey: coachingPrefsKey)
        }
    }

    /// Refresh evaluation + local ARIA brief after a user action label.
    func refreshAnalyst(lastAction: String? = nil, isPartner: Bool = false) {
        let snap = isPartner ? partnerSnapshot : snapshot
        let set = isPartner
            ? MenstrualTrackingSettings(
                enabled: partnerSettings.enabled,
                shareWithAria: partnerSettings.shareWithAria,
                averageCycleOverride: partnerSettings.averageCycleOverride,
                averagePeriodOverride: partnerSettings.averagePeriodOverride,
                typicalLutealDays: partnerSettings.typicalLutealDays,
                usesHormonalContraception: partnerSettings.usesHormonalContraception,
                notes: partnerSettings.notes,
                highAccuracyMode: false,
                confirmedPeriodEndDayKey: partnerSettings.confirmedPeriodEndDayKey
            )
            : settings
        let logSet = isPartner ? partnerLogs : logs
        let eval = CycleDataEvaluator.evaluate(
            snapshot: snap,
            settings: set,
            logs: logSet,
            feedback: isPartner ? [] : predictionFeedback,
            lastAction: lastAction,
            isPartner: isPartner
        )
        lastEvaluation = eval
        lastAriaBrief = CycleAriaAnalyst.localBrief(
            evaluation: eval,
            snapshot: snap,
            lastAction: lastAction,
            isPartner: isPartner
        )
    }

    func ariaChatPromptForCycle(isPartner: Bool = false) -> String? {
        let share = isPartner ? partnerSettings.shareWithAria : settings.shareWithAria
        guard share else { return nil }
        let ctx = CycleAriaAnalyst.makeContext(
            snapshot: isPartner ? partnerSnapshot : snapshot,
            evaluation: lastEvaluation,
            settings: settings,
            lastAction: nil,
            isPartner: isPartner
        )
        return CycleAriaAnalyst.chatPrompt(context: ctx, evaluation: lastEvaluation)
    }
}

// MARK: - HealthKit DTO

struct MenstrualHealthKitBundle {
    var flowSamples: [(date: Date, flow: MenstrualFlowLevel)]
    var bbtSamples: [(date: Date, celsius: Double)]
    var ovulationTests: [(date: Date, result: OvulationTestResult)]
    var mucusSamples: [(date: Date, quality: CervicalMucusQuality)]
}
