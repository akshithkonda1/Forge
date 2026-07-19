import SwiftUI

// MARK: - Forge Design System tokens (shared iOS + watchOS)
//
// Ported from ForgeSwift/ForgeDesignSystem.swift (`FDS`). Named `ForgeDS`
// so the iOS app can adopt it incrementally without clashing with its
// internal `FDS` enum. Haptics are intentionally NOT here — they are
// platform-specific (UIKit generators vs WKInterfaceDevice) and live in
// each app target.

public enum ForgeDS {

    public enum Spacing {
        public static let xs:  CGFloat = 4
        public static let sm:  CGFloat = 8
        public static let md:  CGFloat = 12
        public static let lg:  CGFloat = 16
        public static let xl:  CGFloat = 24
        public static let xxl: CGFloat = 32
    }

    public enum Radius {
        public static let xs:   CGFloat = 4
        public static let sm:   CGFloat = 8
        public static let md:   CGFloat = 12
        public static let lg:   CGFloat = 16
        public static let xl:   CGFloat = 20
        public static let pill: CGFloat = 999
    }

    public enum Duration {
        public static let snap:     Double = 0.15
        public static let fast:     Double = 0.25
        public static let standard: Double = 0.35
        public static let slow:     Double = 0.5
        public static let breathe:  Double = 3.0
        public static let ambient:  Double = 20.0
    }

    public enum Spring {
        public static let snap     = Animation.spring(response: 0.25, dampingFraction: 0.75)
        public static let standard = Animation.spring(response: 0.35, dampingFraction: 0.75)
        public static let hero     = Animation.spring(response: 0.45, dampingFraction: 0.70)
        public static let floaty   = Animation.spring(response: 0.55, dampingFraction: 0.65)
        public static let page     = Animation.spring(response: 0.40, dampingFraction: 0.80)
    }
}

// MARK: - Typography (mirrors ForgeTypography on iOS, sized for both screens)

public enum ForgeType {
    public static func title(_ size: CGFloat = 28) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }

    public static func body(_ size: CGFloat = 15.5) -> Font {
        .system(size: size, weight: .regular)
    }

    public static func caption(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .medium)
    }

    public static func metric(_ size: CGFloat = 32) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
}
