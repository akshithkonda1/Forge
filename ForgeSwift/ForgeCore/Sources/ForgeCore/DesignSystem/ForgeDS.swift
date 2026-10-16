import SwiftUI

// MARK: - Forge Design System tokens (shared iOS + watchOS)
//
// Lockstep with `shared/design-tokens.json` via `ForgeDesignTokens`.
// Named `ForgeDS` so the iOS app can alias `FDS` without a clash.
// Motion lives in `ForgeMotion`, haptics in `ForgeHaptics`.

public enum ForgeDS {

    public enum Spacing {
        public static let xs:  CGFloat = CGFloat(ForgeDesignTokens.Spacing.xs)
        public static let sm:  CGFloat = CGFloat(ForgeDesignTokens.Spacing.sm)
        public static let md:  CGFloat = CGFloat(ForgeDesignTokens.Spacing.md)
        public static let lg:  CGFloat = CGFloat(ForgeDesignTokens.Spacing.lg)
        public static let xl:  CGFloat = CGFloat(ForgeDesignTokens.Spacing.xl)
        public static let xxl: CGFloat = CGFloat(ForgeDesignTokens.Spacing.xxl)
        public static let xxxl: CGFloat = CGFloat(ForgeDesignTokens.Spacing.xxxl)
    }

    public enum Radius {
        public static let xs:   CGFloat = CGFloat(ForgeDesignTokens.Radius.xs)
        public static let sm:   CGFloat = CGFloat(ForgeDesignTokens.Radius.sm)
        public static let md:   CGFloat = CGFloat(ForgeDesignTokens.Radius.md)
        public static let lg:   CGFloat = CGFloat(ForgeDesignTokens.Radius.lg)
        public static let xl:   CGFloat = CGFloat(ForgeDesignTokens.Radius.xl)
        public static let xxl:  CGFloat = CGFloat(ForgeDesignTokens.Radius.xxl)
        public static let pill: CGFloat = CGFloat(ForgeDesignTokens.Radius.pill)
    }

    public enum Stroke {
        public static let hairline: CGFloat = CGFloat(ForgeDesignTokens.Stroke.hairline)
        public static let thin: CGFloat = CGFloat(ForgeDesignTokens.Stroke.thin)
        public static let ring: CGFloat = CGFloat(ForgeDesignTokens.Stroke.ring)
        public static let compactRing: CGFloat = CGFloat(ForgeDesignTokens.Stroke.compactRing)
    }

    public static let minTap: CGFloat = CGFloat(ForgeDesignTokens.UX.minTap)
    public static let iconSize: CGFloat = CGFloat(ForgeDesignTokens.UX.iconSize)
    public static let safeInset: CGFloat = CGFloat(ForgeDesignTokens.UX.safeInset)
}

// MARK: - Named type scale
//
// One system: display / title / headline / body / caption / metric.
// Faces live in `ForgeFont` (Geist for UI + numbers, Instrument Serif for
// display). Phone roles scale with Dynamic Type via `relativeTo:`.
// Watch / widgets use Compact (same names, fixed sizes).
// Metrics always use Geist's tabular figures (`monospacedDigit`).

public enum ForgeType {
    /// Editorial display — greeting, hero headlines. Serif.
    public static let display = ForgeFont.serif(30, relativeTo: .title2)
    public static let title = ForgeFont.sans(20, weight: .semibold, relativeTo: .title3)
    public static let headline = ForgeFont.sans(17, weight: .semibold, relativeTo: .headline)
    public static let body = ForgeFont.sans(15, weight: .regular, relativeTo: .subheadline)
    /// Body with emphasis — replaces `body.weight(.medium)` (static faces).
    public static let bodyMedium = ForgeFont.sans(15, weight: .medium, relativeTo: .subheadline)
    public static let bodyStrong = ForgeFont.sans(15, weight: .semibold, relativeTo: .subheadline)
    public static let caption = ForgeFont.sans(12, weight: .medium, relativeTo: .caption)
    public static let metric = ForgeFont.sans(20, weight: .semibold, relativeTo: .title3).monospacedDigit()
    /// Screen titles. Serif, large, quiet.
    public static let pageTitle = ForgeFont.serif(36, relativeTo: .title)
    /// The one number a screen is about (readiness, sleep score). Light
    /// weight at size — confident without shouting.
    public static let heroScore = ForgeFont.sans(40, weight: .light, relativeTo: .largeTitle).monospacedDigit()
    public static let micro = ForgeFont.sans(11, weight: .medium, relativeTo: .caption2)
    /// Uppercase section eyebrows (pair with `eyebrowTracking`).
    public static let eyebrow = ForgeFont.sans(11, weight: .semibold, relativeTo: .caption2)
    /// ARIA's voice line — what the coach says, set as text, not an orb.
    public static let ariaVoice = ForgeFont.serif(24, relativeTo: .title3)

    public static func tracking(_ role: ForgeDesignTokens.TypeRole) -> CGFloat {
        CGFloat(role.tracking)
    }

    public static var eyebrowTracking: CGFloat {
        CGFloat(ForgeDesignTokens.eyebrowTracking)
    }

    /// Watch / widget / complication sizes — same role names, smaller canvas.
    /// All sans: the serif is too delicate at wrist sizes.
    public enum Compact {
        public static let display = ForgeFont.sans(
            CGFloat(ForgeDesignTokens.TypeRole.display.compactSize),
            weight: .semibold
        )
        public static let title = ForgeFont.sans(
            CGFloat(ForgeDesignTokens.TypeRole.title.compactSize),
            weight: .semibold
        )
        public static let headline = ForgeFont.sans(
            CGFloat(ForgeDesignTokens.TypeRole.headline.compactSize),
            weight: .semibold
        )
        public static let body = ForgeFont.sans(
            CGFloat(ForgeDesignTokens.TypeRole.body.compactSize),
            weight: .regular
        )
        public static let caption = ForgeFont.sans(
            CGFloat(ForgeDesignTokens.TypeRole.caption.compactSize),
            weight: .medium
        )
        public static let metric = ForgeFont.sans(
            CGFloat(ForgeDesignTokens.TypeRole.metric.compactSize),
            weight: .semibold
        ).monospacedDigit()
        public static let micro = ForgeFont.sans(9, weight: .medium)
    }

    /// Legacy size helpers — prefer the named roles above. Fixed size, like
    /// the `.system(size:)` calls they stood in for.
    public static func title(_ size: CGFloat = 28) -> Font {
        ForgeFont.sans(size, weight: .semibold)
    }

    public static func body(_ size: CGFloat = 15) -> Font {
        ForgeFont.sans(size, weight: .regular)
    }

    public static func caption(_ size: CGFloat = 12) -> Font {
        ForgeFont.sans(size, weight: .medium)
    }

    public static func metric(_ size: CGFloat = 32) -> Font {
        ForgeFont.sans(size, weight: .semibold).monospacedDigit()
    }

    /// Large serif headline at a fixed size (hero copy, empty states).
    public static func serif(_ size: CGFloat = 32, italic: Bool = false) -> Font {
        ForgeFont.serif(size, italic: italic)
    }
}
