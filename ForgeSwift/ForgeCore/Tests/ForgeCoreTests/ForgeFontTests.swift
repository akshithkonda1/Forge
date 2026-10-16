import CoreText
import XCTest
@testable import ForgeCore

/// Locks the bundled typefaces. `Font.custom` silently falls back to the
/// system font when a face cannot be found, so a renamed or missing TTF
/// would not fail any build — it would just quietly un-brand the app.
/// These tests fail instead: every face must ship as a package resource,
/// register process-scoped, and resolve by the exact name `Font.custom`
/// is given.
final class ForgeFontTests: XCTestCase {

    func testEveryFaceShipsAsAResource() {
        for face in ForgeFont.Face.allCases {
            let url = Bundle.module.url(forResource: face.rawValue, withExtension: "ttf")
            XCTAssertNotNil(url, "missing bundled font resource: \(face.rawValue).ttf")
        }
    }

    func testRegistrationResolvesEveryFaceByPostScriptName() {
        // Triggers lazy registration; the meaningful check is the name
        // resolution below — an unregistered name would fall back to a
        // system font with a different PostScript name.
        _ = ForgeFont.registerIfNeeded()
        for face in ForgeFont.Face.allCases {
            // CTFontCreateWithName falls back to a system font for an
            // unknown name, so a mismatched PostScript name fails here.
            let resolved = CTFontCreateWithName(face.rawValue as CFString, 17, nil)
            XCTAssertEqual(
                CTFontCopyPostScriptName(resolved) as String,
                face.rawValue,
                "registered face \(face.rawValue) did not resolve by that name"
            )
        }
    }

    func testSerifFacesResolveSeparately() {
        _ = ForgeFont.registerIfNeeded()
        let regular = CTFontCopyPostScriptName(
            CTFontCreateWithName("InstrumentSerif-Regular" as CFString, 17, nil)
        ) as String
        let italic = CTFontCopyPostScriptName(
            CTFontCreateWithName("InstrumentSerif-Italic" as CFString, 17, nil)
        ) as String
        XCTAssertEqual(regular, "InstrumentSerif-Regular")
        XCTAssertEqual(italic, "InstrumentSerif-Italic")
    }

    /// The Swift family constants must agree with the face names they
    /// describe: every sans face is a `Geist-*` file and every serif face
    /// an `InstrumentSerif-*` file.
    func testFamilyConstantsMatchFaceNames() {
        XCTAssertEqual(ForgeFont.sansFamily, "Geist")
        XCTAssertEqual(ForgeFont.serifFamily, "Instrument Serif")
        for face in ForgeFont.Face.allCases {
            switch face {
            case .serif, .serifItalic:
                XCTAssertTrue(face.rawValue.hasPrefix("InstrumentSerif"))
            default:
                XCTAssertTrue(face.rawValue.hasPrefix("Geist"))
            }
        }
    }
}
