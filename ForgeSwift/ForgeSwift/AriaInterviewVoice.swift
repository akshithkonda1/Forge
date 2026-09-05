import Foundation
import UIKit

/// Spoken interview copy, suggested replies, and voice matching for ARIA
/// onboarding. Pure so tests can lock the relationship beats without spinning
/// the synthesizer or HealthKit.
///
/// The graph stays 12 steps. What changes is the beat *inside* each step:
/// ARIA thinks, speaks, hears a tap or a spoken reply, then answers *this*
/// person before the next ask.
enum AriaInterviewVoice {

    /// Long enough to feel like a person gathering a thought. Reduce Motion
    /// keeps the interview snappy without looking stalled.
    static var thinkBeatNanoseconds: UInt64 {
        UIAccessibility.isReduceMotionEnabled ? 90_000_000 : 420_000_000
    }

    // MARK: - Presence

    static func presenceCaption(listening: Bool, speaking: Bool, thinking: Bool) -> String {
        if listening { return "Listening" }
        if thinking { return "Thinking" }
        if speaking { return "Speaking" }
        return "With you"
    }

    static func shouldShowVoiceDock(for step: AriaInterviewStep) -> Bool {
        switch step {
        case .intro, .details, .ready: return false
        default: return true
        }
    }

    static func voiceHint(for step: AriaInterviewStep) -> String {
        switch step {
        case .intro: return ""
        case .name: return "Say your first name, or type it."
        case .health: return "Say “connect Health” or “later.”"
        case .details: return ""
        case .goals: return "Name a goal, or say “continue.”"
        case .experience: return "Say beginner, a few years, advanced, or elite."
        case .workouts: return "Name a training style, or say “continue.”"
        case .sleep: return "Say early bird, night owl, average, or irregular."
        case .freeTime: return "Name how you spend free time, or say skip."
        case .coaching: return "Say push me, balanced, patient, explain, or elite."
        case .conditions: return "Optional. Say skip, none, or talk."
        case .ready: return ""
        }
    }

    // MARK: - Suggested replies

    struct Reply: Equatable, Identifiable {
        let id: String
        let label: String
        let kind: Kind

        enum Kind: Equatable {
            case startTalking
            case confirmName
            case connectHealth
            case skipHealthAndContinue
            case continueHealth
            case experience(ExperienceLevel)
            case sleep(SleepRhythmBand)
            case coaching(OnboardingCoachingStyle)
            case confirmGoals
            case confirmWorkouts
            case skipInterests
            case confirmInterests
            case skipConditions
            case noneConditions
        }
    }

    static func suggestedReplies(
        step: AriaInterviewStep,
        profile: OnboardingProfile,
        health: HealthKitState,
        calendar: HealthKitState
    ) -> [Reply] {
        switch step {
        case .intro, .details, .ready:
            return []
        case .name:
            var rows: [Reply] = [
                Reply(id: "talk", label: "I’ll say it", kind: .startTalking),
            ]
            if profile.isPreferredNameValid {
                rows.append(Reply(
                    id: "confirm-name",
                    label: "That’s me — \(profile.firstName)",
                    kind: .confirmName
                ))
            }
            return rows
        case .health:
            var rows: [Reply] = []
            if health != .authorized {
                rows.append(Reply(id: "health-connect", label: "Connect Apple Health", kind: .connectHealth))
            }
            if health == .authorized || calendar == .authorized {
                rows.append(Reply(id: "health-continue", label: "That’s enough — continue", kind: .continueHealth))
            }
            rows.append(Reply(id: "health-later", label: "I’ll add it later", kind: .skipHealthAndContinue))
            return rows
        case .goals:
            return profile.fitnessGoals.isEmpty ? [] : [
                Reply(id: "goals-go", label: "Those. Continue", kind: .confirmGoals),
            ]
        case .experience:
            return [
                Reply(id: "xp-beg", label: "I’m new", kind: .experience(.beginner)),
                Reply(id: "xp-int", label: "A few years in", kind: .experience(.intermediate)),
                Reply(id: "xp-adv", label: "I’m advanced", kind: .experience(.advanced)),
                Reply(id: "xp-elite", label: "I compete", kind: .experience(.elite)),
            ]
        case .workouts:
            return profile.preferredWorkouts.isEmpty ? [] : [
                Reply(id: "wo-go", label: "That’s what I do", kind: .confirmWorkouts),
            ]
        case .sleep:
            return [
                Reply(id: "sl-early", label: "Early bird", kind: .sleep(.earlyBird)),
                Reply(id: "sl-avg", label: "Normal-ish", kind: .sleep(.average)),
                Reply(id: "sl-owl", label: "Night owl", kind: .sleep(.nightOwl)),
                Reply(id: "sl-irr", label: "No fixed pattern", kind: .sleep(.irregular)),
            ]
        case .freeTime:
            if profile.freeTimeInterests.isEmpty {
                return [Reply(id: "ft-skip", label: "Skip this", kind: .skipInterests)]
            }
            return [Reply(id: "ft-go", label: "That’s my life", kind: .confirmInterests)]
        case .coaching:
            return [
                Reply(id: "c-drive", label: "Push me", kind: .coaching(.driven)),
                Reply(id: "c-bal", label: "Keep me steady", kind: .coaching(.balanced)),
                Reply(id: "c-sup", label: "Be patient", kind: .coaching(.supportive)),
                Reply(id: "c-sci", label: "Explain the why", kind: .coaching(.scientist)),
                Reply(id: "c-elite", label: "Treat me like an athlete", kind: .coaching(.elite)),
            ]
        case .conditions:
            return [
                Reply(id: "cond-none", label: "Nothing to flag", kind: .noneConditions),
                Reply(id: "cond-skip", label: "Skip", kind: .skipConditions),
                Reply(id: "cond-talk", label: "I’ll say it", kind: .startTalking),
            ]
        }
    }

    // MARK: - Opening + prompts

    static func introLine(firstName: String, questLabel: String?) -> String {
        let quest = questLabel.map { " You already locked \($0) — we’ll train from that." } ?? ""
        if firstName.isEmpty {
            return "I'm ARIA. I'll be in your mornings, your sessions, and the night you actually sleep. Lifestyle coach, not a doctor. About a minute — then I'm in the loop every day."
        }
        return "Welcome, \(firstName). I'm ARIA — I'll be in your mornings, your sessions, and the night you actually sleep. Lifestyle coach, not a doctor.\(quest) About a minute, then I'm with you every day."
    }

    static func prompt(
        _ step: AriaInterviewStep,
        profile: OnboardingProfile,
        healthAuthorized: Bool,
        healthPrefill: Bool,
        vo2Max: Double?
    ) -> String {
        switch step {
        case .intro:
            return introLine(firstName: profile.firstName, questLabel: profile.fitnessGoals.first?.label)
        case .name:
            if profile.isPreferredNameValid {
                return "I have you as \(profile.firstName) from sign-up. That’s what I’ll say at wake-up and after training. Confirm the spelling — last name is optional and stays on your profile."
            }
            return "What should I call you every day? First name is enough — that’s what I’ll use in coaching. Last name is optional and stays on your profile."
        case .health:
            return "Two things make me useful tomorrow morning: Apple Health, and the busy windows on your calendar — never the titles. Health first. This is how I stop being an app you open when you remember."
        case .details:
            if healthAuthorized && healthPrefill {
                return "Apple Health already has some of your details. Check date of birth, biological sex, height, and weight — change anything that's off. I use these for heart-rate zones and Cycle Health. This is not gender."
            }
            return "Your details next — date of birth, biological sex, height, and weight. I use these for heart-rate zones, calories, and Cycle Health. This is not gender."
        case .goals:
            return goalsPrompt(profile: profile)
        case .experience:
            return experiencePrompt(vo2Max: vo2Max)
        case .workouts:
            return "What training do you actually enjoy? Pick what you'll still do on a messy Tuesday — adherence is the whole game."
        case .sleep:
            return "When do you actually sleep and wake? I'll put hard sessions and wind-down on your clock, not a generic 6am."
        case .freeTime:
            return "Outside training — how do you like to spend free time? I design around the life you already have, not a fantasy week."
        case .coaching:
            return "Last coaching choice: how should I talk to you when the day is messy — 6am and 10pm, not just when you're motivated?"
        case .conditions:
            return "Do you have any conditions I should respect when coaching — ADHD, epilepsy, an injury, a chronic illness, a disability, or something else? Optional. I'm a lifestyle coach, not a doctor. I won't diagnose or treat; I'll only use this to keep guidance safer and more realistic."
        case .ready:
            return ""
        }
    }

    static func goalsPrompt(profile: OnboardingProfile) -> String {
        if profile.fitnessGoals.count == 1 {
            return "You already locked \(profile.fitnessGoals[0].label). Keep it, or add a second goal — these become the days we don't skip."
        }
        if !profile.firstName.isEmpty {
            return "\(profile.firstName), what are we building toward? Pick every outcome that would make skipping Forge feel like skipping a person who showed up."
        }
        return "What are we building toward? Pick every outcome that matters — that's the loop I'll protect."
    }

    static func experiencePrompt(vo2Max: Double?) -> String {
        if let vo2 = vo2Max, vo2 >= 45 {
            return "Your Apple Health VO₂max looks solid. How would you rate your training experience? I'll load you accordingly — not a generic plan."
        }
        return "How long have you been training seriously? I need this so day one isn't too soft or too stupid."
    }

    // MARK: - Acknowledgments (spoken after *this* answer)

    static func acknowledgeName(_ firstName: String) -> String {
        "\(firstName). I'll use that every day — morning check-ins, session cues, the night you should already be down."
    }

    static func acknowledgeHealthSkip() -> String {
        "Alright. I can still coach — I'll just guess more until Health is in. You can add it in Settings when you're ready. Let's keep going."
    }

    static func acknowledgeHealthContinue(health: HealthKitState, calendar: HealthKitState) -> String {
        switch (health == .authorized, calendar == .authorized) {
        case (true, true):
            return "Health and calendar are in. Tomorrow morning I won't be starting from zero."
        case (true, false):
            return "Health is in. That's the daily loop. Calendar can wait."
        case (false, true):
            return "Calendar's in — I'll fit training around busy windows. Health whenever you're ready."
        case (false, false):
            return "We'll go on what you tell me. The invitation stays open."
        }
    }

    static func acknowledgeDetails() -> String {
        "Locked. That's enough to coach you as a body, not a template."
    }

    static func acknowledgeGoals(_ labels: [String]) -> String {
        let listed = labels.joined(separator: ", ")
        return "\(listed). Those are the days we don't negotiate with."
    }

    static func acknowledgeExperience(_ level: ExperienceLevel) -> String {
        switch level {
        case .beginner:
            return "New is a good place to be. I'll keep the first weeks honest and repeatable."
        case .intermediate:
            return "A few years in — I'll treat you like someone who already knows the room."
        case .advanced:
            return "Advanced. I'll assume you can take structure, and I'll still watch recovery."
        case .elite:
            return "Competitive. Readiness first, then output. I won't waste your window."
        }
    }

    static func acknowledgeWorkouts(_ labels: [String]) -> String {
        let listed = labels.prefix(3).joined(separator: ", ")
        return "\(listed). That's what I'll program when motivation is lying."
    }

    static func acknowledgeSleep(_ band: SleepRhythmBand) -> String {
        switch band {
        case .earlyBird:
            return "Early bird. Hard work lives in the morning. I won't pretend you're a 10pm person."
        case .average:
            return "A normal-ish clock. I'll park wind-down before the night gets away from you."
        case .nightOwl:
            return "Night owl. I will not put your hard session at 6am. We train on your clock."
        case .irregular:
            return "No fixed pattern. I'll seed a wind-down you can grab on the nights you can — not a fake 10pm."
        }
    }

    static func acknowledgeInterests(_ labels: [String]) -> String {
        if labels.isEmpty {
            return "All good. Training still has to fit a real week."
        }
        return "\(labels.joined(separator: ", ")). I'll protect that time, not eat it."
    }

    static func acknowledgeCoaching(_ style: OnboardingCoachingStyle) -> String {
        switch style {
        case .driven:
            return "Push. That's how I'll sound at 6am and at 10pm — standards, not vibes."
        case .balanced:
            return "Steady. I'll push when the signal says so, and I'll back off when it doesn't."
        case .supportive:
            return "Patient. I'll still tell you the truth — just without turning the day into a trial."
        case .scientist:
            return "I'll show the why. You get the mechanism, not just the order."
        case .elite:
            return "Athlete mode. Readiness, output, recovery — that's the daily conversation."
        }
    }

    static func missedLine() -> String {
        "I missed that. Tap a reply, or say it again — I'm here."
    }

    // MARK: - Spoken matching

    enum SpokenMatch: Equatable {
        case fillName(String)
        case confirmName
        case connectHealth
        case skipHealthAndContinue
        case continueHealth
        case experience(ExperienceLevel)
        case sleep(SleepRhythmBand)
        case coaching(OnboardingCoachingStyle)
        case toggleGoals([OnboardingFitnessGoal])
        case confirmGoals
        case toggleWorkouts([OnboardingWorkoutType])
        case confirmWorkouts
        case toggleInterests([LifestyleInterest])
        case skipInterests
        case confirmInterests
        case skipConditions
        case noneConditions
        case fillConditionsNote(String)
        case missed
    }

    static func matchSpoken(
        _ text: String,
        step: AriaInterviewStep,
        profile: OnboardingProfile
    ) -> SpokenMatch? {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        let lower = raw.lowercased()

        switch step {
        case .intro, .details, .ready:
            return nil
        case .name:
            if isContinuePhrase(lower), profile.isPreferredNameValid { return .confirmName }
            if let name = spokenNameCandidate(raw) { return .fillName(name) }
            return .missed
        case .health:
            if lower.contains("later") || lower.contains("skip") || lower.contains("not now")
                || lower.contains("no thanks") {
                return .skipHealthAndContinue
            }
            if lower.contains("continue") || lower.contains("enough") || lower.contains("that's it")
                || lower.contains("thats it") {
                return .continueHealth
            }
            if lower.contains("health") || lower.contains("connect")
                || lower == "yes" || lower.hasPrefix("yes ") {
                return .connectHealth
            }
            return .missed
        case .goals:
            if isContinuePhrase(lower), !profile.fitnessGoals.isEmpty { return .confirmGoals }
            let hits = OnboardingFitnessGoal.allCases.filter { goal in
                lower.contains(goal.label.lowercased()) || lower.contains(spokenGoalAlias(goal))
            }
            if !hits.isEmpty { return .toggleGoals(hits) }
            return .missed
        case .experience:
            if let level = matchExperience(lower) { return .experience(level) }
            return .missed
        case .workouts:
            if isContinuePhrase(lower), !profile.preferredWorkouts.isEmpty { return .confirmWorkouts }
            let hits = OnboardingWorkoutType.allCases.filter { w in
                lower.contains(w.label.lowercased())
            }
            if !hits.isEmpty { return .toggleWorkouts(hits) }
            return .missed
        case .sleep:
            if let band = matchSleep(lower) { return .sleep(band) }
            return .missed
        case .freeTime:
            if lower.contains("skip") || lower.contains("nothing") || lower.contains("pass") {
                return .skipInterests
            }
            if isContinuePhrase(lower) { return .confirmInterests }
            let hits = LifestyleInterest.allCases.filter { interest in
                lower.contains(interest.label.lowercased())
            }
            if !hits.isEmpty { return .toggleInterests(hits) }
            return .missed
        case .coaching:
            if let style = matchCoaching(lower) { return .coaching(style) }
            return .missed
        case .conditions:
            if lower.contains("skip") || lower.contains("not now") || lower.contains("later") {
                return .skipConditions
            }
            if lower.contains("none") || lower.contains("nothing") || lower.contains("no conditions")
                || lower.contains("i'm good") || lower.contains("im good") {
                return .noneConditions
            }
            return .fillConditionsNote(raw)
        }
    }

    // MARK: - Internals

    private static func isContinuePhrase(_ lower: String) -> Bool {
        let folded = foldApostrophes(lower)
        return folded == "continue" || folded == "done" || folded == "that's it" || folded == "thats it"
            || folded == "that's me" || folded == "thats me" || folded == "go" || folded == "next"
            || folded.contains("continue") || folded.contains("that's me") || folded.contains("thats me")
    }

    private static func foldApostrophes(_ text: String) -> String {
        text.replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: "`", with: "'")
    }

    private static func spokenNameCandidate(_ raw: String) -> String? {
        let folded = foldApostrophes(raw)
        let stops: Set<String> = [
            "say", "type", "call", "please", "um", "uh", "me", "my", "name",
            "is", "it's", "its", "i'm", "im", "i'll", "ill", "it", "the", "a",
        ]
        let kept = folded.split(separator: " ").map(String.init).filter { token in
            !stops.contains(token.lowercased())
        }
        let candidate = kept.joined(separator: " ")
        guard looksLikeName(candidate) else { return nil }
        return candidate
    }

    private static func looksLikeName(_ raw: String) -> Bool {
        let parts = raw.split(separator: " ")
        guard (1...4).contains(parts.count) else { return false }
        let compact = raw.replacingOccurrences(of: " ", with: "")
        return (2...32).contains(compact.count)
            && raw.rangeOfCharacter(from: .decimalDigits) == nil
    }

    private static func spokenGoalAlias(_ goal: OnboardingFitnessGoal) -> String {
        switch goal {
        case .loseWeight: return "weight"
        case .buildMuscle: return "muscle"
        case .improveEndurance: return "endurance"
        case .increaseFlexibility: return "flex"
        case .betterSleep: return "sleep"
        case .reducStress: return "stress"
        case .athleticPerformance: return "performance"
        case .generalHealth: return "health"
        }
    }

    private static func matchExperience(_ lower: String) -> ExperienceLevel? {
        if lower.contains("beginner") || lower.contains("new") || lower.contains("just start")
            || lower.contains("getting started") {
            return .beginner
        }
        if lower.contains("elite") || lower.contains("compete") || lower.contains("competitive")
            || lower.contains("athlete") {
            return .elite
        }
        if lower.contains("advanced") { return .advanced }
        if lower.contains("intermediate") || lower.contains("few years") || lower.contains("some experience") {
            return .intermediate
        }
        return nil
    }

    private static func matchSleep(_ lower: String) -> SleepRhythmBand? {
        if lower.contains("inconsistent") || lower.contains("irregular") || lower.contains("shift")
            || lower.contains("no pattern") || lower.contains("no fixed") {
            return .irregular
        }
        if lower.contains("owl") || lower.contains("late night") || lower.contains("night owl")
            || lower == "night" || lower.hasPrefix("night ") {
            return .nightOwl
        }
        if lower.contains("early") || lower.contains("morning person") {
            return .earlyBird
        }
        if lower.contains("average") || lower.contains("normal") || lower.contains("typical") {
            return .average
        }
        return nil
    }

    private static func matchCoaching(_ lower: String) -> OnboardingCoachingStyle? {
        if lower.contains("push") || lower.contains("driven") || lower.contains("intense") {
            return .driven
        }
        if lower.contains("patient") || lower.contains("support") || lower.contains("kind") {
            return .supportive
        }
        if lower.contains("scientist") || lower.contains("explain") || lower.contains("data")
            || lower.contains("why") {
            return .scientist
        }
        if lower.contains("elite") || lower.contains("athlete") || lower.contains("performance") {
            return .elite
        }
        if lower.contains("balance") || lower.contains("steady") {
            return .balanced
        }
        return nil
    }
}
