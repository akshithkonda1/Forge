import XCTest
@testable import ForgeCore

final class HealthDeviceCatalogTests: XCTestCase {

    override func setUp() {
        super.setUp()
        HealthDeviceCatalog.resetOverlays()
    }

    override func tearDown() {
        HealthDeviceCatalog.resetOverlays()
        super.tearDown()
    }

    func testEveryDeviceHasAUniqueIDAndName() {
        let ids = HealthDeviceCatalog.all.map(\.id)
        let names = HealthDeviceCatalog.all.map(\.name)
        XCTAssertEqual(ids.count, Set(ids).count)
        XCTAssertEqual(names.count, Set(names).count)
        XCTAssertGreaterThanOrEqual(ids.count, 16)
    }

    func testEveryDeviceIsIOSAndHealthCompatible() {
        for device in HealthDeviceCatalog.listing {
            XCTAssertTrue(device.hasIOSApp, device.name)
            XCTAssertTrue(device.stillCompatible, device.name)
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
        XCTAssertEqual(HealthDeviceCatalog.device(matching: "oura-ring")?.name, "Oura Ring Gen3")
    }

    func testCompaniesGroupMultipleProducts() {
        let oura = HealthDeviceCatalog.devices(fromMaker: "Oura")
        XCTAssertGreaterThanOrEqual(oura.count, 2)
        let larq = HealthDeviceCatalog.devices(fromMaker: "LARQ")
        XCTAssertGreaterThanOrEqual(larq.count, 2)
        XCTAssertTrue(HealthDeviceCatalog.brands.contains { $0.name == "LARQ" })
    }

    func testFilterBrandsByDeviceType() {
        let hydration = HealthDeviceCatalog.searchBrands("", category: .hydration)
        XCTAssertTrue(hydration.contains { $0.name == "LARQ" })
        XCTAssertFalse(hydration.contains { $0.name == "Oura" })
    }

    func testArtworkMapsProductsToPhotos() {
        XCTAssertEqual(HealthDeviceCatalog.device(matching: "larq-bottle")?.artwork, .bottle)
        XCTAssertEqual(HealthDeviceCatalog.device(matching: "oura-ring")?.artwork, .ring)
        XCTAssertEqual(HealthDeviceCatalog.device(matching: "apple-watch")?.artwork, .watch)
        XCTAssertEqual(HealthDeviceCatalog.device(matching: "dexcom")?.artwork, .sensor)
        XCTAssertEqual(HealthDeviceCatalog.device(matching: "larq-bottle")?.photoAssetName, "DevicePhoto-larq-bottle")
    }

    func testNamesAreRetailBoxNames() {
        let names = Set(HealthDeviceCatalog.all.map(\.name))
        XCTAssertTrue(names.contains("Apple Watch Series 11"))
        XCTAssertTrue(names.contains("Apple Watch Ultra 3"))
        XCTAssertTrue(names.contains("Apple Watch SE 3"))
        XCTAssertTrue(names.contains("AirPods Pro 3"))
        XCTAssertTrue(names.contains("Oura Ring 4"))
        XCTAssertTrue(names.contains("Oura Ring 5"))
        XCTAssertTrue(names.contains("WHOOP 5.0"))
        XCTAssertTrue(names.contains("WHOOP MG"))
        XCTAssertTrue(names.contains("Garmin Forerunner 970"))
        XCTAssertTrue(names.contains("Garmin fēnix 8"))
        XCTAssertTrue(names.contains("Garmin Venu 4"))
        XCTAssertTrue(names.contains("LARQ Bottle PureVis 2"))
        XCTAssertTrue(names.contains("LARQ Pitcher PureVis"))
        XCTAssertTrue(names.contains("HidrateSpark PRO 2"))
        XCTAssertTrue(names.contains("Eight Sleep Pod 5"))
        XCTAssertTrue(names.contains("Withings ScanWatch 2"))
        XCTAssertTrue(names.contains("Withings Sleep Analyzer"))
        XCTAssertTrue(names.contains("Withings Body Comp"))
        XCTAssertTrue(names.contains("Peloton Bike+"))
        XCTAssertTrue(names.contains("Dexcom G7"))
        XCTAssertTrue(names.contains("FreeStyle Libre 3"))
        XCTAssertTrue(names.contains("COROS PACE 3"))
        XCTAssertTrue(names.contains("Fitbit Charge 6"))
        XCTAssertTrue(names.contains("Google Pixel Watch 5"))
        XCTAssertFalse(names.contains("Garmin watch"))
        XCTAssertFalse(names.contains("Polar watch"))
        XCTAssertFalse(names.contains("Amazfit / Zepp"))
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

    func testListingDropsIncompatibleModelsAfterFiveCycles() {
        XCTAssertNotNil(HealthDeviceCatalog.all.first { $0.id == "apple-watch-s6" })
        XCTAssertNotNil(HealthDeviceCatalog.all.first { $0.id == "oura-ring-heritage" })
        XCTAssertFalse(HealthDeviceCatalog.listing.contains { $0.id == "apple-watch-s6" })
        XCTAssertFalse(HealthDeviceCatalog.listing.contains { $0.id == "oura-ring-heritage" })
        XCTAssertFalse(HealthDeviceCatalog.search("heritage").contains { $0.id == "oura-ring-heritage" })
        XCTAssertFalse(HealthDeviceCatalog.devices(fromMaker: "Apple").contains { $0.id == "apple-watch-s6" })
        XCTAssertTrue(HealthDeviceCatalog.listing.contains { $0.id == "apple-watch" })
        XCTAssertTrue(HealthDeviceCatalog.listing.contains { $0.id == "oura-ring-5" })
        XCTAssertTrue(HealthDeviceCatalog.listing.contains { $0.id == "oura-ring" })
    }

    func testArchiveStillResolvesConnectedRetiredIDs() {
        XCTAssertEqual(HealthDeviceCatalog.device(matching: "apple-watch-s6")?.id, "apple-watch-s6")
        XCTAssertEqual(HealthDeviceCatalog.device(matching: "oura-ring-heritage")?.id, "oura-ring-heritage")
        XCTAssertEqual(
            HealthDeviceCatalog.migrateStoredIDs(["apple-watch-s6", "oura-ring-heritage"]),
            ["apple-watch-s6", "oura-ring-heritage"]
        )
        XCTAssertFalse(HealthDeviceCatalog.isListed(
            HealthDeviceCatalog.device(matching: "apple-watch-s6")!
        ))
    }

    func testBrandsCountOnlyListedProductsAndExposeNewestYear() {
        let oura = HealthDeviceCatalog.brands.first { $0.name == "Oura" }
        XCTAssertEqual(oura?.productCount, 3)
        XCTAssertEqual(oura?.newestYear, 2026)
        let apple = HealthDeviceCatalog.brands.first { $0.name == "Apple" }
        XCTAssertEqual(apple?.productCount, 5)
        XCTAssertEqual(apple?.newestYear, 2025)
        XCTAssertFalse(HealthDeviceCatalog.brands.contains { $0.name == "Oura" && $0.productCount >= 4 })
    }

    func testListingSortsNewestGenerationFirst() {
        let oura = HealthDeviceCatalog.devices(fromMaker: "Oura")
        XCTAssertEqual(Array(oura.map(\.id).prefix(3)), ["oura-ring-5", "oura-ring-4", "oura-ring"])
        XCTAssertEqual(oura.map(\.generation), oura.map(\.generation).sorted(by: >))
        let eight = HealthDeviceCatalog.devices(fromMaker: "Eight Sleep")
        XCTAssertEqual(eight.first?.id, "eight-sleep-pod5")
    }

    func testAddingANewCycleAgesTheLineOffTheShelf() {
        let series = (6...11).map { gen in
            catalogDevice(
                id: "s\(gen)",
                generation: gen,
                compatible: gen >= 7
            )
        }
        let before = HealthDeviceCatalog.listed(from: series)
        XCTAssertTrue(before.contains { $0.id == "s11" })
        XCTAssertTrue(before.contains { $0.id == "s7" })
        XCTAssertFalse(before.contains { $0.id == "s6" })

        let after = HealthDeviceCatalog.listed(from: series + [
            catalogDevice(id: "s12", generation: 12, compatible: true)
        ])
        XCTAssertTrue(after.contains { $0.id == "s12" })
        XCTAssertTrue(after.contains { $0.id == "s8" })
        XCTAssertFalse(after.contains { $0.id == "s7" })
        XCTAssertFalse(after.contains { $0.id == "s6" })
    }

    func testCompatibleModelsStayPastFiveCycles() {
        let devices = (1...12).map { gen in
            catalogDevice(id: "keep-\(gen)", generation: gen, compatible: true)
        }
        let listed = HealthDeviceCatalog.listed(from: devices)
        XCTAssertEqual(Set(listed.map(\.id)), Set(devices.map(\.id)))
    }

    func testRemoteOverlayAddsANewProductWithoutAnAppUpdate() {
        let incoming = catalogDevice(id: "s12", generation: 12, compatible: true)
        HealthDeviceCatalog.applyRemote(HealthDeviceCatalogPayload(devices: [incoming]))
        XCTAssertEqual(HealthDeviceCatalog.device(matching: "s12")?.name, "s12")
        XCTAssertTrue(HealthDeviceCatalog.listing.contains { $0.id == "s12" })
    }

    func testRemoteOverlayAgesTheBundledLine() {
        let series12 = HealthDevice(
            id: "apple-watch-s12",
            name: "Apple Watch Series 12",
            maker: "Apple",
            category: .apple,
            summary: "Next Series.",
            metrics: ["Heart rate"],
            writesToAppleHealth: true,
            hasIOSApp: true,
            worksWithAppleWatch: true,
            appStoreURL: nil,
            setupHint: "Pair in the Watch app.",
            symbolName: "applewatch",
            line: "apple-watch-series",
            generation: 12,
            releasedYear: 2026,
            stillCompatible: true
        )
        HealthDeviceCatalog.applyRemote(HealthDeviceCatalogPayload(devices: [series12]))
        XCTAssertTrue(HealthDeviceCatalog.listing.contains { $0.id == "apple-watch-s12" })
        XCTAssertTrue(HealthDeviceCatalog.listing.contains { $0.id == "apple-watch" })
        XCTAssertFalse(HealthDeviceCatalog.listing.contains { $0.id == "apple-watch-s6" })
    }

    func testHealthKitSourceBecomesACatalogRow() {
        let found = HealthDeviceCatalog.inferredDevices(
            fromHealthSources: ["Suunto Race", "Oura", "iPhone", "Health"],
            known: HealthDeviceCatalog.bundled,
            year: 2026
        )
        XCTAssertEqual(found.map(\.id), ["discovered-suunto-race"])
        XCTAssertEqual(found.first?.maker, "Suunto")
        HealthDeviceCatalog.applyDiscovered(found)
        XCTAssertEqual(HealthDeviceCatalog.device(matching: "Suunto Race")?.id, "discovered-suunto-race")
        XCTAssertTrue(HealthDeviceCatalog.listing.contains { $0.id == "discovered-suunto-race" })
        XCTAssertEqual(HealthDeviceCatalog.devices(fromMaker: "Oura").count, 3)
    }

    func testCatalogPayloadRoundTrips() throws {
        let payload = HealthDeviceCatalogPayload(
            version: 2,
            updatedAt: "2026-08-12T00:00:00Z",
            devices: [catalogDevice(id: "s12", generation: 12, compatible: true)],
            retire: ["apple-watch-s6"]
        )
        let data = try HealthDeviceCatalog.encodePayload(payload)
        let decoded = try HealthDeviceCatalog.decodePayload(data)
        XCTAssertEqual(decoded.version, 2)
        XCTAssertEqual(decoded.devices.map(\.id), ["s12"])
        XCTAssertEqual(decoded.retire, ["apple-watch-s6"])
    }

    private func catalogDevice(
        id: String,
        generation: Int,
        compatible: Bool
    ) -> HealthDevice {
        HealthDevice(
            id: id,
            name: id,
            maker: "Apple",
            category: .apple,
            summary: "test",
            metrics: ["Heart"],
            writesToAppleHealth: compatible,
            hasIOSApp: compatible,
            worksWithAppleWatch: true,
            appStoreURL: nil,
            setupHint: "test",
            symbolName: "applewatch",
            line: "apple-watch-series",
            generation: generation,
            releasedYear: 2014 + generation,
            stillCompatible: compatible
        )
    }
}
