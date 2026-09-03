import SwiftUI

// MARK: - Forge Design System (FDS)

enum FDS {
    
    // MARK: - Spacing
    
    enum Spacing {
        static let xs:  CGFloat = 4
        static let sm:  CGFloat = 8
        static let md:  CGFloat = 12
        static let lg:  CGFloat = 16
        static let xl:  CGFloat = 24
        static let xxl: CGFloat = 32
    }
    
    // MARK: - Radius
    
    enum Radius {
        static let xs:   CGFloat = 6
        static let sm:   CGFloat = 10
        static let md:   CGFloat = 14
        static let lg:   CGFloat = 18
        static let xl:   CGFloat = 22
        static let xxl:  CGFloat = 28
        static let pill: CGFloat = 999
    }

    // MARK: - Type

    enum TypeScale {
        static func display(_ size: CGFloat = 32) -> Font {
            .system(size: size, weight: .semibold, design: .rounded)
        }
        static func title(_ size: CGFloat = 22) -> Font {
            .system(size: size, weight: .semibold, design: .rounded)
        }
        static func body(_ size: CGFloat = 15) -> Font {
            .system(size: size, weight: .regular, design: .default)
        }
        static func label(_ size: CGFloat = 12) -> Font {
            .system(size: size, weight: .semibold, design: .rounded)
        }
        static func micro(_ size: CGFloat = 10) -> Font {
            .system(size: size, weight: .semibold, design: .rounded)
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
        static let snap     = Animation.spring(response: 0.25, dampingFraction: 0.75)
        static let standard = Animation.spring(response: 0.35, dampingFraction: 0.75)
        static let hero     = Animation.spring(response: 0.45, dampingFraction: 0.70)
        static let floaty   = Animation.spring(response: 0.55, dampingFraction: 0.65)
        static let page     = Animation.spring(response: 0.40, dampingFraction: 0.80)
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

// MARK: - PulsingRingView

struct PulsingRingView: View {
    let index: Int
    let color: Color
    let isAnimating: Bool
    
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 0.6
    
    var body: some View {
        Circle()
            .stroke(color.opacity(opacity), lineWidth: 2)
            .frame(width: 140, height: 140)
            .scaleEffect(scale)
            .onAppear {
                guard isAnimating else { return }
                let baseDelay = Double(index) * 0.4
                
                withAnimation(
                    .easeOut(duration: 2.0)
                    .repeatForever(autoreverses: false)
                    .delay(baseDelay)
                ) {
                    scale = 2.2
                    opacity = 0.0
                }
            }
            .onChange(of: isAnimating) { _, newValue in
                if newValue {
                    scale = 1.0
                    opacity = 0.6
                    let baseDelay = Double(index) * 0.4
                    
                    withAnimation(
                        .easeOut(duration: 2.0)
                        .repeatForever(autoreverses: false)
                        .delay(baseDelay)
                    ) {
                        scale = 2.2
                        opacity = 0.0
                    }
                } else {
                    scale = 1.0
                    opacity = 0.6
                }
            }
    }
}
