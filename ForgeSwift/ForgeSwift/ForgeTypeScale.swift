import SwiftUI

// MARK: - Forge Type Scale
//
// `ForgeTypography` (Theme+Readiness.swift) has been dead code since it
// was written — grep finds zero call sites — because it wraps
// `.system(size:)` with fixed point sizes, which never respond to the
// user's Dynamic Type setting at all. `ForgeType` replaces it with roles
// built on SwiftUI's semantic text styles (`.largeTitle`, `.title`,
// `.body`, ...), which the system scales automatically with the user's
// preferred text size — while keeping the app's rounded/bold identity
// via `.weight()`/`design: .rounded`.
//
// Adoption is a per-view, mechanical swap: `.font(.system(size: 28,
// weight: .bold, design: .rounded))` → `.font(ForgeType.title)`. Views
// with large numeric readouts (readiness score, heart rate) that need a
// fixed visual size at the smallest Dynamic Type setting should still
// prefer `ForgeType.metric`/`.metricLarge` over a raw fixed size — they
// scale too, just anchored to a larger base text style so the number
// stays legible at a glance even before the user enlarges anything.

enum ForgeType {
    /// Hero numeric readouts — the readiness score, a live heart rate.
    static var metricLarge: Font { .system(.largeTitle, design: .rounded).weight(.bold) }
    /// Secondary numeric readouts — stat tiles, summary numbers.
    static var metric: Font { .system(.title, design: .rounded).weight(.bold) }

    static var display: Font { .system(.largeTitle, design: .rounded).weight(.bold) }
    static var title: Font { .system(.title, design: .rounded).weight(.bold) }
    static var title2: Font { .system(.title2, design: .rounded).weight(.bold) }
    static var title3: Font { .system(.title3, design: .rounded).weight(.semibold) }

    static var headline: Font { .system(.headline) }
    static var body: Font { .system(.body) }
    static var callout: Font { .system(.callout) }
    static var subheadline: Font { .system(.subheadline) }
    static var footnote: Font { .system(.footnote) }
    static var caption: Font { .system(.caption).weight(.medium) }
    static var caption2: Font { .system(.caption2) }
}
