import XCTest
import ForgeCore
@testable import ForgeSwift

final class ForgeStrikeMarkTests: XCTestCase {

    func testWelcomeFirstPageIsTheStrikeMark() {
        XCTAssertEqual(AuthWelcomePages.firstId, ForgeWelcomeCopy.firstPageId)
        XCTAssertEqual(AuthWelcomePages.firstTitle, ForgeWelcomeCopy.tagline)
        XCTAssertEqual(AuthWelcomePages.count, 5)
        XCTAssertEqual(ForgeWelcomeCopy.tagline, "Forged, not promised. The rest is you.")
    }

    func testSplashHoldStillBeatsTheStrike() {
        XCTAssertGreaterThanOrEqual(
            ForgeSplashTiming.hold + ForgeSplashTiming.fadeOut,
            ForgeStrikeMarkGeometry.strikeDuration
        )
        XCTAssertLessThan(ForgeSplashTiming.hold + ForgeSplashTiming.fadeOut, ForgeSplashTiming.freezeCeiling)
        XCTAssertNotEqual(ForgeStrikeMarkGeometry.kind, AriaSigilGeometry.kind)
        XCTAssertNotEqual(ForgeStrikeMarkGeometry.kind, ForgeFireGeometry.kind)
    }

    func testBrandMarkForwardsToStrikeMark() {
        XCTAssertEqual(ForgeStrikeMarkGeometry.assetName, "ForgeStrikeMark")
        XCTAssertEqual(ForgeWelcomeCopy.markLabel, "Forge mark, a hammer striking a flame")
        XCTAssertTrue(ForgeStrikeMarkGeometry.isCompact(size: 18))
        XCTAssertTrue(ForgeStrikeMarkGeometry.isCompact(size: 22))
    }
}
