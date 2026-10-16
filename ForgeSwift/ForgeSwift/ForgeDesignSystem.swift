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
        static let xxxl: CGFloat = ForgeDS.Spacing.xxxl
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
    
    // MARK: - Gradients
    //
    // Retired for the premium refresh: each name now resolves to a flat fill
    // (one accent, no sheen) so existing call sites keep compiling.

    enum Gradient {
        static let ember = LinearGradient.flat(Color.ember)
        static let emberDeep = LinearGradient.flat(Color.ember)
        static let steel = LinearGradient.flat(Color.steel)
        static let aurora = LinearGradient.flat(Color.ember)
        static let chrome = LinearGradient.flat(Color.clear)
        static let neon = LinearGradient.flat(Color.ember)
        static let glass = LinearGradient.flat(Color.clear)
    }
}

// MARK: - View Modifiers

// ForgePress - adds press animation effect
struct ForgePressModifier: ViewModifier {
    @State private var pressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(pressed && !reduceMotion ? 0.98 : 1.0)
            .animation(reduceMotion ? nil : ForgeMotion.snappy, value: pressed)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    func body(content: Content) -> some View {
        content
            .opacity(appeared || reduceMotion ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : HomeMetrics.entranceRise)
            .animation(
                reduceMotion ? nil : ForgeMotion.gentle.delay(Double(index) * 0.06),
                value: appeared
            )
    }
}

extension View {
    func forgeEntrance(index: Int, appeared: Bool) -> some View {
        modifier(ForgeEntranceModifier(index: index, appeared: appeared))
    }
}
