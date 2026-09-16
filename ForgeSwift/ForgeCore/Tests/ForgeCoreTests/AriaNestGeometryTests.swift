import XCTest
@testable import ForgeCore

/// Locks the B+E nest mark: three soft-hex rings, metal sun, `#FF4D00` accent,
/// Reduce Motion freeze, ≤12 Hz tick. Matches Lex `#288` `soft-hex-field`.
final class AriaNestGeometryTests: XCTestCase {

    func testNestKindAndLock() {
        XCTAssertEqual(AriaNestGeometry.kind, "soft-hex-field")
        XCTAssertEqual(AriaNestGeometry.mixLock, "B+E")
        XCTAssertEqual(AriaNestGeometry.assetName, "AriaMark")
        XCTAssertEqual(AriaNestGeometry.ringCount, 3)
        XCTAssertEqual(AriaNestGeometry.hexCount, 3)
        XCTAssertEqual(AriaNestGeometry.forgeOrangeHex, "FF4D00")
        XCTAssertEqual(AriaNestGeometry.brandHueLightHex, "FF6B2B")
        XCTAssertEqual(AriaNestGeometry.pearlHex, "F7F4F0")
        XCTAssertEqual(AriaNestGeometry.pearlHotHex, "FFFFFF")
        XCTAssertEqual(AriaNestGeometry.nestFrostHex, "A9D8FF")
        XCTAssertEqual(AriaNestGeometry.hearthGlowHex, "3A0E12")
        XCTAssertEqual(AriaNestGeometry.ringHex, ["F7F4F0", "A9D8FF", "FF4D00"])
        XCTAssertEqual(AriaNestGeometry.stillPoseAngleDeg, 18, accuracy: 0.0001)
        XCTAssertEqual(AriaNestGeometry.cornerRoundness, 0.34, accuracy: 0.0001)
        XCTAssertEqual(AriaNestGeometry.orbDiameterIdle, 0.22, accuracy: 0.0001)
        XCTAssertEqual(AriaNestGeometry.orbDiameterSpeaking, 0.245, accuracy: 0.0001)
    }

    func testMatchesLexPR288Contract() {
        XCTAssertEqual(AriaNestGeometry.radii, [0.46, 0.52, 0.58])
        XCTAssertEqual(AriaNestGeometry.eccentricity, [0.07, 0.05, 0.06])
        XCTAssertEqual(AriaNestGeometry.tiltDeg, [-18, 24, -12])
        XCTAssertEqual(AriaNestGeometry.phaseOffsets, [0.0, 0.33, 0.66])
        XCTAssertEqual(AriaNestGeometry.ringOpacities, [0.88, 0.78, 0.72])
        XCTAssertEqual(AriaNestGeometry.idleOrbitHz, [0.065, -0.042, 0.028])
        XCTAssertEqual(AriaNestGeometry.speakingOrbitHz, [0.09, -0.06, 0.04])
        XCTAssertEqual(AriaNestGeometry.liquidWaveHz, 0.42, accuracy: 0.0001)
        XCTAssertEqual(AriaNestGeometry.paintHz, 12, accuracy: 0.0001)
        XCTAssertEqual(AriaNestGeometry.strokeWidthCompact, 1.5, accuracy: 0.0001)
        XCTAssertEqual(AriaNestGeometry.strokeWidthHero, 1.75, accuracy: 0.0001)
        XCTAssertEqual(AriaNestGeometry.heroMinimumSize, 90, accuracy: 0.0001)
        XCTAssertEqual(AriaNestGeometry.compactRecommend, 28, accuracy: 0.0001)
        XCTAssertEqual(AriaNestGeometry.wordmarkPrimaryMax, 32, accuracy: 0.0001)
        XCTAssertEqual(AriaNestGeometry.hearthSpecularMax, 0.55, accuracy: 0.0001)
        XCTAssertEqual(AriaNestGeometry.paintedOpacityFloor, 0.70, accuracy: 0.0001)
        XCTAssertEqual(AriaNestGeometry.splash, "mark+wordmark")
        XCTAssertEqual(AriaNestGeometry.visibleRingIndices(size: 28), [0, 1, 2])
        XCTAssertEqual(AriaNestGeometry.visibleRingIndices(size: 90), [0, 1, 2])
        XCTAssertEqual(AriaNestGeometry.compactRingIndices, [0, 1, 2])
        XCTAssertEqual(AriaNestGeometry.contrastRingIndices, [0, 1, 2])
    }

    func testTickBudgetIsWatchSafe() {
        XCTAssertEqual(AriaNestGeometry.tickHz, 12, accuracy: 0.0001)
        XCTAssertEqual(AriaNestGeometry.tickInterval, 1.0 / 12.0, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(AriaNestGeometry.tickHz, 12.0001)
        XCTAssertLessThan(AriaNestGeometry.waveformHz, 1.0)
        XCTAssertLessThan(AriaNestGeometry.metalRippleHz, 1.0)
        XCTAssertLessThan(AriaNestGeometry.liquidWaveHz, 0.5)
        XCTAssertLessThanOrEqual(AriaNestGeometry.maxWobbleHz, 0.15)
    }

    func testStillPoseIgnoresStateAndClock() {
        let idle = AriaNestGeometry.hex(index: 2, time: 1, presence: .idle, reduceMotion: true)
        let talk = AriaNestGeometry.hex(index: 2, time: 40, presence: .speaking, reduceMotion: true)
        XCTAssertEqual(idle.rx, talk.rx, accuracy: 0.0001)
        XCTAssertEqual(idle.ry, talk.ry, accuracy: 0.0001)
        XCTAssertEqual(idle.rotation, talk.rotation, accuracy: 0.0001)
        XCTAssertEqual(idle.opacity, talk.opacity, accuracy: 0.0001)
        XCTAssertEqual(idle.wavePhase, talk.wavePhase, accuracy: 0.0001)
        XCTAssertEqual(idle.waveAmp, talk.waveAmp, accuracy: 0.0001)
    }

    func testHexesMoveWhenAliveAndFreezeWhenReduced() {
        let a = AriaNestGeometry.hex(index: 1, time: 0.4, presence: .idle, reduceMotion: false)
        let b = AriaNestGeometry.hex(index: 1, time: 1.1, presence: .idle, reduceMotion: false)
        XCTAssertFalse(abs(a.rotation - b.rotation) < 0.00001)
        let stillA = AriaNestGeometry.hex(index: 2, time: 1, presence: .speaking, reduceMotion: true)
        let stillB = AriaNestGeometry.hex(index: 2, time: 40, presence: .speaking, reduceMotion: true)
        XCTAssertEqual(stillA.rotation, stillB.rotation, accuracy: 0.0001)
    }

    func testIdleOrbitIsSofterThanSpeaking() {
        XCTAssertGreaterThan(abs(AriaNestGeometry.idleOrbitHz[0]), abs(AriaNestGeometry.idleOrbitHz[2]))
        XCTAssertLessThan(AriaNestGeometry.idleOrbitHz[1], 0)
        for index in 0..<AriaNestGeometry.ringCount {
            XCTAssertGreaterThan(
                abs(AriaNestGeometry.speakingOrbitHz[index]),
                abs(AriaNestGeometry.idleOrbitHz[index])
            )
        }
    }

    func testThreeRingsAtDistinctTilts() {
        var rotations = Set<String>()
        for index in 0..<AriaNestGeometry.ringCount {
            let pose = AriaNestGeometry.hex(
                index: index,
                time: AriaNestGeometry.stillPose,
                presence: .idle,
                reduceMotion: true
            )
            XCTAssertGreaterThan(pose.rx, pose.ry)
            XCTAssertGreaterThan(pose.ry, 0.3)
            XCTAssertLessThan(pose.rx, 1.05)
            rotations.insert(String(format: "%.4f", pose.rotation))
        }
        XCTAssertEqual(rotations.count, AriaNestGeometry.ringCount)
    }

    func testLivingHexFreezesWithReduceMotion() {
        let a = AriaNestGeometry.livingHex(
            index: 1, time: 1, presence: .speaking, amplitude: 0.9, reduceMotion: true
        )
        let b = AriaNestGeometry.livingHex(
            index: 1, time: 40, presence: .speaking, amplitude: 0.9, reduceMotion: true
        )
        let base = AriaNestGeometry.hex(index: 1, time: 1, presence: .speaking, reduceMotion: true)
        XCTAssertEqual(a.rx, b.rx, accuracy: 0.0001)
        XCTAssertEqual(a.ry, b.ry, accuracy: 0.0001)
        XCTAssertEqual(a.rotation, b.rotation, accuracy: 0.0001)
        XCTAssertEqual(a.rx, base.rx, accuracy: 0.0001)
    }

    func testLivingHexAndOrbWaveWhenSpeaking() {
        let a = AriaNestGeometry.livingHex(
            index: 1, time: 0.2, presence: .speaking, amplitude: 0.95, reduceMotion: false
        )
        let b = AriaNestGeometry.livingHex(
            index: 1, time: 0.55, presence: .speaking, amplitude: 0.95, reduceMotion: false
        )
        XCTAssertFalse(
            abs(a.rx - b.rx) < 0.00001
                && abs(a.ry - b.ry) < 0.00001
                && abs(a.rotation - b.rotation) < 0.00001
        )
        let coreA = AriaNestGeometry.orbCore(
            time: 0.2, presence: .speaking, amplitude: 0.95, reduceMotion: false
        )
        let coreB = AriaNestGeometry.orbCore(
            time: 0.55, presence: .speaking, amplitude: 0.95, reduceMotion: false
        )
        XCTAssertFalse(abs(coreA.sx - coreB.sx) < 0.00001 && abs(coreA.sy - coreB.sy) < 0.00001)
        let still = AriaNestGeometry.orbCore(
            time: 99, presence: .speaking, amplitude: 0.95, reduceMotion: true
        )
        XCTAssertEqual(still.sx, 1, accuracy: 0.0001)
        XCTAssertEqual(still.sy, 1, accuracy: 0.0001)
        XCTAssertEqual(still.diameter, AriaNestGeometry.orbDiameterIdle, accuracy: 0.0001)
    }

    func testSpeakingDriveIsStrongerThanIdle() {
        XCTAssertGreaterThan(
            AriaNestGeometry.waveformDrive(presence: .speaking, amplitude: 0.8),
            AriaNestGeometry.waveformDrive(presence: .idle, amplitude: 0.8)
        )
        XCTAssertGreaterThan(
            AriaNestGeometry.waveformDrive(presence: .listening, amplitude: 0.8),
            AriaNestGeometry.waveformDrive(presence: .idle, amplitude: 0.8)
        )
    }

    func testHueRhythmIsPearlFrostOrange() {
        XCTAssertEqual(AriaNestGeometry.ringHex(at: 0), "F7F4F0")
        XCTAssertEqual(AriaNestGeometry.ringHex(at: 1), "A9D8FF")
        XCTAssertEqual(AriaNestGeometry.ringHex(at: 2), "FF4D00")
        XCTAssertTrue(AriaNestGeometry.ringIsPearl(0))
        XCTAssertFalse(AriaNestGeometry.ringIsPearl(1))
        XCTAssertTrue(AriaNestGeometry.ringIsOrangeAccent(2))
    }

    func testPaintedOpacityFloorAndCompactStill() {
        XCTAssertEqual(AriaNestGeometry.paintedNestOpacity(0.72, flicker: 0.78), 0.70, accuracy: 0.0001)
        XCTAssertEqual(AriaNestGeometry.paintedNestOpacity(0.88, flicker: 1), 0.88, accuracy: 0.0001)
        XCTAssertTrue(AriaNestGeometry.ringOpacities.allSatisfy { $0 >= 0.70 })
        XCTAssertEqual(AriaNestGeometry.sizeTier(32), .compact)
        XCTAssertEqual(AriaNestGeometry.sizeTier(36), .mid)
        XCTAssertEqual(AriaNestGeometry.sizeTier(90), .hero)
        XCTAssertFalse(AriaNestGeometry.shouldOrbit(size: 28, reduceMotion: false))
        XCTAssertTrue(AriaNestGeometry.shouldOrbit(size: 96, reduceMotion: false))
        XCTAssertFalse(AriaNestGeometry.shouldOrbit(size: 96, reduceMotion: true))
        let live = AriaNestGeometry.livingHex(
            index: 2, time: 0.4, presence: .speaking, amplitude: 0.95, reduceMotion: false
        )
        XCTAssertGreaterThanOrEqual(live.opacity, AriaNestGeometry.paintedOpacityFloor)
    }

    func testNestPathIsSoftHexNotFlower() {
        XCTAssertLessThanOrEqual(AriaNestGeometry.hexBiasAmount, 0.07)
        let points = AriaNestGeometry.nestRingPoints(
            roundness: AriaNestGeometry.cornerRoundness,
            wavePhase: 0,
            waveAmp: 0.02
        )
        XCTAssertEqual(points.count, AriaNestGeometry.pathSamples)
        let radii = points.map { hypot($0.x, $0.y) }
        let minR = radii.min() ?? 0
        let maxR = radii.max() ?? 0
        XCTAssertGreaterThan(minR, 0.85)
        XCTAssertLessThan(maxR, 1.12)
        // Flower petals would swing much harder than a restrained nest weave.
        XCTAssertLessThan((maxR - minR) / minR, 0.18)
    }

    func testStandBySurfaceUsesSystemSmallAndNestFaceNotRingField() {
        XCTAssertEqual(AriaNestGeometry.StandBy.widgetFamilyName, "systemSmall")
        XCTAssertEqual(AriaNestGeometry.StandBy.widgetKind, "StandByNestWidget")
        XCTAssertEqual(AriaNestGeometry.kind, "soft-hex-field")
        XCTAssertNotEqual(AriaNestGeometry.kind, AriaRingFieldGeometry.kind)
        XCTAssertEqual(AriaNestGeometry.StandBy.nightstandBackgroundHex, "000000")
        XCTAssertEqual(AriaNestGeometry.StandBy.clockHex, AriaNestGeometry.pearlHex)
        XCTAssertGreaterThanOrEqual(
            AriaNestGeometry.StandBy.markSize,
            AriaNestGeometry.heroMinimumSize
        )
        XCTAssertEqual(AriaNestGeometry.splash, "mark+wordmark")
        XCTAssertEqual(ForgeWidgetLink.standBy, ForgeWidgetLink.today)
    }

    func testStandByNestFreezesForReduceMotionAndNightMode() {
        XCTAssertTrue(AriaNestGeometry.StandBy.shouldAnimate(reduceMotion: false))
        XCTAssertFalse(AriaNestGeometry.StandBy.shouldAnimate(reduceMotion: true))
        XCTAssertFalse(AriaNestGeometry.StandBy.shouldAnimate(reduceMotion: false, nightMode: true))
        XCTAssertEqual(
            AriaNestGeometry.StandBy.tickInterval(reduceMotion: false),
            AriaNestGeometry.tickInterval,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            AriaNestGeometry.StandBy.tickInterval(reduceMotion: true),
            1,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            AriaNestGeometry.StandBy.tickInterval(reduceMotion: false, nightMode: true),
            1,
            accuracy: 0.0001
        )
        XCTAssertLessThanOrEqual(AriaNestGeometry.StandBy.idleAmplitude, 0.22)
    }

    func testStrokeNeverDropsBelowCompactFloor() {
        for index in 0..<AriaNestGeometry.ringCount {
            XCTAssertGreaterThanOrEqual(
                AriaNestGeometry.strokeWidth(size: AriaNestGeometry.compactRecommend, index: index),
                AriaNestGeometry.strokeWidthCompact
            )
        }
        XCTAssertGreaterThanOrEqual(
            AriaNestGeometry.strokeWidth(size: AriaNestGeometry.heroMinimumSize),
            AriaNestGeometry.strokeWidthHero
        )
    }
}
