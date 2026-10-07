import XCTest
import ForgeCore
@testable import ForgeSwift

/// Locks Today's Progress math, HUD clamp, Lifestyle/At Home placement,
/// and coach copy so Home cannot slide back into a stub.
@MainActor
final class HomeTodayProgressTests: XCTestCase {

    func testEmptyDayIsZeroAndHonest() {
        let snap = TodayProgress.snapshot(TodayProgress.Input(
            readiness: 40,
            sleepHours: nil,
            didTrain: false,
            isWorkoutActive: false,
            hasSession: false,
            waterGlasses: 0,
            steps: 0,
            habitDone: 0,
            habitTotal: 6,
            hasLifeSignal: false
        ))
        XCTAssertEqual(snap.percent, 0)
        XCTAssertEqual(snap.completed, 0)
        XCTAssertEqual(snap.total, TodayProgress.trackCount)
        XCTAssertTrue(snap.empty)
        XCTAssertEqual(snap.vibeLine, TodayProgress.emptyLine)
        XCTAssertTrue(snap.voiceOverLabel.contains("Today's progress 0 out of 100"))
    }

    func testFullDayIsOneHundred() {
        let snap = TodayProgress.snapshot(TodayProgress.Input(
            readiness: 88,
            sleepHours: 7.4,
            didTrain: true,
            isWorkoutActive: false,
            hasSession: true,
            waterGlasses: 2.0,
            steps: 8_400,
            habitDone: 2,
            habitTotal: 6,
            hasLifeSignal: true
        ))
        XCTAssertEqual(snap.percent, 100)
        XCTAssertEqual(snap.completed, 5)
        XCTAssertEqual(snap.vibeLabel, "Peak")
        XCTAssertFalse(snap.empty)
        XCTAssertTrue(snap.tracks.allSatisfy(\.done))
    }

    func testPartialDayCountsSleepAndWaterOnly() {
        let snap = TodayProgress.snapshot(TodayProgress.Input(
            readiness: 72,
            sleepHours: 6.5,
            didTrain: false,
            isWorkoutActive: false,
            hasSession: true,
            waterGlasses: 1.0,
            steps: 0,
            habitDone: 0,
            habitTotal: 6,
            hasLifeSignal: true
        ))
        XCTAssertEqual(snap.completed, 2)
        XCTAssertEqual(snap.percent, 40)
        XCTAssertEqual(snap.vibeLabel, "Good")
        XCTAssertFalse(snap.tracks.first { $0.id == "train" }?.done ?? true)
        XCTAssertTrue(snap.tracks.first { $0.id == "sleep" }?.done ?? false)
    }

    func testActiveSessionCountsAsTrain() {
        let snap = TodayProgress.snapshot(TodayProgress.Input(
            readiness: 70,
            sleepHours: nil,
            didTrain: false,
            isWorkoutActive: true,
            hasSession: true,
            waterGlasses: 0,
            steps: 0,
            habitDone: 0,
            habitTotal: 0,
            hasLifeSignal: true
        ))
        XCTAssertEqual(snap.tracks.first { $0.id == "train" }?.done, true)
        XCTAssertEqual(snap.tracks.first { $0.id == "train" }?.detail, "In session")
    }

    func testCopyNeverSoundsMedical() {
        let lines = [
            TodayProgress.emptyLine,
            TodayProgress.vibeLine(score: 90, empty: false, hasLife: true),
            TodayProgress.vibeLine(score: 40, empty: true, hasLife: false),
            HomeCoachCopy.easyDayLow,
            HomeCoachCopy.pulledBack(score: 62),
        ]
        for line in lines {
            for banned in TodayProgress.bannedPhrases {
                XCTAssertFalse(line.lowercased().contains(banned), "\(line) contained \(banned)")
            }
        }
    }

    func testHudSweepClamps() {
        XCTAssertEqual(HudChrome.sweep(from: -12), 0)
        XCTAssertEqual(HudChrome.sweep(from: 0), 0)
        XCTAssertEqual(HudChrome.sweep(from: 50), 0.5, accuracy: 0.0001)
        XCTAssertEqual(HudChrome.sweep(from: 100), 1)
        XCTAssertEqual(HudChrome.sweep(from: 140), 1)
        XCTAssertEqual(HudChrome.tickCount, HomeReadinessTokens.tickCount)
        XCTAssertEqual(HudChrome.majorEvery, HomeReadinessTokens.majorEvery)
        XCTAssertEqual(HudChrome.tickCount, 48)
        XCTAssertEqual(HudChrome.majorEvery, 6)
        XCTAssertEqual(HudChrome.tickHz, 6, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(HudChrome.tickHz, HomeReadinessTokens.tickHzCeiling)
        XCTAssertLessThanOrEqual(HudChrome.tickHz, AriaNestGeometry.paintHz)
        XCTAssertGreaterThan(HomeMetrics.hudRadius, 0)
        XCTAssertEqual(HudChrome.plate.forgeHexString, HomeReadinessTokens.plateHex)
        XCTAssertEqual(HudChrome.emberSteel.forgeHexString, HomeReadinessTokens.emberSteelHex)
    }

    func testReduceMotionPaintsFinalValueAndPausesClock() {
        XCTAssertEqual(
            HomeReadinessTokens.ringSweep(percent: 80, reduceMotion: true, animatedProgress: 0),
            0.8,
            accuracy: 0.0001
        )
        XCTAssertTrue(
            HudChrome.isClockPaused(
                reduceMotion: true, sceneActive: true, onscreen: true, animate: true
            )
        )
        XCTAssertTrue(
            HudChrome.isClockPaused(
                reduceMotion: false, sceneActive: false, onscreen: true, animate: true
            )
        )
        XCTAssertTrue(
            HudChrome.isClockPaused(
                reduceMotion: false, sceneActive: true, onscreen: false, animate: true
            )
        )
        XCTAssertFalse(
            HudChrome.isClockPaused(
                reduceMotion: false, sceneActive: true, onscreen: true, animate: true
            )
        )
        XCTAssertEqual(HomeReadinessTokens.headGlow(time: 0.4, paused: true), 1, accuracy: 0.0001)
        XCTAssertEqual(HomeReadinessTokens.headGlow(time: 9, paused: true), 1, accuracy: 0.0001)
        XCTAssertTrue(HomeTrendMath.isFrozen(reduceMotion: true, minimal: false))
    }

    func testCopyNeverUsesClinicalOrForeignBandNames() {
        let surface = [
            TodayProgress.headerTitle,
            TodayProgress.emptyLine,
            TodayProgress.vibeLine(score: 90, empty: false, hasLife: true),
            TodayProgress.vibeLine(score: 72, empty: false, hasLife: true),
            TodayProgress.vibeLine(score: 60, empty: true, hasLife: true),
            TodayProgress.vibeLine(score: 40, empty: true, hasLife: false),
            HomeReadiness.label(90),
            HomeReadiness.label(72),
            HomeReadiness.label(60),
            HomeReadiness.label(40),
            HomeReadiness.voiceOverLabel(72),
            HomeCoachCopy.easyDayLow,
            HomeCoachCopy.pulledBack(score: 62),
        ]
        for line in surface {
            for banned in TodayProgress.bannedPhrases {
                XCTAssertFalse(line.lowercased().contains(banned), "\(line) contained \(banned)")
            }
            for foreign in HomeReadinessTokens.foreignBandLabels {
                XCTAssertFalse(line == foreign, "HUD band slid into \(foreign)")
            }
        }
        XCTAssertEqual(HomeReadiness.label(90), "Peak")
        XCTAssertEqual(HomeReadiness.label(72), "Good")
        XCTAssertEqual(HomeReadiness.label(60), "Fair")
        XCTAssertEqual(HomeReadiness.label(40), "Low")
        XCTAssertEqual(HomeReadiness.color(90).forgeHexString, "22C55E")
        XCTAssertEqual(HomeReadiness.color(72).forgeHexString, "FF4D00")
        XCTAssertEqual(HomeReadiness.color(60).forgeHexString, "5B8DEF")
        XCTAssertEqual(HomeReadiness.color(40).forgeHexString, "EF4444")
    }

    func testNestGeometryUntouchedAndNotUsedAsProgressChrome() {
        XCTAssertEqual(AriaNestGeometry.kind, "soft-hex-field")
        XCTAssertEqual(AriaNestGeometry.mixLock, "B+E")
        XCTAssertEqual(AriaNestGeometry.ringCount, 3)
        XCTAssertEqual(AriaNestGeometry.ringHex, ["F7F4F0", "A9D8FF", "FF4D00"])
        XCTAssertEqual(AriaNestGeometry.radii, [0.46, 0.52, 0.58])
        XCTAssertEqual(AriaNestGeometry.tickHz, 12, accuracy: 0.0001)
        XCTAssertEqual(AriaNestGeometry.stillPoseAngleDeg, 18, accuracy: 0.0001)
        XCTAssertNotEqual(HomeReadinessTokens.kind, AriaNestGeometry.kind)
        XCTAssertNotEqual(HudChrome.tickCount, AriaNestGeometry.ringCount)
        XCTAssertLessThan(HudChrome.tickHz, AriaNestGeometry.tickHz)
        XCTAssertEqual(HomeReadinessFieldView.isFrozen(reduceMotion: true, minimal: false), true)
    }

    func testLifestyleDeepLinkSendsTomorrowAndAtHomeToWellbeing() {
        XCTAssertEqual(LifestyleDeepLink.segment(from: "tomorrow"), .wellbeing)
        XCTAssertEqual(LifestyleDeepLink.segment(from: "home"), .wellbeing)
        XCTAssertEqual(LifestyleDeepLink.segment(from: "athome"), .wellbeing)
        XCTAssertEqual(LifestyleDeepLink.segment(from: "at-home"), .wellbeing)
        XCTAssertEqual(LifestyleDeepLink.segment(from: "wellbeing"), .wellbeing)
        XCTAssertEqual(LifestyleDeepLink.segment(from: "cook"), .homeCooking)
        XCTAssertEqual(LifestyleDeepLink.segment(from: "nutrition"), .nutrition)
    }

    func testPredictiveCoachPictureCachesUntilInputsChange() {
        let store = AppStore()
        store.readiness.overall = 74
        store.dailyMetrics.hrv = 48
        let first = store.predictiveCoachPicture()
        let second = store.predictiveCoachPicture()
        XCTAssertEqual(first.forecast.predictedScore, second.forecast.predictedScore)
        XCTAssertEqual(first.forecast.posture, second.forecast.posture)
        XCTAssertNotNil(store.cachedPredictiveCoachKey)
        store.readiness.overall = 40
        let third = store.predictiveCoachPicture()
        XCTAssertNotEqual(store.cachedPredictiveCoachKey, nil)
        XCTAssertLessThanOrEqual(third.forecast.predictedScore, first.forecast.predictedScore + 5)
    }

    func testTodayHeaderAndRingStayPresentable() {
        XCTAssertEqual(TodayProgress.headerTitle, "TODAY'S PROGRESS")
        XCTAssertEqual(TodayProgress.trackCount, 5)
        XCTAssertGreaterThanOrEqual(HudChrome.ringSize, 160)
        XCTAssertGreaterThanOrEqual(HudChrome.compactRingSize, 80)
        XCTAssertEqual(HudChrome.ringSize, CGFloat(HomeReadinessTokens.ringSize))
        XCTAssertEqual(HudChrome.stroke, CGFloat(HomeReadinessTokens.stroke), accuracy: 0.0001)
    }
}
