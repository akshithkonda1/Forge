import SwiftUI

struct ForgeAmbientBackground: View {
    let step: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.background, Color(hex: "140A06").opacity(0.78), Color.background],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [routeColor.opacity(0.16), routeColor.opacity(0.04), .clear],
                center: UnitPoint(x: 0.32, y: 0.18),
                startRadius: 10,
                endRadius: 420
            )
            .blur(radius: reduceMotion ? 0 : 22)

            if !reduceMotion {
                // Static wash — an infinite phase loop was rasterizing two
                // full-screen blurs for the entire interview.
                RadialGradient(
                    colors: [Color.ember.opacity(0.08), .clear],
                    center: UnitPoint(x: 0.72, y: 0.52),
                    startRadius: 0,
                    endRadius: 280
                )
                .blur(radius: 24)
            }
        }
    }

    private var routeColor: Color {
        switch step {
        case 0, 1: return Color.aurora
        case 2: return Color.steel
        case 3: return Color.ember
        case 7, 8: return Color.vitality
        default: return .ember
        }
    }
}

struct OnboardingFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
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
            let size = sub.sizeThatFits(.unspecified)
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
