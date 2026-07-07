import SwiftUI

// MARK: - Forge Semantic Color Tokens
//
// Extends the base palette in ColorExtensions.swift with two things the
// design system was missing:
//
// 1. Named tokens for colors that were already in constant use across the
//    app as raw `Color(hex:)` literals — `A855F7` (24 uses), `6366F1`
//    (12 uses), and `F59E0B` (25 uses) were already the app's de facto
//    violet/indigo/amber accents, just never centralized. These exact
//    hex values are also `ForgePalette.violet` / `.indigo` / `.amber` in
//    the watch app's shared ForgeCore package — naming them here gives
//    the two platforms one brand palette instead of two independent ones.
// 2. Semantic roles the token layer had no name for at all: an overlay
//    scrim, a focus ring, on-accent text, and a disabled state.

extension Color {
    // MARK: Extended brand accents (previously untokenized, high-repeat hex)

    /// Mindfulness / calm accent. Matches ForgeCore.ForgePalette.violet.
    static let violet      = Color(hex: "A855F7")
    /// Secondary calm accent, pairs with violet. Matches ForgePalette.indigo.
    static let indigo      = Color(hex: "6366F1")
    /// Attention/energy accent distinct from warning-yellow. Matches
    /// ForgePalette.amber.
    static let amber       = Color(hex: "F59E0B")
    static let amberLight  = Color(hex: "FFB84D")
    /// Achievement / personal-record indicator.
    static let gold        = Color(hex: "FFD700")
    /// Lighter sky-blue highlight, distinct from steel.
    static let sky         = Color(hex: "38BDF8")

    // MARK: Semantic roles with no prior token

    /// Full-screen dimming behind sheets/modals.
    static let scrim        = Color.black.opacity(0.55)
    /// Ring drawn around a focused control (external keyboard / Switch
    /// Control focus, not just VoiceOver).
    static let focusRing    = Color.steelLight
    /// Text/icon color placed directly on a filled accent background
    /// (e.g. inside an ember-filled button), where `.textPrimary` white
    /// may not be the intended contrast choice for every accent.
    static let onAccent     = Color.white
    /// Disabled control state — one token instead of ad hoc `.opacity()`
    /// calls scattered per-view.
    static let disabledText = Color(hex: "52525B").opacity(0.6)
    static let disabledFill = Color(hex: "222222").opacity(0.5)
}
