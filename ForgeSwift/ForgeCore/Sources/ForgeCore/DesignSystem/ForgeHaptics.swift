import SwiftUI
#if os(iOS)
import UIKit
#elseif os(watchOS)
import WatchKit
#endif

// MARK: - Haptics
//
// One vocabulary for every target (`ForgeDesignTokens.Haptic`):
//
//   selection  pickers, segmented controls, tabs, chips
//   press      primary buttons and deliberate taps (light impact)
//   success    a workout or set logged, a goal closed
//   warning    something needs attention
//   error      a failure shown on screen
//
// Nothing plays on scroll, appear, or data that arrives on its own.
// Both paths go through the system feedback engine, so the system
// haptics switch (Settings › Sounds & Haptics) silences all of them.

public typealias ForgeHaptic = ForgeDesignTokens.Haptic

extension ForgeHaptic {
    public var feedback: SensoryFeedback {
        switch self {
        case .selection: return .selection
        case .press: return .impact(weight: .light)
        case .success: return .success
        case .warning: return .warning
        case .error: return .error
        }
    }
}

public extension View {
    /// Plays `haptic` whenever `trigger` changes. Prefer this whenever the
    /// moment already lives in state (a selection, a logged set, an error).
    func forgeHaptic<T: Equatable>(_ haptic: ForgeHaptic, trigger: T) -> some View {
        sensoryFeedback(haptic.feedback, trigger: trigger)
    }

    /// Plays `haptic` when `trigger` changes and `condition(old, new)` holds.
    func forgeHaptic<T: Equatable>(
        _ haptic: ForgeHaptic,
        trigger: T,
        condition: @escaping (_ old: T, _ new: T) -> Bool
    ) -> some View {
        sensoryFeedback(haptic.feedback, trigger: trigger, condition: condition)
    }
}

/// The imperative path, for a tap whose action has no state to observe
/// (a coordinator method, a button that only navigates). Same mapping as
/// `forgeHaptic(_:trigger:)`.
public enum ForgeHaptics {
    /// Hammer-on-anvil. `UIImpactFeedbackGenerator` `.rigid` — not the light
    /// `.press` used for buttons. Off under Reduce Motion at the call site.
    public static let strikeToken = "rigid"

    @MainActor
    public static func play(_ haptic: ForgeHaptic) {
        #if os(iOS)
        switch haptic {
        case .selection:
            UISelectionFeedbackGenerator().selectionChanged()
        case .press:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        #elseif os(watchOS)
        let type: WKHapticType
        switch haptic {
        case .selection, .press: type = .click
        case .success: type = .success
        case .warning: type = .retry
        case .error: type = .failure
        }
        WKInterfaceDevice.current().play(type)
        #endif
    }

    @MainActor
    public static func playStrike() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        #elseif os(watchOS)
        WKInterfaceDevice.current().play(.click)
        #endif
    }
}
