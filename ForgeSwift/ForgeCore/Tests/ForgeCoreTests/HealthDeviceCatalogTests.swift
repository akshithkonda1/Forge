import XCTest
@testable import ForgeCore

final class HealthDeviceCatalogTests: XCTestCase {

    func testEveryDeviceHasAUniqueIDAndName() {
        let ids = HealthDeviceCatalog.all.map(\.id)
        let names = HealthDeviceCatalog.all.map(\.name)
        XCTAssertEqual(ids.count, Set(ids).count)
        XCTAssertEqual(names.count, Set(names).count)
        XCTAssertGreaterThanOrEqual(ids.count, 16)
    }

    func testEveryDeviceIsIOSAndHealthCompatible() {
        for device in HealthDeviceCatalog.all {
            XCTAssertTrue(device.hasIOSApp, device.name)
            XCTAssertFalse(device.metrics.isEmpty, device.name)
            XCTAssertFalse(device.setupHint.isEmpty, device.name)
        }
    }

    func testLarqBottleIsInTheHydrationLibrary() {
        let larq = HealthDeviceCatalog.device(matching: "LARQ Bottle")
        XCTAssertEqual(larq?.id, "larq-bottle")
        XCTAssertEqual(larq?.category, .hydration)
        XCTAssertTrue(larq?.writesToAppleHealth == true)
        XCTAssertTrue(larq?.hasIOSApp == true)
    }

    func testMatchingAcceptsOldDisplayNames() {
        XCTAssertEqual(HealthDeviceCatalog.device(matching: "Apple Watch")?.id, "apple-watch")
        XCTAssertEqual(HealthDeviceCatalog.device(matching: "Oura Ring")?.id, "oura-ring")
        XCTAssertEqual(HealthDeviceCatalog.device(matching: "oura-ring")?.name, "Oura Ring")
    }

    func testMigrateDedupsLegacyNames() {
        let migrated = HealthDeviceCatalog.migrateStoredIDs([
            "Apple Watch", "apple-watch", "Oura Ring", "Whoop",
        ])
        XCTAssertEqual(migrated, ["apple-watch", "oura-ring", "whoop"])
    }

    func testSearchFindsByMetricAndMaker() {
        XCTAssertTrue(HealthDeviceCatalog.search("glucose").contains { $0.id == "dexcom" })
        XCTAssertTrue(HealthDeviceCatalog.search("larq").contains { $0.id == "larq-bottle" })
        XCTAssertTrue(HealthDeviceCatalog.search("water").contains { $0.id == "hidratespark" })
    }
}
