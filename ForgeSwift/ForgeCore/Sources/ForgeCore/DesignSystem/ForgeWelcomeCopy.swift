import Foundation

/// Welcome / launch taglines. **Switch the live line by changing `activeIndex` only.**
///
/// Lockstep with `shared/forge-welcome.json`. Alternates stay compiled so a
/// swap is one integer, not a hunt through splash and onboarding call sites.
public enum ForgeWelcomeCopy: Sendable {
    /// 0 primary · 1 heat · 2 work. The only switch.
    public static let activeIndex = 0

    public static let primary = "Forged, not promised. The rest is you."
    public static let heat = "We bring the heat. You do the shaping."
    public static let work = "Stronger than you came in, if you put in the work."

    public static let all: [String] = [primary, heat, work]

    public static var tagline: String { all[activeIndex] }

    /// VoiceOver name for the procedural hammer-and-flame mark.
    public static let markLabel = "Forge mark, a hammer striking a flame"

    public static let firstPageId = "brand"
    public static let firstPageKicker = "Forge"
    public static let firstPageBody = "A calm place to train and live. The work is still yours."
}
