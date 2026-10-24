import XCTest
@testable import ForgeCore

final class ForgeWelcomeCopyTests: XCTestCase {

    func testActiveTaglineIsPrimary() {
        XCTAssertEqual(ForgeWelcomeCopy.activeIndex, 0)
        XCTAssertEqual(ForgeWelcomeCopy.all.count, 3)
        XCTAssertEqual(ForgeWelcomeCopy.primary, "Forged, not promised. The rest is you.")
        XCTAssertEqual(ForgeWelcomeCopy.heat, "We bring the heat. You do the shaping.")
        XCTAssertEqual(ForgeWelcomeCopy.work, "Stronger than you came in, if you put in the work.")
        XCTAssertEqual(ForgeWelcomeCopy.all[0], ForgeWelcomeCopy.primary)
        XCTAssertEqual(ForgeWelcomeCopy.all[1], ForgeWelcomeCopy.heat)
        XCTAssertEqual(ForgeWelcomeCopy.all[2], ForgeWelcomeCopy.work)
        XCTAssertEqual(ForgeWelcomeCopy.tagline, ForgeWelcomeCopy.all[ForgeWelcomeCopy.activeIndex])
        XCTAssertEqual(ForgeWelcomeCopy.tagline, ForgeWelcomeCopy.primary)
    }

    func testMarkLabelAndFirstPageLock() {
        XCTAssertEqual(ForgeWelcomeCopy.markLabel, "Forge mark, a hammer striking a flame")
        XCTAssertEqual(ForgeWelcomeCopy.firstPageId, "brand")
        XCTAssertEqual(ForgeWelcomeCopy.firstPageKicker, "Forge")
        XCTAssertEqual(
            ForgeWelcomeCopy.firstPageBody,
            "A calm place to train and live. The work is still yours."
        )
        XCTAssertFalse(ForgeWelcomeCopy.markLabel.isEmpty)
    }

    func testWelcomeCopyDoesNotLeakHealthMetrics() {
        let lines = ForgeWelcomeCopy.all + [
            ForgeWelcomeCopy.markLabel,
            ForgeWelcomeCopy.firstPageBody,
            ForgeWelcomeCopy.firstPageKicker,
        ]
        for line in lines {
            XCTAssertFalse(line.localizedCaseInsensitiveContains("HRV"), line)
            XCTAssertFalse(line.localizedCaseInsensitiveContains("heart rate"), line)
            XCTAssertFalse(line.localizedCaseInsensitiveContains("VO2"), line)
            XCTAssertFalse(line.localizedCaseInsensitiveContains("HealthKit"), line)
            XCTAssertNil(ForgeDesignTokens.containsBannedPhrase(line), line)
        }
    }
}
