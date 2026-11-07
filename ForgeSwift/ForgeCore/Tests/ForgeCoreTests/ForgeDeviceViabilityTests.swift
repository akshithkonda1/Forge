import XCTest
@testable import ForgeCore

final class ForgeDeviceViabilityTests: XCTestCase {

    func testReadyWhenOSBuildAndHealthKitPass() {
        let v = ForgeDeviceViabilityCheck.evaluate(
            major: 26, minor: 5,
            appBuild: "12",
            minimumBuild: "1",
            healthKitAvailable: true,
            healthKitAuthorized: true
        )
        XCTAssertTrue(v.ready)
        XCTAssertTrue(v.reasons.isEmpty)
        XCTAssertFalse(v.reasons.contains { $0.contains("188") || $0.contains("hrv") })
    }

    func testBelow265IsNotReadyAndCarriesNoHealthValues() {
        let v = ForgeDeviceViabilityCheck.evaluate(
            major: 26, minor: 4,
            appBuild: "12",
            healthKitAvailable: true,
            healthKitAuthorized: true
        )
        XCTAssertFalse(v.osMeetsMinimum)
        XCTAssertFalse(v.ready)
        XCTAssertTrue(v.reasons.contains { $0.contains("26.5") })
        XCTAssertFalse(v.reasons.joined().contains("\(ForgeOutboundSanitizer.Canary.heartRate)"))
    }

    func testHealthKitDeniedIsNotAVital() {
        let v = ForgeDeviceViabilityCheck.evaluate(
            major: 27, minor: 0,
            appBuild: "12",
            healthKitAvailable: true,
            healthKitAuthorized: false
        )
        XCTAssertFalse(v.ready)
        XCTAssertTrue(v.reasons.contains { $0.lowercased().contains("permission") })
        XCTAssertFalse(v.reasons.joined().contains("bpm"))
    }
}
