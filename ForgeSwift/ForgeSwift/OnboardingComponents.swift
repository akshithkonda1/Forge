import SwiftUI

/// The onboarding atmosphere: the brand moment, tinted per interview beat.
/// Static at rest; `PremiumAtmosphere` owns the Color.background layer, so
/// callers do not stack a second one under it.
struct ForgeAmbientBackground: View {
    /// `AriaInterviewStep.rawValue`. `AriaForgePrepView` passes 3, which maps
    /// to the ember route.
    let step: Int

    var body: some View {
        PremiumAtmosphere(
            accent: routeColor,
            secondary: Color(hex: "A9D8FF"),
            intensity: 0.8
        )
    }

    /// Domain accent per beat: aurora to meet, steel for Health, vitality for
    /// the habit beats, ember for tone and the first chat.
    private var routeColor: Color {
        guard let beat = AriaInterviewStep(rawValue: step) else { return .ember }
        switch beat {
        case .intro, .name:
            return Color.aurora
        case .health:
            return Color.steel
        case .goals, .experience, .workouts, .schedule, .sleep, .freeTime:
            return Color.vitality
        case .details, .coaching, .conditions, .ready:
            return Color.ember
        }
    }
}

/// Wrapping row layout. Subviews are measured against the container width so
/// a chip wider than the row wraps its text instead of overflowing.
struct OnboardingFlowLayout: Layout {
    var spacing: CGFloat = 8

    private func measure(_ subview: LayoutSubview, maxWidth: CGFloat) -> CGSize {
        subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        for sub in subviews {
            let size = measure(sub, maxWidth: maxWidth)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowH + spacing
                rowH = 0
            }
            rowH = max(rowH, size.height)
            x += size.width + spacing
        }
        return CGSize(width: maxWidth, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowH: CGFloat = 0
        for sub in subviews {
            let size = measure(sub, maxWidth: bounds.width)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowH + spacing
                rowH = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            rowH = max(rowH, size.height)
            x += size.width + spacing
        }
    }
}
