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
}
