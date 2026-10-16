import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Color Design Tokens (premium dark system)

extension Color {
    // Backgrounds — flat, neutral near-blacks (no blue cast, no washes).
    // Depth comes from one step of surface lightness plus a hairline.
    static let background      = Color(hex: "09090B")
    static let surface         = Color(hex: "111113")
    static let surfaceElevated = Color(hex: "18181B")
    static let surfaceHover    = Color(hex: "1F1F23")
    static let cardBackground  = Color(hex: "0F0F11")
    static let surfaceGlass    = Color.white.opacity(0.04)

    // Borders — hairline luminance
    static let borderColor = Color(hex: "2A2A32")
    static let borderLight = Color(hex: "3A3A44")
    static let borderHairline = Color.white.opacity(0.08)
    /// The one separator: a 0.5–1 pt line at this opacity.
    static let forgeSeparator = Color.white.opacity(0.07)
    static let borderEmber = Color.ember.opacity(0.35)

    // Ember (primary brand energy)
    static let ember      = Color(hex: "FF4D00")
    static let emberLight = Color(hex: "FF7A3D")
    static let emberDark  = Color(hex: "C43A00")
    static let emberSoft  = Color(hex: "FF4D00").opacity(0.14)

    // Steel (secondary / focus / recovery)
    static let steel      = Color(hex: "5B8DEF")
    static let steelLight = Color(hex: "7BA6F7")
    static let steelDark  = Color(hex: "3D6FD4")
    /// Miss / rest chrome — steel, never alert red. Lockstep with `missHex`.
    static let miss       = Color(hex: "7BA6F7")

    // Violet accent (ARIA / intelligence)
    static let aurora = Color(hex: "A78BFA")

    // Vitality green. Distinct from `success` (34D399): this is the de-facto
    // brand green already used ~15 times across Home for lifestyle, peak
    // readiness and positive-state chips. Tokenised so those stop being literals.
    static let vitality = Color(hex: "22C55E")

    // Indigo, for partner / support surfaces.
    static let indigo = Color(hex: "6366F1")

    // Amber, for nutrition and fuel accents.
    static let amber = Color(hex: "FFB84D")

    // Alert red used by the readiness ramp. Slightly hotter than `danger`
    // (F87171), which stays reserved for genuine error states.
    static let alert = Color(hex: "EF4444")

    // Text
    /// Warm white — brand wordmark, primary-on-dark button fill.
    static let paper = Color(hex: "F7F4F0")
    static let textPrimary   = Color(hex: "FAFAFA")
    static let textSecondary = Color(hex: "A1A1AA")
    static let textTertiary  = Color(hex: "71717A")
    static let textMuted     = Color(hex: "52525B")

    // Status
    static let success = Color(hex: "34D399")
    static let warning = Color(hex: "FBBF24")
    static let danger  = Color(hex: "F87171")

    // Hex initializer
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:  (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 255, 255, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    /// Round-trip partner to `init(hex:)` — lets colors ride along in `Codable` models.
    /// Falls back to steel-grey for colors UIKit can't resolve to RGB (e.g. some
    /// dynamic system colors), so persistence never loses a card.
    var forgeHexString: String {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return "8A94A6" }
        return String(
            format: "%02X%02X%02X",
            Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded())
        )
        #else
        return "8A94A6"
        #endif
    }
}

// MARK: - Gradient helpers
//
// Premium refresh: decorative gradients are retired. These helpers keep their
// names and types so call sites compile unchanged, but each now resolves to a
// flat fill (or nothing). Gradients that encode data (sleep stages, HR zones,
// trend fills) are drawn locally by their charts and are untouched.

extension LinearGradient {
    /// A "gradient" of one color — a flat fill that still type-checks as
    /// `LinearGradient` wherever a gradient used to be passed.
    static func flat(_ color: Color) -> LinearGradient {
        LinearGradient(colors: [color, color], startPoint: .top, endPoint: .bottom)
    }

    static var emberGradient: LinearGradient {
        .flat(.ember)
    }

    static var sleepRing: LinearGradient {
        .flat(.steel)
    }

    static var premiumSurface: LinearGradient {
        .flat(.clear)
    }

    static var premiumChrome: LinearGradient {
        .flat(.clear)
    }
}

extension RadialGradient {
    /// Retired ambient glow. Kept so callers compile; draws nothing.
    static func ambientGlow(_ color: Color, opacity: Double = 0.18) -> RadialGradient {
        RadialGradient(colors: [.clear, .clear], center: .center, startRadius: 0, endRadius: 1)
    }
}

// MARK: - HR Zone helper

struct HRZone {
    let zone: Int
    let label: String
    let color: Color
}

func hrZone(for bpm: Int) -> HRZone {
    if bpm < 110 { return HRZone(zone: 1, label: "Zone 1", color: .textTertiary) }
    if bpm < 130 { return HRZone(zone: 2, label: "Zone 2", color: .steel) }
    if bpm < 150 { return HRZone(zone: 3, label: "Zone 3", color: .success) }
    if bpm < 165 { return HRZone(zone: 4, label: "Zone 4", color: .ember) }
    return HRZone(zone: 5, label: "Zone 5", color: .danger)
}

// MARK: - View Modifiers (global premium cards)

struct ForgeCardModifier: ViewModifier {
    var elevated: Bool = false
    /// Accent no longer tints the card (no washes, no halos). Kept for API.
    var accent: Color? = nil

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: FDS.Radius.xl, style: .continuous)
                    .fill(elevated ? Color.surfaceElevated : Color.surface)
            }
            .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.xl, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: FDS.Radius.xl, style: .continuous)
                    .strokeBorder(Color.borderHairline, lineWidth: ForgeUX.hairline)
            }
    }
}

extension View {
    func forgeCard(elevated: Bool = false, accent: Color? = nil) -> some View {
        modifier(ForgeCardModifier(elevated: elevated, accent: accent))
    }

    /// Screen chrome: one flat near-black field. The accent parameter is kept
    /// for API compatibility; screens no longer carry colored washes.
    func forgeScreenBackground(accent: Color = .ember) -> some View {
        background {
            Color.background.ignoresSafeArea()
        }
    }
}
