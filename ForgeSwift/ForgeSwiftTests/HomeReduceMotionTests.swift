import XCTest
@testable import ForgeSwift

/// Locks Reduce Motion still poses for the Home ring-field and sleep chart.
@MainActor
final class HomeReduceMotionTests: XCTestCase {

    func testReduceMotionFreezesRingFieldAndChart() {
        XCTAssertTrue(HomeReadinessFieldView.isFrozen(reduceMotion: true, minimal: false))
        XCTAssertTrue(HomeReadinessFieldView.isFrozen(reduceMotion: false, minimal: true))
        XCTAssertTrue(HomeReadinessFieldView.isFrozen(reduceMotion: true, minimal: true))
        XCTAssertFalse(HomeReadinessFieldView.isFrozen(reduceMotion: false, minimal: false))

        XCTAssertEqual(HomeTrendSection.plottedScore(70, grown: false, reduceMotion: true), 70)
        XCTAssertEqual(HomeTrendSection.plottedScore(30, grown: false, reduceMotion: true), 30)
        XCTAssertEqual(HomeTrendSection.plottedScore(70, grown: false, reduceMotion: false), 0)
        XCTAssertEqual(HomeTrendSection.plottedScore(70, grown: true, reduceMotion: false), 70)
        XCTAssertEqual(HomeTrendSection.plottedScore(70, grown: true, reduceMotion: true), 70)
    }
}
