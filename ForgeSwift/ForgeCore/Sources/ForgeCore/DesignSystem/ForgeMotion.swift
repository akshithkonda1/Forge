import SwiftUI
#if os(iOS)
import UIKit
#elseif os(watchOS)
import WatchKit
#endif

// MARK: - Motion
//
// Three springs and one sweep. Motion answers an event (a tap, a log, new
// data) and settles; nothing loops while the screen is idle. Under Reduce
// Motion nothing travels: springs become a short crossfade and moving
// transitions become opacity.

public enum ForgeMotion {
    private typealias Token = ForgeDesignTokens.Motion

    /// Taps, toggles, chips, press states.
    public static let snappy = Animation.spring(response: Token.snappyResponse, dampingFraction: Token.snappyDamping)
    /// Cards expanding, content swapping, sheets and page changes.
    public static let smooth = Animation.spring(response: Token.smoothResponse, dampingFraction: Token.smoothDamping)
    /// Arrivals: a banner, a result, a hero settling in.
    public static let gentle = Animation.spring(response: Token.gentleResponse, dampingFraction: Token.gentleDamping)
    /// Ring and progress fills: the arc length is the data, so it eases out once.
    public static let sweep = Animation.easeOut(duration: Token.sweepSeconds)
    /// What every animation becomes under Reduce Motion.
    public static let crossfade = Animation.easeInOut(duration: 0.2)
    /// Decorative TimelineView ceiling. Brand nest may sit on this value;
    /// looping chrome must not exceed it.
    public static let maxTickHz: Double = Token.maxTickHz
    public static let maxTickInterval: Double = 1.0 / maxTickHz

    /// Pause a decorative TimelineView when Reduce Motion is on, the scene
    /// is inactive, or the view is off-screen. No always-on clocks.
    public static func isDecorativeClockPaused(
        reduceMotion: Bool,
        sceneActive: Bool,
        onscreen: Bool
    ) -> Bool {
        reduceMotion || !sceneActive || !onscreen
    }

    /// Staggered sweep for a row of dials.
    public static func sweep(staggeredBy index: Int) -> Animation {
        sweep.delay(0.08 * Double(index))
    }

    /// `animation`, or the crossfade when Reduce Motion is on.
    public static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? crossfade : animation
    }

    /// The system Reduce Motion setting, for code outside a view body.
    /// Views should read `@Environment(\.accessibilityReduceMotion)`.
    @MainActor
    public static var isReduced: Bool {
        #if os(iOS)
        return UIAccessibility.isReduceMotionEnabled
        #elseif os(watchOS)
        return WKAccessibilityIsReduceMotionEnabled()
        #else
        return false
        #endif
    }
}

/// `withAnimation` that honours Reduce Motion.
@MainActor
@discardableResult
public func withForgeMotion<Result>(
    _ animation: Animation = ForgeMotion.smooth,
    _ body: () throws -> Result
) rethrows -> Result {
    try withAnimation(ForgeMotion.resolved(animation, reduceMotion: ForgeMotion.isReduced), body)
}

public extension View {
    /// `.animation(_:value:)` that honours Reduce Motion.
    func forgeAnimation<V: Equatable>(_ animation: Animation = ForgeMotion.smooth, value: V) -> some View {
        modifier(ForgeAnimationModifier(animation: animation, value: value))
    }

    /// `.transition(_:)` that falls back to opacity under Reduce Motion.
    func forgeTransition(_ transition: AnyTransition) -> some View {
        modifier(ForgeTransitionModifier(transition: transition))
    }
}

private struct ForgeAnimationModifier<V: Equatable>: ViewModifier {
    let animation: Animation
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(ForgeMotion.resolved(animation, reduceMotion: reduceMotion), value: value)
    }
}

private struct ForgeTransitionModifier: ViewModifier {
    let transition: AnyTransition
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transition(reduceMotion ? .opacity : transition)
    }
}
