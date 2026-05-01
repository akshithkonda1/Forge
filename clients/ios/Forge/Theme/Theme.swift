import SwiftUI

// MARK: - Color Palette

extension Color {
    // Backgrounds
    static let forgeBackground = Color(hex: "0A0A0A")
    static let forgeSurface = Color(hex: "141414")
    static let forgeSurfaceElevated = Color(hex: "1A1A1A")
    static let forgeSurfaceHover = Color(hex: "222222")

    // Borders
    static let forgeBorder = Color(hex: "2A2A2A")
    static let forgeBorderLight = Color(hex: "333333")

    // Ember (Primary)
    static let ember = Color(hex: "FF4D00")
    static let emberLight = Color(hex: "FF6B2B")
    static let emberDark = Color(hex: "CC3D00")

    // Steel (Secondary)
    static let steel = Color(hex: "3B82F6")
    static let steelLight = Color(hex: "60A5FA")

    // Text
    static let textPrimary = Color.white
    static let textSecondary = Color(hex: "A1A1AA")
    static let textTertiary = Color(hex: "71717A")
    static let textMuted = Color(hex: "52525B")

    // Semantic
    static let forgeSuccess = Color(hex: "22C55E")
    static let forgeWarning = Color(hex: "EAB308")
    static let forgeDanger = Color(hex: "EF4444")

    // Sleep stages
    static let sleepDeep = Color(hex: "3B82F6")
    static let sleepREM = Color(hex: "A78BFA")
    static let sleepLight = Color(hex: "71717A")
    static let sleepAwake = Color(hex: "EF4444")
}

extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")))
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)
        self.init(
            red: Double((rgbValue >> 16) & 0xFF) / 255.0,
            green: Double((rgbValue >> 8) & 0xFF) / 255.0,
            blue: Double(rgbValue & 0xFF) / 255.0
        )
    }
}

// MARK: - Gradients

extension LinearGradient {
    static let emberGradient = LinearGradient(
        colors: [.ember, .emberLight],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let steelGradient = LinearGradient(
        colors: [.steel, .steelLight],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - Readiness Helpers

func readinessColor(for score: Int) -> Color {
    if score >= 80 { return .forgeSuccess }
    if score >= 60 { return .ember }
    if score >= 40 { return .forgeWarning }
    return .forgeDanger
}

func readinessLabel(for score: Int) -> String {
    if score >= 80 { return "Primed" }
    if score >= 60 { return "Good" }
    if score >= 40 { return "Fair" }
    return "Rest Day"
}

func intensityColor(_ intensity: String) -> Color {
    switch intensity {
    case "max": return .forgeDanger
    case "high": return .ember
    case "moderate": return .forgeWarning
    case "low": return .forgeSuccess
    default: return .textSecondary
    }
}

// MARK: - View Modifiers

struct ForgeCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.forgeSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct ForgeCardBorderedStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.forgeSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.forgeBorder, lineWidth: 1)
            )
    }
}

extension View {
    func forgeCard() -> some View { modifier(ForgeCardStyle()) }
    func forgeBorderedCard() -> some View { modifier(ForgeCardBorderedStyle()) }
}
