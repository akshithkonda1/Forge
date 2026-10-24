import XCTest
@testable import ForgeCore

final class ForgeStrikeMarkGeometryTests: XCTestCase {

    func testKindIsHammerStrikeNotAriaNest() {
        XCTAssertEqual(ForgeStrikeMarkGeometry.kind, "hammer-strike")
        XCTAssertEqual(ForgeStrikeMarkGeometry.assetName, "ForgeStrikeMark")
        XCTAssertNotEqual(ForgeStrikeMarkGeometry.kind, AriaNestGeometry.kind)
        XCTAssertNotEqual(ForgeStrikeMarkGeometry.assetName, AriaNestGeometry.assetName)
        XCTAssertEqual(ForgeStrikeMarkGeometry.paintHz, 12, accuracy: 0.001)
        XCTAssertLessThanOrEqual(ForgeStrikeMarkGeometry.paintHz, ForgeDesignTokens.Motion.maxTickHz)
        XCTAssertEqual(ForgeStrikeMarkGeometry.sparkCount, 6)
        XCTAssertEqual(ForgeStrikeMarkGeometry.strikeDuration, 0.55, accuracy: 0.001)
        XCTAssertLessThan(ForgeStrikeMarkGeometry.strikeDuration, 1.0)
    }

    func testReduceMotionIsIdlePose() {
        let a = ForgeStrikeMarkGeometry.pose(progress: 0, reduceMotion: true)
        let b = ForgeStrikeMarkGeometry.pose(progress: 1, reduceMotion: true)
        XCTAssertEqual(a.hammerAngleDeg, ForgeStrikeMarkGeometry.idleAngleDeg, accuracy: 0.0001)
        XCTAssertEqual(a.flare, ForgeStrikeMarkGeometry.idleFlare, accuracy: 0.0001)
        XCTAssertTrue(a.settled)
        XCTAssertEqual(a.hammerAngleDeg, b.hammerAngleDeg, accuracy: 0.0001)
        XCTAssertEqual(a.flare, b.flare, accuracy: 0.0001)
        let spark = ForgeStrikeMarkGeometry.spark(index: 2, progress: 0.5, reduceMotion: true)
        XCTAssertEqual(spark.opacity, 0, accuracy: 0.0001)
    }

    func testStrikeMovesThenSettles() {
        let raised = ForgeStrikeMarkGeometry.pose(progress: 0.1, reduceMotion: false)
        let impact = ForgeStrikeMarkGeometry.pose(progress: 0.4, reduceMotion: false)
        let idle = ForgeStrikeMarkGeometry.pose(progress: 1, reduceMotion: false)
        XCTAssertEqual(raised.hammerAngleDeg, ForgeStrikeMarkGeometry.raisedAngleDeg, accuracy: 0.0001)
        XCTAssertEqual(impact.hammerAngleDeg, ForgeStrikeMarkGeometry.impactAngleDeg, accuracy: 0.0001)
        XCTAssertEqual(idle.hammerAngleDeg, ForgeStrikeMarkGeometry.idleAngleDeg, accuracy: 0.0001)
        XCTAssertGreaterThan(impact.flare, raised.flare)
        XCTAssertGreaterThan(impact.flare, idle.flare)
        XCTAssertTrue(idle.settled)
        XCTAssertFalse(raised.settled)
    }

    func testSparksFlyAfterImpactAndVanishWhenSettled() {
        let before = ForgeStrikeMarkGeometry.spark(index: 1, progress: 0.2, reduceMotion: false)
        let mid = ForgeStrikeMarkGeometry.spark(index: 1, progress: 0.52, reduceMotion: false)
        let done = ForgeStrikeMarkGeometry.spark(index: 1, progress: 1, reduceMotion: false)
        XCTAssertEqual(before.opacity, 0, accuracy: 0.0001)
        XCTAssertGreaterThan(mid.opacity, 0.2)
        XCTAssertEqual(done.opacity, 0, accuracy: 0.0001)
        XCTAssertGreaterThan(abs(mid.x - before.x) + abs(mid.y - before.y), 0.02)
    }

    func testPathsAreClosedAndHammerHasAHead() {
        let hammer = ForgeStrikeMarkGeometry.hammerCommands()
        XCTAssertGreaterThanOrEqual(hammer.count, 8)
        guard case .move(let x, _) = hammer.first else {
            return XCTFail("hammer starts with a move")
        }
        XCTAssertLessThan(x, 0, "striking face sits left of the neck")
        if case .close = hammer.last {
        } else {
            XCTFail("hammer path must close")
        }
        for index in 0..<3 {
            let tongue = ForgeStrikeMarkGeometry.flameCommands(index: index, flare: 1)
            XCTAssertGreaterThanOrEqual(tongue.count, 4)
            if case .close = tongue.last {
            } else {
                XCTFail("flame \(index) must close")
            }
        }
        let svg = ForgeStrikeMarkGeometry.svgPath(hammer, side: 100)
        XCTAssertTrue(svg.contains("M "))
        XCTAssertTrue(svg.contains("Z"))
        XCTAssertTrue(hasSharpNeck(hammer), "head must step into the handle — a T, not a spatula")
        XCTAssertGreaterThan(headHeight(hammer), 0.28)
        XCTAssertLessThan(ForgeStrikeMarkGeometry.idleAngleDeg, -18)
        XCTAssertGreaterThan(ForgeStrikeMarkGeometry.idleAngleDeg, -30)
    }

    private func hasSharpNeck(_ commands: [ForgeStrikeMarkGeometry.Command]) -> Bool {
        var previous: (x: Double, y: Double)?
        for command in commands {
            let point: (x: Double, y: Double)?
            switch command {
            case .move(let x, let y), .line(let x, let y):
                point = (x, y)
            default:
                point = nil
            }
            if let point, let previous, abs(point.x - previous.x) < 0.0001, abs(point.y - previous.y) > 0.08 {
                return true
            }
            if let point { previous = point }
        }
        return false
    }

    private func headHeight(_ commands: [ForgeStrikeMarkGeometry.Command]) -> Double {
        var minY = Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        for command in commands {
            let y: Double?
            switch command {
            case .move(_, let value), .line(_, let value):
                y = value
            default:
                y = nil
            }
            if let y {
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        return maxY - minY
    }

    func testBrandColorsPassWCAGAAOnBackground() {
        let background = ForgeDesignTokens.ColorHex.background
        XCTAssertGreaterThanOrEqual(
            ForgeStrikeMarkGeometry.contrastRatio(hexA: ForgeStrikeMarkGeometry.paperHex, hexB: background),
            4.5
        )
        XCTAssertGreaterThanOrEqual(
            ForgeStrikeMarkGeometry.contrastRatio(hexA: ForgeStrikeMarkGeometry.emberHex, hexB: background),
            4.5
        )
        XCTAssertGreaterThanOrEqual(
            ForgeStrikeMarkGeometry.contrastRatio(hexA: ForgeDesignTokens.ColorHex.textTertiary, hexB: background),
            4.5
        )
        XCTAssertEqual(ForgeStrikeMarkGeometry.emberHex, ForgeDesignTokens.ColorHex.ember)
        XCTAssertEqual(ForgeStrikeMarkGeometry.emberLightHex, ForgeDesignTokens.ColorHex.emberLight)
        XCTAssertEqual(ForgeStrikeMarkGeometry.emberDarkHex, ForgeDesignTokens.ColorHex.emberDark)
        XCTAssertEqual(ForgeStrikeMarkGeometry.amberHex, ForgeDesignTokens.ColorHex.amber)
    }

    func testCompactThresholdAndProgressClamp() {
        XCTAssertTrue(ForgeStrikeMarkGeometry.isCompact(size: 22))
        XCTAssertTrue(ForgeStrikeMarkGeometry.isCompact(size: 18))
        XCTAssertFalse(ForgeStrikeMarkGeometry.isCompact(size: 90))
        XCTAssertEqual(ForgeStrikeMarkGeometry.normalizedProgress(elapsed: -1), 0, accuracy: 0.0001)
        XCTAssertEqual(ForgeStrikeMarkGeometry.normalizedProgress(elapsed: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(ForgeStrikeMarkGeometry.normalizedProgress(elapsed: 9), 1, accuracy: 0.0001)
        XCTAssertEqual(
            ForgeStrikeMarkGeometry.normalizedProgress(elapsed: ForgeStrikeMarkGeometry.strikeDuration),
            1,
            accuracy: 0.0001
        )
    }
}
