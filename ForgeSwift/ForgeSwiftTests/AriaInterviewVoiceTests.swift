import XCTest
@testable import ForgeSwift

/// Locks the interview relationship layer: spoken copy, suggested replies,
/// and voice matching. Does not spin AVSpeech — that's AriaPresence.
final class AriaInterviewVoiceTests: XCTestCase {

    func testIntroAlwaysSaysARIANotAriaAndNotADoctor() {
        let unnamed = AriaInterviewVoice.introLine(firstName: "", questLabel: nil)
        XCTAssertTrue(unnamed.contains("I'm ARIA"))
        XCTAssertFalse(unnamed.contains("I'm Aria"))
        XCTAssertTrue(unnamed.localizedCaseInsensitiveContains("not a doctor"))
        XCTAssertTrue(unnamed.localizedCaseInsensitiveContains("every day"))

        let named = AriaInterviewVoice.introLine(firstName: "Maya", questLabel: "Build Muscle")
        XCTAssertTrue(named.contains("Welcome, Maya"))
        XCTAssertTrue(named.contains("I'm ARIA"))
        XCTAssertTrue(named.contains("Build Muscle"))
        XCTAssertTrue(named.localizedCaseInsensitiveContains("every day"))
    }

    func testNameAcknowledgmentUsesTheNameAndImpliesDaily() {
        let line = AriaInterviewVoice.acknowledgeName("Maya")
        XCTAssertTrue(line.hasPrefix("Maya"))
        XCTAssertTrue(line.localizedCaseInsensitiveContains("every day"))
        XCTAssertLessThan(line.count, AriaSpeechPrep.characterLimit)
    }

    func testNightOwlAckRefusesGenericSixAM() {
        let line = AriaInterviewVoice.acknowledgeSleep(.nightOwl)
        XCTAssertTrue(line.localizedCaseInsensitiveContains("night owl"))
        XCTAssertTrue(line.contains("6am") || line.localizedCaseInsensitiveContains("your clock"))
        XCTAssertFalse(line.localizedCaseInsensitiveContains("inconsistent"))
    }

    func testIrregularSpokenAliasesMapToIrregularNotAMissingCase() {
        let profile = OnboardingProfile()
        let misspellings = [
            "my sleep is inconsistent",
            "irregular",
            "shift work",
            "no fixed pattern",
        ]
        for phrase in misspellings {
            XCTAssertEqual(
                AriaInterviewVoice.matchSpoken(phrase, step: .sleep, profile: profile),
                .sleep(.irregular),
                phrase
            )
        }
        XCTAssertEqual(
            AriaInterviewVoice.matchSpoken("I'm a night owl", step: .sleep, profile: profile),
            .sleep(.nightOwl)
        )
        XCTAssertEqual(
            AriaInterviewVoice.matchSpoken("early bird", step: .sleep, profile: profile),
            .sleep(.earlyBird)
        )
        XCTAssertNil(SleepRhythmBand(rawValue: "inconsistent"))
    }

    func testExperienceAndCoachingVoiceMatch() {
        let profile = OnboardingProfile()
        XCTAssertEqual(
            AriaInterviewVoice.matchSpoken("I'm new", step: .experience, profile: profile),
            .experience(.beginner)
        )
        XCTAssertEqual(
            AriaInterviewVoice.matchSpoken("a few years in", step: .experience, profile: profile),
            .experience(.intermediate)
        )
        XCTAssertEqual(
            AriaInterviewVoice.matchSpoken("push me", step: .coaching, profile: profile),
            .coaching(.driven)
        )
        XCTAssertEqual(
            AriaInterviewVoice.matchSpoken("explain the why", step: .coaching, profile: profile),
            .coaching(.scientist)
        )
        XCTAssertEqual(
            AriaInterviewVoice.matchSpoken("keep me steady", step: .coaching, profile: profile),
            .coaching(.balanced)
        )
    }

    func testHealthSkipAndConnectVoiceMatch() {
        let profile = OnboardingProfile()
        XCTAssertEqual(
            AriaInterviewVoice.matchSpoken("I'll add it later", step: .health, profile: profile),
            .skipHealthAndContinue
        )
        XCTAssertEqual(
            AriaInterviewVoice.matchSpoken("connect Apple Health", step: .health, profile: profile),
            .connectHealth
        )
        XCTAssertEqual(
            AriaInterviewVoice.matchSpoken("yesterday I ran", step: .health, profile: profile),
            .missed,
            "substring 'yes' in yesterday must not trigger connect"
        )
    }

    func testSuggestedRepliesStayOnTheTwelveStepGraph() {
        let empty = OnboardingProfile()
        XCTAssertEqual(
            AriaInterviewVoice.suggestedReplies(
                step: .sleep, profile: empty, health: .unknown, calendar: .unknown
            ).count,
            4
        )
        XCTAssertFalse(
            AriaInterviewVoice.suggestedReplies(
                step: .name, profile: empty, health: .unknown, calendar: .unknown
            ).isEmpty
        )
        XCTAssertTrue(
            AriaInterviewVoice.suggestedReplies(
                step: .details, profile: empty, health: .unknown, calendar: .unknown
            ).isEmpty
        )
        XCTAssertEqual(AriaInterviewStep.allCases.count, 12)
        XCTAssertTrue(AriaInterviewVoice.shouldShowVoiceDock(for: .name))
        XCTAssertFalse(AriaInterviewVoice.shouldShowVoiceDock(for: .ready))
    }

    func testPresenceCaptionPriority() {
        XCTAssertEqual(
            AriaInterviewVoice.presenceCaption(listening: true, speaking: true, thinking: true),
            "Listening"
        )
        XCTAssertEqual(
            AriaInterviewVoice.presenceCaption(listening: false, speaking: false, thinking: true),
            "Thinking"
        )
        XCTAssertEqual(
            AriaInterviewVoice.presenceCaption(listening: false, speaking: true, thinking: false),
            "Speaking"
        )
        XCTAssertEqual(
            AriaInterviewVoice.presenceCaption(listening: false, speaking: false, thinking: false),
            "With you"
        )
    }

    func testNameFillAndConfirmFromVoice() {
        var profile = OnboardingProfile()
        XCTAssertEqual(
            AriaInterviewVoice.matchSpoken("Maya Chen", step: .name, profile: profile),
            .fillName("Maya Chen")
        )
        XCTAssertEqual(
            AriaInterviewVoice.matchSpoken("call me Maya", step: .name, profile: profile),
            .fillName("Maya")
        )
        XCTAssertEqual(
            AriaInterviewVoice.matchSpoken("I'll say it", step: .name, profile: profile),
            .missed
        )
        profile.name = "Maya"
        XCTAssertEqual(
            AriaInterviewVoice.matchSpoken("that's me", step: .name, profile: profile),
            .confirmName
        )
    }

    func testPromptAndAckFitSpeechCeiling() {
        var profile = OnboardingProfile()
        profile.name = "Maya"
        profile.fitnessGoals = [.buildMuscle]
        for step in AriaInterviewStep.allCases {
            let line = AriaInterviewVoice.prompt(
                step,
                profile: profile,
                healthAuthorized: true,
                healthPrefill: true,
                vo2Max: 48
            )
            XCTAssertLessThan(line.count, AriaSpeechPrep.characterLimit, "\(step)")
            if let clipped = AriaSpeechPrep.clipped(line) {
                XCTAssertEqual(clipped, line)
            }
        }
        XCTAssertNotNil(AriaSpeechPrep.clipped(AriaInterviewVoice.acknowledgeName("Maya")))
        XCTAssertNil(AriaSpeechPrep.clipped("   "))
    }

    func testFirstSessionScriptStillNamesThePerson() {
        var profile = OnboardingProfile()
        profile.name = "Maya"
        profile.fitnessGoals = [.buildMuscle]
        profile.preferredWorkouts = [.weightlifting]
        profile.coachingStyle = .balanced
        profile.sleepBand = .nightOwl
        let script = AriaOnboardingGuide.firstSessionScript(profile: profile, healthConnected: true)
        XCTAssertTrue(script.contains("Maya"))
        XCTAssertTrue(script.localizedCaseInsensitiveContains("build muscle") || script.contains("weightlifting"))
        XCTAssertLessThan(script.count, AriaSpeechPrep.characterLimit)
    }

    @MainActor
    func testGoBackStillDoesNotReenterIntro() {
        // Graph lock twin — voice work must not reopen #168 or the name-back path.
        let coordinator = OnboardingCoordinator()
        coordinator.step = .name
        XCTAssertFalse(coordinator.canGoBack)
        coordinator.step = .health
        coordinator.goBack()
        XCTAssertEqual(coordinator.step, .name)
        coordinator.step = .coaching
        coordinator.goBack()
        XCTAssertEqual(coordinator.step, .freeTime)
    }
}
