import Foundation
import SwiftUI

struct OnboardingChatMessage: Identifiable {
    enum Role { case aria, user }
    let id = UUID()
    let role: Role
    let text: String
    var timestamp: Date = Date()
}

/// One conversational turn: the lines ARIA should say, the quick-reply chips to
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
struct OnboardingAriaBot {

    func opening(profile: OnboardingProfile, health: UserHealthProfile?, healthConnected: Bool) -> AriaTurn {
        let intro = "Hey \(name(profile)) — I'm ARIA, your coach. I've been reading your setup while you filled it out."
        let context = "You're training at a \(profile.experienceLevel.label.lowercased()) level, aiming for \(goalPhrase(profile)). \(healthLine(health, connected: healthConnected))"
        let question = "To tailor day one — how many days a week can you realistically train?"
        return AriaTurn(messages: [intro, context, question],
                        suggestions: ["2–3 days", "4–5 days", "6+ days"])
    }

    // `step` is a 0-indexed conversation turn counter (0, 1, 2…), NOT OnboardingRoute.rawValue.
    // Passing the wrong index causes premature synthesis (default branch) after turn 0.
    func reply(step: Int, input: String, answers: [String], profile: OnboardingProfile) -> AriaTurn {
        switch step {
        case 0:
            return AriaTurn(
                messages: ["\(input) is a strong, sustainable base.",
                           "When do you usually have the most energy to move?"],
                suggestions: ["Mornings", "Evenings", "It varies"],
                tags: ["weekly_days:\(slug(input))"]
            )
        case 1:
            return AriaTurn(
                messages: ["Good — I'll bias your harder sessions toward \(input.lowercased()).",
                           "Last thing: what's usually gotten in the way before?"],
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
        p.trimmedName.isEmpty ? "there" : p.trimmedName
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
            return "Once you connect Apple Health, I'll tune everything to your recovery."
        }
        var facts: [String] = []
        if let weight = health?.weightKg { facts.append("\(Int(weight)) kg") }
        if let height = health?.heightCm { facts.append("\(Int(height)) cm") }
        if let vo2 = health?.vo2Max { facts.append("VO₂max ~\(Int(vo2))") }
        if facts.isEmpty {
            return "I can see your Apple Health data too, so recovery will shape your load."
        }
        return "I can already see \(facts.joined(separator: ", ")) from Apple Health — that anchors your baseline."
    }

    private func synthesis(profile p: OnboardingProfile, answers: [String], obstacle: String) -> String {
        let days = answers.first ?? "a few days"
        let obstacleLine: String
        switch obstacle.lowercased() {
        case let s where s.contains("time"):   obstacleLine = "I'll keep sessions tight so time is never the reason you skip."
        case let s where s.contains("motiv"):  obstacleLine = "I'll keep the wins visible so momentum carries you on the low days."
        case let s where s.contains("injur"):  obstacleLine = "I'll ramp load carefully and program around anything that flares up."
        default:                                obstacleLine = "I'll keep it adaptive so it fits whatever the week throws at you."
        }
        return "Here's the plan I'm forming, \(name(p)): a \(p.coachingStyle.label.lowercased()) approach built around \(goalPhrase(p)), \(days.lowercased()) a week, starting at \(p.experienceLevel.label.lowercased()) intensity. \(obstacleLine) Ready when you are."
    }

    private func slug(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: " ", with: "_")
    }
}
