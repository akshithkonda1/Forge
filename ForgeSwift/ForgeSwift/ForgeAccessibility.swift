import SwiftUI

// MARK: - Forge Accessibility Helpers
//
// Small, reusable modifiers so accessibility is applied consistently across the
// app rather than ad hoc. These are additive and behavior-neutral for sighted
// users — they only change what assistive technologies (VoiceOver, Switch
// Control, Full Keyboard Access) perceive.

extension View {

    /// Marks this view as a heading so VoiceOver users can jump between sections
    /// with the rotor. Use on section titles.
    func forgeHeader() -> some View {
        accessibilityAddTraits(.isHeader)
    }

    /// Configures a custom bottom-bar item to read like a native tab: one focusable
    /// button that announces its name, selected state, and position in the bar.
    /// Apply to the tab's `Button`.
    func forgeTab(_ name: String, isSelected: Bool, index: Int, count: Int) -> some View {
        self
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(name)
            .accessibilityValue("Tab \(index) of \(count)")
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityHint(isSelected ? "" : "Opens \(name)")
    }

    /// Groups a purely-informational card into a single VoiceOver element with an
    /// explicit label + value, so it reads as one coherent unit instead of many
    /// disconnected fragments. Pass an empty `value` to combine label only.
    func forgeInfoCard(label: String, value: String = "") -> some View {
        self
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(value)
    }

    /// Ensures a control meets the 44×44pt minimum hit target Apple recommends,
    /// without changing its visual size.
    func forgeMinTapTarget() -> some View {
        contentShape(Rectangle())
            .frame(minWidth: 44, minHeight: 44)
    }
}

// MARK: - Motion

extension Animation {
    /// Returns this animation, or `nil` when the user has asked for reduced motion.
    /// Use for continuous / looping / decorative animation so motion-sensitive
    /// users get a calm, static presentation.
    func forgeMotion(_ reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : self
    }
}
