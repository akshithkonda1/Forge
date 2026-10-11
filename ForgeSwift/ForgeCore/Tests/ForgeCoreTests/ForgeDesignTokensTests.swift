import XCTest
@testable import ForgeCore

/// Locks `shared/design-tokens.json` to ForgeCore tokens: Home palette,
/// named type scale, event-only motion, 44 pt taps, copy voice.
final class ForgeDesignTokensTests: XCTestCase {

    private struct File: Decodable {
        struct Color: Decodable {
            let background: String
            let ember: String
            let steel: String
            let steelLight: String
            let miss: String
            let plate: String
            let vitality: String
            let alert: String
            let textPrimary: String
        }

        struct Spacing: Decodable {
            let xs: Double
            let sm: Double
            let md: Double
            let lg: Double
            let xl: Double
            let xxl: Double
        }

        struct Radius: Decodable {
            let xs: Double
            let sm: Double
            let md: Double
            let lg: Double
            let xl: Double
            let xxl: Double
            let pill: Double
        }

        struct TypeFile: Decodable {
            struct Role: Decodable {
                let textStyle: String
                let weight: String
                let design: String
                let tracking: Double
                let lineHeight: Double
                let tabular: Bool
                let compactSize: Double
            }

            let displayFamily: String
            let bodyFamily: String
            let metricFamily: String
            let roles: [String: Role]
        }

        struct Motion: Decodable {
            let eventOnly: Bool
            let liveGlowDefault: Bool
            let respectReduceMotion: Bool
            let maxTickHz: Double
            let curve: String
            let sweepSeconds: Double
        }

        struct UX: Decodable {
            let minTap: Double
            let onePrimaryCTA: Bool
            let permissionSkip: String
            let darkAppearance: String
            let haptics: [String: String]
        }

        struct Copy: Decodable {
            let voice: String
            let ariaRole: String
            let neverExpandARIA: Bool
            let bannedPhrases: [String]
        }

        let kind: String
        let surface: String
        let mixLock: String
        let color: Color
        let spacing: Spacing
        let radius: Radius
        let type: TypeFile
        let motion: Motion
        let ux: UX
        let copy: Copy
    }

    private static func loadFile() throws -> File {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared")
            .appendingPathComponent("design-tokens.json")
        return try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
    }

    func testFileMatchesSwiftTokens() throws {
        let file = try Self.loadFile()
        XCTAssertEqual(file.kind, ForgeDesignTokens.kind)
        XCTAssertEqual(file.surface, ForgeDesignTokens.surface)
        XCTAssertEqual(file.mixLock, ForgeDesignTokens.mixLock)
        XCTAssertEqual(file.color.background, ForgeDesignTokens.ColorHex.background)
        XCTAssertEqual(file.color.ember, ForgeDesignTokens.ColorHex.ember)
        XCTAssertEqual(file.color.steel, ForgeDesignTokens.ColorHex.steel)
        XCTAssertEqual(file.color.steelLight, ForgeDesignTokens.ColorHex.steelLight)
        XCTAssertEqual(file.color.miss, ForgeDesignTokens.ColorHex.miss)
        XCTAssertEqual(file.color.plate, ForgeDesignTokens.ColorHex.plate)
        XCTAssertEqual(file.color.vitality, ForgeDesignTokens.ColorHex.vitality)
        XCTAssertEqual(file.color.alert, ForgeDesignTokens.ColorHex.alert)
        XCTAssertEqual(file.color.miss, HomeReadinessTokens.missHex)
        XCTAssertNotEqual(file.color.miss, file.color.alert)
        XCTAssertEqual(file.spacing.lg, ForgeDesignTokens.Spacing.lg)
        XCTAssertEqual(file.radius.xl, ForgeDesignTokens.Radius.xl)
        XCTAssertEqual(CGFloat(file.spacing.lg), ForgeDS.Spacing.lg)
        XCTAssertEqual(CGFloat(file.radius.xl), ForgeDS.Radius.xl)
    }

    func testNamedTypeScale() throws {
        let file = try Self.loadFile()
        let names = ForgeDesignTokens.TypeRole.allCases.map(\.rawValue)
        XCTAssertEqual(names, ["display", "title", "headline", "body", "caption", "metric"])
        for role in ForgeDesignTokens.TypeRole.allCases {
            let json = file.type.roles[role.rawValue]
            XCTAssertEqual(json?.textStyle, role.textStyle, role.rawValue)
            XCTAssertEqual(json?.weight, role.weight, role.rawValue)
            XCTAssertEqual(json?.design, role.design, role.rawValue)
            XCTAssertEqual(json?.tracking ?? -99, role.tracking, accuracy: 0.0001)
            XCTAssertEqual(json?.lineHeight ?? -99, role.lineHeight, accuracy: 0.0001)
            XCTAssertEqual(json?.tabular, role.tabular)
            XCTAssertEqual(json?.compactSize ?? -99, role.compactSize, accuracy: 0.0001)
        }
        XCTAssertTrue(ForgeDesignTokens.TypeRole.metric.tabular)
        XCTAssertFalse(ForgeDesignTokens.TypeRole.body.tabular)
        XCTAssertEqual(file.type.displayFamily, "system-rounded")
        XCTAssertEqual(file.type.metricFamily, "system-rounded-tabular")
    }

    func testMotionIsEventOnly() throws {
        let file = try Self.loadFile()
        XCTAssertTrue(file.motion.eventOnly)
        XCTAssertFalse(file.motion.liveGlowDefault)
        XCTAssertTrue(file.motion.respectReduceMotion)
        XCTAssertLessThanOrEqual(file.motion.maxTickHz, 12)
        XCTAssertEqual(file.motion.curve, "standard")
        XCTAssertEqual(file.motion.sweepSeconds, ForgeDesignTokens.Motion.sweepSeconds, accuracy: 0.0001)
        XCTAssertTrue(ForgeDesignTokens.Motion.eventOnly)
        XCTAssertEqual(HomeReadinessTokens.tickHzCeiling, file.motion.maxTickHz, accuracy: 0.0001)
    }

    func testUXAndCopyVoice() throws {
        let file = try Self.loadFile()
        XCTAssertEqual(file.ux.minTap, 44)
        XCTAssertTrue(file.ux.onePrimaryCTA)
        XCTAssertEqual(file.ux.permissionSkip, "always-visible")
        XCTAssertEqual(file.ux.darkAppearance, "required")
        XCTAssertEqual(file.ux.haptics["primaryCTA"], "medium")
        XCTAssertEqual(file.ux.haptics["press"], "light")
        XCTAssertEqual(file.copy.voice, "identity-first")
        XCTAssertEqual(file.copy.ariaRole, "lifestyle coach")
        XCTAssertTrue(file.copy.neverExpandARIA)
        XCTAssertTrue(file.copy.bannedPhrases.contains("Adaptive Recovery"))
        XCTAssertTrue(file.copy.bannedPhrases.contains("recovery week"))
        XCTAssertEqual(
            ForgeDesignTokens.containsBannedPhrase("Adaptive Recovery Interactive Assistant"),
            "Adaptive Recovery"
        )
        XCTAssertNil(ForgeDesignTokens.containsBannedPhrase("Do this now"))
        for label in ReadinessBand.allCases.map(\.label) {
            XCTAssertFalse(HomeReadinessTokens.foreignBandLabels.contains(label), label)
        }
    }

    func testPaletteUsesHomeHex() {
        XCTAssertEqual(ForgeDesignTokens.ColorHex.ember, "FF4D00")
        XCTAssertEqual(ForgeDesignTokens.ColorHex.steel, "5B8DEF")
        XCTAssertEqual(ForgeDesignTokens.ColorHex.miss, HomeReadinessTokens.emberSteelHex)
    }
}
