import XCTest
import ForgeCore
@testable import ForgeSwift

@MainActor
final class ForgeChromeTests: XCTestCase {

    func testTypeScaleAliasesForgeType() {
        XCTAssertEqual(FDS.Spacing.lg, ForgeDS.Spacing.lg)
        XCTAssertEqual(FDS.Radius.xl, ForgeDS.Radius.xl)
        XCTAssertEqual(FDS.minTapIfPresent, 44)
        XCTAssertEqual(ForgeDesignTokens.TypeRole.allCases.map(\.rawValue), [
            "display", "title", "headline", "body", "caption", "metric"
        ])
        XCTAssertTrue(ForgeDesignTokens.TypeRole.metric.tabular)
    }

    func testReadinessHelpersUseHomeWords() {
        XCTAssertEqual(readinessLabel(for: 90), "Peak")
        XCTAssertEqual(readinessLabel(for: 72), "Good")
        XCTAssertEqual(readinessLabel(for: 60), "Fair")
        XCTAssertEqual(readinessLabel(for: 40), "Low")
        XCTAssertEqual(HomeReadiness.label(90), "Peak")
        XCTAssertEqual(ReadinessBand(score: 72).label, "Good")
        for foreign in HomeReadinessTokens.foreignBandLabels {
            XCTAssertNotEqual(readinessLabel(for: 90), foreign)
            XCTAssertNotEqual(readinessLabel(for: 40), foreign)
        }
    }

    func testCoachCopyStaysIdentityFirst() {
        XCTAssertEqual(HomeCoachCopy.nextNow, "Do this now")
        XCTAssertEqual(HomeCoachCopy.lighterWin, "A lighter win")
        XCTAssertEqual(AriaMeetCopy.eyebrow, "Your lifestyle coach")
        XCTAssertNil(HomeReadinessTokens.containsBannedPhrase(AriaMeetCopy.eyebrow))
        XCTAssertNil(ForgeDesignTokens.containsBannedPhrase(AriaMeetCopy.lead))
        XCTAssertNil(ForgeDesignTokens.containsBannedPhrase(HomeCoachCopy.easyDayLow))
        XCTAssertFalse(AriaMeetCopy.eyebrow.localizedCaseInsensitiveContains("Adaptive Recovery"))
        XCTAssertFalse(AriaMeetCopy.lead.localizedCaseInsensitiveContains("recovery week"))
    }

    func testUXTokens() {
        XCTAssertEqual(ForgeUX.minTap, 44)
        XCTAssertEqual(ForgeDesignTokens.UX.navBack, "leading")
        XCTAssertEqual(ForgeDesignTokens.UX.sheetClose, "trailing")
        XCTAssertEqual(ForgeDesignTokens.Haptic.primaryCTA.token, "medium")
        XCTAssertEqual(ForgeDesignTokens.Haptic.press.token, "light")
        XCTAssertTrue(ForgeDesignTokens.Motion.eventOnly)
        XCTAssertFalse(HomeReadinessTokens.liveGlowDefault)
    }
}

private extension FDS {
    static var minTapIfPresent: CGFloat { ForgeDS.minTap }
}
