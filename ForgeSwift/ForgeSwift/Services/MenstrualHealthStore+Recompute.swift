import Foundation
import Combine
import HealthKit
import ActivityKit
import ForgeCore

extension MenstrualHealthStore {

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
}
