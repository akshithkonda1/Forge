import SwiftUI

enum ARIAMood: Equatable {
    case energized   // High readiness + morning
    case focused     // Medium readiness + daytime
    case calm        // Evening or low readiness
    case pushed      // User said "not feeling it"

    var displayName: String {
        switch self {
        case .energized: return "Energized"
        case .focused:   return "Focused"
        case .calm:      return "Calm"
        case .pushed:    return "Supportive"
        }
    }

    var emoji: String {
        switch self {
        case .energized: return "⚡️"
        case .focused:   return "🎯"
        case .calm:      return "🌙"
        case .pushed:    return "🤝"
        }
    }

    var accentColor: Color {
        switch self {
        case .energized: return Color.ember
        case .focused:   return Color(hex: "4A90D9")
        case .calm:      return Color(hex: "A855F7")
        case .pushed:    return Color(hex: "22C55E")
        }
    }

    var typingStyle: String {
        switch self {
        case .energized: return "Let's Go!!! Let's seize the day!!"
        case .focused:   return "Noted. Let's lock in. "
        case .calm:      return "Of course, you do you. "
        case .pushed:    return "I've got you. "
        }
    }

    static func derive(readiness: Int, sleepScore: Int? = nil) -> ARIAMood {
        let hour = Calendar.current.component(.hour, from: Date())
        // Thin sleep damps "energized" even when readiness looks high — keeps
        // mood aligned with cross-zone biometrics ARIA is about to coach on.
        let sleepDamp = (sleepScore ?? 100) < 60
        if readiness >= 80 && hour < 15 && !sleepDamp { return .energized }
        if readiness < 50 || sleepDamp && readiness < 70 { return hour >= 18 ? .calm : .pushed }
        if readiness >= 60              { return .focused }
        if hour >= 20                   { return .calm }
        return .focused
    }
}

// Both the empty state and the input area offer these, so this is not
// file-private: it maps mood and readiness onto suggested actions.
func smartQuickActions(mood: ARIAMood, readiness: Int, messageCount: Int) -> [(label: String, icon: String, color: Color)] {
    let hour = Calendar.current.component(.hour, from: Date())

    // Core actions — always present but reordered by context
    var actions: [(label: String, icon: String, color: Color)] = []

    // Time-of-day first action
    if hour < 10 {
        actions.append(("Morning brief", "sunrise.fill", mood.accentColor))
    } else if hour >= 20 {
        actions.append(("Wind down plan", "moon.zzz.fill", Color(hex: "A855F7")))
    } else {
        actions.append(("What now?", "sparkles", mood.accentColor))
    }

    // Readiness-reactive
    if readiness >= 85 {
        actions.append(("I'm fired up 🔥", "bolt.fill", Color.ember))
    } else if readiness < 55 {
        actions.append(("Easy day options", "leaf.fill", Color(hex: "22C55E")))
    } else {
        actions.append(("Today's workout", "dumbbell.fill", Color.ember))
    }

    // Always useful
    actions.append(("How'd I sleep?", "moon.fill", Color(hex: "4A90D9")))
    actions.append(("Am I progressing?", "chart.line.uptrend.xyaxis", Color(hex: "22C55E")))

    if messageCount == 0 {
        actions.append(("Something hurts", "heart.text.square.fill", Color(hex: "EF4444")))
    } else {
        actions.append(("Change my plan", "arrow.triangle.2.circlepath", Color(hex: "F59E0B")))
    }

    actions.append(("Motivate me", "flame.fill", Color.ember))

    return actions
}

enum VoiceState: Equatable {
    case idle, listening, processing, speaking
    case error(String)

    var orbState: AROrbState {
        switch self {
        case .idle:       return .idle
        case .listening:  return .listening
        case .processing: return .processing
        case .speaking:   return .speaking
        case .error:      return .idle
        }
    }

    var label: String {
        switch self {
        case .idle:           return "Tap to speak"
        case .listening:      return "Listening…"
        case .processing:     return "Thinking…"
        case .speaking:       return "ARIA speaking"
        case .error(let m):   return m
        }
    }

    var sublabel: String {
        switch self {
        case .idle:       return "Say anything to ARIA"
        case .listening:  return "Speak clearly"
        case .processing: return "Analyzing your biometrics"
        case .speaking:   return "Tap to interrupt"
        case .error:      return "Try again"
        }
    }
}

enum HapticEvent {
    case messageSent        // Light + delay + success
    case messageReceived    // Soft impact
    case reactionAdded      // Selection + light
    case milestone          // Heavy + notification success
    case voiceStart         // Medium + rigid
    case quickChipTap       // Selection
    case celebration        // Sequence of impacts
    case typing             // Very light
}

enum AriaComposerMode: String, CaseIterable {
    case chat
    case research

    var title: String {
        switch self {
        case .chat: return "Chat"
        case .research: return "Research"
        }
    }

    var placeholder: String {
        switch self {
        case .chat: return "Ask ARIA anything…"
        case .research: return "Ask ARIA to go deep…"
        }
    }

    static func researchPrompt(for question: String) -> String {
        """
        [DEEP RESEARCH]
        Write a structured brief, not a chatty reply. Use this person's Forge context (sleep, readiness, training, lifestyle, cycle if present). Be honest about uncertainty.

        Format exactly:
        What we know
        What the evidence says
        What to do this week
        What we should not claim

        Question: \(question)
        """
    }
}
