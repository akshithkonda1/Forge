import SwiftUI
import UIKit

extension View {
    func roundedCorners(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(WorkoutRoundedCorner(radius: radius, corners: corners))
    }

    /// Softens both ends of a horizontal scroller so a chip clipped by the screen
    /// edge reads as "keep scrolling" instead of a broken layout. Drawn as a
    /// non-interactive overlay so it never swallows a drag from the scroll view.
    func scrollEdgeFade(width: CGFloat = 22) -> some View {
        overlay(alignment: .leading) {
            LinearGradient(colors: [Color.background, Color.background.opacity(0)], startPoint: .leading, endPoint: .trailing)
                .frame(width: width)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .trailing) {
            LinearGradient(colors: [Color.background.opacity(0), Color.background], startPoint: .leading, endPoint: .trailing)
                .frame(width: width)
                .allowsHitTesting(false)
        }
    }
}

private struct WorkoutRoundedCorner: Shape {
    let radius: CGFloat; let corners: UIRectCorner
    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius)).cgPath)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
