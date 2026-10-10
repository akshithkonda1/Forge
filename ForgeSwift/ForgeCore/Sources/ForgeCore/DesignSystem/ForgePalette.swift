import SwiftUI

// MARK: - Forge Palette (shared iOS + watchOS)
//
// Lockstep with `shared/design-tokens.json` / Home Theme.
// The initializer is `forgeHex` so linking ForgeCore into the iOS app
// never collides with the app's `Color(hex:)`.
//
// Ember is energy — never guilt. Miss / rest states use steelLight
// (`miss`), not alert red. ARIA states are roles on these same tokens.

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
    public static let background      = Color(forgeHex: ForgeDesignTokens.ColorHex.background)
    public static let surface         = Color(forgeHex: ForgeDesignTokens.ColorHex.surface)
    public static let surfaceElevated = Color(forgeHex: ForgeDesignTokens.ColorHex.surfaceElevated)
    public static let surfaceHover    = Color(forgeHex: ForgeDesignTokens.ColorHex.surfaceHover)
    public static let cardBackground  = Color(forgeHex: ForgeDesignTokens.ColorHex.cardBackground)

    public static let ember      = Color(forgeHex: ForgeDesignTokens.ColorHex.ember)
    public static let emberLight = Color(forgeHex: ForgeDesignTokens.ColorHex.emberLight)
    public static let emberCore  = Color(forgeHex: "FFE28A")
    public static let emberDark  = Color(forgeHex: ForgeDesignTokens.ColorHex.emberDark)

    public static let steel      = Color(forgeHex: ForgeDesignTokens.ColorHex.steel)
    public static let steelLight = Color(forgeHex: ForgeDesignTokens.ColorHex.steelLight)
    public static let steelDark  = Color(forgeHex: ForgeDesignTokens.ColorHex.steelDark)
    public static let miss       = Color(forgeHex: ForgeDesignTokens.ColorHex.miss)
    public static let plate      = Color(forgeHex: ForgeDesignTokens.ColorHex.plate)

    public static let aurora = Color(forgeHex: ForgeDesignTokens.ColorHex.aurora)
    public static let violet = Color(forgeHex: ForgeDesignTokens.ColorHex.aurora)
    public static let indigo = Color(forgeHex: ForgeDesignTokens.ColorHex.indigo)
    public static let jade   = Color(forgeHex: ForgeDesignTokens.ColorHex.success)
    public static let teal   = Color(forgeHex: "2DD4BF")
    public static let amber  = Color(forgeHex: ForgeDesignTokens.ColorHex.amber)
    public static let vitality = Color(forgeHex: ForgeDesignTokens.ColorHex.vitality)
    public static let alert  = Color(forgeHex: ForgeDesignTokens.ColorHex.alert)

    public static let textPrimary   = Color(forgeHex: ForgeDesignTokens.ColorHex.textPrimary)
    public static let textSecondary = Color(forgeHex: ForgeDesignTokens.ColorHex.textSecondary)
    public static let textTertiary  = Color(forgeHex: ForgeDesignTokens.ColorHex.textTertiary)
    public static let textMuted     = Color(forgeHex: ForgeDesignTokens.ColorHex.textMuted)

    public static let success = Color(forgeHex: ForgeDesignTokens.ColorHex.success)
    public static let warning = Color(forgeHex: ForgeDesignTokens.ColorHex.warning)
    public static let danger  = Color(forgeHex: ForgeDesignTokens.ColorHex.danger)

    public static let ariaIdle       = ember
    public static let ariaListening  = teal
    public static let ariaProcessing = steel
    public static let ariaSpeaking   = emberLight
    public static let ariaRecover    = jade
    public static let ariaWindDown   = indigo
}
