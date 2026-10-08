import SwiftUI

// MARK: - Forge Design System tokens (shared iOS + watchOS)
//
// Lockstep with `shared/design-tokens.json` via `ForgeDesignTokens`.
// Named `ForgeDS` so the iOS app can alias `FDS` without a clash.
// Haptics stay in each app target (UIKit vs WKInterfaceDevice).

public enum ForgeDS {

    public enum Spacing {
        public static let xs:  CGFloat = CGFloat(ForgeDesignTokens.Spacing.xs)
        public static let sm:  CGFloat = CGFloat(ForgeDesignTokens.Spacing.sm)
        public static let md:  CGFloat = CGFloat(ForgeDesignTokens.Spacing.md)
        public static let lg:  CGFloat = CGFloat(ForgeDesignTokens.Spacing.lg)
        public static let xl:  CGFloat = CGFloat(ForgeDesignTokens.Spacing.xl)
        public static let xxl: CGFloat = CGFloat(ForgeDesignTokens.Spacing.xxl)
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

    public enum Duration {
        public static let snap:     Double = ForgeDesignTokens.Motion.snapResponse
        public static let fast:     Double = 0.25
        public static let standard: Double = ForgeDesignTokens.Motion.standardResponse
        public static let slow:     Double = 0.5
        public static let breathe:  Double = 3.0
        public static let ambient:  Double = 20.0
        public static let sweep:    Double = ForgeDesignTokens.Motion.sweepSeconds
    }

    public enum Spring {
        public static let snap     = Animation.spring(
            response: ForgeDesignTokens.Motion.snapResponse,
            dampingFraction: ForgeDesignTokens.Motion.snapDamping
        )
        public static let standard = Animation.spring(
            response: ForgeDesignTokens.Motion.standardResponse,
            dampingFraction: ForgeDesignTokens.Motion.standardDamping
        )
        public static let hero     = Animation.spring(
            response: ForgeDesignTokens.Motion.heroResponse,
            dampingFraction: ForgeDesignTokens.Motion.heroDamping
        )
        public static let floaty   = Animation.spring(response: 0.55, dampingFraction: 0.65)
        public static let page     = Animation.spring(
            response: ForgeDesignTokens.Motion.pageResponse,
            dampingFraction: ForgeDesignTokens.Motion.pageDamping
        )
        public static let sweep    = Animation.easeOut(duration: ForgeDesignTokens.Motion.sweepSeconds)
    }

    public static let minTap: CGFloat = CGFloat(ForgeDesignTokens.UX.minTap)
    public static let iconSize: CGFloat = CGFloat(ForgeDesignTokens.UX.iconSize)
    public static let safeInset: CGFloat = CGFloat(ForgeDesignTokens.UX.safeInset)
}

// MARK: - Named type scale
//
// One system: display / title / headline / body / caption / metric.
// Phone uses Dynamic Type. Watch / widgets use Compact (same names).
// Metrics always use tabular / monospaced digits.

public enum ForgeType {
    public static let display = Font.system(.title2, design: .rounded).weight(.semibold)
    public static let title = Font.system(.title3, design: .rounded).weight(.semibold)
    public static let headline = Font.system(.headline, design: .rounded).weight(.semibold)
    public static let body = Font.subheadline
    public static let caption = Font.system(.caption, design: .rounded).weight(.semibold)
    public static let metric = Font.system(.title3, design: .rounded).weight(.bold).monospacedDigit()
    public static let pageTitle = Font.system(.title, design: .rounded).weight(.semibold)
    public static let heroScore = Font.system(.largeTitle, design: .rounded).weight(.bold).monospacedDigit()
    public static let micro = Font.system(.caption2, design: .rounded).weight(.semibold)

    public static func tracking(_ role: ForgeDesignTokens.TypeRole) -> CGFloat {
        CGFloat(role.tracking)
    }

    public static var eyebrowTracking: CGFloat {
        CGFloat(ForgeDesignTokens.eyebrowTracking)
    }

    /// Watch / widget / complication sizes — same role names, smaller canvas.
    public enum Compact {
        public static let display = Font.system(
            size: CGFloat(ForgeDesignTokens.TypeRole.display.compactSize),
            weight: .semibold,
            design: .rounded
        )
        public static let title = Font.system(
            size: CGFloat(ForgeDesignTokens.TypeRole.title.compactSize),
            weight: .semibold,
            design: .rounded
        )
        public static let headline = Font.system(
            size: CGFloat(ForgeDesignTokens.TypeRole.headline.compactSize),
            weight: .semibold,
            design: .rounded
        )
        public static let body = Font.system(
            size: CGFloat(ForgeDesignTokens.TypeRole.body.compactSize),
            weight: .regular
        )
        public static let caption = Font.system(
            size: CGFloat(ForgeDesignTokens.TypeRole.caption.compactSize),
            weight: .semibold,
            design: .rounded
        )
        public static let metric = Font.system(
            size: CGFloat(ForgeDesignTokens.TypeRole.metric.compactSize),
            weight: .bold,
            design: .rounded
        ).monospacedDigit()
        public static let micro = Font.system(size: 9, weight: .semibold, design: .rounded)
    }

    /// Legacy size helpers — prefer the named roles above.
    public static func title(_ size: CGFloat = 28) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }

    public static func body(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .regular)
    }

    public static func caption(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }

    public static func metric(_ size: CGFloat = 32) -> Font {
        .system(size: size, weight: .bold, design: .rounded).monospacedDigit()
    }
}
