import XCTest
@testable import ForgeCore

final class HumanLivingCharacterTests: XCTestCase {

    func testLivingTagsAreClosedAndNonInvasive() {
        let persona = QualityOfLifePersona(
            archetype: .homebody,
            sleepNeedPreferenceHours: 7.5,
            nutritionRelationship: "fuel",
            eatingRhythm: .light,
            movementPreference: .cardio,
            hobbies: [.cooking, .reading]
        )
        let tags = persona.livingTags()
        XCTAssertTrue(tags.contains("living:archetype:homebody"))
        XCTAssertTrue(tags.contains("living:eat:fuel"))
        XCTAssertTrue(tags.contains("living:volume:light"))
        XCTAssertTrue(tags.contains("living:move:cardio"))
        XCTAssertTrue(tags.contains("living:hobby:cooking"))
        XCTAssertTrue(tags.contains("living:hobby:reading"))
        XCTAssertTrue(tags.contains("living:sleep_need:7.5"))
        XCTAssertFalse(tags.contains { $0.contains("uncle") || $0.contains("family") })
    }

    func testCharacterLineStaysOnDeviceAndNamesHowTheyLive() {
        let persona = QualityOfLifePersona(
            archetype: .outdoors,
            nutritionRelationship: "comfort",
            eatingRhythm: .heavy,
            movementPreference: .strength,
            hobbies: [.outdoors, .gym]
        )
        let line = persona.characterLine().lowercased()
        XCTAssertTrue(line.contains("outdoors"))
        XCTAssertTrue(line.contains("strength"))
        XCTAssertTrue(line.contains("on-device") || line.contains("model"))
        XCTAssertFalse(line.contains("uncle"))
    }

    func testCharacterQuestionDoesNotStealQoLGradeAsks() {
        XCTAssertTrue(QualityOfLifeLivingStore.isCharacterQuestion("who am I to you"))
        XCTAssertTrue(QualityOfLifeLivingStore.isCharacterQuestion("what do you know about me"))
        XCTAssertTrue(QualityOfLifeLivingStore.isCharacterQuestion("how do I live"))
        XCTAssertFalse(QualityOfLifeLivingStore.isCharacterQuestion("what's my quality of life"))
        XCTAssertFalse(QualityOfLifeLivingStore.isCharacterQuestion("what should I eat today"))
    }

    func testLegacyPersonaDecodeWithoutLivingFields() throws {
        struct Legacy: Codable {
            var archetype: String
            var sleepNeedPreferenceHours: Double?
            var nutritionRelationship: String?
        }
        let encoded = try JSONEncoder().encode(Legacy(
            archetype: "homebody",
            sleepNeedPreferenceHours: 8,
            nutritionRelationship: "fuel"
        ))
        let persona = try JSONDecoder().decode(QualityOfLifePersona.self, from: encoded)
        XCTAssertEqual(persona.archetype, .homebody)
        XCTAssertNil(persona.movementPreference)
        XCTAssertNil(persona.hobbies)
        XCTAssertEqual(persona.livingTags().contains("living:archetype:homebody"), true)
    }

    func testLivingDecisionNoteIsLocalAndOptional() {
        XCTAssertNil(QualityOfLifePersona.livingDecisionNote(from: ["qol:80"]))
        let note = QualityOfLifePersona.livingDecisionNote(from: [
            "living:move:cardio",
            "living:hobby:cooking",
            "living:hobby:music",
        ])
        XCTAssertTrue(note?.localizedCaseInsensitiveContains("cardio") == true)
        XCTAssertTrue(note?.localizedCaseInsensitiveContains("local profile") == true)
    }

    func testEmptyPersonaCharacterLineAdmitsMissingProfile() {
        let suite = "forge.living.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let line = QualityOfLifeLivingStore.characterLine(defaults: defaults)
        XCTAssertTrue(line.localizedCaseInsensitiveContains("lifestyle"))
        XCTAssertTrue(line.localizedCaseInsensitiveContains("on-device")
                      || line.localizedCaseInsensitiveContains("local")
                      || line.localizedCaseInsensitiveContains("family tree"))
        defaults.removePersistentDomain(forName: suite)
    }
}
