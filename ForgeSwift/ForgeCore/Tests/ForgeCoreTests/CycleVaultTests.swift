import XCTest
@testable import ForgeCore

final class CycleVaultTests: XCTestCase {

    private var store: InMemorySecureStore!
    private var root: URL!
    private var vault: CycleVault!

    override func setUp() {
        super.setUp()
        store = InMemorySecureStore()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ForgeCycleVault-tests-\(UUID().uuidString)", isDirectory: true)
        vault = CycleVault(secureStore: store, rootDirectory: root)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        store = nil
        vault = nil
        super.tearDown()
    }

    func testRoundTripLiveState() throws {
        let payload = Data("cycle-log-not-for-userdefaults".utf8)
        try vault.writeLive(payload)
        XCTAssertEqual(try vault.readLive(), payload)
        XCTAssertTrue(vault.hasLiveBox)
        XCTAssertTrue(store.keys.contains(CycleVault.wrappingKeyAccount))
        XCTAssertFalse(String(data: try Data(contentsOf: vault.liveURL), encoding: .utf8)?.contains("cycle-log") == true,
                       "ciphertext must not contain the plaintext")
    }

    func testWrongKeyCannotOpen() throws {
        try vault.writeLive(Data("secret-chart".utf8))
        let other = InMemorySecureStore()
        let attacker = CycleVault(secureStore: other, rootDirectory: root)
        XCTAssertThrowsError(try attacker.readLive())
    }

    func testMonthlyArchiveKeepsTwelve() throws {
        for i in 1...15 {
            let key = String(format: "2025-%02d", i)
            try vault.writeMonth(key, plaintext: Data("month-\(i)".utf8))
        }
        let keys = try vault.monthKeys()
        XCTAssertEqual(keys.count, 12)
        XCTAssertFalse(keys.contains("2025-01"))
        XCTAssertFalse(keys.contains("2025-03"))
        XCTAssertEqual(keys.last, "2025-15")
        XCTAssertEqual(try vault.readMonth("2025-15"), Data("month-15".utf8))
    }

    func testWipeDeletesFilesAndWrappingKey() throws {
        try vault.writeLive(Data("wipe-me".utf8))
        try vault.writeMonth("2026-01", plaintext: Data("jan".utf8))
        try vault.wipe()
        XCTAssertFalse(vault.hasLiveBox)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        XCTAssertFalse(store.keys.contains(CycleVault.wrappingKeyAccount))
    }

    func testPurgeMonthsLeavesLiveBox() throws {
        try vault.writeLive(Data("keep-live".utf8))
        try vault.writeMonth("2026-01", plaintext: Data("jan".utf8))
        try vault.writeMonth("2026-02", plaintext: Data("feb".utf8))
        try vault.purgeMonths()
        XCTAssertEqual(try vault.readLive(), Data("keep-live".utf8))
        XCTAssertEqual(try vault.monthKeys(), [])
    }

    func testMonthKeyFormat() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 9
        comps.day = 5
        comps.hour = 12
        let date = cal.date(from: comps)!
        XCTAssertEqual(CycleVault.monthKey(for: date, calendar: cal), "2026-09")
    }
}

final class CycleRhythmReportTests: XCTestCase {

    func testClinicianReportOmitsFertilityAndSex() {
        let months = [
            CycleMonthlyDigest(
                monthKey: "2026-08",
                daysLogged: 28,
                bleedingDays: 5,
                cycleStarts: 1,
                medianCycleDays: 28,
                medianPeriodDays: 5,
                cycleLengthMin: 26,
                cycleLengthMax: 31,
                averagePain: 4.2,
                painDays: 3,
                symptomCounts: ["cramps": 4, "fatigue": 6],
                predictionMAE: 1.1,
                predictionSamples: 8,
                highAccuracyMode: true,
                lifestyleGoal: "running"
            ),
            CycleMonthlyDigest(
                monthKey: "2026-09",
                daysLogged: 12,
                bleedingDays: 2,
                cycleStarts: 0,
                symptomCounts: ["cramps": 1]
            ),
        ]
        let text = CycleRhythmReport.clinicianText(
            months: months,
            generatedDayKey: "2026-09-05",
            typicalCycle: 28,
            typicalPeriod: 5,
            mae: 1.1,
            maeSamples: 8
        )
        XCTAssertTrue(text.contains("12-MONTH TRACKING SUMMARY"))
        XCTAssertTrue(text.contains("Days logged: 40"))
        XCTAssertTrue(text.contains("cramps: 5"))
        XCTAssertTrue(text.contains("2026-08"))
        XCTAssertTrue(text.contains("NOT IN THIS REPORT"))
        let lower = text.lowercased()
        for term in CycleRhythmReport.forbiddenClinicianTerms {
            XCTAssertFalse(lower.contains(term), "clinician report leaked \(term)")
        }
    }

    func testEmptyArchiveStillHonest() {
        let text = CycleRhythmReport.clinicianText(
            months: [],
            generatedDayKey: "2026-09-05",
            typicalCycle: nil,
            typicalPeriod: nil,
            mae: nil,
            maeSamples: 0
        )
        XCTAssertTrue(text.contains("No monthly archives yet"))
        XCTAssertFalse(text.lowercased().contains("fertile"))
    }
}

final class CycleDiscretionPolicyTests: XCTestCase {

    func testStealthBlanksWatchFields() {
        let fields = CycleDiscretionPolicy.watchFields(
            mode: .stealth,
            phaseRaw: "menstruation",
            dayInCycle: 2,
            daysUntilNext: 26
        )
        XCTAssertNil(fields.phase)
        XCTAssertNil(fields.dayInCycle)
        XCTAssertNil(fields.daysUntilNext)
        XCTAssertNil(fields.lockLine)
    }

    func testKindNeverNamesThePhase() {
        let fields = CycleDiscretionPolicy.watchFields(
            mode: .kind,
            phaseRaw: "fertileWindow",
            dayInCycle: 14,
            daysUntilNext: 14
        )
        XCTAssertNil(fields.phase)
        XCTAssertEqual(fields.lockLine, "Take it easy")
        XCTAssertFalse(fields.lockLine?.lowercased().contains("period") == true)
        XCTAssertFalse(fields.lockLine?.lowercased().contains("fertile") == true)
    }

    func testClinicalPassesThrough() {
        let fields = CycleDiscretionPolicy.watchFields(
            mode: .clinical,
            phaseRaw: "luteal",
            dayInCycle: 22,
            daysUntilNext: 6
        )
        XCTAssertEqual(fields.phase, "luteal")
        XCTAssertEqual(fields.dayInCycle, 22)
        XCTAssertEqual(fields.daysUntilNext, 6)
    }
}

final class CycleGoalCoachTests: XCTestCase {

    func testRunningOnPeriodCapsMilesAndPromisesARebuild() {
        let rx = CycleGoalCoach.prescribe(
            goal: .running,
            phaseRaw: "menstruation",
            isBleeding: true,
            periodFinishedRecently: false,
            preferLighterTraining: true,
            recoveryBias: 0.8,
            highAccuracy: true
        )
        let blob = (rx.headline + rx.volumeLine + rx.intensityLine + rx.returnLine).lowercased()
        XCTAssertTrue(blob.contains("period") || blob.contains("bleed"))
        XCTAssertTrue(rx.volumeLine.lowercased().contains("mile"))
        XCTAssertTrue(rx.intensityLine.lowercased().contains("easy")
                      || rx.intensityLine.lowercased().contains("interval"))
        XCTAssertTrue(rx.returnLine.lowercased().contains("rebuild")
                      || rx.returnLine.lowercased().contains("usual"))
        XCTAssertFalse(blob.contains("fertile"))
        XCTAssertFalse(blob.contains("ovulat"))
    }

    func testRunningAfterPeriodRebuildsTowardNormal() {
        let rx = CycleGoalCoach.prescribe(
            goal: .running,
            phaseRaw: "follicular",
            isBleeding: false,
            periodFinishedRecently: true,
            preferLighterTraining: false,
            recoveryBias: 0.3,
            highAccuracy: false
        )
        XCTAssertTrue(rx.headline.lowercased().contains("finished")
                      || rx.volumeLine.lowercased().contains("rebuild"))
        XCTAssertTrue(rx.volumeLine.lowercased().contains("mile")
                      || rx.returnLine.lowercased().contains("mileage")
                      || rx.returnLine.lowercased().contains("balanced"))
    }

    func testPauseStyleDoesNotPrescribeMilesOnPeriod() {
        let rx = CycleGoalCoach.prescribe(
            goal: .running,
            phaseRaw: "menstruation",
            isBleeding: true,
            periodFinishedRecently: false,
            preferLighterTraining: false,
            recoveryBias: 0.2,
            highAccuracy: false,
            periodStyle: .pause
        )
        let volume = rx.volumeLine.lowercased()
        XCTAssertTrue(volume.contains("walk") || volume.contains("rest"))
        XCTAssertTrue(volume.contains("no run"))
        XCTAssertFalse(volume.contains("2–4") || volume.contains("3–5"))
        XCTAssertTrue(rx.headline.lowercased().contains("walk") || rx.headline.lowercased().contains("rest"))
    }
}

final class CycleInviteChannelTests: XCTestCase {

    func testFallbackBodyDoesNotCarryAShareURL() {
        let payload = PartnerInvitePayload(
            shareURL: URL(string: "https://www.icloud.com/share/0abcDEF123456789")!,
            fromDisplayName: "Sam",
            roleRaw: "romantic",
            roleLabel: "Partner",
            expiresAt: Date().addingTimeInterval(3600)
        )
        XCTAssertTrue(payload.iMessageOnly)
        XCTAssertFalse(payload.smsAccessIsValid)
        let body = payload.fallbackMessageBody.lowercased()
        XCTAssertFalse(body.contains("icloud.com"))
        XCTAssertFalse(body.contains("share/"))
        XCTAssertTrue(body.contains("imessage"))
        for term in ["cycle", "period", "menstrual", "fertile"] {
            XCTAssertFalse(body.contains(term), "SMS invalid-path copy leaked \(term)")
        }
    }
}
