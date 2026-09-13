import XCTest
@testable import ForgeSwift

/// Locks Lex’s friend-first six beats: Meet, Name, Health nest, Habits ≤3,
/// Tone lines, First chat opener. No calibrate. Health status from #263.
final class FriendFirstOnboardingTests: XCTestCase {

    func testHealthNestCopyAndStatusHonesty() {
        XCTAssertEqual(AriaInterviewVoice.healthWrapper, "So I can keep up with you")
        XCTAssertEqual(
            AriaInterviewVoice.healthBody,
            "If you connect Apple Health, I can learn your sleep and movement with you — so I can take care of you better, not to judge."
        )
        XCTAssertEqual(AriaInterviewVoice.healthDenyLine, "All good… I’m still here.")
        XCTAssertEqual(AriaInterviewVoice.acknowledgeHealthSkip(), AriaInterviewVoice.healthDenyLine)
        XCTAssertEqual(
            AriaInterviewVoice.acknowledgeHealthContinue(health: .denied, calendar: .unknown),
            AriaInterviewVoice.healthDenyLine
        )

        XCTAssertEqual(
            AriaInterviewVoice.healthStatusLabel(state: .authorized, pulling: false),
            "Connected"
        )
        XCTAssertEqual(
            AriaInterviewVoice.healthStatusLabel(state: .denied, pulling: false),
            "Offline"
        )
        XCTAssertEqual(
            AriaInterviewVoice.healthStatusLabel(state: .unknown, pulling: true),
            "Pulling…"
        )
        XCTAssertEqual(
            AriaInterviewVoice.healthStatusLabel(state: .requesting, pulling: false),
            "Pulling…"
        )
    }

    func testHabitsAreThreeFriendChipsAndCapAtThree() {
        XCTAssertEqual(FriendHabitChip.allCases.count, 3)
        XCTAssertEqual(AriaInterviewVoice.habitsWrapper, "So I can learn more about you")

        let empty = OnboardingProfile()
        let replies = AriaInterviewVoice.suggestedReplies(
            step: .freeTime, profile: empty, health: .unknown, calendar: .unknown
        )
        let habitReplies = replies.filter {
            if case .habit = $0.kind { return true }
            return false
        }
        XCTAssertEqual(habitReplies.count, 3)

        XCTAssertEqual(
            AriaInterviewVoice.matchSpoken("better nights", step: .freeTime, profile: empty),
            .toggleHabits([.betterNights])
        )
        XCTAssertEqual(
            AriaInterviewVoice.matchSpoken("move with me", step: .freeTime, profile: empty),
            .toggleHabits([.moveWithMe])
        )
        XCTAssertEqual(
            AriaInterviewVoice.matchSpoken("stay close", step: .freeTime, profile: empty),
            .toggleHabits([.stayClose])
        )
    }

    @MainActor
    func testHabitToggleCapsAtThreeAndMapsExistingFields() {
        let coordinator = OnboardingCoordinator()
        coordinator.step = .freeTime
        XCTAssertEqual(FriendHabitChip.allCases.count, 3)
        for chip in FriendHabitChip.allCases {
            coordinator.toggleHabit(chip)
        }
        XCTAssertEqual(coordinator.profile.friendHabits.count, 3)
        coordinator.toggleHabit(.betterNights)
        XCTAssertEqual(coordinator.profile.friendHabits.count, 2)
        coordinator.toggleHabit(.betterNights)
        XCTAssertEqual(Set(coordinator.profile.friendHabits), Set(FriendHabitChip.allCases))
        XCTAssertTrue(coordinator.profile.fitnessGoals.contains(.betterSleep))
        XCTAssertTrue(coordinator.profile.fitnessGoals.contains(.generalHealth))
        XCTAssertTrue(coordinator.profile.freeTimeInterests.contains(.social))
        XCTAssertFalse(coordinator.profile.preferredWorkouts.isEmpty)
    }

    func testToneIsCheckInSpacePatternsHonestPeer() {
        XCTAssertEqual(
            OnboardingCoachingStyle.friendToneStyles.map(\.friendToneTitle),
            ["Check-in", "Space", "Patterns", "Honest peer"]
        )
        let empty = OnboardingProfile()
        let labels = AriaInterviewVoice.suggestedReplies(
            step: .coaching, profile: empty, health: .unknown, calendar: .unknown
        ).map(\.label)
        XCTAssertEqual(labels, ["Check-in", "Space", "Patterns", "Honest peer"])
        XCTAssertTrue(AriaInterviewVoice.acknowledgeCoaching(.balanced).localizedCaseInsensitiveContains("check-in"))
        XCTAssertTrue(AriaInterviewVoice.acknowledgeCoaching(.supportive).localizedCaseInsensitiveContains("space"))
        XCTAssertTrue(AriaInterviewVoice.acknowledgeCoaching(.scientist).localizedCaseInsensitiveContains("pattern"))
        XCTAssertTrue(AriaInterviewVoice.acknowledgeCoaching(.driven).localizedCaseInsensitiveContains("honest"))
    }

    func testPromptsSpeakAsINameARIAAndNeverCalibrate() {
        var profile = OnboardingProfile()
        profile.name = "Maya"
        for step in AriaInterviewStep.allCases {
            let line = AriaInterviewVoice.prompt(
                step,
                profile: profile,
                healthAuthorized: false,
                healthPrefill: false,
                vo2Max: nil
            )
            XCTAssertFalse(line.localizedCaseInsensitiveContains("calibrate"), "\(step)")
            XCTAssertFalse(line.contains("I'm Aria"), "\(step)")
        }
        let health = AriaInterviewVoice.prompt(
            .health, profile: profile, healthAuthorized: false, healthPrefill: false, vo2Max: nil
        )
        XCTAssertTrue(health.contains(AriaInterviewVoice.healthWrapper))
        XCTAssertTrue(health.contains("not to judge"))
        let habits = AriaInterviewVoice.prompt(
            .freeTime, profile: profile, healthAuthorized: false, healthPrefill: false, vo2Max: nil
        )
        XCTAssertTrue(habits.contains(AriaInterviewVoice.habitsWrapper))
        let tone = AriaInterviewVoice.prompt(
            .coaching, profile: profile, healthAuthorized: false, healthPrefill: false, vo2Max: nil
        )
        XCTAssertTrue(tone.localizedCaseInsensitiveContains("check-in"))
        XCTAssertTrue(tone.localizedCaseInsensitiveContains("honest peer"))
    }

    func testFirstChatOpenerIsFriendAndNamesARIA() {
        var profile = OnboardingProfile()
        profile.name = "Maya"
        profile.coachingStyle = .balanced
        let opener = AriaOnboardingGuide.welcomeChatMessage(profile: profile, healthConnected: true)
        XCTAssertTrue(opener.contains("Maya"))
        XCTAssertTrue(opener.contains("ARIA"))
        XCTAssertFalse(opener.contains("I'm Aria"))
        XCTAssertFalse(opener.localizedCaseInsensitiveContains("calibrate"))
        XCTAssertTrue(opener.localizedCaseInsensitiveContains("i'm here") || opener.contains("I'm here"))
    }

    func testProgressLabelsAreTheSixBeats() {
        XCTAssertEqual(AriaInterviewStep.intro.progressLabel, "Meet")
        XCTAssertEqual(AriaInterviewStep.name.progressLabel, "Name")
        XCTAssertEqual(AriaInterviewStep.health.progressLabel, "Health")
        XCTAssertEqual(AriaInterviewStep.freeTime.progressLabel, "Habits")
        XCTAssertEqual(AriaInterviewStep.coaching.progressLabel, "Tone")
        XCTAssertEqual(AriaInterviewStep.ready.progressLabel, "First chat")
    }
}
