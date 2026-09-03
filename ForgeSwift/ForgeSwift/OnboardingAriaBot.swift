import Foundation
import SwiftUI

struct OnboardingChatMessage: Identifiable {
    enum Role { case aria, user }
    let id = UUID()
    let role: Role
    let text: String
    var timestamp: Date = Date()
}

/// One conversational turn: the line ARIA should say, the quick-reply chips to
/// offer next, whether the intake is finished, and any data captured from the
/// user's answer (fed into ARIA's living context on completion).
struct AriaTurn {
    var messages: [String]
    var suggestions: [String] = []
    var finished: Bool = false
    var tags: [String] = []
    var constraints: [String] = []
}

/// Deterministic stand-in for the real ARIA coach during onboarding. It produces
/// scripted, data-aware turns so the flow is fully testable offline and needs no
/// network on first launch. When the live coach is ready, replace the bodies with
/// calls to `AriaService.shared.sendMessage(...)` — the coordinator contract
/// (opening + reply → AriaTurn) stays identical.
///
/// One message per turn. Stacked intros cost layout, delay, and attention
/// without adding signal the chips don't already carry.
struct OnboardingAriaBot {

    func opening(profile: OnboardingProfile, health: UserHealthProfile?, healthConnected: Bool) -> AriaTurn {
        let line = "Hey \(name(profile)) — \(profile.experienceLevel.label.lowercased()) toward \(goalPhrase(profile)). \(healthLine(health, connected: healthConnected)) How many days a week can you actually train?"
        return AriaTurn(
            messages: [line],
            suggestions: ["2–3 days", "4–5 days", "6+ days"]
        )
    }

    // `step` is a 0-indexed conversation turn counter (0, 1, 2…), NOT OnboardingRoute.rawValue.
    // Passing the wrong index causes premature synthesis (default branch) after turn 0.
    func reply(step: Int, input: String, answers: [String], profile: OnboardingProfile) -> AriaTurn {
        switch step {
        case 0:
            return AriaTurn(
                messages: ["\(input) is a sustainable base. When do you usually have the most energy to move?"],
                suggestions: ["Mornings", "Evenings", "It varies"],
                tags: ["weekly_days:\(slug(input))"]
            )
        case 1:
            return AriaTurn(
                messages: ["I'll bias harder sessions toward \(input.lowercased()). What's usually gotten in the way before?"],
                suggestions: ["Time", "Motivation", "Past injuries", "Nothing major"],
                tags: ["energy:\(slug(input))"]
            )
        default:
            let injury = input.lowercased().contains("injur")
            return AriaTurn(
                messages: [synthesis(profile: profile, answers: answers, obstacle: input)],
                finished: true,
                tags: ["obstacle:\(slug(input))"],
                constraints: injury ? ["injury-aware programming"] : []
            )
        }
    }

    // MARK: helpers

    private func name(_ p: OnboardingProfile) -> String {
        p.trimmedName.isEmpty ? "there" : p.firstName
    }

    private func goalPhrase(_ p: OnboardingProfile) -> String {
        let goals = p.fitnessGoals.map { $0.label.lowercased() }
        switch goals.count {
        case 0:  return "overall fitness"
        case 1:  return goals[0]
        case 2:  return "\(goals[0]) and \(goals[1])"
        default: return "\(goals[0]), \(goals[1]), and more"
        }
    }

    private func healthLine(_ health: UserHealthProfile?, connected: Bool) -> String {
        guard connected else {
            return "Connect Apple Health anytime and recovery will shape the load."
        }
        if health?.vo2Max != nil || health?.weightKg != nil {
            return "Apple Health is already in — recovery will shape the load."
        }
        return "I can see Apple Health, so recovery will shape the load."
    }

    private func synthesis(profile p: OnboardingProfile, answers: [String], obstacle: String) -> String {
        let days = answers.first ?? "a few days"
        let energy = answers.dropFirst().first.map { " Energy peaks \($0.lowercased())." } ?? ""
        let sleep = p.sleepBand.map { " Sleep: \($0.label.lowercased())." } ?? ""
        let obstacleLine: String
        switch obstacle.lowercased() {
        case let s where s.contains("time"):   obstacleLine = "Sessions stay tight so time isn't why you skip."
        case let s where s.contains("motiv"):  obstacleLine = "Wins stay visible so low days still move."
        case let s where s.contains("injur"):  obstacleLine = "Load ramps carefully around anything that flares."
        default:                                obstacleLine = "It stays adaptive for whatever the week throws."
        }
        return "Plan forming, \(name(p)): \(p.coachingStyle.label.lowercased()) around \(goalPhrase(p)), \(days.lowercased()) a week, \(p.experienceLevel.label.lowercased()) intensity.\(energy)\(sleep) \(obstacleLine)"
    }

    private func slug(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: " ", with: "_")
    }
}
