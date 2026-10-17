import Foundation

/// Named characteristics of Forge's own design language.
///
/// Lockstep with `docs/forge-design-language.md`. Typography is intentionally
/// absent — faces, sizes, weights, and tracking stay in `ForgeFont` / `ForgeType`.
public enum ForgeDesignLanguage: Sendable {

    public static let docPath = "docs/forge-design-language.md"
    public static let motif = "mosaic"

    public enum Shape: String, CaseIterable, Sendable {
        case tessera
        case sweep
        case capsule
        case hairline
    }

    public enum Surface: String, CaseIterable, Sendable {
        case background
        case plate
        case elevated
    }

    public static let tesseraRadius = ForgeDesignTokens.Radius.lg
    public static let hairline = ForgeDesignTokens.Stroke.hairline
    public static let missIsNotAlert = true
    public static let motionEventOnly = ForgeDesignTokens.Motion.eventOnly
    public static let liveGlowDefault = ForgeDesignTokens.Motion.liveGlowDefault
    public static let minTap = ForgeDesignTokens.UX.minTap
    public static let skipAlwaysVisible = true
    public static let onePrimaryCTA = ForgeDesignTokens.UX.onePrimaryCTA

    /// Color fills the sweep; idle plates stay quiet. Ember is energy, never guilt.
    public static let colorLaw =
        "Ember is energy, never guilt. Miss uses steel-light, never alert red."

    public static let motionLaw =
        "Event-only. A win is a haptic plus a hairline pulse. Nothing loops while idle."

    public static let mosaicLaw =
        "Life is one picture of tesserae. A win lights one tile. Readiness is one solid sweep."

    public static let typeLaw =
        "Keep typography exactly as shipped. Do not change faces, sizes, weights, or tracking."

    public static let interactionLaw =
        "One primary CTA. Skip always visible on teaching. One gesture per beat, in the real UI."

    public static var characteristics: [String] {
        [
            Shape.tessera.rawValue,
            Shape.sweep.rawValue,
            Shape.capsule.rawValue,
            Shape.hairline.rawValue,
            motif,
            colorLaw,
            motionLaw,
            typeLaw,
        ]
    }
}
