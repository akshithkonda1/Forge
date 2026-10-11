import Foundation

/// Cross-client design tokens. Lockstep with `shared/design-tokens.json`.
///
/// Home (PR #444) is the look: existing palette, system-rounded type,
/// Peak / Good / Fair / Low, event-only glow. Nest brand stays
/// `AriaNestGeometry`. Watch compact type uses the same role names at
/// smaller sizes. Web CSS reads the same JSON.
public enum ForgeDesignTokens: Sendable {
    public static let kind = "forge-design-tokens"
    public static let surface = "all-clients"
    public static let mixLock = "home-is-source"

    public enum ColorHex {
        public static let background = "08080C"
        public static let surface = "101014"
        public static let surfaceElevated = "17171C"
        public static let surfaceHover = "1C1C22"
        public static let cardBackground = "0E0E10"
        public static let border = "2A2A32"
        public static let borderLight = "3A3A44"
        public static let ember = "FF4D00"
        public static let emberLight = "FF7A3D"
        public static let emberDark = "C43A00"
        public static let steel = "5B8DEF"
        public static let steelLight = "7BA6F7"
        public static let steelDark = "3D6FD4"
        public static let aurora = "A78BFA"
        public static let vitality = "22C55E"
        public static let indigo = "6366F1"
        public static let amber = "FFB84D"
        public static let alert = "EF4444"
        public static let textPrimary = "FAFAFA"
        public static let textSecondary = "A1A1AA"
        public static let textTertiary = "71717A"
        public static let textMuted = "52525B"
        public static let success = "34D399"
        public static let warning = "FBBF24"
        public static let danger = "F87171"
        public static let plate = "7EC8FF"
        public static let miss = "7BA6F7"
    }

    public enum Spacing {
        public static let xs: Double = 4
        public static let sm: Double = 8
        public static let md: Double = 12
        public static let lg: Double = 16
        public static let xl: Double = 24
        public static let xxl: Double = 32
    }

    public enum Radius {
        public static let xs: Double = 6
        public static let sm: Double = 10
        public static let md: Double = 14
        public static let lg: Double = 18
        public static let xl: Double = 22
        public static let xxl: Double = 28
        public static let pill: Double = 999
    }

    public enum Stroke {
        public static let hairline: Double = 0.8
        public static let thin: Double = 1
        public static let ring: Double = 5.5
        public static let compactRing: Double = 4.5
    }

    public enum Shadow {
        public static let cardY: Double = 6
        public static let cardRadius: Double = 10
        public static let cardOpacity: Double = 0.28
        public static let glowRadius: Double = 5
        public static let glowOpacity: Double = 0.16
    }

    public enum TypeRole: String, CaseIterable, Sendable {
        case display
        case title
        case headline
        case body
        case caption
        case metric

        public var textStyle: String {
            switch self {
            case .display: return "title2"
            case .title: return "title3"
            case .headline: return "headline"
            case .body: return "subheadline"
            case .caption: return "caption"
            case .metric: return "title3"
            }
        }

        public var weight: String {
            switch self {
            case .display, .title, .headline, .caption: return "semibold"
            case .body: return "regular"
            case .metric: return "bold"
            }
        }

        public var design: String {
            switch self {
            case .body: return "default"
            default: return "rounded"
            }
        }

        public var tracking: Double {
            switch self {
            case .display: return -0.4
            case .title: return -0.3
            case .headline: return -0.2
            case .body: return 0
            case .caption: return 0.2
            case .metric: return -0.4
            }
        }

        public var lineHeight: Double {
            switch self {
            case .display: return 1.15
            case .title: return 1.2
            case .headline: return 1.25
            case .body: return 1.35
            case .caption: return 1.3
            case .metric: return 1.1
            }
        }

        public var tabular: Bool {
            self == .metric
        }

        public var compactSize: Double {
            switch self {
            case .display: return 16
            case .title: return 13
            case .headline: return 12
            case .body: return 11
            case .caption: return 10
            case .metric: return 18
            }
        }
    }

    public static let displayFamily = "system-rounded"
    public static let bodyFamily = "system"
    public static let metricFamily = "system-rounded-tabular"
    public static let eyebrowTracking: Double = 1.4

    public enum Motion {
        public static let eventOnly = true
        public static let liveGlowDefault = false
        public static let respectReduceMotion = true
        public static let maxTickHz: Double = 12
        public static let curve = "standard"
        public static let snapResponse: Double = 0.25
        public static let snapDamping: Double = 0.75
        public static let standardResponse: Double = 0.35
        public static let standardDamping: Double = 0.75
        public static let heroResponse: Double = 0.45
        public static let heroDamping: Double = 0.7
        public static let pageResponse: Double = 0.4
        public static let pageDamping: Double = 0.8
        public static let sweepSeconds: Double = 1.2
    }

    public enum UX {
        public static let minTap: Double = 44
        public static let onePrimaryCTA = true
        public static let primaryCTAPlacement = "hero-bottom"
        public static let navBack = "leading"
        public static let sheetClose = "trailing"
        public static let permissionSkip = "always-visible"
        public static let darkAppearance = "required"
        public static let iconWeight = "semibold"
        public static let iconSize: Double = 16
        public static let safeInset: Double = 16
    }

    public enum Haptic: String, CaseIterable, Sendable {
        case select
        case press
        case primaryCTA
        case success
        case error
        case destructive

        public var token: String {
            switch self {
            case .select: return "selection"
            case .press: return "light"
            case .primaryCTA: return "medium"
            case .success: return "notification.success"
            case .error: return "notification.error"
            case .destructive: return "notification.warning"
            }
        }
    }

    public static let bannedPhrases = [
        "diagnos", "treat", "prescribe", "cure", "medical advice",
        "recovery-first", "recovery week", "Adaptive Recovery"
    ]

    public static let neverExpandARIA = true
    public static let ariaRole = "lifestyle coach"

    public static func containsBannedPhrase(_ line: String) -> String? {
        let lower = line.lowercased()
        return bannedPhrases.first { lower.contains($0.lowercased()) }
    }
}
