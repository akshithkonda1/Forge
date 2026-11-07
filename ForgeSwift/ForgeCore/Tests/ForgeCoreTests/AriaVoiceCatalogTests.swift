import XCTest
import ForgeCore

final class AriaVoiceCatalogTests: XCTestCase {

    func testFeaturedRecipesAvoidTrademarkedNames() {
        XCTAssertEqual(AriaVoiceCatalog.featuredIDs, ["warm", "calm", "neutral", "spark", "ember"])
        XCTAssertEqual(AriaVoiceCatalog.defaultModel, "kokoro-82m")
        XCTAssertEqual(AriaVoiceCatalog.recipe(id: "warm")?.voiceID, "af_heart")
        XCTAssertTrue(AriaVoiceCatalog.labelsAvoidTrademarkedCharacters(AriaVoiceCatalog.recipes))
        XCTAssertEqual(AriaVoiceCatalog.recipe(id: "ember")?.label, "Ember")
        XCTAssertFalse(AriaVoiceCatalog.recipes.contains { $0.label.lowercased().contains("toph") })
    }

    func testSwitchingProfileChangesNextSpeakVoiceID() {
        let warm = AriaVoiceCatalog.recipe(id: "warm")!
        let ember = AriaVoiceCatalog.recipe(id: "ember")!
        var selection = AriaVoiceCatalog.Selection()
        selection = AriaVoiceCatalog.apply(selection: selection, to: warm)
        let first = AriaVoiceCatalog.speakBody(text: "I'm ARIA.", selection: selection)
        XCTAssertEqual(first["voice_id"] as? String, "af_heart")
        XCTAssertEqual(first["profile_id"] as? String, "warm")
        XCTAssertNil(first["text"])

        selection = AriaVoiceCatalog.apply(selection: selection, to: ember)
        let next = AriaVoiceCatalog.speakBody(text: "I'm ARIA.", selection: selection)
        XCTAssertEqual(next["voice_id"] as? String, "af_bella")
        XCTAssertEqual(next["profile_id"] as? String, "ember")
        XCTAssertEqual(next["speed"] as? Double, 1.05)
        XCTAssertNotEqual(first["voice_id"] as? String, next["voice_id"] as? String)
    }

    func testSelectionPersistsIndependentlyOfPersonality() {
        let suite = "forge.aria.voice.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var selection = AriaVoiceCatalog.Selection(profileID: "ember", voiceID: "af_bella", speed: 1.05)
        selection.persist(to: defaults)
        let loaded = AriaVoiceCatalog.Selection.load(from: defaults)
        XCTAssertEqual(loaded.profileID, "ember")
        XCTAssertEqual(loaded.voiceID, "af_bella")
        XCTAssertEqual(AriaVoiceCatalog.Selection.storageKey, "forge.aria.voice.profile.v1")
        XCTAssertNotEqual(AriaVoiceCatalog.Selection.storageKey, "forge.coaching.personality.v1")
    }

    func testCatalogURLStaysOnTheSingleVoiceSurface() {
        let live = URL(string: "https://api.forge.test")!
        let url = AriaVoiceCatalog.catalogURL(baseURL: live, query: "warm")
        XCTAssertEqual(url?.path.hasSuffix("/ai/voice"), true)
        XCTAssertTrue(url?.query?.contains("q=warm") == true)
        XCTAssertNil(AriaVoiceCatalog.catalogURL(baseURL: ForgeAuthConfig.dummyOfflineAPI))
    }
}
