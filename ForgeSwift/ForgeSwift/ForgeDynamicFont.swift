import SwiftUI
import UIKit

// MARK: - Dynamic Type support for fixed-size fonts
//
// The scorecard's top inclusivity finding: none of the ~850
// `.font(.system(size:))` call sites across the app's four largest
// views respond to the user's Dynamic Type text-size setting at all —
// `.system(size:)` is a fixed point size by design and never scales.
//
// `Font.forgeDynamic` is a drop-in replacement with the same
// (size, weight, design) signature that instead wraps a `UIFont` in
// `UIFontMetrics`, Apple's documented mechanism for giving a custom
// fixed-size font real Dynamic Type behavior. At the default ("Large")
// content size category it renders at *exactly* the size passed in —
// so swapping `.system(size:weight:design:)` for `.forgeDynamic(size:
// weight:design:)` is visually a no-op today, and only changes what
// happens when the user turns on a larger or an Accessibility text size.
extension Font {
    static func forgeDynamic(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> Font {
        var uiFont = UIFont.systemFont(ofSize: size, weight: weight.uiKitWeight)
        if design != .default, let descriptor = uiFont.fontDescriptor.withDesign(design.uiKitDesign) {
            uiFont = UIFont(descriptor: descriptor, size: size)
        }
        return Font(UIFontMetrics.default.scaledFont(for: uiFont))
    }
}

private extension Font.Weight {
    var uiKitWeight: UIFont.Weight {
        switch self {
        case .black:     return .black
        case .heavy:     return .heavy
        case .bold:      return .bold
        case .semibold:  return .semibold
        case .medium:    return .medium
        case .regular:   return .regular
        case .light:     return .light
        case .thin:      return .thin
        case .ultraLight: return .ultraLight
        default:         return .regular
        }
    }
}

private extension Font.Design {
    var uiKitDesign: UIFontDescriptor.SystemDesign {
        switch self {
        case .rounded:     return .rounded
        case .serif:       return .serif
        case .monospaced:  return .monospaced
        default:           return .default
        }
    }
}
