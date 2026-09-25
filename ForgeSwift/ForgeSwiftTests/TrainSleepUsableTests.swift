import XCTest
import ForgeCore
@testable import ForgeSwift

/// Locks Train auto-scale, extra-set, and nav copy so the tab stays a session
/// — not a catalog — and Sleep's empty state stays honest.
@MainActor
final class TrainSleepUsableTests: XCTestCase {

    func testTrainTabIsNotNamedWorkout() {
        XCTAssertEqual(TabItem.workout.label, "Train")
        XCTAssertEqual(ForgePrimaryDestination.workout.title, "Train")
    }

    func testAutoScaleCutsVolumeWhenReadinessIsLow() {
        let plan = samplePlan(sets: 4, weight: 135, duration: 45)
        let low = ReadinessData(overall: 40, sleepQuality: 40, recoveryScore: 40, stressLevel: 70, energyBank: 30)
        let scaled = AdaptiveEngine.apply(to: plan, readiness: low, experience: .intermediate)
        XCTAssertTrue(scaled.autoScaled)
        XCTAssertLessThan(scaled.exercises[0].sets, 4)
        XCTAssertLessThan(scaled.exercises[0].weight ?? 135, 135)
        XCTAssertEqual(scaled.scaleHeadline, "Recovery day protocol")
    }

    func testAutoScaleLeavesOnPlanUnmodified() {
        let plan = samplePlan(sets: 4, weight: 135, duration: 45)
        let mid = ReadinessData(overall: 75, sleepQuality: 75, recoveryScore: 75, stressLevel: 40, energyBank: 70)
        let scaled = AdaptiveEngine.apply(to: plan, readiness: mid, experience: .intermediate)
        XCTAssertFalse(scaled.autoScaled)
        XCTAssertEqual(scaled.exercises[0].sets, 4)
        XCTAssertEqual(scaled.exercises[0].weight, 135)
        XCTAssertEqual(scaled.scaleHeadline, "On plan")
    }

    func testAddFeltSetDoesNotUndoScale() {
        let store = AppStore()
        store.todayWorkout = samplePlan(sets: 3, weight: 100, duration: 30)
        store.addFeltSet(exerciseId: "bench")
        XCTAssertEqual(store.todayWorkout?.exercises.first?.sets, 4)
        store.addFeltSet(exerciseId: "missing")
        XCTAssertEqual(store.todayWorkout?.exercises.first?.sets, 4)
    }

    func testTrainDayCallRestWinsOverHighReadiness() {
        XCTAssertEqual(TrainDayCall.resolve(readiness: 90, isRestDay: true, intensity: .high), .rest)
        XCTAssertEqual(TrainDayCall.rest.cta, "Optional easy work")
    }

    func testTrainDayCallRecoverWhenReadinessIsLow() {
        XCTAssertEqual(TrainDayCall.resolve(readiness: 40, isRestDay: false, intensity: .high), .recover)
        XCTAssertEqual(TrainDayCall.resolve(readiness: 80, isRestDay: false, intensity: .high), .train)
        XCTAssertEqual(TrainDayCall.resolve(readiness: 62, isRestDay: false, intensity: .high), .easy)
    }

    func testAgingQuestionIsNotClassifiedAsTraining() {
        let gen = RuleBasedResponseGenerator()
        XCTAssertEqual(gen.domain(of: "what's my training age?"), .aging)
        XCTAssertEqual(gen.domain(of: "how old am I compared to fitness age"), .aging)
        XCTAssertEqual(gen.domain(of: "what should I train today?"), .training)
    }

    func testAgingLiveFetchIsAllowedWithoutLocalTestingGate() {
        XCTAssertTrue(
            AriaWebResearch.liveFetchAllowed(question: "what's my training age?", domainRawValue: "lifestyle")
        )
        XCTAssertTrue(
            AriaWebResearch.liveFetchAllowed(question: "hello", domainRawValue: "aging")
        )
        XCTAssertTrue(
            AriaWebResearch.isResearchWorthy(text: "what's my fitness age?", leadingDomain: .lifestyle)
        )
        XCTAssertTrue(
            AriaWebResearch.isDummyResearchWorthy(text: "VO2 max cardiorespiratory fitness")
        )
    }

    func testVendorAgesReachLifestyleAndTrainBridge() {
        AgingVendorStore.replaceAll([
            AgingVendorAge(kind: .fitness, years: 32, confidence: 0.9, source: "garmin"),
            AgingVendorAge(kind: .inner, years: 33, confidence: 0.8, source: "ultrahuman")
        ])
        defer { AgingVendorStore.replaceAll([]) }
        let snap = AgingBridge.snapshot(age: 38, sexFemale: false, stats: nil)
        XCTAssertLessThan(snap.biologicalAge ?? 99, 38)
        XCTAssertTrue(snap.sources.contains { $0.contains("garmin") })
        XCTAssertTrue(snap.hasComparison)
    }

    func testOpenTrainHomeDoesNotStartTheWorkout() {
        let store = AppStore()
        store.todayWorkout = samplePlan(sets: 3, weight: 100, duration: 30)
        store.openTrainHome()
        XCTAssertFalse(store.isWorkoutActive)
        XCTAssertEqual(store.activeTab, .workout)
        XCTAssertNotNil(store.todayWorkout)
    }

    func testLifeShapedSessionLandsOnTrainIdle() {
        let store = AppStore()
        store.startLifeShapedSession()
        XCTAssertFalse(store.isWorkoutActive)
        XCTAssertEqual(store.activeTab, .workout)
        XCTAssertNotNil(store.todayWorkout)
    }

    func testHomePrimaryActionOpensSessionInsteadOfStarting() {
        let action = HomePrimaryAction.startWorkout(id: "p", name: "Push")
        XCTAssertFalse(action.title.localizedCaseInsensitiveContains("start"))
        XCTAssertTrue(action.title.localizedCaseInsensitiveContains("session"))
        XCTAssertEqual(action.icon, "dumbbell.fill")
    }

    func testWriteTodaysSessionDoesNotStartTheWorkout() {
        let store = AppStore()
        store.rebuildTodayPlanFromLife()
        XCTAssertFalse(store.isWorkoutActive)
        XCTAssertNotNil(store.todayWorkout)
    }

    func testSleepEmptyCopyNeverAsksAriaWhenThereIsNoNight() {
        let copy = HealthKitSleepService.dayEmptyCopy(healthConnected: true)
        XCTAssertFalse(copy.cta.localizedCaseInsensitiveContains("ask"))
        XCTAssertTrue(copy.message.localizedCaseInsensitiveContains("apple health"))
    }

    func testHomeEasySessionCopyIsCoachNotClinical() {
        let store = AppStore()
        store.dailyMetrics.hrv = 55
        store.readiness.overall = 40
        let action = HomePrimaryAction.resolve(store: store)
        XCTAssertEqual(action.title, HomeCoachCopy.easySessionTitle)
        guard case .recoveryDay(let reason) = action else {
            return XCTFail("low readiness with a life signal should be an easy day")
        }
        for banned in HomeCoachCopy.bannedPhrases {
            XCTAssertFalse(reason.localizedCaseInsensitiveContains(banned), reason)
            XCTAssertFalse(action.title.localizedCaseInsensitiveContains(banned))
        }
        XCTAssertEqual(reason, HomeCoachCopy.easyDayLow)
    }

    func testHomeCoachCopyNeverUsesBannedPhrases() {
        let samples = [
            HomeCoachCopy.easySessionTitle,
            HomeCoachCopy.easyDayGuidance,
            HomeCoachCopy.easyDayLow,
            HomeCoachCopy.pulledBack(score: 62),
            HomeReadiness.label(40),
            HomeReadiness.voiceOverLabel(72),
        ]
        for sample in samples {
            for banned in HomeCoachCopy.bannedPhrases {
                XCTAssertFalse(sample.localizedCaseInsensitiveContains(banned), sample)
            }
        }
        XCTAssertEqual(HomeReadiness.label(90), "Peak")
        XCTAssertEqual(HomeReadiness.voiceOverLabel(72), "Readiness 72 out of 100, Good")
    }

    func testHomeTrendSeriesNeedsThreeNightsAndClampsScores() {
        XCTAssertTrue(HomeTrendSeries.points(from: [
            SleepData(date: "2026-09-24", totalHours: 7, deepMinutes: 60, remMinutes: 80, lightMinutes: 200, awakeMinutes: 20, score: 70),
            SleepData(date: "2026-09-25", totalHours: 7, deepMinutes: 60, remMinutes: 80, lightMinutes: 200, awakeMinutes: 20, score: 80),
        ], now: fridaySep25).isEmpty)

        let nights = [
            SleepData(date: "2026-09-25", totalHours: 7.2, deepMinutes: 70, remMinutes: 90, lightMinutes: 210, awakeMinutes: 15, score: 50),
            SleepData(date: "2026-09-24", totalHours: 7.2, deepMinutes: 70, remMinutes: 90, lightMinutes: 210, awakeMinutes: 15, score: 140),
            SleepData(date: "2026-09-23", totalHours: 6.8, deepMinutes: 50, remMinutes: 80, lightMinutes: 200, awakeMinutes: 25, score: 90),
            SleepData(date: "2026-09-22", totalHours: 6.1, deepMinutes: 40, remMinutes: 70, lightMinutes: 190, awakeMinutes: 30, score: 10),
        ]
        let snapshot = HomeTrendSeries.snapshot(from: nights, now: fridaySep25)
        let points = snapshot.points
        XCTAssertEqual(points.map(\.score), [30, 90, 100])
        XCTAssertEqual(points.map(\.rawScore), [10, 90, 140])
        XCTAssertEqual(HomeTrendSeries.average(points), 73)
        XCTAssertEqual(HomeTrendSeries.rawAverage(points), 80)

        let calendar = Calendar.current
        XCTAssertEqual(points.map { calendar.component(.day, from: $0.date) }, [22, 23, 24])
        XCTAssertEqual(points.map { calendar.component(.month, from: $0.date) }, [9, 9, 9])
        XCTAssertEqual(snapshot.missingNights, 4)
        XCTAssertFalse(points.contains { calendar.component(.day, from: $0.date) == 25 })

        let spoken = HomeTrendSeries.accessibilitySummary(snapshot)
        XCTAssertTrue(spoken.hasPrefix("Sleep score, last seven nights"), spoken)
        XCTAssertTrue(spoken.contains("Latest 140"), spoken)
        XCTAssertTrue(spoken.contains("average 80"), spoken)
        XCTAssertTrue(spoken.contains("4 nights missing"), spoken)
        XCTAssertFalse(spoken.contains("skipped"), spoken)
        XCTAssertEqual(HomeTrendSeries.headerTitle, "SLEEP · LAST 7 NIGHTS")
        XCTAssertEqual(HomeTrendSeries.trendWindowDays, 7)
        XCTAssertEqual(HomeTrendSeries.trendWindowAnchor, "lastNight")
        XCTAssertEqual(HomeTrendSeries.trendPoints, "window")
        XCTAssertEqual(HomeTrendSeries.loadingVoiceOver, "Sleep, last seven nights, loading")
        XCTAssertEqual(HomeTrendSeries.expandHint, "Shows more detail")
        XCTAssertGreaterThanOrEqual(HomeMetrics.heroFieldSize, 90)
        XCTAssertGreaterThanOrEqual(HomeMetrics.heroFieldSize, AriaRingFieldGeometry.heroMinimumSize)
        XCTAssertEqual(HomeRingField.tickHz, 12, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(HomeRingField.tickHz, 12)
        XCTAssertEqual(HomeRingField.tickInterval, 1.0 / 12.0, accuracy: 0.0001)
    }

    func testHomeTrendSeriesDropsUnparseableDatesWithoutCountingThem() {
        let nights = [
            SleepData(date: "2026-09-25", totalHours: 7.2, deepMinutes: 70, remMinutes: 90, lightMinutes: 210, awakeMinutes: 15, score: 80),
            SleepData(date: "not-a-date", totalHours: 6.0, deepMinutes: 40, remMinutes: 70, lightMinutes: 180, awakeMinutes: 20, score: 50),
            SleepData(date: "2026-09-23", totalHours: 6.8, deepMinutes: 50, remMinutes: 80, lightMinutes: 200, awakeMinutes: 25, score: 70),
            SleepData(date: "2026-09-22", totalHours: 6.1, deepMinutes: 40, remMinutes: 70, lightMinutes: 190, awakeMinutes: 30, score: 60),
            SleepData(date: "2026-09-21", totalHours: 6.0, deepMinutes: 40, remMinutes: 70, lightMinutes: 185, awakeMinutes: 28, score: 55),
        ]
        let snapshot = HomeTrendSeries.snapshot(from: nights, now: fridaySep25)
        XCTAssertEqual(snapshot.points.map(\.score), [55, 60, 70])
        XCTAssertEqual(snapshot.points.count, 3)
        XCTAssertEqual(snapshot.missingNights, 4)
        XCTAssertNil(HomeTrendSeries.parseNightDate("not-a-date"))

        let spoken = HomeTrendSeries.accessibilitySummary(snapshot)
        XCTAssertTrue(spoken.hasPrefix("Sleep score, last seven nights"), spoken)
        XCTAssertTrue(spoken.contains("4 nights missing"), spoken)
        XCTAssertFalse(spoken.contains("skipped"), spoken)
    }

    func testHomeTrendSeriesMonWedThuGapCountsFourMissingNights() {
        // now = Fri 2026-09-25 → lastNight Thu 24 → window Fri 18 … Thu 24.
        // Present: Mon 21, Wed 23, Thu 24. Missing: 18, 19, 20, 22.
        let nights = [
            SleepData(date: "2026-09-24", totalHours: 7.0, deepMinutes: 60, remMinutes: 80, lightMinutes: 200, awakeMinutes: 20, score: 80),
            SleepData(date: "2026-09-23", totalHours: 6.8, deepMinutes: 50, remMinutes: 80, lightMinutes: 200, awakeMinutes: 25, score: 70),
            SleepData(date: "2026-09-21", totalHours: 6.5, deepMinutes: 45, remMinutes: 75, lightMinutes: 190, awakeMinutes: 30, score: 60),
        ]
        let snapshot = HomeTrendSeries.snapshot(from: nights, now: fridaySep25)
        XCTAssertEqual(snapshot.points.count, 3)
        XCTAssertEqual(snapshot.missingNights, 4)
        XCTAssertEqual(HomeTrendSeries.missingPhrase(snapshot.missingNights), "4 nights missing")
        XCTAssertEqual(HomeTrendSeries.missingPhrase(1), "1 night missing")

        let spoken = HomeTrendSeries.accessibilitySummary(snapshot)
        XCTAssertTrue(spoken.contains("4 nights missing"), spoken)
        XCTAssertFalse(spoken.contains("0 nights missing"), spoken)
        XCTAssertFalse(spoken.contains("skipped"), spoken)
    }

    func testHomeTrendSeriesTrailingGapAfterWatchOffCountsMissingNights() {
        // now = Fri 2026-09-25 → lastNight Thu 24 → window Fri 18 … Thu 24.
        // Points only Fri 18 through Mon 21 (4 nights). Missing Tue 22, Wed 23, Thu 24.
        // Sep 17 is older than the window and must not plot or speak.
        let nights = [
            SleepData(date: "2026-09-21", totalHours: 7.0, deepMinutes: 60, remMinutes: 80, lightMinutes: 200, awakeMinutes: 20, score: 80),
            SleepData(date: "2026-09-20", totalHours: 6.8, deepMinutes: 50, remMinutes: 80, lightMinutes: 200, awakeMinutes: 25, score: 70),
            SleepData(date: "2026-09-19", totalHours: 6.6, deepMinutes: 48, remMinutes: 76, lightMinutes: 195, awakeMinutes: 28, score: 65),
            SleepData(date: "2026-09-18", totalHours: 6.4, deepMinutes: 45, remMinutes: 75, lightMinutes: 190, awakeMinutes: 30, score: 60),
            SleepData(date: "2026-09-17", totalHours: 6.2, deepMinutes: 40, remMinutes: 70, lightMinutes: 180, awakeMinutes: 32, score: 50),
        ]
        let snapshot = HomeTrendSeries.snapshot(from: nights, now: fridaySep25)
        XCTAssertEqual(snapshot.points.count, 4)
        XCTAssertEqual(snapshot.missingNights, 3)
        XCTAssertEqual(HomeTrendSeries.missingPhrase(snapshot.missingNights), "3 nights missing")
        XCTAssertFalse(snapshot.points.contains { Calendar.current.component(.day, from: $0.date) == 17 })
        XCTAssertEqual(
            HomeTrendSeries.lastNight(now: fridaySep25).map { Calendar.current.startOfDay(for: $0) },
            Calendar.current.startOfDay(for: ymd("2026-09-24"))
        )

        let spoken = HomeTrendSeries.accessibilitySummary(snapshot)
        XCTAssertTrue(spoken.contains("3 nights missing"), spoken)
        XCTAssertFalse(spoken.contains("skipped"), spoken)
        XCTAssertFalse(spoken.contains("50"), spoken)
    }

    func testHomeTrendSeriesFullSevenNightsOmitsMissingPhrase() {
        // Full window is Fri 18 through Thu 24 when now = Fri 25.
        let nights = (18...24).map { day in
            SleepData(
                date: String(format: "2026-09-%02d", day),
                totalHours: 7,
                deepMinutes: 60,
                remMinutes: 80,
                lightMinutes: 200,
                awakeMinutes: 20,
                score: 70 + (day - 18)
            )
        }.reversed()
        let snapshot = HomeTrendSeries.snapshot(from: Array(nights), now: fridaySep25)
        XCTAssertEqual(snapshot.points.count, 7)
        XCTAssertEqual(snapshot.missingNights, 0)
        XCTAssertNil(HomeTrendSeries.missingPhrase(snapshot.missingNights))

        let spoken = HomeTrendSeries.accessibilitySummary(snapshot)
        XCTAssertTrue(spoken.hasPrefix("Sleep score, last seven nights"), spoken)
        XCTAssertFalse(spoken.contains("missing"), spoken)
        XCTAssertFalse(spoken.contains("skipped"), spoken)
    }

    func testHomeTrendSeriesVoiceOverSpeaksRawScoreBelowPlotFloor() {
        let nights = [
            SleepData(date: "2026-09-25", totalHours: 7.0, deepMinutes: 60, remMinutes: 80, lightMinutes: 200, awakeMinutes: 20, score: 99),
            SleepData(date: "2026-09-24", totalHours: 7.0, deepMinutes: 60, remMinutes: 80, lightMinutes: 200, awakeMinutes: 20, score: 70),
            SleepData(date: "2026-09-23", totalHours: 6.8, deepMinutes: 50, remMinutes: 80, lightMinutes: 200, awakeMinutes: 25, score: 65),
            SleepData(date: "2026-09-22", totalHours: 6.1, deepMinutes: 40, remMinutes: 70, lightMinutes: 190, awakeMinutes: 30, score: 22),
        ]
        let snapshot = HomeTrendSeries.snapshot(from: nights, now: fridaySep25)
        XCTAssertEqual(snapshot.points.map(\.rawScore), [22, 65, 70])
        XCTAssertEqual(snapshot.points.map(\.score), [30, 65, 70])
        XCTAssertEqual(snapshot.points[0].score, 30)
        XCTAssertEqual(snapshot.points[0].rawScore, 22)
        XCTAssertFalse(snapshot.points.contains { Calendar.current.component(.day, from: $0.date) == 25 })
        XCTAssertEqual(snapshot.missingNights, 4)

        let spoken = HomeTrendSeries.accessibilitySummary(snapshot)
        let pointLabel = HomeTrendSeries.pointAccessibilityLabel(snapshot.points[0])
        XCTAssertTrue(spoken.contains("22"), spoken)
        XCTAssertTrue(spoken.contains("Latest 70"), spoken)
        XCTAssertFalse(spoken.contains("Latest 99"), spoken)
        XCTAssertFalse(spoken.contains("99"), spoken)
        XCTAssertTrue(pointLabel.hasSuffix(" 22"), pointLabel)
        XCTAssertFalse(pointLabel.contains("30"), pointLabel)
    }

    func testHomeTrendSeriesLastNightJustAfterChicagoMidnightUsesLocalCalendar() {
        var chicago = Calendar(identifier: .gregorian)
        chicago.timeZone = TimeZone(identifier: "America/Chicago")!
        let now = chicago.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 0, minute: 5))!
        let stamp = chicago.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 23, minute: 30))!

        let anchor = HomeTrendSeries.lastNight(now: now, calendar: chicago)
        XCTAssertEqual(chicago.component(.day, from: anchor!), 24)
        XCTAssertEqual(chicago.component(.month, from: anchor!), 9)
        XCTAssertEqual(
            HomeTrendSeries.windowDays(now: now, calendar: chicago).map { chicago.component(.day, from: $0) },
            [18, 19, 20, 21, 22, 23, 24]
        )

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(utc.component(.day, from: stamp), 25, "23:30 Chicago is already 25 in UTC")
        let utcAnchor = HomeTrendSeries.lastNight(now: now, calendar: utc)!
        XCTAssertGreaterThan(
            utc.startOfDay(for: stamp),
            utc.startOfDay(for: utcAnchor),
            "UTC lastNight would drop the Thu 23:30 Chicago stamp"
        )

        let iso = ISO8601DateFormatter()
        iso.timeZone = chicago.timeZone
        iso.formatOptions = [.withInternetDateTime]
        let nights = [
            SleepData(date: iso.string(from: stamp), totalHours: 7.0, deepMinutes: 60, remMinutes: 80, lightMinutes: 200, awakeMinutes: 20, score: 80),
            SleepData(date: "2026-09-23", totalHours: 6.8, deepMinutes: 50, remMinutes: 80, lightMinutes: 200, awakeMinutes: 25, score: 70),
            SleepData(date: "2026-09-22", totalHours: 6.5, deepMinutes: 45, remMinutes: 75, lightMinutes: 190, awakeMinutes: 30, score: 60),
        ]
        let snapshot = HomeTrendSeries.snapshot(from: nights, now: now, calendar: chicago)
        XCTAssertEqual(snapshot.points.count, 3)
        XCTAssertTrue(snapshot.points.contains { chicago.component(.day, from: $0.date) == 24 })
        XCTAssertEqual(chicago.component(.day, from: snapshot.points.last!.date), 24)
        XCTAssertEqual(snapshot.missingNights, 4)
    }

    private var fridaySep25: Date { ymd("2026-09-25") }

    private func ymd(_ raw: String) -> Date {
        DateFormatter.cachedYMD.date(from: raw)!
    }

    private func samplePlan(sets: Int, weight: Int, duration: Int) -> WorkoutPlan {
        WorkoutPlan(
            id: "train-test",
            name: "Push",
            type: .strength,
            duration: duration,
            intensity: .high,
            exercises: [
                Exercise(
                    id: "bench",
                    name: "Bench Press",
                    sets: sets,
                    reps: "8",
                    weight: weight,
                    restSeconds: 90,
                    notes: nil
                )
            ]
        )
    }
}
