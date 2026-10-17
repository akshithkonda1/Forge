import XCTest
@testable import ForgeCore

/// Locks `shared/readiness.json` to Home progress chrome: Peak/Good/Fair/Low,
/// Reduce Motion still-pose, Nest stays a different kind.
final class HomeReadinessTokensTests: XCTestCase {

    private struct File: Decodable {
        struct Band: Decodable {
            let id: String
            let label: String
            let min: Int
            let hex: String
            let token: String
        }

        struct Chrome: Decodable {
            let plateHex: String
            let emberSteelHex: String
            let tickCount: Int
            let majorEvery: Int
            let ringSize: Double
            let compactRingSize: Double
            let stroke: Double
            let compactStroke: Double
            let eventHz: Double
            let eventHzCeiling: Double
            let glowHz: Double
            let chromeFloor: Double
            let glanceMinimumScale: Double
        }

        struct Motivation: Decodable {
            let almostTherePercent: Int
            let closingRemaining: Int
            let almostThereFloor: Double
            let eventGlowOnly: Bool
            let liveGlowDefault: Bool
            let brackets: Bool
            let scanlines: Bool
            let missHex: String
            let glowRadius: Double
            let tickMajorWidth: Double
            let tickMinorWidth: Double
        }

        struct Trend: Decodable {
            let plotFloor: Int
            let plotCap: Int
            let trendWindowDays: Int
            let trendWindowAnchor: String
            let trendPoints: String
            let nightDate: String
            let nightCutoffHour: Int
        }

        let kind: String
        let surface: String
        let mixLock: String
        let bands: [Band]
        let chrome: Chrome
        let motivation: Motivation
        let trend: Trend
        let bannedSurfacePhrases: [String]
    }

    private static func loadFile() throws -> File {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared")
            .appendingPathComponent("readiness.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(File.self, from: data)
    }

    func testSharedFileMatchesSwiftTokens() throws {
        let file = try Self.loadFile()
        XCTAssertEqual(file.kind, HomeReadinessTokens.kind)
        XCTAssertEqual(file.surface, HomeReadinessTokens.surface)
        XCTAssertEqual(file.mixLock, HomeReadinessTokens.mixLock)
        XCTAssertEqual(file.chrome.plateHex, HomeReadinessTokens.plateHex)
        XCTAssertEqual(file.chrome.emberSteelHex, HomeReadinessTokens.emberSteelHex)
        XCTAssertEqual(file.chrome.tickCount, 0)
        XCTAssertEqual(file.chrome.tickCount, HomeReadinessTokens.tickCount)
        XCTAssertEqual(file.chrome.majorEvery, HomeReadinessTokens.majorEvery)
        XCTAssertEqual(file.chrome.ringSize, HomeReadinessTokens.ringSize, accuracy: 0.0001)
        XCTAssertEqual(file.chrome.compactRingSize, HomeReadinessTokens.compactRingSize, accuracy: 0.0001)
        XCTAssertEqual(file.chrome.stroke, HomeReadinessTokens.stroke, accuracy: 0.0001)
        XCTAssertEqual(file.chrome.compactStroke, HomeReadinessTokens.compactStroke, accuracy: 0.0001)
        XCTAssertEqual(file.chrome.eventHz, HomeReadinessTokens.eventHz, accuracy: 0.0001)
        XCTAssertEqual(file.chrome.eventHzCeiling, HomeReadinessTokens.eventHzCeiling, accuracy: 0.0001)
        XCTAssertEqual(file.chrome.glowHz, HomeReadinessTokens.glowHz, accuracy: 0.0001)
        XCTAssertEqual(file.chrome.chromeFloor, HomeReadinessTokens.tickChromeFloor, accuracy: 0.0001)
        XCTAssertEqual(file.chrome.glanceMinimumScale, HomeReadinessTokens.glanceMinimumScale, accuracy: 0.0001)
        XCTAssertEqual(file.motivation.almostTherePercent, HomeReadinessTokens.almostTherePercent)
        XCTAssertEqual(file.motivation.closingRemaining, HomeReadinessTokens.closingRemaining)
        XCTAssertEqual(file.motivation.almostThereFloor, HomeReadinessTokens.almostThereFloor, accuracy: 0.0001)
        XCTAssertEqual(file.motivation.eventGlowOnly, HomeReadinessTokens.eventGlowOnly)
        XCTAssertEqual(file.motivation.liveGlowDefault, HomeReadinessTokens.liveGlowDefault)
        XCTAssertEqual(file.motivation.brackets, HomeReadinessTokens.brackets)
        XCTAssertEqual(file.motivation.scanlines, HomeReadinessTokens.scanlines)
        XCTAssertEqual(file.motivation.missHex, HomeReadinessTokens.missHex)
        XCTAssertEqual(file.motivation.glowRadius, HomeReadinessTokens.glowRadius, accuracy: 0.0001)
        XCTAssertEqual(file.motivation.tickMajorWidth, HomeReadinessTokens.tickMajorWidth, accuracy: 0.0001)
        XCTAssertEqual(file.motivation.tickMinorWidth, HomeReadinessTokens.tickMinorWidth, accuracy: 0.0001)
        XCTAssertEqual(file.trend.plotFloor, HomeReadinessTokens.plotFloor)
        XCTAssertEqual(file.trend.plotCap, HomeReadinessTokens.plotCap)
        XCTAssertEqual(file.trend.trendWindowDays, HomeReadinessTokens.trendWindowDays)
        XCTAssertEqual(file.trend.trendWindowAnchor, HomeReadinessTokens.trendWindowAnchor)
        XCTAssertEqual(file.trend.trendPoints, HomeReadinessTokens.trendPoints)
        XCTAssertEqual(file.trend.nightDate, HomeReadinessTokens.nightDate)
        XCTAssertEqual(file.trend.nightCutoffHour, HomeReadinessTokens.nightCutoffHour)
        XCTAssertEqual(file.bannedSurfacePhrases, HomeReadinessTokens.bannedSurfacePhrases)

        let expected = [
            ("peak", "Peak", 85, "22C55E", "vitality"),
            ("good", "Good", 70, "F5A524", "amber"),
            ("fair", "Fair", 50, "5B8DEF", "steel"),
            ("low", "Low", 0, "EF4444", "alert")
        ]
        XCTAssertEqual(file.bands.count, expected.count)
        for (band, want) in zip(file.bands, expected) {
            XCTAssertEqual(band.id, want.0)
            XCTAssertEqual(band.label, want.1)
            XCTAssertEqual(band.min, want.2)
            XCTAssertEqual(band.hex, want.3)
            XCTAssertEqual(band.token, want.4)
        }
    }

    func testHomeBandsAreNotClinicalOrWatchWords() throws {
        let file = try Self.loadFile()
        let labels = file.bands.map(\.label) + HomeReadinessTokens.Band.allCases.map(\.label)
        for label in labels {
            XCTAssertFalse(HomeReadinessTokens.foreignBandLabels.contains(label), label)
            XCTAssertNil(HomeReadinessTokens.containsBannedPhrase(label), label)
        }
        XCTAssertEqual(HomeReadinessTokens.label(for: 90), "Peak")
        XCTAssertEqual(HomeReadinessTokens.label(for: 72), "Good")
        XCTAssertEqual(HomeReadinessTokens.label(for: 60), "Fair")
        XCTAssertEqual(HomeReadinessTokens.label(for: 40), "Low")
        XCTAssertEqual(HomeReadinessTokens.hex(for: 90), "22C55E")
        XCTAssertEqual(HomeReadinessTokens.hex(for: 72), "F5A524")
        XCTAssertEqual(HomeReadinessTokens.hex(for: 60), "5B8DEF")
        XCTAssertEqual(HomeReadinessTokens.hex(for: 40), "EF4444")
    }

    func testSweepClampsAndReduceMotionIsFinalValue() {
        XCTAssertEqual(HomeReadinessTokens.sweep(from: -12), 0, accuracy: 0.0001)
        XCTAssertEqual(HomeReadinessTokens.sweep(from: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(HomeReadinessTokens.sweep(from: 50), 0.5, accuracy: 0.0001)
        XCTAssertEqual(HomeReadinessTokens.sweep(from: 100), 1, accuracy: 0.0001)
        XCTAssertEqual(HomeReadinessTokens.sweep(from: 140), 1, accuracy: 0.0001)

        XCTAssertEqual(
            HomeReadinessTokens.ringSweep(percent: 64, reduceMotion: true, animatedProgress: 0.1),
            0.64,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            HomeReadinessTokens.ringSweep(percent: 64, reduceMotion: false, animatedProgress: 0.1),
            0.1,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            HomeReadinessTokens.ringSweep(percent: 64, reduceMotion: false, animatedProgress: nil),
            0.64,
            accuracy: 0.0001
        )
    }

    func testReduceMotionStillPosePausesClockAndHoldsGlow() {
        XCTAssertTrue(
            HomeReadinessTokens.isClockPaused(
                reduceMotion: true, sceneActive: true, onscreen: true, animate: true
            )
        )
        XCTAssertTrue(
            HomeReadinessTokens.isClockPaused(
                reduceMotion: false, sceneActive: false, onscreen: true, animate: true
            )
        )
        XCTAssertTrue(
            HomeReadinessTokens.isClockPaused(
                reduceMotion: false, sceneActive: true, onscreen: false, animate: true
            )
        )
        XCTAssertFalse(
            HomeReadinessTokens.isClockPaused(
                reduceMotion: false, sceneActive: true, onscreen: true, animate: true
            )
        )
        XCTAssertEqual(HomeReadinessTokens.headGlow(time: 1, paused: true), 1, accuracy: 0.0001)
        XCTAssertEqual(HomeReadinessTokens.headGlow(time: 40, paused: true), 1, accuracy: 0.0001)
        let liveA = HomeReadinessTokens.headGlow(time: 0.2, paused: false)
        let liveB = HomeReadinessTokens.headGlow(time: 1.8, paused: false)
        XCTAssertGreaterThan(abs(liveA - liveB), 0.00001)
    }

    func testTickDialIsRetired() {
        XCTAssertEqual(HomeReadinessTokens.tickCount, 0)
        XCTAssertFalse(HomeReadinessTokens.tickArmed(index: 0, sweep: 1))
        XCTAssertEqual(HomeReadinessTokens.paintedTickOpacity(major: true, armed: true, glow: 1), 0, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(HomeReadinessTokens.eventHz, HomeReadinessTokens.eventHzCeiling)
        XCTAssertLessThanOrEqual(HomeReadinessTokens.eventHz, AriaNestGeometry.paintHz)
        XCTAssertTrue(HomeReadinessTokens.showsInArcMeta(isAccessibilitySize: false))
        XCTAssertFalse(HomeReadinessTokens.showsInArcMeta(isAccessibilitySize: true))
        XCTAssertEqual(HomeReadinessTokens.glanceMinimumScale, 0.7, accuracy: 0.0001)
        XCTAssertEqual(HomeReadinessTokens.tickInterval, 1.0 / HomeReadinessTokens.eventHz, accuracy: 0.0001)
    }

    func testMotivationTokensStaySolidAndEventDriven() {
        XCTAssertTrue(HomeReadinessTokens.eventGlowOnly)
        XCTAssertFalse(HomeReadinessTokens.liveGlowDefault)
        XCTAssertFalse(HomeReadinessTokens.brackets, "no HUD / suit brackets")
        XCTAssertFalse(HomeReadinessTokens.scanlines, "no HUD scanlines")
        XCTAssertEqual(HomeReadinessTokens.tickCount, 0, "no tick dial")
        XCTAssertEqual(HomeReadinessTokens.missHex, HomeReadinessTokens.emberSteelHex)
        XCTAssertNotEqual(HomeReadinessTokens.missHex, HomeReadinessTokens.Band.low.hex)
        XCTAssertTrue(HomeReadinessTokens.isAlmostThere(percent: 80, remaining: 1))
        XCTAssertTrue(HomeReadinessTokens.isAlmostThere(percent: 80, remaining: 2))
        XCTAssertTrue(HomeReadinessTokens.isAlmostThere(percent: 60, remaining: 1))
        XCTAssertFalse(HomeReadinessTokens.isAlmostThere(percent: 40, remaining: 3))
        XCTAssertFalse(HomeReadinessTokens.isAlmostThere(percent: 100, remaining: 0))
        XCTAssertTrue(HomeReadinessTokens.isClosed(100))
        XCTAssertTrue(HomeReadinessTokens.tileAlmostThere(0.80))
        XCTAssertFalse(HomeReadinessTokens.tileAlmostThere(0.40))
        XCTAssertFalse(HomeReadinessTokens.tileAlmostThere(1))
        XCTAssertFalse(
            HomeReadinessTokens.shouldRunClock(
                reduceMotion: false, sceneActive: true, onscreen: true, eventGlow: false
            )
        )
        XCTAssertTrue(
            HomeReadinessTokens.shouldRunClock(
                reduceMotion: false, sceneActive: true, onscreen: true, eventGlow: true
            )
        )
        XCTAssertFalse(
            HomeReadinessTokens.shouldRunClock(
                reduceMotion: true, sceneActive: true, onscreen: true, eventGlow: true
            )
        )
    }

    func testNestGeometryIsUntouchedByHomeChrome() {
        XCTAssertEqual(AriaNestGeometry.kind, "soft-hex-field")
        XCTAssertEqual(AriaNestGeometry.mixLock, "B+E")
        XCTAssertEqual(AriaNestGeometry.ringCount, 3)
        XCTAssertEqual(AriaNestGeometry.ringHex, ["F7F4F0", "A9D8FF", "FF4D00"])
        XCTAssertEqual(AriaNestGeometry.tickHz, 12, accuracy: 0.0001)
        XCTAssertEqual(AriaNestGeometry.radii, [0.46, 0.52, 0.58])
        XCTAssertEqual(AriaNestGeometry.stillPoseAngleDeg, 18, accuracy: 0.0001)
        XCTAssertNotEqual(HomeReadinessTokens.kind, AriaNestGeometry.kind)
        XCTAssertNotEqual(HomeReadinessTokens.mixLock, AriaNestGeometry.mixLock)
        XCTAssertNotEqual(HomeReadinessTokens.tickCount, AriaNestGeometry.ringCount)
        XCTAssertNotEqual(HomeReadinessTokens.plateHex, AriaNestGeometry.forgeOrangeHex)
    }

    func testTrendMathReadsTheSameFloors() {
        XCTAssertEqual(HomeTrendMath.plotFloor, HomeReadinessTokens.plotFloor)
        XCTAssertEqual(HomeTrendMath.plotCap, HomeReadinessTokens.plotCap)
        XCTAssertTrue(HomeTrendMath.isFrozen(reduceMotion: true, minimal: false))
        XCTAssertEqual(HomeTrendMath.plottedScore(70, grown: false, reduceMotion: true), 70)
    }
}
