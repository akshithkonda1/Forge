import SwiftUI
import ForgeCore

// MARK: - Forge Design System (FDS)
//
// App-side alias of `ForgeDS` / `shared/design-tokens.json`. Home is the look.

enum FDS {
    
    // MARK: - Spacing
    
    enum Spacing {
        static let xs:  CGFloat = ForgeDS.Spacing.xs
        static let sm:  CGFloat = ForgeDS.Spacing.sm
        static let md:  CGFloat = ForgeDS.Spacing.md
        static let lg:  CGFloat = ForgeDS.Spacing.lg
        static let xl:  CGFloat = ForgeDS.Spacing.xl
        static let xxl: CGFloat = ForgeDS.Spacing.xxl
    }
    
    // MARK: - Radius
    
    enum Radius {
        static let xs:   CGFloat = ForgeDS.Radius.xs
        static let sm:   CGFloat = ForgeDS.Radius.sm
        static let md:   CGFloat = ForgeDS.Radius.md
        static let lg:   CGFloat = ForgeDS.Radius.lg
        static let xl:   CGFloat = ForgeDS.Radius.xl
        static let xxl:  CGFloat = ForgeDS.Radius.xxl
        static let pill: CGFloat = ForgeDS.Radius.pill
    }

    // MARK: - Type

    enum TypeScale {
        static let display = ForgeType.display
        static let title = ForgeType.title
        static let headline = ForgeType.headline
        static let body = ForgeType.body
        static let caption = ForgeType.caption
        static let metric = ForgeType.metric
        static let pageTitle = ForgeType.pageTitle
        static let heroScore = ForgeType.heroScore
        static let micro = ForgeType.micro

        /// Legacy size helpers — prefer the named roles.
        static func pageTitle(_ size: CGFloat = 34) -> Font {
            ForgeType.title(size)
        }
        static func display(_ size: CGFloat = 32) -> Font {
            ForgeType.title(size)
        }
        static func title(_ size: CGFloat = 22) -> Font {
            ForgeType.title(size)
        }
        static func body(_ size: CGFloat = 15) -> Font {
            ForgeType.body(size)
        }
        static func label(_ size: CGFloat = 12) -> Font {
            ForgeType.caption(size)
        }
        static func micro(_ size: CGFloat = 10) -> Font {
            ForgeType.caption(size)
        }

        /// Dynamic Type–aware tokens. Same named scale as `ForgeType`.
        enum Dynamic {
            static let pageTitle = ForgeType.pageTitle
            static let display = ForgeType.display
            static let title = ForgeType.title
            static let headline = ForgeType.headline
            static let body = ForgeType.body
            static let label = ForgeType.caption
            static let micro = ForgeType.micro
            static let metric = ForgeType.metric
            static let heroScore = ForgeType.heroScore
            static let caption = ForgeType.caption
        }
    }
    
    // MARK: - Duration
    
    enum Duration {
        static let snap:    Double = 0.15
        static let fast:    Double = 0.25
        static let standard: Double = 0.35
        static let slow:    Double = 0.5
        static let breathe: Double = 3.0
        static let ambient: Double = 20.0
    }
    
    // MARK: - Spring Animations

    enum Spring {
        static let snap     = Animation.spring(SwiftUI.Spring(response: 0.25, dampingRatio: 0.75))
        static let standard = Animation.spring(SwiftUI.Spring(response: 0.35, dampingRatio: 0.75))
        static let hero     = Animation.spring(SwiftUI.Spring(response: 0.45, dampingRatio: 0.70))
        static let floaty   = Animation.spring(SwiftUI.Spring(response: 0.55, dampingRatio: 0.65))
        static let page     = Animation.spring(SwiftUI.Spring(response: 0.40, dampingRatio: 0.80))
        /// Slow inhale — used for ARIA reveals and orb breath.
        static let fluid    = Animation.spring(SwiftUI.Spring(response: 0.82, dampingRatio: 0.78))
        /// Whoop-style score fill: 1.2s ease-out. Apple rings use the same 12-o'clock start.
        static let sweep    = Animation.easeOut(duration: 1.2)
        /// Oura progressive stagger between glanceable score dials.
        static func sweepDelay(_ index: Int) -> Animation {
            sweep.delay(0.08 * Double(index))
        }
    }
    
    // MARK: - Gradients
    
    enum Gradient {
        static let ember = LinearGradient(
            colors: [Color.emberLight, Color.ember, Color.emberDark],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        static let emberDeep = LinearGradient(
            colors: [Color(hex: "FF6B2B"), Color(hex: "FF4D00"), Color(hex: "C43A00")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        static let steel = LinearGradient(
            colors: [Color.steelLight, Color.steel, Color.steelDark],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        static let aurora = LinearGradient(
            colors: [Color.ember.opacity(0.9), Color.aurora, Color.steel.opacity(0.85)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        static let chrome = LinearGradient(
            colors: [Color.white.opacity(0.14), Color.white.opacity(0.04), Color.clear],
            startPoint: .top,
            endPoint: .bottom
        )

        static let neon = LinearGradient(
            colors: [Color(hex: "00D2FF"), Color(hex: "7B61FF"), Color(hex: "FF2D55")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        static let glass = LinearGradient(
            colors: [Color.white.opacity(0.12), Color.white.opacity(0.02)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    // MARK: - Haptics
    
    static func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
    
    static func selectionHaptic() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
    
    static func notificationHaptic(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }

    /// One haptic table: select, press, primary CTA, success, error, destructive.
    static func haptic(_ event: ForgeDesignTokens.Haptic) {
        switch event {
        case .select: selectionHaptic()
        case .press: haptic(.light)
        case .primaryCTA: haptic(.medium)
        case .success: notificationHaptic(.success)
        case .error: notificationHaptic(.error)
        case .destructive: notificationHaptic(.warning)
        }
    }
    
    // MARK: - Accessibility Adaptive Animation
    
    static func adaptiveAnimation(_ animation: Animation) -> Animation {
        if UIAccessibility.isReduceMotionEnabled {
            return .linear(duration: 0.2)
        }
        return animation
    }
}

// MARK: - View Modifiers

// ForgePress - adds press animation effect
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

// ForgeEntrance - staggered entrance animation
struct ForgeEntranceModifier: ViewModifier {
    let index: Int
    let appeared: Bool
    
    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
            .animation(
                FDS.Spring.hero.delay(Double(index) * 0.06),
                value: appeared
            )
    }
}

extension View {
    func forgeEntrance(index: Int, appeared: Bool) -> some View {
        modifier(ForgeEntranceModifier(index: index, appeared: appeared))
    }
}
