import Foundation
import Combine
import UIKit
import HealthKit
import ForgeCore
#if canImport(FoundationModels)
import FoundationModels
#endif

extension AppStore {

    func refreshDailyData() async {
        let previous = refreshDailyDataTail
        let task = Task { @MainActor in
            await previous?.value
            await self.executeRefreshDailyData()
        }
        refreshDailyDataTail = task
        await task.value
    }

    private func executeRefreshDailyData() async {
        dataLoadState = .loading
        lastLifeIngestError = nil
        let hk = HealthKitManager.shared
        let seeded = await seedTestReadyHealthKitIfNeeded()
        let authorized = await hk.checkAuthorizationStatus()
        healthKitLive = authorized

        if authorized {
            await hk.refreshHydration()
            if let snapshot = await hk.fetchRecentSnapshot(), snapshot.hasData {
                updateMetrics(
                    steps: snapshot.steps,
                    activeCalories: snapshot.activeCalories,
                    hrv: snapshot.hrv.map { Int($0) },
                    restingHR: snapshot.restingHeartRate,
                    deepSleep: nil,
                    totalSleep: snapshot.sleepHours.map { Int($0 * 60) }
                )
                if let weight = userProfile.weight {
                    userProfile.weight = weight
                }
            }
        }

        let samples = BiometricsObserveService.shared.samplesFromStore(self)
        _ = await BiometricsObserveService.shared.observe(store: self, samples: samples)

        MenstrualHealthStore.shared.enableForFemaleProfileIfNeeded(gender: userProfile.gender)
        if let sex = userProfile.biologicalSex {
            MenstrualHealthStore.shared.enableForBiologicalSexIfNeeded(sex)
        }
        if MenstrualHealthStore.shared.settings.enabled {
            MenstrualHealthStore.shared.seedTestReadyCycleIfNeeded(
                testReady: AriaService.shouldUseTestReadyDummy
            )
            MenstrualHealthStore.shared.refresh(from: self)
        }

        if !seeded || !hasMeaningfulLifeSignal {
            installFakeHealthPackIfNeeded()
        } else {
            usingTestReadyHealthPack = true
        }
        learnFromFirstHealthConnectIfNeeded()

        await ingestTestReadyCalendarIfNeeded()

        lastMetricsRefresh = Date()
        if todayWorkout == nil || todayWorkout?.exercises.isEmpty == true {
            rebuildTodayPlanFromLife()
        }
        recomputeStreak()
        await flushPendingWidgetWater()
        publishHomeWidgets()
        if TestReadyLaunchPolicy.homeWaitsForMedicationCatalog {
            await MedicationPharmacy.prepare()
        }
        dataLoadState = .loaded
        objectWillChange.send()

        if TestReadyLaunchPolicy.homeWaitsForThirtyDayHealthQueries
            || TestReadyLaunchPolicy.homeWaitsForRemoteDashboard {
            await runBackgroundLifeHydrate(authorized: authorized)
        } else {
            scheduleBackgroundLifeHydrate(authorized: authorized)
        }
    }

    /// 30-day history and remote dashboard after Home is already on screen.
    private func scheduleBackgroundLifeHydrate(authorized: Bool) {
        guard backgroundLifeHydrateTask == nil else { return }
        backgroundLifeHydrateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.backgroundLifeHydrateTask = nil }
            await self.runBackgroundLifeHydrate(authorized: authorized)
        }
    }

    private func runBackgroundLifeHydrate(authorized: Bool) async {
        let hk = HealthKitManager.shared
        if authorized {
            let nights = await HealthKitSleepService.shared.fetchRecentSleepData(days: 30)
            mergeSleepDataLocally(nights)
            let workouts = await hk.fetchWorkoutsForHistory(days: 30)
            mergeWorkoutsFromHealthKit(workouts)
            recomputeStreak()
        }
        if MenstrualHealthStore.shared.settings.enabled {
            await MenstrualHealthStore.shared.quietWeeklyHealthKitSync(force: !authorized)
        }
        await syncHealthBatchAndDashboard()
        await applyRemoteDailyPlan()
        await refreshCoachInsightsIfNeeded()
        publishHomeWidgets()
        objectWillChange.send()
    }

    /// Simulator Test-Ready patch: apply the ForgeCore pack in memory immediately
    /// so Home is not waiting on HealthKit, then write Apple Health in the background.
    @discardableResult
    func seedTestReadyHealthKitIfNeeded() async -> Bool {
        #if targetEnvironment(simulator)
        let isSimulator = true
        #else
        let isSimulator = false
        #endif
        let alreadyAuthorized = await HealthKitManager.shared.checkAuthorizationStatus()
        guard FakeHealthPack.shouldSeedHealthKit(
            debugBuild: ForgeAuthPolicy.isDebugBuild,
            testReady: AriaService.shouldUseTestReadyDummy,
            isSimulator: isSimulator,
            healthAuthorized: alreadyAuthorized
        ) else { return false }
        let seed = Self.testReadySessionSeed
        if !TestReadyLaunchPolicy.shouldRewrite(
            installedSeed: HealthKitManager.shared.installedTestReadySeed,
            sessionSeed: seed
        ) {
            usingTestReadyHealthPack = true
            recordLifeIngestError(HealthKitManager.shared.lastPackWriteError)
            return true
        }
        let pack = await Task.detached(priority: .utility) {
            FakeHealthPack.generate(seed: seed)
        }.value
        apply(pack)
        usingTestReadyHealthPack = true
        // Home must not wait on the Health sheet or the pack rewrite.
        // Connect Health during onboarding is the user-initiated Allow path.
        if TestReadyLaunchPolicy.homeWaitsForHealthKitAuthorizationSheet {
            do {
                try await HealthKitManager.shared.requestTestReadyPackAuthorization()
            } catch {
                recordLifeIngestError(LifeIngestError.explain(
                    error,
                    doing: "Couldn't authorize the Test-Ready Health pack"
                ))
                return true
            }
        }
        if TestReadyLaunchPolicy.homeWaitsForHealthKitPackWrite {
            do {
                try await HealthKitManager.shared.replaceTestReadyPack(pack)
                recordLifeIngestError(HealthKitManager.shared.lastPackWriteError)
            } catch {
                recordLifeIngestError(LifeIngestError.explain(
                    error,
                    doing: "Couldn't write the Test-Ready Health pack into Apple Health"
                ))
            }
            return true
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await HealthKitManager.shared.replaceTestReadyPack(pack)
                self.recordLifeIngestError(HealthKitManager.shared.lastPackWriteError)
            } catch {
                self.recordLifeIngestError(LifeIngestError.explain(
                    error,
                    doing: "Couldn't write the Test-Ready Health pack into Apple Health"
                ))
            }
        }
        return true
    }

    /// Test-ready EventKit writes land on a Forge-owned calendar only.
    /// Tags that follow are classified kinds + busy windows — never titles.
    func ingestTestReadyCalendarIfNeeded() async {
        await CalendarManager.shared.ingestUpcomingIfAuthorized()
        recordLifeIngestError(CalendarManager.shared.lastSeedError)
        let tags = CalendarManager.shared.calendarTags
        guard !tags.isEmpty else { return }
        AriaContextStore.shared.applyCalendarIngestTags(tags)
    }

    /// Remember what Apple Health just taught ARIA. Once per fingerprint so
    /// reseeding the sim pack does not spam the same insight.
    func learnFromFirstHealthConnectIfNeeded() {
        let snap = AriaFirstHealthBriefing.snapshot(from: self)
        guard snap.fromHealthKit, hasMeaningfulLifeSignal else { return }
        let token = AriaFirstHealthBriefing.fingerprint(snap)
        let key = "forge.aria.learnedHealthConnect.v1"
        if UserDefaults.standard.string(forKey: key) == token { return }
        for insight in AriaFirstHealthBriefing.learnInsights(snapshot: snap) {
            AriaContextStore.shared.addInsight(insight)
            rememberDurable(insight)
        }
        UserDefaults.standard.set(token, forKey: key)
    }

    func mergeWorkoutsFromHealthKit(_ workouts: [HKWorkout]) {
        guard !workouts.isEmpty else { return }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        var merged = Dictionary(workoutHistory.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        for workout in workouts {
            let date = String(formatter.string(from: workout.startDate).prefix(10))
            let name = (workout.metadata?[HealthKitManager.testReadySessionNameKey] as? String)
                ?? (workout.metadata?[HKMetadataKeyWorkoutBrandName] as? String)
                ?? "Session"
            let intensityRaw = workout.metadata?[HealthKitManager.testReadyIntensityKey] as? String
            let volume = Int(workout.metadata?[HealthKitManager.testReadyVolumeKey] as? String ?? "") ?? 0
            let type: WorkoutType = {
                switch workout.workoutActivityType {
                case .traditionalStrengthTraining: return .strength
                case .running, .walking, .cycling: return .cardio
                case .highIntensityIntervalTraining: return .hiit
                case .yoga: return .yoga
                case .flexibility, .cooldown: return .mobility
                case .basketball, .soccer, .tennis, .volleyball, .golf, .hiking,
                     .americanFootball, .lacrosse, .rugby, .boxing, .baseball:
                    return .sportSpecific
                default: return .strength
                }
            }()
            let record = WorkoutHistory(
                id: workout.uuid.uuidString,
                date: date,
                name: name,
                type: type,
                duration: max(1, Int((workout.duration / 60).rounded())),
                volume: volume,
                intensity: WorkoutIntensity(rawValue: intensityRaw ?? "") ?? .moderate
            )
            merged[record.id] = record
        }
        workoutHistory = merged.values.sorted { $0.date > $1.date }
    }

    /// SimRunner-shaped 30-day pack from ForgeCore. In-memory fallback when
    /// HealthKit cannot be written. Real HealthKit samples always win.
    /// Seed for this run's Test-Ready dataset.
    ///
    /// Stable for the process so Home and Lifestyle share one pack. A new
    /// Simulator launch mints a new persona. Tests that need a fixed shape
    /// pass their own seed into `FakeHealthPack.generate`.
    static var testReadySessionSeed: Int {
        TestReadyLaunchPolicy.sessionSeed(now: Date(), defaults: .standard) {
            let time = UInt64(max(0, Date().timeIntervalSince1970 * 1_000))
            return Int(truncatingIfNeeded: time ^ UInt64(truncatingIfNeeded: UUID().hashValue))
        }
    }

    /// Turn the pack's lifestyle history into tags ARIA already reads.
    ///
    /// Without this the markers and social events are generated, written and
    /// never seen — thirty days of evenings that no surface can reach, which is
    /// the same failure as a widget that is not in its bundle. `lifestyleTags`
    /// is the existing channel to both the local path and the backend, so the
    /// history travels the same way every other lifestyle signal does.
    static func lifestyleTags(from pack: FakeHealthPack) -> [String] {
        var tags: [String] = []
        tags.append("persona:\(pack.personaLabel)")
        if let today = pack.today {
            if !today.felt.isEmpty { tags.append("felt:\(today.felt)") }
            if !today.storyLine.isEmpty { tags.append("story:\(today.storyLine)") }
            if let cycle = today.cycle {
                tags.append("cycle:phase:\(cycle.phase)")
                tags.append("cycle:day:\(cycle.dayInCycle)")
                if cycle.isBleeding { tags.append("cycle:bleeding") }
            }
        }

        // Last night is the one the user is living in right now, so it gets to
        // be specific rather than aggregate.
        if let recent = pack.days.dropFirst().first, let event = recent.social.first {
            tags.append("lastnight:\(event.kind.rawValue)")
            if event.drinks > 0 { tags.append("lastnight:drinks:\(event.drinks)") }
            if event.ranLate { tags.append("lastnight:late") }
        }

        // Where the month actually went, most-visited first. Counts, not
        // coordinates: ARIA should know this person trains and eats out, not
        // where they were on the 14th.
        var placeCounts: [String: Int] = [:]
        var drinkingNights = 0
        var socialNights = 0
        for day in pack.days {
            for marker in day.markers {
                placeCounts[marker.kind.rawValue, default: 0] += 1
            }
            if let event = day.social.first {
                socialNights += 1
                if event.drinks >= 2 { drinkingNights += 1 }
            }
        }
        for (kind, count) in placeCounts.sorted(by: { $0.value > $1.value }).prefix(4) {
            tags.append("place:\(kind):\(count)")
        }
        tags.append("social:nights:\(socialNights)")
        if drinkingNights > 0 { tags.append("social:drinking_nights:\(drinkingNights)") }

        let workDays = placeCounts["work"] ?? 0
        if workDays >= pack.days.count / 3 { tags.append("routine:office_regular") }
        if (placeCounts["travel"] ?? 0) >= 2 { tags.append("routine:travels") }

        return tags
    }

    func installFakeHealthPackIfNeeded() {
        let testReady = AriaService.shouldUseTestReadyDummy
        guard FakeHealthPack.shouldInstall(
            debugBuild: ForgeAuthPolicy.isDebugBuild,
            testReady: testReady,
            hasRealHealthSignal: hasMeaningfulLifeSignal
        ) else {
            return
        }
        apply(FakeHealthPack.generate(seed: Self.testReadySessionSeed))
    }

    func apply(_ pack: FakeHealthPack) {
        guard let today = pack.today else { return }
        usingTestReadyHealthPack = true
        dailyMetrics = DailyMetrics(
            steps: today.steps,
            activeCalories: today.activeCalories,
            hrv: today.hrvMs,
            restingHR: today.restingHR,
            deepSleep: Int(today.night.deepMinutes.rounded()),
            totalSleep: Int(today.night.totalMinutes.rounded())
        )
        let score = ReadinessCalculator.score(from: pack.readinessInputs)
        readiness = ReadinessData(
            overall: score.overall,
            sleepQuality: score.sleepQuality,
            recoveryScore: score.recovery,
            stressLevel: max(0, 100 - score.recovery),
            energyBank: score.overall
        )
        sleepData = pack.days.map { day in
            SleepData(
                date: day.isoDate,
                totalHours: day.night.totalMinutes / 60,
                deepMinutes: Int(day.night.deepMinutes.rounded()),
                remMinutes: Int(day.night.remMinutes.rounded()),
                lightMinutes: Int(day.night.coreMinutes.rounded()),
                awakeMinutes: Int(day.night.awakeMinutes.rounded()),
                score: day.sleepScore,
                onset: day.night.start,
                wake: day.night.end
            )
        }
        AriaContextStore.shared.applyLifestyleHistoryTags(Self.lifestyleTags(from: pack))

        workoutHistory = pack.days.compactMap { day in
            guard let session = day.workout else { return nil }
            return WorkoutHistory(
                id: "fake-\(day.isoDate)-\(session.name)",
                date: day.isoDate,
                name: session.name,
                type: WorkoutType(rawValue: session.type.rawValue) ?? .strength,
                duration: session.durationMinutes,
                volume: session.volume,
                intensity: WorkoutIntensity(rawValue: session.intensity) ?? .moderate
            )
        }
        if HealthKitManager.shared.todayWaterMilliliters == 0 {
            HealthKitManager.shared.installTestReadyHydration(milliliters: today.hydrationMl)
        }
    }

    /// Sleep, HRV, or any Health write that means today's number is theirs — not a blank launch.
    var hasMeaningfulLifeSignal: Bool {
        dailyMetrics.totalSleep > 0
            || dailyMetrics.hrv > 0
            || sleepData.contains(where: { $0.totalHours > 0 })
            || (healthKitLive && (dailyMetrics.steps > 0 || dailyMetrics.activeCalories > 0))
    }

    /// Rebuild today's session from readiness, cycle, equipment, constraints, theme.
    /// Skipped while a session is in progress so we don't yank the floor out.
    func rebuildTodayPlanFromLife() {
        guard !isWorkoutActive else { return }
        let plan = AriaPlanEngine.evaluate(
            input: "Build today's session from my sleep, readiness, cycle, equipment, and the time I actually have.",
            context: makeTrainerContext()
        )
        var workout = plan.workoutPlan
        let dayKey: String = {
            let f = DateFormatter()
            f.calendar = Calendar.current
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: Date())
        }()
        workout.id = "life-\(dayKey)-\(workout.name)"
        todayWorkout = workout
    }

    /// Open a specific weekday (or yesterday) from the walking week.
    func adoptSplitSession(weekday: Int? = nil, replayPrior: Bool = false) {
        guard !isWorkoutActive else { return }
        let input: String
        if replayPrior {
            input = "Do yesterday's session"
        } else if let weekday, (0...6).contains(weekday) {
            input = "Do \(WeeklySplit.dayNames[weekday])'s session"
        } else {
            input = "Build today's session from my sleep, readiness, cycle, equipment, and the time I actually have."
        }
        let plan = AriaPlanEngine.evaluate(input: input, context: makeTrainerContext(query: input))
        var workout = plan.workoutPlan
        let dayKey: String = {
            let f = DateFormatter()
            f.calendar = Calendar.current
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: Date())
        }()
        workout.id = "life-\(dayKey)-\(workout.name)"
        todayWorkout = workout
    }

    func syncHealthBatchAndDashboard() async {
        lastMetricsRefresh = Date()
        guard ForgeCloudSync.shared.isRemoteEligible else { return }
        do {
            let metrics = ForgeCloudSync.healthMetrics(from: self)
            if !metrics.isEmpty {
                _ = try await ForgeCloudSync.shared.postHealthBatch(metrics)
            }
            let dashboard = try await ForgeCloudSync.shared.fetchDashboard()
            applyDashboard(dashboard)
            lastCloudSyncError = nil
            lastCloudSyncAt = Date()
        } catch let failure as ForgeAPI.Failure {
            if !failure.deservesOfflineFallback {
                lastCloudSyncError = failure.userMessage
            }
        } catch {
            lastCloudSyncError = LifeIngestError.explain(
                error,
                doing: "Couldn't sync today's dashboard"
            )
        }
    }

    func applyRemoteDailyPlan() async {
        guard ForgeCloudSync.shared.isRemoteEligible, !isWorkoutActive else { return }
        do {
            let plan = try await ForgeCloudSync.shared.generateWorkoutPlan()
            applyCoachWorkoutPlan(plan)
            lastCloudSyncError = nil
        } catch let failure as ForgeAPI.Failure {
            if !failure.deservesOfflineFallback {
                lastCloudSyncError = failure.userMessage
            }
        } catch {
            lastCloudSyncError = LifeIngestError.explain(
                error,
                doing: "Couldn't load today's training plan"
            )
        }
    }

    func refreshCoachInsightsIfNeeded() async {
        guard ForgeCloudSync.shared.isRemoteEligible else { return }
        if remoteSleepInsight == nil {
            if let insight = try? await ForgeCloudSync.shared.fetchSleepInsight(), !insight.insight.isEmpty {
                remoteSleepInsight = insight.insight
            }
        }
        if remoteProgressReview == nil {
            if let review = try? await ForgeCloudSync.shared.fetchProgressReview(), !review.review.isEmpty {
                remoteProgressReview = review.review
            }
        }
    }

    func applyDashboard(_ dashboard: CloudDashboardToday) {
        if let readinessPayload = dashboard.readiness, readinessPayload.isUsable, let overall = readinessPayload.overall {
            readiness.overall = overall
            if let value = readinessPayload.sleepQuality { readiness.sleepQuality = value }
            if let value = readinessPayload.recoveryScore { readiness.recoveryScore = value }
            if let value = readinessPayload.stressLevel { readiness.stressLevel = value }
            if let value = readinessPayload.energyBank { readiness.energyBank = value }
            usingTestReadyHealthPack = false
        }

        var sources = dashboard.dailyMetrics?.sources ?? []
        sources.append(contentsOf: dashboard.connections.map(\.provider).filter { !$0.isEmpty })
        if healthKitLive { sources.insert("apple-health", at: 0) }
        var seen = Set<String>()
        metricSources = sources.filter { seen.insert($0).inserted }

        if let metrics = dashboard.dailyMetrics {
            let preferServer = !healthKitLive
            if preferServer || dailyMetrics.steps == 0, let value = metrics.steps { dailyMetrics.steps = value }
            if preferServer || dailyMetrics.activeCalories == 0, let value = metrics.activeCalories { dailyMetrics.activeCalories = value }
            if preferServer || dailyMetrics.hrv == 0, let value = metrics.hrv { dailyMetrics.hrv = value }
            if preferServer || dailyMetrics.restingHR == 0, let value = metrics.restingHR { dailyMetrics.restingHR = value }
            if preferServer || dailyMetrics.deepSleep == 0, let value = metrics.deepSleep { dailyMetrics.deepSleep = value }
            if preferServer || dailyMetrics.totalSleep == 0, let value = metrics.totalSleep { dailyMetrics.totalSleep = value }
        }

        if !isWorkoutActive, let plan = dashboard.todayWorkout, !plan.exercises.isEmpty {
            todayWorkout = mapCloudWorkoutPlan(plan)
        }

        if !healthKitLive {
            let nights = dashboard.recentSleep.compactMap { night -> SleepData? in
                guard !night.date.isEmpty else { return nil }
                return SleepData(
                    date: night.date,
                    totalHours: night.totalHours,
                    deepMinutes: night.deepMinutes,
                    remMinutes: night.remMinutes,
                    lightMinutes: night.lightMinutes,
                    awakeMinutes: night.awakeMinutes,
                    score: night.score
                )
            }
            mergeSleepDataLocally(nights)

            if workoutHistory.isEmpty {
                workoutHistory = dashboard.recentWorkouts.map { item in
                    WorkoutHistory(
                        id: item.id,
                        date: item.date,
                        name: item.name,
                        type: WorkoutType(rawValue: item.type ?? "") ?? .strength,
                        duration: item.duration,
                        volume: item.volume,
                        intensity: WorkoutIntensity(rawValue: item.intensity ?? "") ?? .moderate
                    )
                }
            }
        }

        if personalRecords.isEmpty {
            personalRecords = dashboard.personalRecords.filter { !$0.exercise.isEmpty }.map { record in
                PersonalRecord(
                    exercise: record.exercise,
                    value: record.value,
                    unit: record.unit,
                    date: record.date
                )
            }
        }
    }

    func applyCoachWorkoutPlan(_ plan: CloudCoachWorkoutPlan) {
        guard !isWorkoutActive else { return }
        if let remote = plan.todayPlan, !remote.exercises.isEmpty {
            todayWorkout = mapCloudWorkoutPlan(remote)
            return
        }
        if todayWorkout == nil {
            rebuildTodayPlanFromLife()
        }
        if var workout = todayWorkout {
            if let name = plan.todayPlan?.name, !name.isEmpty {
                workout.name = name
            } else if let focus = plan.baseline?.focus, !focus.isEmpty {
                workout.name = "\(focus.capitalized) Focus"
            }
            if let intensity = plan.todayPlan?.intensity ?? plan.baseline?.intensity,
               let mapped = WorkoutIntensity(rawValue: intensity) {
                workout.intensity = mapped
            }
            todayWorkout = workout
        }
    }

    func mapCloudWorkoutPlan(_ plan: CloudWorkoutPlanDTO) -> WorkoutPlan {
        let exercises = plan.exercises.enumerated().map { index, move in
            Exercise(
                id: move.id ?? "cloud-\(index)",
                name: move.name,
                sets: move.sets,
                reps: move.reps,
                weight: move.weight,
                restSeconds: move.restSeconds ?? 60,
                notes: move.notes
            )
        }
        return WorkoutPlan(
            id: plan.id ?? "cloud-today",
            name: plan.name,
            type: WorkoutType(rawValue: plan.type ?? "") ?? .strength,
            duration: plan.duration ?? max(20, exercises.count * 8),
            intensity: WorkoutIntensity(rawValue: plan.intensity ?? "") ?? .moderate,
            exercises: exercises
        )
    }

    /// Write the session from *this* moment's life, then open Train.
    /// Recovery and "build" both land here — not in chat.
    func startLifeShapedSession() {
        if !isWorkoutActive {
            rebuildTodayPlanFromLife()
            startWorkout()
        }
        activeTab = .workout
    }

    /// Update user metrics (typically from HealthKit integration)
    func updateMetrics(
        steps: Int? = nil,
        activeCalories: Int? = nil,
        hrv: Int? = nil,
        restingHR: Int? = nil,
        deepSleep: Int? = nil,
        totalSleep: Int? = nil
    ) {
        if let steps = steps { dailyMetrics.steps = steps }
        if let activeCalories = activeCalories { dailyMetrics.activeCalories = activeCalories }
        if let hrv = hrv { dailyMetrics.hrv = hrv }
        if let restingHR = restingHR { dailyMetrics.restingHR = restingHR }
        if let deepSleep = deepSleep { dailyMetrics.deepSleep = deepSleep }
        if let totalSleep = totalSleep { dailyMetrics.totalSleep = totalSleep }
        
        // Recalculate readiness based on new metrics
        recalculateReadiness()
    }

    /// Recalculate readiness score based on current metrics
    private func recalculateReadiness() {
        // Simplified readiness calculation
        // In production, this would use more sophisticated algorithms
        
        let sleepScore = calculateSleepScore()
        let hrvScore = calculateHRVScore()
        let restingHRScore = calculateRestingHRScore()
        
        readiness.overall = (sleepScore + hrvScore + restingHRScore) / 3
        readiness.sleepQuality = sleepScore
        readiness.recoveryScore = (hrvScore + restingHRScore) / 2
    }

    private func calculateSleepScore() -> Int {
        let totalHours = Double(dailyMetrics.totalSleep) / 60
        let deepMinutes = dailyMetrics.deepSleep
        
        var score = 0
        
        // Total sleep score (0-50 points)
        if totalHours >= 7.5 {
            score += 50
        } else if totalHours >= 7 {
            score += 40
        } else if totalHours >= 6 {
            score += 25
        } else {
            score += 10
        }
        
        // Deep sleep score (0-50 points)
        if deepMinutes >= 90 {
            score += 50
        } else if deepMinutes >= 70 {
            score += 40
        } else if deepMinutes >= 50 {
            score += 25
        } else {
            score += 10
        }
        
        return min(score, 100)
    }

    private func calculateHRVScore() -> Int {
        // HRV scoring (typical range: 20-100ms)
        let hrv = dailyMetrics.hrv
        
        if hrv >= 60 {
            return 90
        } else if hrv >= 50 {
            return 80
        } else if hrv >= 40 {
            return 65
        } else if hrv >= 30 {
            return 50
        } else {
            return 30
        }
    }

    private func calculateRestingHRScore() -> Int {
        // Resting HR scoring (lower is better for athletes)
        let hr = dailyMetrics.restingHR
        
        if hr <= 55 {
            return 95
        } else if hr <= 60 {
            return 85
        } else if hr <= 65 {
            return 75
        } else if hr <= 70 {
            return 60
        } else {
            return 40
        }
    }
    
    // MARK: - Profile Management

    func connectHealthDevice(_ id: String) {
        var ids = HealthDeviceCatalog.migrateStoredIDs(userProfile.connectedDevices)
        if !ids.contains(id) { ids.append(id) }
        userProfile.connectedDevices = ids
    }

    func disconnectHealthDevice(_ id: String) {
        var ids = HealthDeviceCatalog.migrateStoredIDs(userProfile.connectedDevices)
        ids.removeAll { $0 == id }
        userProfile.connectedDevices = ids
    }

    func mergeSleepDataLocally(_ local: [SleepData]) {
        guard !local.isEmpty else { return }
        var merged = Dictionary(sleepData.map { ($0.date, $0) }, uniquingKeysWith: { _, new in new })
        for night in local {
            merged[night.date] = night
        }
        sleepData = merged.values.sorted { $0.date > $1.date }
        HealthKitSleepService.shared.rememberSleepSignals(from: sleepData)
        Task { await SleepAlarmScheduler.sync(ForgeAlarmStore.shared.alarms) }
        if let latest = sleepData.first {
            dailyMetrics.totalSleep = Int(latest.totalHours * 60)
            dailyMetrics.deepSleep = latest.deepMinutes
            recalculateReadiness()
        }
    }

    func addSleepData(_ sleep: SleepData) {
        sleepData.insert(sleep, at: 0)
        
        // Update daily metrics
        dailyMetrics.totalSleep = Int(sleep.totalHours * 60)
        dailyMetrics.deepSleep = sleep.deepMinutes
        
        // Recalculate readiness
        recalculateReadiness()
    }
    
    // MARK: - Personal Records
}
