import SwiftUI
import UIKit

// MARK: - Workout view helpers (extracted from WorkoutView.swift)

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

extension UIImage {
    func downscaledJPEG(maxDimension: CGFloat, quality: CGFloat) -> Data? {
        let longest = max(size.width, size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: quality)
    }
}

// MARK: - Corner Radius Helper

extension View {
    func roundedCorners(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(WorkoutRoundedCorner(radius: radius, corners: corners))
    }
}

struct WorkoutRoundedCorner: Shape {
    let radius: CGFloat; let corners: UIRectCorner
    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius)).cgPath)
    }
}

// MARK: - Comparable clamp

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
