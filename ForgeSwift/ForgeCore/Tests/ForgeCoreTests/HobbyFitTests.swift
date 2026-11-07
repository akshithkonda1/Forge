import XCTest
@testable import ForgeCore

final class HobbyFitTests: XCTestCase {

    private func working(
        _ tendency: UserWorkingModel.Tendency,
        _ stance: UserWorkingModel.Stance = .keepRhythm,
        _ feel: UserWorkingModel.PredictedFeel = .mixed
    ) -> UserWorkingModel.Snapshot {
        UserWorkingModel.Snapshot(
            tendency: tendency,
            stance: stance,
            predictedFeel: feel,
            confidence: .low,
            drivers: [],
            steeringLine: ""
        )
    }

    func testFourMentalityValuesUseSpeakPhrases() {
        let quiet = HobbyFit.signal(socialBand: .reserved, peopleEnergy: .thin, working: working(.protector))
        XCTAssertEqual(quiet, .quiet)
        XCTAssertEqual(HobbyFit.speak(quiet), "quiet stretch")

        let open = HobbyFit.signal(socialBand: .sociable, peopleEnergy: .open, working: working(.steady, .keepRhythm, .available))
        XCTAssertEqual(open, .open)
        XCTAssertEqual(HobbyFit.speak(open), "up for a little more")

        let drained = HobbyFit.signal(socialBand: .burnedOut, peopleEnergy: .thin, working: working(.overreacher))
        XCTAssertEqual(drained, .drainedSocial)
        XCTAssertEqual(HobbyFit.speak(drained), "lots on lately")

        let restored = HobbyFit.signal(socialBand: .mixed, peopleEnergy: .enough, working: working(.rebuilding, .rebuildTrust))
        XCTAssertEqual(restored, .restored)
        XCTAssertEqual(HobbyFit.speak(restored), "a calmer patch")
    }

    func testCanonLinesStayCoachCopy() {
        let lines = [
            HobbyFit.canonLine(signal: .quiet),
            HobbyFit.canonLine(signal: .quiet, curious: true),
            HobbyFit.canonLine(signal: .drainedSocial),
            HobbyFit.canonLine(signal: .drainedSocial, skipGroups: true),
            HobbyFit.canonLine(signal: .open),
            HobbyFit.canonLine(signal: .restored),
            HobbyFit.coolDownLine(label: "Hike club"),
        ]
        XCTAssertTrue(lines[0].contains("quieter stretch"))
        XCTAssertTrue(lines[1].contains("Quiet stretch"))
        XCTAssertTrue(lines[2].contains("Lots on lately"))
        XCTAssertTrue(lines[3].contains("skip group stuff"))
        XCTAssertEqual(
            HobbyFit.coolDownLine(label: "Hike club"),
            "Hike club's still around if you ever want another look. It's not going anywhere."
        )
        for line in lines {
            XCTAssertTrue(HobbyFit.speechIsClean(line), line)
            XCTAssertFalse(line.contains("drained_social"))
        }
    }

    func testDismissalIsNeverCited() {
        XCTAssertEqual(HobbyFit.dismissalLine(label: "Hike club"), "")
        XCTAssertFalse(HobbyFit.dismissalLine(label: "Hike club").contains("Hike"))
    }

    func testHobbyShapeDropsContactPII() {
        let cooking = HobbyFit.hobbies(from: [.cooking, .outdoors])
        XCTAssertEqual(cooking.map(\.id), ["cooking", "outdoors"])
        XCTAssertEqual(cooking[0].kind, .creative)
        XCTAssertEqual(cooking[1].kind, .outdoor)

        XCTAssertNil(HobbyFit.normalize(label: "sam@x.com"))
        XCTAssertNil(HobbyFit.normalize(label: "Call 5551212"))
        let pottery = HobbyFit.normalize(
            label: "Pottery nights",
            kind: "creative",
            interest: "high",
            lastEngagedAt: "2026-10-01"
        )
        XCTAssertEqual(pottery?.id, "pottery_nights")
        XCTAssertEqual(pottery?.kind, .creative)
        XCTAssertEqual(pottery?.interest, .high)
        XCTAssertEqual(pottery?.lastEngagedAt, "2026-10-01")
    }

    func testPictureKeepsEnumOutOfAriaTags() {
        let picture = PredictiveCoach.picture(
            forecastInput: ReadinessForecastEngine.Input(
                currentReadiness: 72,
                sleepMinutes: 480,
                hrvMs: 60,
                restingHR: 55,
                todayStrain: 4,
                stressLevel: 30
            ),
            workingInput: UserWorkingModel.Input(sleepScores: [80, 80], readinessToday: 72),
            socialEnergy0to10: 2,
            currentHobbies: [.cooking]
        )
        XCTAssertEqual(picture.mentality, .quiet)
        XCTAssertEqual(picture.hobbyFitSpeak, "quiet stretch")
        XCTAssertEqual(picture.fitHobbies.first?.label, "Cooking")
        let tags = picture.ariaTags.joined(separator: " ")
        XCTAssertFalse(tags.contains("drained_social"))
        XCTAssertFalse(tags.contains("mentality:"))
        XCTAssertTrue(HobbyFit.speechIsClean(picture.hobbyFitSpeak))
    }

    func testLivingHobbyCatalogHasUniqueRawValues() {
        let ids = LivingHobby.allCases.map(\.rawValue)
        XCTAssertEqual(Set(ids).count, ids.count, "LivingHobby raw values must be unique; a duplicate 'outdoors' crashes Dictionary(uniqueKeysWithValues:)")
        XCTAssertEqual(ids.filter { $0 == "outdoors" }.count, 1)

        let rows = HobbyFit.hobbies(from: LivingHobby.allCases + [.outdoors])
        let rowIDs = rows.map(\.id)
        XCTAssertEqual(Set(rowIDs).count, rowIDs.count)
        XCTAssertEqual(rowIDs.filter { $0 == "outdoors" }.count, 1)
    }

    func testEngageKeepsFirstOutdoorsWhenPersonaAndProfileOverlap() {
        let persona = HobbyFit.hobbies(from: [.outdoors, .gym])
        let profile = [
            HobbyFit.Hobby(id: "outdoors", label: "Being outside", kind: .outdoor, interest: .medium, lastEngagedAt: "2026-10-10"),
            HobbyFit.Hobby(id: "cooking", label: "Cooking", kind: .creative, interest: .medium),
        ]
        let engaged = HobbyFit.engage(
            fromWorkouts: [
                .init(name: "Lunch walk", type: "cardio", dateISO: "2026-10-16"),
                .init(name: "Morning hike", type: "cardio", dateISO: "2026-10-16"),
            ],
            existing: persona + profile
        )
        XCTAssertEqual(engaged.filter { $0.id == "outdoors" }.count, 1)
        XCTAssertEqual(engaged.first { $0.id == "outdoors" }?.lastEngagedAt, "2026-10-16")
        XCTAssertTrue(engaged.contains { $0.id == "gym" })
        XCTAssertTrue(engaged.contains { $0.id == "cooking" })
    }

    func testGymIsNotSoloAndFreeTextNormalizes() {
        let gym = HobbyFit.hobbies(from: [.gym]).first
        XCTAssertEqual(gym?.kind, .social)
        XCTAssertEqual(HobbyFit.normalize(label: "CrossFit gym")?.kind, .social)
        let rows = HobbyFit.normalizeHobbies(labels: ["Pottery nights", "sam@x.com", "Gardening"])
        XCTAssertEqual(rows.map(\.id), ["pottery_nights", "gardening"])
        XCTAssertEqual(HobbyFit.chipToggle(selected: ["cooking"], tapping: "reading", cap: 3), ["cooking", "reading"])
        XCTAssertEqual(HobbyFit.chipToggle(selected: ["a", "b", "c"], tapping: "d", cap: 3), ["a", "b", "c"])
    }

    func testHealthKitSetsLastEngagedAndCountsTowardTheDay() {
        let engaged = HobbyFit.engage(
            fromWorkouts: [
                .init(name: "Morning hike", type: "cardio", dateISO: "2026-10-16"),
                .init(name: "Vinyasa yoga", type: "yoga", dateISO: "2026-10-16"),
                .init(name: "Dance cardio", type: "hiit", dateISO: "2026-10-15"),
                .init(name: "Backyard gardening", type: "other", dateISO: "2026-10-16"),
                .init(name: "Lunch walk", type: "cardio", dateISO: "2026-10-16"),
            ],
            existing: []
        )
        XCTAssertTrue(engaged.contains { $0.id == "outdoors" && $0.lastEngagedAt == "2026-10-16" })
        XCTAssertTrue(engaged.contains { $0.label == "Yoga" && $0.lastEngagedAt == "2026-10-16" })
        XCTAssertTrue(engaged.contains { $0.label == "Dance" })
        XCTAssertTrue(engaged.contains { $0.label == "Gardening" })
        let day = HobbyFit.dayContribution(hobbies: engaged, todayISO: "2026-10-16")
        XCTAssertGreaterThan(day.habitWins + Int(day.moveMinutes), 0)
        let mosaic = HobbyFit.applyToMosaic(StatsMosaic.Input(), contribution: day)
        XCTAssertGreaterThan(mosaic.habitsDone + (mosaic.steps ?? 0), 0)
        let time = HobbyFit.lifestyleTime(
            hobbies: engaged,
            nowISODay: "2026-10-16",
            weekDays: ["2026-10-10", "2026-10-16"]
        )
        XCTAssertGreaterThan(time.engagedThisWeek, 0)
        XCTAssertFalse(time.line.lowercased().contains("score"))
        XCTAssertFalse(time.line.lowercased().contains("should have"))
    }

    func testLiveSignalsNeverClaimCertaintyAndCooldownWires() {
        let working = UserWorkingModel.Snapshot(
            tendency: .protector,
            stance: .keepRhythm,
            predictedFeel: .mixed,
            confidence: .low,
            drivers: [],
            steeringLine: ""
        )
        let reading = HobbyFit.reading(
            socialBand: .reserved,
            peopleEnergy: .thin,
            working: working,
            live: .init(
                calendarEventsToday: 6,
                sleepHoursLastNight: 5,
                sleepHoursTypical: 7.5,
                hrvTrend: -10,
                hour: 22,
                conversation: ["need a night in"]
            )
        )
        XCTAssertLessThan(reading.confidence, 1)
        XCTAssertGreaterThan(reading.sources, 1)
        XCTAssertTrue(HobbyFit.speechIsClean(reading.speak))

        let pottery = HobbyFit.normalize(label: "Pottery nights", kind: "creative")!
        var log = HobbyFit.SuggestionLog()
        log = HobbyFit.rememberIgnored(log, id: pottery.id, cooldownUntil: "2026-10-20")
        XCTAssertFalse(HobbyFit.shouldOffer(id: pottery.id, log: log, todayISO: "2026-10-16"))
        XCTAssertTrue(HobbyFit.shouldOffer(id: pottery.id, log: log, todayISO: "2026-10-21"))
        let cooled = HobbyFit.suggestions(
            hobbies: [pottery],
            path: .openGently,
            mentality: .quiet,
            keepLight: false,
            log: log,
            todayISO: "2026-10-21"
        )
        XCTAssertTrue(cooled.contains { !$0.cooldownLine.isEmpty })
        XCTAssertEqual(HobbyFit.dismissalLine(label: "Pottery"), "")
    }

    func testHobbiesLiftQoLWhenPresentAndNeverShameWhenAbsent() {
        let none = QualityOfLifeCalculator.score(from: QualityOfLifeInputs(socialConnection0to10: 6))
        let some = QualityOfLifeCalculator.score(
            from: QualityOfLifeInputs(socialConnection0to10: 6, hobbyEngagedThisWeek: 3)
        )
        XCTAssertGreaterThan(some.score(for: .social) ?? 0, none.score(for: .social) ?? 0)
        let emptyHobbies = QualityOfLifeCalculator.score(
            from: QualityOfLifeInputs(steps: 8_000),
            persona: QualityOfLifePersona(archetype: .balanced, hobbies: nil)
        )
        XCTAssertEqual(emptyHobbies.score(for: .activity), 100)
    }
}
