import XCTest
import ForgeCore

final class AriaTTSPrivacyTests: XCTestCase {
    func testQualitativeCoachingIsSafe() {
        let cleaned = AriaTTSPrivacy.sanitize(
            "I'm ARIA. Let's look at how you actually slept."
        )
        XCTAssertTrue(cleaned.canSendToCloud)
    }

    func testCanaryNameAndHealthNeverPass() {
        let line = "\(AriaTTSPrivacy.canaryName) \(AriaTTSPrivacy.canaryEmail) \(AriaTTSPrivacy.canaryHRV) \(AriaTTSPrivacy.canaryReadiness)"
        let cleaned = AriaTTSPrivacy.sanitize(line, names: [AriaTTSPrivacy.canaryName])
        XCTAssertFalse(cleaned.safe)
        XCTAssertFalse(cleaned.text.contains(AriaTTSPrivacy.canaryName))
        XCTAssertFalse(cleaned.text.contains(AriaTTSPrivacy.canaryEmail))
        XCTAssertFalse(cleaned.text.contains("HRV 32"))
    }
}
