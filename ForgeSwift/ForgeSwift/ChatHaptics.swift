import SwiftUI

/// Haptic strength scales with ARIA's mood: a supportive or wind-down moment
/// should feel softer than a high-energy one. `nil` keeps the neutral feel.
private func moodHapticScale(_ mood: ARIAMood?) -> CGFloat {
    switch mood {
    case .calm, .pushed: return 0.62
    case .energized:     return 1.0
    case .focused, nil:  return 0.82
    }
}

func choreographedHaptic(_ event: HapticEvent, mood: ARIAMood? = nil) {
    let scale = moodHapticScale(mood)
    switch event {
    case .messageSent:
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: scale)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: scale)
        }
    case .messageReceived:
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: scale)
    case .reactionAdded:
        UISelectionFeedbackGenerator().selectionChanged()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: scale)
        }
    case .milestone:
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    case .voiceStart:
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: scale)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: scale)
        }
    case .quickChipTap:
        UISelectionFeedbackGenerator().selectionChanged()
    case .celebration:
        for i in 0..<4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.1) {
                UIImpactFeedbackGenerator(style: i % 2 == 0 ? .heavy : .medium).impactOccurred()
            }
        }
    case .typing:
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.3 * scale)
    }
}
