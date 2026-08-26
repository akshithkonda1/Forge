import XCTest
@testable import ForgeSwift

/// The digest is the only thing a supporter is allowed to hold. These tests
/// fail if a tier starts smuggling flow, fertility, BBT, or a next-period date
/// the owner did not opt into.
final class PartnerCycleDigestTests: XCTestCase {

    // MARK: - Tiers

    func testOnPeriodIsYesOrNoWithNoBleedDayOrTiming() {
        let digest = PartnerCycleDigest(redacting: bleedingSnapshot(), tier: .onPeriod)

        XCTAssertEqual(digest.phase, .bleeding)
        XCTAssertEqual(digest.energy, .steady, "energy would leak luteal vs follicular")
        XCTAssertNil(digest.periodDay)
        XCTAssertNil(digest.daysUntilNextPeriodApprox)
        XCTAssertTrue(digest.extraThoughtfulnessHelps)
        XCTAssertEqual(digest.supportHeadline, "Be extra kind this week.")
    }

    func testOnPeriodWhenNotBleedingDoesNotLookLikeNoData() {
        let digest = PartnerCycleDigest(redacting: fertileSnapshot(), tier: .onPeriod)

        XCTAssertEqual(digest.phase, .notBleeding)
        XCTAssertNil(digest.periodDay)
        XCTAssertNil(digest.daysUntilNextPeriodApprox)
        XCTAssertFalse(digest.extraThoughtfulnessHelps)
        XCTAssertEqual(digest.supportHeadline, "Everyday support is enough.")
    }

    func testSupportCoachIncludesBleedDayAndDropsTiming() {
        let digest = PartnerCycleDigest(redacting: bleedingSnapshot(), tier: .supportCoach)

        XCTAssertEqual(digest.phase, .bleeding)
        XCTAssertEqual(digest.periodDay, 2)
        XCTAssertNil(digest.daysUntilNextPeriodApprox, "timing is opt-in")
        XCTAssertTrue(digest.supportHeadline.contains("Day 2"))
    }

    func testSupportCoachDefaultHidesFertileWindowAsRebuilding() {
        let digest = PartnerCycleDigest(redacting: fertileSnapshot())

        XCTAssertEqual(digest.phase, .rebuilding,
                       "fertile/ovulatory days must be indistinguishable from follicular")
        XCTAssertNil(digest.periodDay)
        XCTAssertNil(digest.daysUntilNextPeriodApprox)
    }

    func testTimingIncludesCoarseNextPeriodWindow() {
        let digest = PartnerCycleDigest(redacting: fertileSnapshot(), tier: .timing)

        XCTAssertEqual(digest.phase, .rebuilding)
        XCTAssertEqual(digest.daysUntilNextPeriodApprox, 14)
        XCTAssertNil(digest.periodDay)
    }

    // MARK: - Redaction

    func testDigestJSONNeverCarriesSnapshotSecrets() throws {
        for tier in PartnerShareTier.allCases {
            let digest = PartnerCycleDigest(redacting: bleedingSnapshot(), tier: tier)
            let data = try JSONEncoder().encode(digest)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

            let forbidden = [
                "fertileScore", "ovulationDayInCycle", "cycleGoal", "twwDaysElapsed",
                "flow", "symptoms", "bbt", "mucus", "condition", "dayInCycle",
                "nextPeriod", "ovulationConfidence",
            ]
            for key in forbidden {
                XCTAssertNil(object[key], "tier \(tier.rawValue) leaked \(key)")
            }

            let allowed: Set<String> = [
                "phase", "energy", "daysUntilNextPeriodApprox", "periodDay",
                "extraThoughtfulnessHelps", "supportHeadline", "asOfDayKey",
                "periodFinished", "periodFinishedDayKey",
            ]
            for key in object.keys {
                XCTAssertTrue(allowed.contains(key), "unexpected digest key \(key)")
            }
        }
    }

    func testInviteFallbackNamesNoCycleDetails() {
        let invite = PartnerCycleInvite(
            shareURL: URL(string: "https://www.icloud.com/share/abc")!,
            role: .romantic,
            fromDisplayName: "Sam"
        )
        let body = invite.fallbackMessageBody.lowercased()
        XCTAssertFalse(body.contains("period"))
        XCTAssertFalse(body.contains("cycle"))
        XCTAssertFalse(body.contains("fertile"))
        XCTAssertTrue(body.contains("support"))
        XCTAssertTrue(invite.bubbleCaption.lowercased().contains("support"))
    }

    // MARK: - Fixtures

    private func bleedingSnapshot() -> MenstrualCycleSnapshot {
        var snap = MenstrualCycleSnapshot.empty
        snap.asOfDayKey = "2026-03-12"
        snap.trackingEnabled = true
        snap.phase = .menstruation
        snap.dayInCycle = 2
        snap.currentPeriodDayCount = 2
        snap.isCurrentlyBleeding = true
        snap.recommendRecoveryBias = true
        snap.fertileScore = 88
        snap.ovulationDayInCycle = 14
        snap.cycleGoal = .ttc
        snap.twwDaysElapsed = 3
        snap.condition = .endometriosis
        snap.periodTimingConfidence = 0.9
        snap.nextPeriod = CyclePredictionRange(
            earliestDayKey: "2026-04-07",
            medianDayKey: "2026-04-09",
            latestDayKey: "2026-04-11"
        )
        return snap
    }

    private func fertileSnapshot() -> MenstrualCycleSnapshot {
        var snap = MenstrualCycleSnapshot.empty
        snap.asOfDayKey = "2026-03-12"
        snap.trackingEnabled = true
        snap.phase = .fertileWindow
        snap.dayInCycle = 14
        snap.isCurrentlyBleeding = false
        snap.fertileScore = 92
        snap.ovulationDayInCycle = 14
        snap.cycleGoal = .ttc
        snap.periodTimingConfidence = 0.8
        snap.nextPeriod = CyclePredictionRange(
            earliestDayKey: "2026-03-24",
            medianDayKey: "2026-03-26",
            latestDayKey: "2026-03-28"
        )
        return snap
    }
}
