import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Color Design Tokens (premium dark system)

extension Color {
    // Backgrounds — deeper, more cinematic blacks
    static let background      = Color(hex: "08080C")
    static let surface         = Color(hex: "101014")
    static let surfaceElevated = Color(hex: "17171C")
    static let surfaceHover    = Color(hex: "1C1C22")
    static let cardBackground  = Color(hex: "0E0E10")
    static let surfaceGlass    = Color.white.opacity(0.04)

    // Borders — hairline luminance
    static let borderColor = Color(hex: "2A2A32")
    static let borderLight = Color(hex: "3A3A44")
    static let borderHairline = Color.white.opacity(0.08)
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

extension LinearGradient {
    static var emberGradient: LinearGradient {
        LinearGradient(
            colors: [.emberLight, .ember, .emberDark],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var sleepRing: LinearGradient {
        LinearGradient(
            colors: [.steel, .steelLight, .aurora.opacity(0.8)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var premiumSurface: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.07),
                Color.white.opacity(0.02),
                Color.clear
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var premiumChrome: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.12),
                Color.white.opacity(0.04),
                Color.clear
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

extension RadialGradient {
    static func ambientGlow(_ color: Color, opacity: Double = 0.18) -> RadialGradient {
        RadialGradient(
            colors: [color.opacity(opacity), color.opacity(opacity * 0.35), .clear],
            center: .center,
            startRadius: 4,
            endRadius: 180
        )
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
    var accent: Color? = nil

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: FDS.Radius.xl, style: .continuous)
                        .fill(elevated ? Color.surfaceElevated : Color.surface)
                    RoundedRectangle(cornerRadius: FDS.Radius.xl, style: .continuous)
                        .fill(LinearGradient.premiumSurface)
                    if let accent {
                        RoundedRectangle(cornerRadius: FDS.Radius.xl, style: .continuous)
                            .fill(
                                RadialGradient(
                                    colors: [accent.opacity(0.12), .clear],
                                    center: .topLeading,
                                    startRadius: 10,
                                    endRadius: 220
                                )
                            )
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.xl, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: FDS.Radius.xl, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.12),
                                Color.white.opacity(0.04),
                                (accent ?? Color.white).opacity(0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .forgeCardShadow()
    }
}

extension View {
    func forgeCard(elevated: Bool = false, accent: Color? = nil) -> some View {
        modifier(ForgeCardModifier(elevated: elevated, accent: accent))
    }

    /// Screen chrome: deep black + subtle ambient gradient.
    func forgeScreenBackground(accent: Color = .ember) -> some View {
        background {
            ZStack {
                Color.background.ignoresSafeArea()
                RadialGradient(
                    colors: [accent.opacity(0.05), .clear],
                    center: UnitPoint(x: 0.2, y: 0.0),
                    startRadius: 10,
                    endRadius: 360
                )
                .ignoresSafeArea()
            }
        }
    }
}
