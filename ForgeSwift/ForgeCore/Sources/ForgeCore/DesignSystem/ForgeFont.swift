import SwiftUI
import CoreText

// MARK: - Forge typefaces
//
// Two families, both SIL Open Font License 1.1, bundled with ForgeCore so the
// phone app, Watch, widgets and the iMessage extension all resolve the same
// faces (licenses ship beside the files in Resources/Fonts):
//
//   • Geist (Vercel) — the UI and numbers face. A tight, engineered grotesk
//     with true tabular figures, so metrics read like an instrument.
//     Geist's *default* figures are proportional; tabular digits are an
//     opt-in feature (`tnum`), so every metric role applies
//     `.monospacedDigit()`. Plain `sans` body text keeps proportional
//     digits on purpose — add `.monospacedDigit()` for any counting or
//     animating number, or its width will jitter as the value changes.
//   • Instrument Serif — display only (greeting, page titles, ARIA's voice).
//     One editorial note so the app reads calm and considered, not "AI app".
//
// Registration is lazy and process-scoped (CoreText), triggered by the first
// font request, so no target needs a UIAppFonts entry or launch hook. If a
// face is ever missing, `Font.custom` falls back to the system font: text
// still renders, it just loses the brand face.
//
// Dynamic Type: pass `relativeTo:` (or use a `TextStyle` overload) and the
// face scales with the user's text size. Omit it to keep a fixed size — that
// is the exact behaviour of the `.system(size:)` calls this layer replaced.

public enum ForgeFont {

    public enum Face: String, CaseIterable, Sendable {
        case light = "Geist-Light"
        case regular = "Geist-Regular"
        case medium = "Geist-Medium"
        case semibold = "Geist-SemiBold"
        case bold = "Geist-Bold"
        case serif = "InstrumentSerif-Regular"
        case serifItalic = "InstrumentSerif-Italic"
    }

    public static let sansFamily = "Geist"
    public static let serifFamily = "Instrument Serif"

    // MARK: Registration

    private static let didRegister: Bool = {
        registerBundledFonts()
        return true
    }()

    /// Safe to call any number of times; registers once per process.
    @discardableResult
    public static func registerIfNeeded() -> Bool {
        didRegister
    }

    private static func registerBundledFonts() {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        for face in Face.allCases {
            let url = bundle.url(forResource: face.rawValue, withExtension: "ttf")
                ?? bundle.url(forResource: face.rawValue, withExtension: "ttf", subdirectory: "Fonts")
            guard let url else { continue }
            // Returns false (kCTFontManagerErrorAlreadyRegistered) on a second
            // registration in the same process; that is harmless.
            _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    // MARK: Faces

    /// Static Geist face for a SwiftUI weight. Heavier-than-bold maps to Bold,
    /// lighter-than-light maps to Light (only these five weights ship).
    public static func face(for weight: Font.Weight) -> Face {
        if weight == .ultraLight || weight == .thin || weight == .light { return .light }
        if weight == .medium { return .medium }
        if weight == .semibold { return .semibold }
        if weight == .bold || weight == .heavy || weight == .black { return .bold }
        return .regular
    }

    /// Default point size of each text style at the standard (Large) setting.
    public static func defaultSize(for style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: return 34
        case .title: return 28
        case .title2: return 22
        case .title3: return 20
        case .headline: return 17
        case .body: return 17
        case .callout: return 16
        case .subheadline: return 15
        case .footnote: return 13
        case .caption: return 12
        case .caption2: return 11
        default: return 17
        }
    }

    // MARK: Sans (Geist)

    /// Geist at `size`. With `relativeTo` it scales with Dynamic Type; without,
    /// it is fixed (a drop-in for `.system(size:weight:)`).
    public static func sans(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        relativeTo style: Font.TextStyle? = nil
    ) -> Font {
        registerIfNeeded()
        let name = face(for: weight).rawValue
        if let style {
            return .custom(name, size: size, relativeTo: style)
        }
        return .custom(name, fixedSize: size)
    }

    /// Geist sized and scaled like a system text style (drop-in for
    /// `.system(.headline)` / `.font(.caption)`).
    public static func sans(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        sans(defaultSize(for: style), weight: weight, relativeTo: style)
    }

    // MARK: Serif (Instrument Serif — display only)

    /// Instrument Serif ships one weight; keep it for large display text.
    public static func serif(
        _ size: CGFloat,
        italic: Bool = false,
        relativeTo style: Font.TextStyle? = nil
    ) -> Font {
        registerIfNeeded()
        let name = (italic ? Face.serifItalic : Face.serif).rawValue
        if let style {
            return .custom(name, size: size, relativeTo: style)
        }
        return .custom(name, fixedSize: size)
    }

    public static func serif(_ style: Font.TextStyle, italic: Bool = false) -> Font {
        // The serif's x-height is small; set it ~25% larger than the style's
        // system size so it optically matches the sans around it.
        serif((defaultSize(for: style) * 1.25).rounded(), italic: italic, relativeTo: style)
    }
}
