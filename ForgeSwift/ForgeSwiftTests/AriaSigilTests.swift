import XCTest
@testable import ForgeSwift

/// Locks the Aria Watch-nest ring field: three ellipses, `#FF4D00`, freeze on Reduce Motion.
final class AriaSigilTests: XCTestCase {

    func testThreeEllipsesOrangeAndStillPose() {
        XCTAssertEqual(AriaSigilGeometry.kind, "soft-hex-field")
        XCTAssertEqual(AriaSigilGeometry.cornerRoundness, 0.34, accuracy: 0.0001)
        XCTAssertEqual(AriaSigilGeometry.assetName, "AriaMark")
        XCTAssertEqual(AriaSigilGeometry.ringCount, 3)
        XCTAssertEqual(AriaSigilGeometry.ellipseCount, 3)
        XCTAssertEqual(AriaSigilGeometry.hexCount, 3)
        XCTAssertEqual(AriaSigilGeometry.forgeOrangeHex, "FF4D00")
        XCTAssertEqual(AriaSigilGeometry.brandHueLightHex, "FF6B2B")
        XCTAssertEqual(AriaSigilPalette.forgeOrangeHex, "FF4D00")
        XCTAssertEqual(AriaSigilPalette.emberHex, "FF4D00")
        XCTAssertEqual(AriaSigilGeometry.stillPoseAngleDeg, 18, accuracy: 0.0001)
        let a = AriaSigilGeometry.ellipse(index: 0, time: AriaSigilGeometry.stillPose, state: .idle, reduceMotion: true)
        let b = AriaSigilGeometry.ellipse(index: 0, time: 99, state: .idle, reduceMotion: true)
        XCTAssertEqual(a.rx, b.rx, accuracy: 0.0001)
        XCTAssertEqual(a.ry, b.ry, accuracy: 0.0001)
        XCTAssertEqual(a.rotation, b.rotation, accuracy: 0.0001)
        XCTAssertEqual(a.opacity, b.opacity, accuracy: 0.0001)
    }

    func testStillPoseIgnoresStateAndClock() {
        let idle = AriaSigilGeometry.ellipse(index: 2, time: 1, state: .idle, reduceMotion: true)
        let talk = AriaSigilGeometry.ellipse(index: 2, time: 40, state: .speaking, reduceMotion: true)
        XCTAssertEqual(idle.rx, talk.rx, accuracy: 0.0001)
        XCTAssertEqual(idle.ry, talk.ry, accuracy: 0.0001)
        XCTAssertEqual(idle.rotation, talk.rotation, accuracy: 0.0001)
    }

    func testIdleSpinIsSofterThanSpeaking() {
        XCTAssertLessThan(AriaSigilGeometry.idleSpinHz, AriaSigilGeometry.speakingSpinHz)
        XCTAssertEqual(AriaSigilGeometry.idleSpinHz, 0.05, accuracy: 0.0001)
        XCTAssertEqual(AriaSigilGeometry.speakingSpinHz, 0.09, accuracy: 0.0001)
    }

    func testEllipsesMoveWhenAliveAndFreezeWhenReduced() {
        let a = AriaSigilGeometry.ellipse(index: 1, time: 0.4, state: .idle, reduceMotion: false)
        let b = AriaSigilGeometry.ellipse(index: 1, time: 1.1, state: .idle, reduceMotion: false)
        XCTAssertFalse(
            abs(a.rotation - b.rotation) < 0.00001
                && abs(a.rx - b.rx) < 0.00001
                && abs(a.ry - b.ry) < 0.00001
        )
        let stillA = AriaSigilGeometry.ellipse(index: 2, time: 1, state: .speaking, reduceMotion: true)
        let stillB = AriaSigilGeometry.ellipse(index: 2, time: 40, state: .speaking, reduceMotion: true)
        XCTAssertEqual(stillA.rotation, stillB.rotation, accuracy: 0.0001)
    }

    func testThreeEllipsesOverlapAtDistinctTilts() {
        var rotations = Set<String>()
        for index in 0..<AriaSigilGeometry.ellipseCount {
            let pose = AriaSigilGeometry.ellipse(
                index: index,
                time: AriaSigilGeometry.stillPose,
                state: .idle,
                reduceMotion: true
            )
            XCTAssertGreaterThan(pose.rx, pose.ry)
            XCTAssertGreaterThan(pose.ry, 0.3)
            XCTAssertLessThan(pose.rx, 1.05)
            rotations.insert(String(format: "%.4f", pose.rotation))
        }
        XCTAssertEqual(rotations.count, AriaSigilGeometry.ellipseCount)
    }

    func testAlwaysShowsThreeEllipses() {
        XCTAssertEqual(AriaSigilGeometry.radii, [0.46, 0.52, 0.58])
        XCTAssertEqual(AriaSigilGeometry.ringOpacities, [0.88, 0.78, 0.62])
        XCTAssertEqual(AriaSigilGeometry.contrastFloor, 0.70, accuracy: 0.0001)
        XCTAssertEqual(AriaSigilGeometry.strokeWidthCompact, 1.35, accuracy: 0.0001)
        XCTAssertEqual(AriaSigilGeometry.strokeWidthHero, 1.6, accuracy: 0.0001)
        XCTAssertEqual(AriaSigilGeometry.visibleRingIndices(size: 28), [0, 1, 2])
        XCTAssertEqual(AriaSigilGeometry.visibleRingIndices(size: 90), [0, 1, 2])
        XCTAssertEqual(AriaSigilGeometry.compactRingIndices, [0, 1, 2])
        for index in 0..<AriaSigilGeometry.ellipseCount {
            XCTAssertGreaterThanOrEqual(
                AriaSigilGeometry.strokeWidth(size: AriaSigilGeometry.compactRecommend, index: index),
                AriaSigilGeometry.strokeWidthCompact
            )
        }
    }

    func testRingFieldContractMatchesWatchNest() {
        XCTAssertEqual(AriaSigilGeometry.kind, "soft-hex-field")
        XCTAssertEqual(AriaSigilGeometry.assetName, "AriaMark")
        XCTAssertEqual(AriaSigilGeometry.ringCount, 3)
        // Watch Home compact subset (indices 1, 2, 4 of the 5-ring field).
        XCTAssertEqual(AriaSigilGeometry.radii, [0.46, 0.52, 0.58])
        XCTAssertEqual(AriaSigilGeometry.eccentricity, [0.07, 0.05, 0.06])
        XCTAssertEqual(AriaSigilGeometry.tiltDeg, [-18, 24, -12])
        XCTAssertEqual(AriaSigilGeometry.phaseOffsets, [0.0, 0.33, 0.66])
        XCTAssertEqual(AriaSigilGeometry.ringOpacities, [0.88, 0.78, 0.62])
        XCTAssertEqual(AriaSigilGeometry.idleSpinHz, 0.05, accuracy: 0.0001)
        XCTAssertEqual(AriaSigilGeometry.speakingSpinHz, 0.09, accuracy: 0.0001)
        XCTAssertEqual(AriaSigilGeometry.stillPoseAngleDeg, 18, accuracy: 0.0001)
        XCTAssertEqual(AriaSigilGeometry.strokeWidthCompact, 1.35, accuracy: 0.0001)
        XCTAssertEqual(AriaSigilGeometry.strokeWidthHero, 1.6, accuracy: 0.0001)
        XCTAssertEqual(AriaSigilGeometry.heroMinimumSize, 90)
        XCTAssertEqual(AriaSigilGeometry.compactRecommend, 28)
        XCTAssertEqual(AriaSigilGeometry.forgeOrangeHex, "FF4D00")
    }

    func testMeetCopyIsARIANotAForgePairing() {
        XCTAssertEqual(AriaMeetCopy.title, "This is ARIA")
        XCTAssertTrue(AriaMeetCopy.lead.contains("designed for Forge"))
        XCTAssertFalse(AriaMeetCopy.lead.contains(AriaMeetCopy.pairingForbidden))
        XCTAssertFalse(AriaMeetCopy.title.contains("FORGE"))
        XCTAssertEqual(AriaMeetCopy.capabilities.count, 4)
        XCTAssertTrue(AriaMeetCopy.capabilities.allSatisfy { !$0.icon.isEmpty && !$0.title.isEmpty })
    }

    func testPaletteStaysPreciousNotNeon() {
        XCTAssertEqual(AriaSigilPalette.goldHex, "C9A36A")
        XCTAssertEqual(AriaSigilPalette.voidDeepHex, "030207")
        XCTAssertEqual(AriaSigilPalette.bloodHex, "4A1018")
        XCTAssertEqual(AriaSigilPalette.ivoryHex, "F3EBDD")
        XCTAssertEqual(AriaSigilPalette.emberHex, "FF4D00")
        XCTAssertNotEqual(AriaSigilPalette.photonPrimary(for: .energized), "00D2FF")
        XCTAssertNotEqual(AriaSigilPalette.photonPrimary(for: .focused), "22C55E")
    }

    func testRetiredEmberIsNotTheBrandMark() {
        XCTAssertEqual(AriaSigilEmberLegacy.lobeCount, 4)
        XCTAssertEqual(AriaSigilEmberLegacy.hearthHex, "FF6A1A")
        XCTAssertNotEqual(AriaSigilEmberLegacy.hearthHex, AriaSigilGeometry.forgeOrangeHex)
        XCTAssertNotEqual(AriaSigilEmberLegacy.lobeCount, AriaSigilGeometry.ellipseCount)
    }

    func testWhiteOrbNestsInsideInnermostRing() {
        XCTAssertEqual(AriaSigilGeometry.orbHueHex, "FFFFFF")
        XCTAssertEqual(AriaSigilGeometry.orbNest, 0.88, accuracy: 0.0001)
        let heroInner = AriaSigilGeometry.ellipse(index: 0, time: 0, state: .idle, reduceMotion: true)
        let heroOrb = AriaSigilGeometry.orbCoreRadius(size: AriaSigilGeometry.heroMinimumSize)
        XCTAssertLessThan(Double(heroOrb), (heroInner.ry / 2) * Double(AriaSigilGeometry.heroMinimumSize))
        let compactInner = AriaSigilGeometry.ellipse(index: 1, time: 0, state: .idle, reduceMotion: true)
        let compactOrb = AriaSigilGeometry.orbCoreRadius(size: AriaSigilGeometry.compactRecommend)
        XCTAssertLessThan(Double(compactOrb), (compactInner.ry / 2) * Double(AriaSigilGeometry.compactRecommend))
        XCTAssertGreaterThan(compactOrb, 0)
    }

    func testPearlCoreAndWatchHueRhythm() {
        XCTAssertEqual(AriaSigilGeometry.pearlHex, "F7F4F0")
        XCTAssertEqual(AriaSigilGeometry.pearlHotHex, "FFFFFF")
        XCTAssertEqual(AriaSigilPalette.pearlHex, "F7F4F0")
        // Watch nest: first compact ring is pearl, then orange-light, then orange.
        XCTAssertTrue(AriaSigilGeometry.ringIsPearl(0))
        XCTAssertFalse(AriaSigilGeometry.ringIsPearl(1))
        XCTAssertFalse(AriaSigilGeometry.ringIsPearl(2))
        XCTAssertLessThan(AriaSigilGeometry.waveformHz, 4.0)
        XCTAssertLessThan(AriaSigilGeometry.metalRippleHz, 5.0)
    }

    func testLiquidEllipseFreezesWithReduceMotion() {
        let a = AriaSigilGeometry.liquidEllipse(
            index: 1, time: 1, state: .speaking, amplitude: 0.9, reduceMotion: true
        )
        let b = AriaSigilGeometry.liquidEllipse(
            index: 1, time: 40, state: .speaking, amplitude: 0.9, reduceMotion: true
        )
        let base = AriaSigilGeometry.ellipse(
            index: 1, time: 1, state: .speaking, reduceMotion: true
        )
        XCTAssertEqual(a.rx, b.rx, accuracy: 0.0001)
        XCTAssertEqual(a.ry, b.ry, accuracy: 0.0001)
        XCTAssertEqual(a.rotation, b.rotation, accuracy: 0.0001)
        XCTAssertEqual(a.rx, base.rx, accuracy: 0.0001)
        XCTAssertEqual(a.ry, base.ry, accuracy: 0.0001)
    }

    func testLiquidEllipseAndOrbWaveWhenSpeaking() {
        let a = AriaSigilGeometry.liquidEllipse(
            index: 1, time: 0.2, state: .speaking, amplitude: 0.95, reduceMotion: false
        )
        let b = AriaSigilGeometry.liquidEllipse(
            index: 1, time: 0.55, state: .speaking, amplitude: 0.95, reduceMotion: false
        )
        XCTAssertFalse(
            abs(a.rx - b.rx) < 0.00001
                && abs(a.ry - b.ry) < 0.00001
                && abs(a.rotation - b.rotation) < 0.00001
        )
        let coreA = AriaSigilGeometry.orbCore(
            time: 0.2, state: .speaking, amplitude: 0.95, reduceMotion: false
        )
        let coreB = AriaSigilGeometry.orbCore(
            time: 0.55, state: .speaking, amplitude: 0.95, reduceMotion: false
        )
        XCTAssertFalse(abs(coreA.sx - coreB.sx) < 0.00001 && abs(coreA.sy - coreB.sy) < 0.00001)
        XCTAssertGreaterThan(coreA.ripple, 0.2)
        let still = AriaSigilGeometry.orbCore(
            time: 99, state: .speaking, amplitude: 0.95, reduceMotion: true
        )
        XCTAssertEqual(still.sx, 1, accuracy: 0.0001)
        XCTAssertEqual(still.sy, 1, accuracy: 0.0001)
    }

    func testSpeakingDriveIsStrongerThanIdle() {
        XCTAssertGreaterThan(
            AriaSigilGeometry.waveformDrive(state: .speaking, amplitude: 0.8),
            AriaSigilGeometry.waveformDrive(state: .idle, amplitude: 0.8)
        )
        XCTAssertGreaterThan(
            AriaSigilGeometry.waveformDrive(state: .listening, amplitude: 0.8),
            AriaSigilGeometry.waveformDrive(state: .idle, amplitude: 0.8)
        )
    }

    func testPlanetaryOrbitsDifferByRing() {
        XCTAssertEqual(AriaSigilGeometry.idleOrbitHz.count, 3)
        XCTAssertEqual(AriaSigilGeometry.speakingOrbitHz.count, 3)
        // Inner planet is fastest; middle is retrograde.
        XCTAssertGreaterThan(abs(AriaSigilGeometry.idleOrbitHz[0]), abs(AriaSigilGeometry.idleOrbitHz[2]))
        XCTAssertLessThan(AriaSigilGeometry.idleOrbitHz[1], 0)
        let a = AriaSigilGeometry.ellipse(index: 0, time: 1.0, state: .idle, reduceMotion: false)
        let b = AriaSigilGeometry.ellipse(index: 1, time: 1.0, state: .idle, reduceMotion: false)
        XCTAssertNotEqual(a.rotation, b.rotation, accuracy: 0.0001)
    }
}
