import XCTest
@testable import ForgeCore

final class SleepCoachCopyTests: XCTestCase {

    func testCoachCopyBansThePolicyWords() {
        XCTAssertEqual(SleepCoachCopy.containsBannedPhrase("I'm not a doctor"), "not a doctor")
        XCTAssertEqual(SleepCoachCopy.containsBannedPhrase("outside your range"), "outside your range")
        XCTAssertEqual(SleepCoachCopy.containsBannedPhrase("recovery week"), "recovery week")
        XCTAssertEqual(SleepCoachCopy.containsBannedPhrase("Extra recovery tonight"), "recovery")
        XCTAssertEqual(SleepCoachCopy.containsBannedPhrase("never leaves your phone"), "never leaves your phone")
        XCTAssertNil(SleepCoachCopy.containsBannedPhrase(SleepCoachCopy.disclaimer))
        XCTAssertFalse(SleepCoachCopy.disclaimer.localizedCaseInsensitiveContains("not a doctor"))
        XCTAssertTrue(SleepCoachCopy.disclaimer.contains(SleepCoachCopy.medicalLine))
        XCTAssertFalse(SleepCoachCopy.environmentHint.localizedCaseInsensitiveContains("medical assessment"))
        XCTAssertTrue(SleepCoachCopy.environmentHint.localizedCaseInsensitiveContains("photo of the room"))
    }
}
