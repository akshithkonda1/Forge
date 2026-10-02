import XCTest
@testable import ForgeCore

/// Mirrors backend/ai/simrunner/tests/test_perception.py — same cases, same verdicts.
final class AriaSituationTests: XCTestCase {

    private func input(
        _ prompt: String,
        sleep: Double? = 7.8,
        readiness: Int? = 80,
        environment: AriaEnvironmentRead? = nil,
        hour: Int? = nil,
        horizon: [String] = []
    ) -> AriaSituationInput {
        AriaSituationInput(
            prompt: prompt,
            sleepHours: sleep,
            readiness: readiness,
            localHour: hour,
            calendarHorizonTags: horizon,
            environment: environment
        )
    }

    private let hot = AriaEnvironmentRead(apparentTempC: 36, uvIndex: 9, usAQI: 40, precipitationMm: 0, isDay: true, source: "open-meteo")
    private let smoke = AriaEnvironmentRead(apparentTempC: 20, usAQI: 180, source: "open-meteo")

    func testWordBoundaries() {
        let read = AriaSituation.perceive(input("had brunch and protein, meeting at noon"))
        XCTAssertTrue(read.conflicts.isEmpty)
        XCTAssertNil(read.signal("event"))
        XCTAssertTrue(AriaSituation.matches(" go for a run ", "run "))
        XCTAssertFalse(AriaSituation.matches(" brunch ", "run "))
        XCTAssertFalse(AriaSituation.matches(" protein ", "pr "))
    }

    func testSickOfIsNotIllness() {
        let read = AriaSituation.perceive(input("I'm sick of my job, want to go hard at the gym"))
        XCTAssertNil(read.signal("illness"))
        XCTAssertEqual(read.posture, .push)
    }

    func testFeelsGreatButShortNight() {
        let read = AriaSituation.perceive(input("I feel great, let's go hard on leg day", sleep: 5.2, readiness: 45))
        let kinds = read.conflicts.map(\.kind)
        XCTAssertTrue(kinds.contains("said_vs_measured"))
        XCTAssertTrue(kinds.contains("intent_vs_recovery"))
        XCTAssertTrue(read.decisions.keepLight)
        XCTAssertEqual(read.posture, .protect)
        XCTAssertNotNil(read.spokenLine)
    }

    func testFeelsLowButNumbersReady() {
        let read = AriaSituation.perceive(input("I'm exhausted, what should I train?"))
        XCTAssertTrue(read.spokenLine?.contains("how you feel wins") ?? false)
    }

    func testIllnessAndRedFlags() {
        let sick = AriaSituation.perceive(input("I have a fever, can I still run?"))
        XCTAssertEqual(sick.posture, .rest)
        XCTAssertEqual(sick.research.first?.topic, "fever")
        let flag = AriaSituation.perceive(input("chest pain when I run"))
        XCTAssertEqual(flag.posture, .refer)
        XCTAssertTrue(flag.decisions.referOut)
    }

    func testEventTaperFromSpeechAndCalendar() {
        let said = AriaSituation.perceive(input("Wedding tomorrow, what should I train?"))
        XCTAssertTrue(said.decisions.keepLight && said.decisions.shorten)
        XCTAssertEqual(said.signal("event")?.band, "tomorrow")
        XCTAssertEqual(AriaSituation.eventDays(in: "race in three days"), 3)
        XCTAssertEqual(AriaSituation.eventDays(in: "my marathon is next week"), 7)

        let calendar = AriaSituation.perceive(input("what should I train?", horizon: ["calendar:horizon:travel:9", "calendar:horizon:game:2"]))
        XCTAssertEqual(calendar.signal("event")?.source, .measured)
        XCTAssertTrue(calendar.decisions.shorten)
    }

    func testInjury() {
        let read = AriaSituation.perceive(input("my knee hurts, can we still do a workout"))
        XCTAssertTrue(read.conflicts.map(\.kind).contains("injury_vs_training"))
        XCTAssertTrue(read.spokenLine?.contains("knee") ?? false)
    }

    func testWorldMovesTrainingInside() {
        let hotRun = AriaSituation.perceive(input("going for a long run this afternoon", environment: hot))
        XCTAssertTrue(hotRun.decisions.moveIndoors)
        XCTAssertTrue(hotRun.research.contains { $0.topic == "heat" })
        let smoky = AriaSituation.perceive(input("want to run outside", environment: smoke))
        XCTAssertTrue(smoky.spokenLine?.contains("air") ?? false)
        let calm = AriaSituation.perceive(input("want to run outside", environment: AriaEnvironmentRead(apparentTempC: 18, source: "open-meteo")))
        XCTAssertFalse(calm.decisions.moveIndoors)
    }

    func testLateHardSession() {
        let read = AriaSituation.perceive(input("let's go hard in the gym", hour: 22))
        XCTAssertTrue(read.decisions.shorten)
        XCTAssertEqual(read.signal("time")?.band, "night")
    }

    func testMissingSleepAsksFirst() {
        let read = AriaSituation.perceive(input("what should I train?", sleep: nil))
        XCTAssertTrue(read.decisions.askFirst)
        XCTAssertTrue(read.unknowns.contains("last night's sleep"))
    }

    func testBriefCarriesNoDigits() {
        let read = AriaSituation.perceive(input("I feel great, go hard today", sleep: 5.0, readiness: 40, environment: hot, hour: 7))
        XCTAssertTrue(read.brief.hasPrefix("Posture: protect."))
        XCTAssertNil(read.brief.rangeOfCharacter(from: .decimalDigits))
        XCTAssertTrue(read.reasonTag.hasPrefix("situation · protect"))
    }

    func testResearchQueryIsScrubbed() {
        var raw = input("my name is Lee and I'm 34 — how much protein should I eat? Priya says so")
        raw.privateTerms = ["Priya"]
        let read = AriaSituation.perceive(raw)
        XCTAssertEqual(read.research.first?.topic, "nutrition")
        let query = read.research.first?.query ?? ""
        XCTAssertFalse(query.contains("lee"))
        XCTAssertFalse(query.contains("34"))
        XCTAssertFalse(query.contains("priya"))
    }

    func testPlainTurnNeedsNothing() {
        let read = AriaSituation.perceive(input("thanks!"))
        XCTAssertEqual(read.posture, .steady)
        XCTAssertTrue(read.conflicts.isEmpty)
        XCTAssertTrue(read.research.isEmpty)
    }
}
