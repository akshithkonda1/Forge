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
        XCTAssertEqual(ForgeHaptic.allCases.map(\.rawValue), ["selection", "press", "success", "warning", "error"])
        XCTAssertEqual(ForgeHaptic.press.token, "light")
        XCTAssertTrue(ForgeDesignTokens.Motion.eventOnly)
        XCTAssertFalse(HomeReadinessTokens.liveGlowDefault)
    }

    func testCardPaddingHoldsAt24AndDecorativeClocksStayAtOrUnder12Hz() {
        XCTAssertEqual(FDS.Spacing.xl, 24)
        XCTAssertEqual(HomeMetrics.cardPadding, 24)
        XCTAssertEqual(ForgeLayout.cardPadding, HomeMetrics.cardPadding)
        XCTAssertEqual(HomeMetrics.cardPadding, FDS.Spacing.xl)
        XCTAssertEqual(HomeMetrics.cardRadius, FDS.Radius.xl)
        XCTAssertEqual(ForgeLayout.sectionGap, HomeMetrics.sectionGap)
        XCTAssertEqual(ForgeLayout.screenInset, HomeMetrics.inset)
        XCTAssertEqual(CelebrationOverlay.tickHz, 0, accuracy: 0.0001)
        XCTAssertTrue(CelebrationOverlay.isClockPaused(reduceMotion: false, sceneActive: true, onscreen: true))
        XCTAssertTrue(CelebrationOverlay.isClockPaused(reduceMotion: true, sceneActive: true, onscreen: true))
        XCTAssertFalse(CelebrationOverlay.title.localizedCaseInsensitiveContains("recovery"))
        XCTAssertFalse(CelebrationOverlay.line.localizedCaseInsensitiveContains("recovery"))
        XCTAssertEqual(ForgeMosaicTracks.count, 5)
        XCTAssertEqual(ForgeMosaicTracks.titles, ["Sleep", "Train", "Water", "Move", "Habits"])
        XCTAssertLessThanOrEqual(MusicControlBar.tickHz, ForgeMotion.maxTickHz)
        XCTAssertLessThanOrEqual(TypingIndicator.tickHz, ForgeMotion.maxTickHz)
        XCTAssertEqual(MusicControlBar.tickInterval, 1.0 / MusicControlBar.tickHz, accuracy: 0.0001)
        XCTAssertEqual(TypingIndicator.tickInterval, 1.0 / TypingIndicator.tickHz, accuracy: 0.0001)
        XCTAssertTrue(MusicControlBar.isClockPaused(reduceMotion: false, sceneActive: false, onscreen: true))
        XCTAssertTrue(TypingIndicator.isClockPaused(reduceMotion: false, sceneActive: true, onscreen: false))
        XCTAssertFalse(MusicControlBar.isClockPaused(reduceMotion: false, sceneActive: true, onscreen: true))
        XCTAssertFalse(TypingIndicator.isClockPaused(reduceMotion: false, sceneActive: true, onscreen: true))
    }
}

private extension FDS {
    static var minTapIfPresent: CGFloat { ForgeDS.minTap }
}
