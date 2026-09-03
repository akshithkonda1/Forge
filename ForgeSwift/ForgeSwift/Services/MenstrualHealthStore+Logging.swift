import Foundation
import Combine
import HealthKit
import ActivityKit
import ForgeCore

extension MenstrualHealthStore {

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

    /// Local tester history only. Never HealthKit, never a physical-phone pack.
    func seedTestReadyCycleIfNeeded(testReady: Bool) {
        guard FakeCyclePack.shouldSeed(
            testReady: testReady,
            trackingEnabled: settings.enabled,
            logsEmpty: logs.isEmpty,
            alreadySeeded: defaults.bool(forKey: testReadySeededKey)
        ) else { return }
        logs = FakeCyclePack.generate(seed: AppStore.testReadySessionSeed)
        defaults.set(true, forKey: testReadySeededKey)
        persistLogs()
        recompute()
        refreshAnalyst(lastAction: "test_ready_seed")
        lastModelUpdateMessage = "Tester cycle loaded · local only"
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
        defaults.set(true, forKey: testReadySeededKey)
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
}
