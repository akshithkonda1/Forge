import SwiftUI

// MARK: - Color Design Tokens (mirrors globals.css)

extension Color {
    // Backgrounds
    static let background    = Color(hex: "0A0A0A")
    static let surface       = Color(hex: "141414")
    static let surfaceElevated = Color(hex: "1A1A1A")
    static let surfaceHover  = Color(hex: "222222")
    static let cardBackground = Color(hex: "141414") // Alias for surface

    // Borders
    static let borderColor   = Color(hex: "2A2A2A")
    static let borderLight   = Color(hex: "333333")

    // Ember (primary)
    static let ember         = Color(hex: "FF4D00")
    static let emberLight    = Color(hex: "FF6B2B")
    static let emberDark     = Color(hex: "CC3D00")

    // Steel (secondary)
    static let steel         = Color(hex: "3B82F6")
    static let steelLight    = Color(hex: "60A5FA")
    static let steelDark     = Color(hex: "2563EB")

    // Text
    static let textPrimary   = Color.white
    static let textSecondary = Color(hex: "A1A1AA")
    static let textTertiary  = Color(hex: "71717A")
    static let textMuted     = Color(hex: "52525B")

    // Status
    static let success       = Color(hex: "22C55E")
    static let warning       = Color(hex: "EAB308")
    static let danger        = Color(hex: "EF4444")

    // Hex initializer
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:  (a,r,g,b) = (255,(int>>8)*17,(int>>4&0xF)*17,(int&0xF)*17)
        case 6:  (a,r,g,b) = (255,int>>16,int>>8&0xFF,int&0xFF)
        case 8:  (a,r,g,b) = (int>>24,int>>16&0xFF,int>>8&0xFF,int&0xFF)
        default: (a,r,g,b) = (255,255,255,255)
        }
        self.init(.sRGB,
                  red:     Double(r)/255,
                  green:   Double(g)/255,
                  blue:    Double(b)/255,
                  opacity: Double(a)/255)
    }
}

// MARK: - Gradient helpers

extension LinearGradient {
    static var emberGradient: LinearGradient {
        LinearGradient(colors: [.ember, .emberLight],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static var sleepRing: LinearGradient {
        LinearGradient(colors: [.steel, .steelLight, .steel],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - HR Zone helper (mirrors getHRZone in active-workout-view.tsx)

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

// MARK: - View Modifiers

struct ForgeCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.surface)
            .cornerRadius(16)
    }
}

extension View {
    func forgeCard() -> some View {
        modifier(ForgeCardModifier())
    }
}
