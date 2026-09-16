import XCTest
@testable import ForgeCore

final class BodyModelHRVTests: XCTestCase {

    private func sample(
        _ statistic: HRVStatistic,
        ms: Double,
        density: HRVSamplingDensity? = nil,
        at offset: TimeInterval = 0
    ) -> HRVObservation {
        HRVObservation(
            statistic: statistic,
            milliseconds: ms,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000 + offset),
            samplingDensity: density ?? .default(for: statistic),
            source: "test"
        )
    }

    func testRMSSDAndSDNNAreDistinctTypesAndIdentifiers() {
        XCTAssertNotEqual(HRVStatistic.sdnn, HRVStatistic.rmssd)
        XCTAssertNotEqual(HRVStatistic.sdnn.rawValue, HRVStatistic.rmssd.rawValue)
        XCTAssertEqual(HRVStatistic.sdnn.rawValue, "hrv_sdnn")
        XCTAssertEqual(HRVStatistic.rmssd.rawValue, "hrv_rmssd")
        XCTAssertEqual(
            HRVStatistic.sdnn.healthKitIdentifierRaw,
            "HKQuantityTypeIdentifierHeartRateVariabilitySDNN"
        )
        XCTAssertEqual(
            HRVStatistic.rmssd.healthKitIdentifierRaw,
            "HKQuantityTypeIdentifierHeartRateVariabilityRMSSD"
        )
        XCTAssertNotEqual(
            HealthKitHRVQuantity.sdnnIdentifierRaw,
            HealthKitHRVQuantity.rmssdIdentifierRaw
        )
        XCTAssertEqual(HRVStatistic.sdnn.cloudMetricType, "hrv-sdnn")
        XCTAssertEqual(HRVStatistic.rmssd.cloudMetricType, "hrv-rmssd")
        XCTAssertNotEqual(HRVStatistic.sdnn.cloudMetricType, HRVStatistic.rmssd.cloudMetricType)
    }

    func testMetricNamesNeverAliasRMSSDToSDNN() {
        XCTAssertEqual(HRVStatistic.fromMetricName("rmssd"), .rmssd)
        XCTAssertEqual(HRVStatistic.fromMetricName("hrv_rmssd"), .rmssd)
        XCTAssertEqual(HRVStatistic.fromMetricName("hrv-rmssd"), .rmssd)
        XCTAssertEqual(HRVStatistic.fromMetricName("heartRateVariabilityRMSSD"), .rmssd)
        XCTAssertEqual(
            HRVStatistic.fromHealthKitIdentifierRaw(HealthKitHRVQuantity.rmssdIdentifierRaw),
            .rmssd
        )

        XCTAssertEqual(HRVStatistic.fromMetricName("sdnn"), .sdnn)
        XCTAssertEqual(HRVStatistic.fromMetricName("hrv_sdnn"), .sdnn)
        XCTAssertEqual(HRVStatistic.fromMetricName("hrv"), .sdnn)
        XCTAssertEqual(HRVStatistic.fromMetricName("heartRateVariabilitySDNN"), .sdnn)
        XCTAssertEqual(
            HRVStatistic.fromHealthKitIdentifierRaw(HealthKitHRVQuantity.sdnnIdentifierRaw),
            .sdnn
        )

        XCTAssertNotEqual(
            HRVStatistic.fromMetricName("rmssd"),
            HRVStatistic.fromMetricName("sdnn")
        )
        XCTAssertNotEqual(
            HRVStatistic.fromMetricName("rmssd"),
            HRVStatistic.fromMetricName("hrv")
        )
        XCTAssertNil(HRVStatistic.fromMetricName("recovery"))
        XCTAssertNil(HRVStatistic.fromMetricName("readiness"))
        XCTAssertNil(HRVStatistic.fromMetricName("health-age"))
        XCTAssertNil(HRVStatistic.fromMetricName("healthAge"))
        XCTAssertNil(HRVStatistic.fromMetricName("apple-readiness"))
        XCTAssertNil(HRVStatistic.fromHealthKitIdentifierRaw("HKQuantityTypeIdentifierHeartRate"))
    }

    func testCloudCanonicalTypeDoesNotCollapseRMSSDIntoHRV() {
        XCTAssertEqual(CloudHealthMetricType.canonicalType("hrv-rmssd"), "hrv-rmssd")
        XCTAssertEqual(CloudHealthMetricType.canonicalType("hrv_rmssd"), "hrv-rmssd")
        XCTAssertEqual(CloudHealthMetricType.canonicalType("rmssd"), "hrv-rmssd")
        XCTAssertEqual(CloudHealthMetricType.canonicalType("heartRateVariabilityRMSSD"), "hrv-rmssd")

        XCTAssertEqual(CloudHealthMetricType.canonicalType("hrv"), "hrv")
        XCTAssertEqual(CloudHealthMetricType.canonicalType("hrv-sdnn"), "hrv-sdnn")
        XCTAssertEqual(CloudHealthMetricType.canonicalType("sdnn"), "hrv-sdnn")

        XCTAssertNotEqual(
            CloudHealthMetricType.canonicalType("rmssd"),
            CloudHealthMetricType.canonicalType("hrv")
        )
        XCTAssertNotEqual(
            CloudHealthMetricType.canonicalType("rmssd"),
            CloudHealthMetricType.canonicalType("sdnn")
        )
        XCTAssertTrue(CloudHealthMetricType.valid.contains("hrv-rmssd"))
        XCTAssertTrue(CloudHealthMetricType.valid.contains("hrv-sdnn"))
    }

    func testIngestingRMSSDDoesNotMoveTheSDNNBaseline() {
        var baselines = BodyModelHRVBaselines()
        baselines.ingest(sample(.sdnn, ms: 55))
        baselines.ingest(sample(.sdnn, ms: 57))
        let sdnnBefore = baselines.sdnn
        baselines.ingest(sample(.rmssd, ms: 32))
        baselines.ingest(sample(.rmssd, ms: 30))

        XCTAssertEqual(baselines.sdnn.n, 2)
        XCTAssertEqual(baselines.sdnn.mean, sdnnBefore.mean, accuracy: 1e-12)
        XCTAssertEqual(baselines.sdnn.last, 57)
        XCTAssertEqual(baselines.rmssd.n, 2)
        XCTAssertEqual(baselines.rmssd.last, 30)
        XCTAssertEqual(baselines.rmssd.mean, 31, accuracy: 1e-12)
        XCTAssertNotEqual(baselines.sdnn.last, baselines.rmssd.last)
    }

    func testIngestingSDNNDoesNotMoveTheRMSSDBaseline() {
        var baselines = BodyModelHRVBaselines()
        baselines.ingest(sample(.rmssd, ms: 28))
        baselines.ingest(sample(.rmssd, ms: 26))
        let rmssdBefore = baselines.rmssd
        baselines.ingest(sample(.sdnn, ms: 70))

        XCTAssertEqual(baselines.rmssd.n, 2)
        XCTAssertEqual(baselines.rmssd.mean, rmssdBefore.mean, accuracy: 1e-12)
        XCTAssertEqual(baselines.sdnn.n, 1)
        XCTAssertEqual(baselines.sdnn.last, 70)
    }

    func testSameMillisecondValueStaysOnSeparateTracks() {
        var baselines = BodyModelHRVBaselines()
        baselines.ingest(sample(.sdnn, ms: 40))
        baselines.ingest(sample(.rmssd, ms: 40))
        XCTAssertEqual(baselines.sdnn.n, 1)
        XCTAssertEqual(baselines.rmssd.n, 1)
        XCTAssertEqual(baselines.samplingDensityVersion(.sdnn), HRVSamplingDensity.overnightSparse.version)
        XCTAssertEqual(baselines.samplingDensityVersion(.rmssd), HRVSamplingDensity.denseRMSSD.version)
        XCTAssertNotEqual(
            baselines.samplingDensityVersion(.sdnn),
            baselines.samplingDensityVersion(.rmssd)
        )
    }

    func testSamplingDensityChangeResetsOnlyThatStatistic() {
        var baselines = BodyModelHRVBaselines()
        for i in 0..<5 {
            baselines.ingest(sample(.rmssd, ms: 30 + Double(i), at: Double(i)))
            baselines.ingest(sample(.sdnn, ms: 50 + Double(i), at: Double(i)))
        }
        XCTAssertEqual(baselines.rmssd.n, 5)
        XCTAssertEqual(baselines.sdnn.n, 5)
        let sdnnMean = baselines.sdnn.mean

        let denser = HRVSamplingDensity(version: 3, expectedSamplesPerDay: 288)
        baselines.ingest(sample(.rmssd, ms: 22, density: denser, at: 99))

        XCTAssertEqual(baselines.rmssd.n, 1, "density bump must drop the old RMSSD center")
        XCTAssertEqual(baselines.rmssd.last, 22)
        XCTAssertEqual(baselines.rmssdSamplingDensityVersion, 3)
        XCTAssertEqual(baselines.sdnn.n, 5, "SDNN must survive an RMSSD density migrate")
        XCTAssertEqual(baselines.sdnn.mean, sdnnMean, accuracy: 1e-12)
        XCTAssertEqual(baselines.sdnnSamplingDensityVersion, HRVSamplingDensity.overnightSparse.version)
        XCTAssertNil(baselines.baselineMs(.rmssd), "one post-migrate sample is still thin")
        guard let sdnnBaseline = baselines.baselineMs(.sdnn) else {
            XCTFail("SDNN baseline should remain after an RMSSD density migrate")
            return
        }
        XCTAssertEqual(sdnnBaseline, sdnnMean, accuracy: 1e-12)
    }

    func testUnversionedPersistedBaselinesAreDroppedOnDecode() throws {
        var staleSDNN = OnlineStat()
        staleSDNN.update(60)
        staleSDNN.update(62)
        staleSDNN.update(58)
        let encoder = JSONEncoder()
        let data = try encoder.encode([
            "sdnn": staleSDNN
        ])
        let decoded = try JSONDecoder().decode(BodyModelHRVBaselines.self, from: data)
        XCTAssertEqual(decoded.schemaVersion, BodyModelHRVBaselines.currentSchemaVersion)
        XCTAssertEqual(decoded.sdnn.n, 0, "unknown density must not keep the old SDNN center")
        XCTAssertEqual(decoded.rmssd.n, 0)
        XCTAssertEqual(decoded.sdnnSamplingDensityVersion, 0)
    }

    func testRoundTripPreservesVersionedBaselines() throws {
        var baselines = BodyModelHRVBaselines()
        baselines.ingest(sample(.sdnn, ms: 48))
        baselines.ingest(sample(.rmssd, ms: 21))
        let data = try JSONEncoder().encode(baselines)
        let decoded = try JSONDecoder().decode(BodyModelHRVBaselines.self, from: data)
        XCTAssertEqual(decoded.sdnn.n, 1)
        XCTAssertEqual(decoded.rmssd.n, 1)
        XCTAssertEqual(decoded.sdnn.last, 48)
        XCTAssertEqual(decoded.rmssd.last, 21)
        XCTAssertEqual(decoded.sdnnSamplingDensityVersion, 1)
        XCTAssertEqual(decoded.rmssdSamplingDensityVersion, 2)
    }

    func testStoreIsolatesRMSSDFromSDNNAcrossDefaults() {
        let defaults = UserDefaults(suiteName: "forge.bodyModel.hrv.tests")!
        defaults.removePersistentDomain(forName: "forge.bodyModel.hrv.tests")
        BodyModelHRVBaselineStore.reset(defaults: defaults)

        BodyModelHRVBaselineStore.ingest(sample(.sdnn, ms: 51), defaults: defaults)
        BodyModelHRVBaselineStore.ingest(sample(.rmssd, ms: 19), defaults: defaults)

        let loaded = BodyModelHRVBaselineStore.load(defaults: defaults)
        XCTAssertEqual(loaded.sdnn.last, 51)
        XCTAssertEqual(loaded.rmssd.last, 19)
        XCTAssertEqual(loaded.sdnn.n, 1)
        XCTAssertEqual(loaded.rmssd.n, 1)

        BodyModelHRVBaselineStore.reset(defaults: defaults)
        XCTAssertEqual(BodyModelHRVBaselineStore.load(defaults: defaults).sdnn.n, 0)
    }

    func testDefaultDensitiesAreNotInterchangeable() {
        XCTAssertNotEqual(HRVSamplingDensity.overnightSparse, HRVSamplingDensity.denseRMSSD)
        XCTAssertEqual(HRVSamplingDensity.default(for: .sdnn), .overnightSparse)
        XCTAssertEqual(HRVSamplingDensity.default(for: .rmssd), .denseRMSSD)
        XCTAssertNotEqual(
            HRVSamplingDensity.default(for: .sdnn).version,
            HRVSamplingDensity.default(for: .rmssd).version
        )
    }
}
