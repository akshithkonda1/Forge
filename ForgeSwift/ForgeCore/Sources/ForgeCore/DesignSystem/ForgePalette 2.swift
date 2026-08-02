import SwiftUI

// MARK: - Forge Palette (shared iOS + watchOS)
//
// Ported from ForgeSwift/ColorExtensions.swift. The initializer is named
// `forgeHex` (not `hex`) so linking ForgeCore into the iOS app never
// collides with the app's existing `Color(hex:)` extension.
//
// Watch-specific guidance: the calm/restorative colors (steel, violet,
// jade, indigo) carry the mindfulness and recovery surfaces; ember is
// reserved for energy and genuinely high-alert states, never for guilt.

public extension Color {
    init(forgeHex hex: String) {
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
        self.init(.sRGB,
                  red: Double(r) / 255,
                  green: Double(g) / 255,
                  blue: Double(b) / 255,
                  opacity: Double(a) / 255)
    }
}

public enum ForgePalette {
    // Backgrounds — pure black favors OLED and always-on dimming.
    public static let background      = Color(forgeHex: "0A0A0A")
    public static let surface         = Color(forgeHex: "141414")
    public static let surfaceElevated = Color(forgeHex: "1A1A1A")

    // Ember (primary / energy). High-alert accent only — used sparingly on watch.
    public static let ember      = Color(forgeHex: "FF4D00")
    public static let emberLight = Color(forgeHex: "FF6B2B")

    // Steel (secondary / focus)
    public static let steel      = Color(forgeHex: "3B82F6")
    public static let steelLight = Color(forgeHex: "60A5FA")

    // Calm & restorative range (mindfulness, sleep, recovery)
    public static let violet = Color(forgeHex: "A855F7")
    public static let indigo = Color(forgeHex: "6366F1")
    public static let jade   = Color(forgeHex: "34D399")
    public static let teal   = Color(forgeHex: "2DD4BF")
    public static let amber  = Color(forgeHex: "F59E0B")

    // Text
    public static let textPrimary   = Color.white
    public static let textSecondary = Color(forgeHex: "A1A1AA")
    public static let textTertiary  = Color(forgeHex: "71717A")

    // Status
    public static let success = Color(forgeHex: "22C55E")
    public static let warning = Color(forgeHex: "EAB308")
    public static let danger  = Color(forgeHex: "EF4444")
}
