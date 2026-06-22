import SwiftUI

// MARK: - Forge Design System (FDS)

enum FDS {

    enum Spacing {
        static let xs:  CGFloat = 4
        static let sm:  CGFloat = 8
        static let md:  CGFloat = 12
        static let lg:  CGFloat = 16
        static let xl:  CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let xs:   CGFloat = 4
        static let sm:   CGFloat = 8
        static let md:   CGFloat = 12
        static let lg:   CGFloat = 16
        static let xl:   CGFloat = 20
        static let pill: CGFloat = 999
    }

    enum Duration {
        static let snap:     Double = 0.15
        static let fast:     Double = 0.25
        static let standard: Double = 0.35
        static let slow:     Double = 0.5
        static let breathe:  Double = 3.0
        static let ambient:  Double = 20.0
    }

    enum Spring {
        static let snap     = Animation.spring(response: 0.25, dampingFraction: 0.75)
        static let standard = Animation.spring(response: 0.35, dampingFraction: 0.75)
        static let hero     = Animation.spring(response: 0.45, dampingFraction: 0.70)
        static let floaty   = Animation.spring(response: 0.55, dampingFraction: 0.65)
        static let page     = Animation.spring(response: 0.40, dampingFraction: 0.80)
    }

    enum Gradient {
        static let ember = LinearGradient(
            colors: [Color.ember, Color.emberLight],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        static let steel = LinearGradient(
            colors: [Color.steel, Color.steelLight],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func adaptiveAnimation(_ animation: Animation) -> Animation {
        if UIAccessibility.isReduceMotionEnabled {
            return .linear(duration: 0.2)
        }
        return animation
    }
}

struct ForgePressModifier: ViewModifier {
    @State private var pressed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(pressed ? 0.96 : 1.0)
            .animation(FDS.Spring.snap, value: pressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in pressed = true }
                    .onEnded { _ in pressed = false }
            )
    }
}

extension View {
    func forgePress() -> some View {
        modifier(ForgePressModifier())
    }
}