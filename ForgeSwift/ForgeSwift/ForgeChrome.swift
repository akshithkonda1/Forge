import SwiftUI
import ForgeCore

// MARK: - Shared chrome
//
// One implementation each. Home plate / CTA / type is the look.
// Event-only motion. Reduce Motion respected. 44 pt taps.

enum ForgeUX {
    static let minTap = ForgeDS.minTap
    static let inset = ForgeDS.safeInset
    static let icon = ForgeDS.iconSize
    static let stroke = ForgeDS.Stroke.thin
    static let hairline = ForgeDS.Stroke.hairline
}

struct ForgeCTAEyebrow: View {
    var label: String
    var energy: Color = .ember

    var body: some View {
        Text(label.uppercased())
            .font(ForgeType.micro)
            .foregroundStyle(energy)
            .tracking(ForgeType.eyebrowTracking)
            .accessibilityAddTraits(.isHeader)
    }
}

struct ForgeSectionHeader: View {
    var title: String
    var subtitle: String? = nil
    var energy: Color = .textTertiary

    var body: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.xs) {
            Text(title)
                .font(ForgeType.caption)
                .foregroundStyle(energy)
                .tracking(ForgeType.eyebrowTracking)
                .textCase(.uppercase)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(ForgeType.body)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct ForgeSecondaryButton: View {
    var title: String
    var icon: String? = nil
    var accent: Color = .steel
    var action: () -> Void

    var body: some View {
        Button {
            FDS.haptic(.press)
            action()
        } label: {
            HStack(spacing: FDS.Spacing.sm) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: ForgeUX.icon, weight: .semibold))
                }
                Text(title)
                    .font(HomeType.label)
                    .lineLimit(1)
                    .minimumScaleFactor(ForgeLayout.labelMinScale)
            }
            .foregroundStyle(accent)
            .frame(maxWidth: .infinity)
            .frame(minHeight: ForgeUX.minTap)
            .padding(.horizontal, FDS.Spacing.lg)
            .background(accent.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous)
                    .stroke(accent.opacity(0.28), lineWidth: ForgeUX.hairline)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// Home's chip (HomeLifeChipRow): h10 v7, white 0.08 fill, white 0.12
/// hairline, label in textPrimary. Selected chips take the energy tint
/// (0.14 fill, 0.32 stroke). `fillsWidth` makes the capsule itself fill an
/// equal-width cell.
struct ForgeChip: View {
    var label: String
    var icon: String? = nil
    var energy: Color = HudChrome.emberSteel
    var selected: Bool = false
    var fillsWidth: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .accessibilityHidden(true)
            }
            Text(label)
                .font(HomeType.label)
                .lineLimit(1)
                .minimumScaleFactor(ForgeLayout.labelMinScale)
        }
        .foregroundStyle(selected ? energy : Color.textPrimary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: fillsWidth ? CGFloat.infinity : nil, minHeight: 30)
        .background(selected ? energy.opacity(0.14) : Color.white.opacity(0.08))
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(
                selected ? energy.opacity(0.32) : Color.white.opacity(0.12),
                lineWidth: ForgeUX.hairline
            )
        )
        .accessibilityElement(children: .combine)
    }
}

/// Home's stat cell (HomeCards lifestyleChip): optional 14 pt icon, value in
/// headline, sentence-case micro label, padding 12 in the Home well. Place it
/// in `ForgeStatGrid`, which makes every tile in a row the same height.
struct ForgeStatTile: View {
    var label: String
    var value: String
    var unit: String? = nil
    var energy: Color = .steel
    var icon: String? = nil

    @Environment(\.forgeFillsCell) private var fillsCell

    var body: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.sm) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(energy)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: ForgeLayout.labelValueGap) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value)
                        .font(FDS.TypeScale.Dynamic.headline)
                        .monospacedDigit()
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(ForgeLayout.valueMinScale)
                        .contentTransition(.numericText())
                    if let unit, !unit.isEmpty {
                        Text(unit)
                            .font(HomeType.label)
                            .foregroundStyle(energy)
                            .lineLimit(1)
                    }
                }
                Text(label)
                    .font(HomeType.micro)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: fillsCell ? CGFloat.infinity : nil, alignment: .topLeading)
        .forgeWell()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value) \(unit ?? "")")
    }
}

struct ForgeListRow: View {
    var icon: String? = nil
    var iconColor: Color = .ember
    var title: String
    var subtitle: String? = nil
    var trailing: String? = nil
    var showChevron: Bool = false

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: ForgeLayout.rowGap) {
            if let icon {
                ForgeIconWell(systemImage: icon, tint: iconColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(HomeType.status)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(HomeType.body)
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(2)
                }
                if typeSize.isAccessibilitySize, let trailing {
                    Text(trailing)
                        .font(HomeType.label)
                        .foregroundStyle(Color.textSecondary)
                        .monospacedDigit()
                }
            }
            .layoutPriority(1)
            Spacer(minLength: FDS.Spacing.xs)
            if !typeSize.isAccessibilitySize, let trailing {
                Text(trailing)
                    .font(HomeType.label)
                    .foregroundStyle(Color.textSecondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textMuted)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, ForgeLayout.rowVerticalPadding)
        .frame(minHeight: ForgeUX.minTap)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct ForgeToast: View {
    var title: String
    var message: String? = nil
    var energy: Color = .vitality

    var body: some View {
        HStack(spacing: FDS.Spacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: ForgeUX.icon, weight: .semibold))
                .foregroundStyle(energy)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(HomeType.status)
                    .foregroundStyle(Color.textPrimary)
                if let message {
                    Text(message)
                        .font(HomeType.body)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .forgeContentCard(tint: energy, padding: ForgeLayout.compactCardPadding)
        .accessibilityElement(children: .combine)
    }
}

/// Permission / opt-in card. Same Allow + Skip pattern everywhere.
struct ForgePermissionPrompt: View {
    var title: String
    var message: String
    var systemImage: String
    var accent: Color = .steel
    var allowTitle: String = "Allow"
    var skipTitle: String = "Skip"
    var onAllow: () -> Void
    var onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.md) {
            HStack(spacing: FDS.Spacing.md) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: FDS.Spacing.xs) {
                    Text(title)
                        .font(ForgeType.title)
                        .foregroundStyle(Color.textPrimary)
                    Text(message)
                        .font(ForgeType.body)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ForgePrimaryButton(title: allowTitle, icon: "checkmark", accent: accent, action: onAllow)
            ForgeSecondaryButton(title: skipTitle, accent: HudChrome.emberSteel, action: onSkip)
        }
        .forgeContentCard(accent: accent)
        .accessibilityElement(children: .contain)
    }
}

struct ForgeLoadingState: View {
    var label: String = "Loading"

    var body: some View {
        VStack(spacing: FDS.Spacing.md) {
            ProgressView()
                .tint(Color.ember)
            Text(label)
                .font(ForgeType.caption)
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: ForgeUX.minTap)
        .accessibilityElement(children: .combine)
    }
}

struct ForgeErrorState: View {
    var title: String = "Couldn’t load that"
    var message: String = "Try again when you’re ready."
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: FDS.Spacing.md) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(HudChrome.emberSteel)
            Text(title)
                .font(ForgeType.title)
                .foregroundStyle(Color.textPrimary)
            Text(message)
                .font(ForgeType.body)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
            if let retry {
                ForgeSecondaryButton(title: "Try again", icon: "arrow.clockwise", action: retry)
            }
        }
        .forgeContentCard(alignment: .center)
    }
}

// MARK: - Inset tile
//
// Nested plate for stats, rows, and fields that sit *inside* a card
// (`forgeGlassCard` / `hudPlate`). One fill, one hairline edge, token radius.

private struct ForgeInsetTile: ViewModifier {
    var radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(Color.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.borderHairline, lineWidth: ForgeUX.hairline)
            )
    }
}

extension View {
    func forgeInsetTile(radius: CGFloat = FDS.Radius.md) -> some View {
        modifier(ForgeInsetTile(radius: radius))
    }
}

// MARK: - Forge layout language (design-language spec v1)
//
// Shared layout tokens and components every feature area uses. See the
// design-language spec: one scaffold, one card, one rhythm.


// MARK: - Layout rhythm
//
// Home's numbers, promoted app-wide. PR #448 had no 20 pt token outside Home,
// so card padding fell to 16 while in-card gaps rose to 16. Padding equal to
// the gap is what made the dense screens read as cramped. Each step below is
// strictly smaller than the one before it, so tighter spacing always means
// "more related":
// cardPadding 20 > sectionGap 16 = heroGap 16 > blockGap 14 > rowGap 12 > tileGap 10 > pairGap 4.

enum ForgeLayout {
    /// Horizontal page inset.
    static let screenInset: CGFloat = HomeMetrics.inset
    /// Above the first child of a scroll page. `ForgePageHeader` applies it
    /// itself, so `ForgeScreenStack` defaults to 0. Pass it only on a page
    /// that has no `ForgePageHeader`.
    static let screenTop: CGFloat = FDS.Spacing.sm
    /// Between top-level cards. Applied once by the page stack, never per child.
    static let sectionGap: CGFloat = HomeMetrics.sectionGap
    /// Between blocks inside a hero plate (ring, vibe, tracks, CTA), as on Home.
    static let heroGap: CGFloat = HomeMetrics.heroStackGap
    /// After the last card. The tab bar is a `safeAreaInset`, so this never
    /// includes the bar's own height.
    static let scrollBottomClearance: CGFloat = HomeMetrics.scrollBottomClearance
    /// Interior padding of every standard card.
    static let cardPadding: CGFloat = HomeMetrics.cardPadding
    /// Interior padding for one-line banners, toasts and rail tiles.
    static let compactCardPadding: CGFloat = FDS.Spacing.lg
    /// Between blocks inside a card: header, body, footer.
    static let blockGap: CGFloat = 14
    /// Between repeated rows inside a card.
    static let rowGap: CGFloat = FDS.Spacing.md
    /// Between equal-width tiles and paired buttons.
    static let tileGap: CGFloat = 10
    /// Interior padding of a well (an inset tile nested in a card).
    static let tilePadding: CGFloat = FDS.Spacing.md
    /// Between a title and its subtitle, or an eyebrow and its lead line.
    static let pairGap: CGFloat = FDS.Spacing.xs
    /// Between a label and its value, and between stacked `ForgeMetricRow`s.
    static let labelValueGap: CGFloat = 2
    /// Between chips in a row, and between rows of static chips (Home's chip row).
    static let chipGap: CGFloat = 6
    /// Between rows of `ForgeChipButton`s. A 30 pt chip plus 14 makes rows
    /// 44 pt apart, so each chip's 44 pt tap area meets the next row's exactly.
    static let interactiveChipLineGap: CGFloat = 14
    /// How far `ForgeChipButton` grows its tap area above and below the
    /// 30 pt capsule without growing its layout box.
    static let chipTapOutset: CGFloat = 7
    /// Between unrelated groups in a sheet or form, outside cards.
    static let groupBreak: CGFloat = FDS.Spacing.xl
    /// Vertical padding that turns a 36 pt icon-well row into a 44 pt row.
    static let rowVerticalPadding: CGFloat = FDS.Spacing.xs
    /// Radius of anything nested inside a card.
    static let innerRadius: CGFloat = HomeMetrics.innerRadius
    /// Agenda-row icon well.
    static let iconWell: CGFloat = 36
    /// Narrowest stat cell at the default text size. `ForgeStatGrid` scales it
    /// with Dynamic Type and drops columns when cells would be narrower.
    static let statMinCellWidth: CGFloat = 84
    /// Shrink floor for numbers. Sentences never shrink; they wrap.
    static let valueMinScale: CGFloat = 0.75
    /// Shrink floor for labels, eyebrows and CTA titles.
    static let labelMinScale: CGFloat = 0.85

    /// Caps an `@ScaledMetric` frame so rings and badges grow with the
    /// reader's text size without taking over the row.
    static func scaledCap(_ scaled: CGFloat, base: CGFloat, maxGrowth: CGFloat = 1.4) -> CGFloat {
        min(max(scaled, base), base * maxGrowth)
    }
}

// MARK: - Page scaffold

/// The page body: one flat stack at Home's rhythm. Make it the only child of
/// the screen's `ScrollView`, with `ForgePageHeader` as its first child.
/// `top` defaults to 0 because `ForgePageHeader` owns the 8 pt above it.
struct ForgeScreenStack<Content: View>: View {
    var spacing: CGFloat = ForgeLayout.sectionGap
    var top: CGFloat = 0
    var bottom: CGFloat = ForgeLayout.scrollBottomClearance
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeScreenInsets(top: top, bottom: bottom)
    }
}

private struct ForgeContentCard: ViewModifier {
    var accent: Color?
    var tint: Color?
    var padding: CGFloat
    var alignment: Alignment

    /// `accent` already tints through `forgeGlassCard`; `tint` alone washes
    /// the card in its domain color without the halo.
    private var wash: Color? { accent == nil ? tint : nil }

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: alignment)
            .padding(padding)
            .background {
                if let wash {
                    RoundedRectangle(cornerRadius: FDS.Radius.xl, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [wash.opacity(0.07), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
            .forgeGlassCard(accent: accent)
    }
}

private struct ForgeBarChrome: ViewModifier {
    var edge: VerticalEdge
    var visible: Bool

    func body(content: Content) -> some View {
        content
            .background {
                if visible {
                    Color.background.opacity(0.94)
                        .background(.ultraThinMaterial)
                        .ignoresSafeArea(edges: edge == .top ? Edge.Set.top : Edge.Set.bottom)
                }
            }
            .overlay(alignment: edge == .top ? Alignment.bottom : Alignment.top) {
                if visible {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 0.5)
                        .accessibilityHidden(true)
                }
            }
    }
}

private struct ForgeWell: ViewModifier {
    var padding: CGFloat
    var radius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color.white.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: ForgeUX.stroke)
            )
    }
}

extension View {
    /// Page insets: 16 on the sides, `top` above the first child, 28 after the
    /// last card. `top` defaults to 0 because `ForgePageHeader` owns the 8 pt
    /// above it; pass `ForgeLayout.screenTop` on a page with no page header and
    /// `FDS.Spacing.lg` in a sheet.
    func forgeScreenInsets(
        top: CGFloat = 0,
        bottom: CGFloat = ForgeLayout.scrollBottomClearance
    ) -> some View {
        padding(.horizontal, ForgeLayout.screenInset)
            .padding(.top, top)
            .padding(.bottom, bottom)
    }

    /// The standard card: 20 pt interior padding plus `forgeGlassCard` at
    /// radius xl. Replaces `.padding(FDS.Spacing.lg).forgeGlassCard(...)`.
    /// `accent` adds the halo (hero-adjacent named card only); `tint` gives
    /// the domain wash with no halo; pass neither for a neutral card.
    func forgeContentCard(
        accent: Color? = nil,
        tint: Color? = nil,
        padding: CGFloat = ForgeLayout.cardPadding,
        alignment: Alignment = .leading
    ) -> some View {
        modifier(ForgeContentCard(accent: accent, tint: tint, padding: padding, alignment: alignment))
    }

    /// Home's inner well (white 0.045 fill, white 0.08 1 pt edge, radius 14,
    /// padding 12) for anything nested inside a card. The older opaque
    /// `forgeInsetTile(radius:)` stays for fields and docks that sit directly
    /// on a screen background.
    func forgeWell(
        padding: CGFloat = ForgeLayout.tilePadding,
        radius: CGFloat = ForgeLayout.innerRadius
    ) -> some View {
        modifier(ForgeWell(padding: padding, radius: radius))
    }

    /// Eyebrow in a chosen color. Chaining `.foregroundStyle` after
    /// `forgeSectionLabel()` does not tint, because the inner style wins.
    func forgeSectionLabel(tint: Color) -> some View {
        font(FDS.TypeScale.Dynamic.label)
            .foregroundStyle(tint)
            .tracking(1.4)
            .textCase(.uppercase)
    }

    /// One line that shrinks before it truncates. Numbers use the default
    /// floor; labels and CTA titles pass `ForgeLayout.labelMinScale`.
    func forgeSingleLine(minScale: CGFloat = ForgeLayout.valueMinScale) -> some View {
        lineLimit(1).minimumScaleFactor(minScale)
    }

    /// Sentences grow downward instead of truncating.
    func forgeWrapping() -> some View {
        fixedSize(horizontal: false, vertical: true)
    }

    /// Pinned bar surface, the same as Home's mini header: background 0.94
    /// over ultra-thin material with a 0.5 pt hairline on the content side.
    /// Pass `visible: false` while the bar is not yet pinned so it reads as
    /// part of the page at rest.
    func forgeBarChrome(edge: VerticalEdge = .top, visible: Bool = true) -> some View {
        modifier(ForgeBarChrome(edge: edge, visible: visible))
    }

    /// Grows the tap area without growing the layout box, so a small visual
    /// (a chip, a text link in a header row) gets a 44 pt target while its
    /// row keeps its visual rhythm. Inside a horizontal ScrollView, pad the
    /// scroll content vertically by at least `vertical`, or the outset is clipped.
    func forgeTapOutset(vertical: CGFloat, horizontal: CGFloat = 0) -> some View {
        padding(.vertical, vertical)
            .padding(.horizontal, horizontal)
            .contentShape(Rectangle())
            .padding(.vertical, -vertical)
            .padding(.horizontal, -horizontal)
    }
}

// MARK: - Card header

/// Trailing micro meta for `ForgeCardHeader` ("3 items", "QoL 72 · Good").
struct ForgeCardMeta: View {
    var text: String
    var color: Color = .textMuted

    var body: some View {
        Text(text)
            .font(HomeType.micro)
            .foregroundStyle(color)
            .monospacedDigit()
            .lineLimit(1)
    }
}

/// The first block of a card: an uppercase eyebrow, a spacer, then a trailing
/// meta, `ForgeTextLink`, chip or mini `ProgressView`. The card's title is
/// the eyebrow. Never put a 44 pt icon button here; it would push the row.
struct ForgeCardHeader<Trailing: View>: View {
    var title: String
    var tint: Color = .textTertiary
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: FDS.Spacing.sm) {
            Text(title)
                .forgeSectionLabel(tint: tint)
                .lineLimit(1)
                .minimumScaleFactor(ForgeLayout.labelMinScale)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: FDS.Spacing.sm)
            trailing()
        }
    }
}

extension ForgeCardHeader where Trailing == EmptyView {
    init(_ title: String, tint: Color = .textTertiary) {
        self.init(title: title, tint: tint) { EmptyView() }
    }

    init(title: String, tint: Color = .textTertiary) {
        self.init(title: title, tint: tint) { EmptyView() }
    }
}

extension ForgeCardHeader where Trailing == ForgeCardMeta {
    init(_ title: String, meta: String, metaColor: Color = .textMuted, tint: Color = .textTertiary) {
        self.init(title: title, tint: tint) {
            ForgeCardMeta(text: meta, color: metaColor)
        }
    }
}

/// Tertiary action and the default card footer: accent caption plus a
/// chevron. The 44 pt tap area comes from `forgeTapOutset`, so the link sits
/// in a header row at text height. Pass `expanded` for a disclosure toggle;
/// the chevron then turns.
struct ForgeTextLink: View {
    var title: String
    var accent: Color = .ember
    var expanded: Bool? = nil
    var action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var stateDescription: String {
        guard let expanded else { return "" }
        return expanded ? "Expanded" : "Collapsed"
    }

    var body: some View {
        Button {
            FDS.haptic(.press)
            action()
        } label: {
            HStack(spacing: FDS.Spacing.xs) {
                Text(title)
                    .font(HomeType.label)
                    .lineLimit(1)
                Image(systemName: expanded == nil ? "chevron.right" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .rotationEffect(.degrees(expanded == true ? 180 : 0))
                    .animation(reduceMotion ? nil : FDS.Spring.standard, value: expanded)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(accent)
            .forgeTapOutset(vertical: 14, horizontal: 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(stateDescription)
    }
}

// MARK: - Icon well

/// Tinted circular icon well from the agenda row: 36 pt, a 14 pt semibold
/// glyph, tint at 0.16. It grows gently with Dynamic Type, capped at 1.4x.
struct ForgeIconWell: View {
    let systemImage: String
    var tint: Color
    var diameter: CGFloat

    @ScaledMetric(relativeTo: .subheadline) private var typeScale: CGFloat = 1

    init(systemImage: String, tint: Color = .ember, diameter: CGFloat = ForgeLayout.iconWell) {
        self.systemImage = systemImage
        self.tint = tint
        self.diameter = diameter
    }

    var body: some View {
        let size = diameter * min(max(typeScale, 1), 1.4)
        ZStack {
            Circle()
                .fill(tint.opacity(0.16))
            Image(systemName: systemImage)
                .font(.system(size: size * 0.39, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Metric row

/// Label, spacer, value: Home's contributor row. Stack a group of them in
/// `VStack(spacing: ForgeLayout.labelValueGap)`, as Home does, never at
/// `rowGap`. At accessibility sizes the value drops under the label so
/// neither one truncates.
struct ForgeMetricRow: View {
    var label: String
    var value: String
    var unit: String? = nil
    var tint: Color? = nil
    var detail: String? = nil

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: ForgeLayout.labelValueGap))
            : AnyLayout(HStackLayout(alignment: .center, spacing: FDS.Spacing.sm))
        layout {
            HStack(spacing: 10) {
                if let tint {
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(tint)
                        .frame(width: 2, height: 16)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: ForgeLayout.labelValueGap) {
                    Text(label)
                        .font(HomeType.label)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(HomeType.micro)
                            .foregroundStyle(Color.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if !stacked {
                Spacer(minLength: FDS.Spacing.sm)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(HomeType.metric)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(ForgeLayout.valueMinScale)
                    .contentTransition(.numericText())
                if let unit, !unit.isEmpty {
                    Text(unit)
                        .font(HomeType.label)
                        .foregroundStyle(tint ?? Color.textTertiary)
                        .lineLimit(1)
                }
            }
            .layoutPriority(1)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Equal columns + stat grid

private struct ForgeFillsCellKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Set by `ForgeStatGrid` so each `ForgeStatTile` fills its row's height
    /// and the wells line up. Outside a grid a tile keeps its natural height.
    var forgeFillsCell: Bool {
        get { self[ForgeFillsCellKey.self] }
        set { self[ForgeFillsCellKey.self] = newValue }
    }
}

/// Equal-width columns. Each row is as tall as its tallest cell, and every
/// cell is offered that height. Cells that should fill their slot need
/// `.frame(maxWidth: .infinity, maxHeight: .infinity)` before their chrome.
/// With `minCellWidth > 0` the column count drops when cells would be
/// narrower, and four cells fall to 2 + 2 rather than 3 + 1.
struct ForgeEqualColumnsLayout: Layout {
    var columns: Int
    var spacing: CGFloat = ForgeLayout.tileGap
    var minCellWidth: CGFloat = 0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let width: CGFloat
        if let proposed = proposal.width, proposed.isFinite {
            width = proposed
        } else {
            width = idealWidth(subviews: subviews, cols: max(1, min(columns, subviews.count)))
        }
        let cols = resolvedColumns(width: width, count: subviews.count)
        let heights = rowHeights(subviews: subviews, cols: cols, cellWidth: cellWidth(width, cols))
        let total = heights.reduce(0, +) + spacing * CGFloat(max(0, heights.count - 1))
        return CGSize(width: width, height: total)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let cols = resolvedColumns(width: bounds.width, count: subviews.count)
        let cell = cellWidth(bounds.width, cols)
        let heights = rowHeights(subviews: subviews, cols: cols, cellWidth: cell)
        var y = bounds.minY
        for (row, height) in heights.enumerated() {
            for col in 0..<cols {
                let index = row * cols + col
                guard index < subviews.count else { break }
                let x = bounds.minX + CGFloat(col) * (cell + spacing)
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: cell, height: height)
                )
            }
            y += height + spacing
        }
    }

    private func resolvedColumns(width: CGFloat, count: Int) -> Int {
        let requested = max(1, min(columns, count))
        guard minCellWidth > 0, width.isFinite, width > 0 else { return requested }
        let fit = max(1, Int((width + spacing) / (minCellWidth + spacing)))
        var cols = min(requested, fit)
        if cols > 2, count % cols != 0, count % (cols - 1) == 0 {
            cols -= 1
        }
        return cols
    }

    private func cellWidth(_ width: CGFloat, _ cols: Int) -> CGFloat {
        max(0, (width - spacing * CGFloat(cols - 1)) / CGFloat(cols))
    }

    private func rowHeights(subviews: Subviews, cols: Int, cellWidth: CGFloat) -> [CGFloat] {
        var heights: [CGFloat] = []
        var start = 0
        while start < subviews.count {
            let end = min(start + cols, subviews.count)
            var rowHeight: CGFloat = 0
            for index in start..<end {
                let size = subviews[index].sizeThatFits(ProposedViewSize(width: cellWidth, height: nil))
                rowHeight = max(rowHeight, size.height)
            }
            heights.append(rowHeight)
            start = end
        }
        return heights
    }

    private func idealWidth(subviews: Subviews, cols: Int) -> CGFloat {
        var widest: CGFloat = 0
        for subview in subviews {
            widest = max(widest, subview.sizeThatFits(.unspecified).width)
        }
        return widest * CGFloat(cols) + spacing * CGFloat(cols - 1)
    }
}

/// Stat tiles in equal columns. `columns` is the most per row; the grid
/// drops columns whenever a cell would be narrower than `minCellWidth`
/// (scaled with Dynamic Type), so inside a 20 pt card on a phone 3 is the
/// practical maximum and 4 tiles become 2 x 2. One column from AX3.
/// Fill it with `ForgeStatTile`s.
struct ForgeStatGrid<Content: View>: View {
    var columns: Int = 3
    var minCellWidth: CGFloat = ForgeLayout.statMinCellWidth
    var spacing: CGFloat = ForgeLayout.tileGap
    @ViewBuilder var content: () -> Content

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .headline) private var typeScale: CGFloat = 1

    var body: some View {
        ForgeEqualColumnsLayout(
            columns: typeSize >= .accessibility3 ? 1 : max(1, columns),
            spacing: spacing,
            minCellWidth: minCellWidth * max(1, typeScale)
        ) {
            content()
        }
        .environment(\.forgeFillsCell, true)
    }
}

// MARK: - Adaptive stack

/// An HStack that becomes a leading VStack at accessibility sizes, or at
/// `threshold`. Use it for a title with a trailing pill, a sentence with
/// numbers, or a pair of buttons.
struct ForgeAdaptiveStack<Content: View>: View {
    var spacing: CGFloat = FDS.Spacing.sm
    var alignment: VerticalAlignment = .center
    var threshold: DynamicTypeSize = .accessibility1
    @ViewBuilder var content: () -> Content

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize >= threshold
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
            : AnyLayout(HStackLayout(alignment: alignment, spacing: spacing))
        layout {
            content()
        }
    }
}

// MARK: - Flow layout

/// Wrapping chip layout. Unlike the older `FlowLayout`, a chip wider than the
/// row is offered the row's width, so it shrinks or truncates inside the
/// card instead of running off the screen. Static chips use the defaults
/// (Home's chip row: 6 and 6). Groups of `ForgeChipButton` pass
/// `lineSpacing: ForgeLayout.interactiveChipLineGap`.
struct ForgeFlowLayout: Layout {
    var spacing: CGFloat = ForgeLayout.chipGap
    var lineSpacing: CGFloat = ForgeLayout.chipGap
    var alignment: HorizontalAlignment = .leading

    private struct FlowRow {
        var indices: [Int] = []
        var sizes: [CGSize] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let limit = proposal.width ?? .infinity
        let rows = makeRows(limit: limit, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(0, rows.count - 1))
        let widest = rows.map(\.width).max() ?? 0
        return CGSize(width: limit.isFinite ? limit : widest, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = makeRows(limit: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX + leadingOffset(rowWidth: row.width, available: bounds.width)
            for (slot, index) in row.indices.enumerated() {
                let size = row.sizes[slot]
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: size.width, height: size.height)
                )
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private func leadingOffset(rowWidth: CGFloat, available: CGFloat) -> CGFloat {
        let free = max(0, available - rowWidth)
        if alignment == .center { return free / 2 }
        if alignment == .trailing { return free }
        return 0
    }

    private func makeRows(limit: CGFloat, subviews: Subviews) -> [FlowRow] {
        var rows: [FlowRow] = []
        var current = FlowRow()
        for index in subviews.indices {
            var size = subviews[index].sizeThatFits(.unspecified)
            if limit.isFinite, size.width > limit {
                size = subviews[index].sizeThatFits(ProposedViewSize(width: limit, height: nil))
                size.width = min(size.width, limit)
            }
            if !current.indices.isEmpty, limit.isFinite, current.width + spacing + size.width > limit {
                rows.append(current)
                current = FlowRow()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
            current.sizes.append(size)
        }
        if !current.indices.isEmpty {
            rows.append(current)
        }
        return rows
    }
}

// MARK: - Interactive chip

/// `ForgeChip` as a toggle or filter button. The capsule stays 30 pt tall and
/// the tap area is 44 pt (`forgeTapOutset`), so lay groups out in
/// `ForgeFlowLayout(lineSpacing: ForgeLayout.interactiveChipLineGap)`.
/// Pass `fillsWidth` when the chip sits in an equal-width cell, so the
/// capsule (not just the tap area) fills the cell.
struct ForgeChipButton: View {
    var label: String
    var icon: String? = nil
    var energy: Color = HudChrome.emberSteel
    var selected: Bool = false
    var fillsWidth: Bool = false
    var action: () -> Void

    var body: some View {
        Button {
            FDS.haptic(.select)
            action()
        } label: {
            ForgeChip(label: label, icon: icon, energy: energy, selected: selected, fillsWidth: fillsWidth)
                .forgeTapOutset(vertical: ForgeLayout.chipTapOutset)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Rating scale cell

/// One step of a rating scale (RPE, pain, severity, a 1 to 10 feedback
/// question). Lay 6 to 10 steps out in `ForgeEqualColumnsLayout(columns: 5,
/// spacing: FDS.Spacing.sm)`, which gives one or two even rows of 44 pt
/// cells. Use `ForgeSegmentedControl` only for 4 or fewer labelled steps.
struct ForgeScaleCell: View {
    var title: String
    var selected: Bool
    var tint: Color = .ember
    var accessibilityLabel: String? = nil
    var action: () -> Void

    var body: some View {
        Button {
            FDS.haptic(.select)
            action()
        } label: {
            Text(title)
                .font(HomeType.label)
                .monospacedDigit()
                .foregroundStyle(selected ? tint : Color.textSecondary)
                .forgeSingleLine(minScale: ForgeLayout.labelMinScale)
                .padding(.horizontal, FDS.Spacing.xs)
                .frame(maxWidth: .infinity, minHeight: ForgeUX.minTap)
                .background(
                    RoundedRectangle(cornerRadius: FDS.Radius.sm, style: .continuous)
                        .fill(selected ? tint.opacity(0.16) : Color.white.opacity(0.045))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: FDS.Radius.sm, style: .continuous)
                        .stroke(selected ? tint.opacity(0.32) : Color.white.opacity(0.08), lineWidth: ForgeUX.hairline)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel ?? title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Segmented control

struct ForgeSegmentOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var icon: String? = nil

    var id: Value { value }
}

/// The app's one segmented control. Four options or fewer render as
/// equal-width segments in a track; the track is measured at
/// widest-label x count, so if any label would not fit it becomes an
/// edge-bleed scrolling rail that keeps the selection in view. Five or more
/// options always use the rail. Every segment has a 44 pt hit area.
/// Selection is a tinted thumb (accent 0.16 / 0.32), never a glow. Pass
/// `animatesSelection: false` when the binding drives paging or another
/// animated container (Sleep's TabView).
struct ForgeSegmentedControl<Value: Hashable>: View {
    let options: [ForgeSegmentOption<Value>]
    @Binding var selection: Value
    var accent: Color
    var bleed: CGFloat
    var animatesSelection: Bool

    @Namespace private var thumb
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        _ options: [ForgeSegmentOption<Value>],
        selection: Binding<Value>,
        accent: Color = .ember,
        bleed: CGFloat = ForgeLayout.screenInset,
        animatesSelection: Bool = true
    ) {
        self.options = options
        self._selection = selection
        self.accent = accent
        self.bleed = bleed
        self.animatesSelection = animatesSelection
    }

    var body: some View {
        Group {
            if options.count <= 4 {
                ViewThatFits(in: .horizontal) {
                    track
                    rail
                }
            } else {
                rail
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var track: some View {
        ForgeEqualColumnsLayout(columns: max(1, options.count), spacing: FDS.Spacing.xs) {
            ForEach(options) { option in
                segment(option, inTrack: true)
            }
        }
        .padding(.horizontal, FDS.Spacing.xs)
        .background(Capsule().fill(Color.white.opacity(0.04)))
        .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: ForgeUX.stroke))
    }

    private var rail: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: FDS.Spacing.sm) {
                    ForEach(options) { option in
                        segment(option, inTrack: false)
                    }
                }
                .padding(.horizontal, bleed)
            }
            .padding(.horizontal, -bleed)
            .onAppear { proxy.scrollTo(selection, anchor: .center) }
            .onChange(of: selection) { _, value in
                if reduceMotion {
                    proxy.scrollTo(value, anchor: .center)
                } else {
                    withAnimation(FDS.Spring.standard) { proxy.scrollTo(value, anchor: .center) }
                }
            }
        }
    }

    private func select(_ value: Value) {
        if reduceMotion || !animatesSelection {
            selection = value
        } else {
            withAnimation(FDS.Spring.snap) { selection = value }
        }
    }

    private func segment(_ option: ForgeSegmentOption<Value>, inTrack: Bool) -> some View {
        let isOn = option.value == selection
        return Button {
            guard !isOn else { return }
            FDS.haptic(.select)
            select(option.value)
        } label: {
            HStack(spacing: 6) {
                if let icon = option.icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isOn ? accent : Color.textTertiary)
                        .accessibilityHidden(true)
                }
                Text(option.title)
                    .font(HomeType.label)
                    .foregroundStyle(isOn ? Color.textPrimary : Color.textSecondary)
                    .forgeSingleLine(minScale: ForgeLayout.labelMinScale)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: inTrack ? CGFloat.infinity : nil, minHeight: 36)
            .background {
                if isOn {
                    Capsule()
                        .fill(accent.opacity(0.16))
                        .overlay(Capsule().stroke(accent.opacity(0.32), lineWidth: ForgeUX.hairline))
                        .matchedGeometryEffect(id: inTrack ? "track" : "rail", in: thumb)
                } else if !inTrack {
                    Capsule()
                        .fill(Color.white.opacity(0.04))
                        .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: ForgeUX.stroke))
                }
            }
            .padding(.vertical, FDS.Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(option.value)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - Sheet header

/// The top of a sheet: title and optional subtitle on the leading side, and a
/// 44 pt close button on the trailing side (`ux.sheetClose: trailing`). Put it
/// first in the sheet's padded stack, and pair the sheet with
/// `.presentationDragIndicator(.visible)`. Do not add it to a sheet that
/// already has a NavigationStack toolbar close; keep that one instead.
struct ForgeSheetHeader: View {
    var title: String
    var subtitle: String? = nil
    var closeLabel: String = "Close"
    var onClose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: FDS.Spacing.md) {
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text(title)
                    .font(ForgeType.title)
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(HomeType.body)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                FDS.haptic(.press)
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white.opacity(0.08)))
                    .frame(width: ForgeUX.minTap, height: ForgeUX.minTap)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(closeLabel)
        }
    }
}

// MARK: - In-card states

/// Empty state inside a card, from the Home recipe: a status title over a body
/// line. The copy stays warm and never blames the user.
struct ForgeEmptyNote: View {
    var title: String
    var message: String? = nil
    var systemImage: String? = nil
    var tint: Color = .textTertiary

    var body: some View {
        HStack(alignment: .top, spacing: ForgeLayout.rowGap) {
            if let systemImage {
                ForgeIconWell(systemImage: systemImage, tint: tint)
            }
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text(title)
                    .font(HomeType.status)
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let message, !message.isEmpty {
                    Text(message)
                        .font(HomeType.body)
                        .foregroundStyle(Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Loading state inside a card: the header stays and the body becomes a calm
/// well. It uses a minimum height, so the line can grow with Dynamic Type.
struct ForgeSkeletonWell: View {
    var message: String
    var minHeight: CGFloat = 72

    var body: some View {
        Text(message)
            .font(HomeType.body)
            .foregroundStyle(Color.textTertiary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(ForgeLayout.tilePadding)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .background(
                RoundedRectangle(cornerRadius: ForgeLayout.innerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .accessibilityLabel(message)
    }
}

/// A bulleted sentence. The bullet sits on the text's first baseline.
struct ForgeBulletRow: View {
    var text: String
    var tint: Color = .textTertiary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: FDS.Spacing.sm) {
            Text("\u{2022}")
                .font(HomeType.body)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(text)
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

/// Capsule progress bar, clamped to 0...1 so it can never run past its track.
/// Callers add the accessibility label; the value is announced as a percent.
struct ForgeProgressBar: View {
    var fraction: Double
    var tint: Color = .ember
    var height: CGFloat = 6

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clamped: Double {
        guard fraction.isFinite else { return 0 }
        return min(1, max(0, fraction))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(tint)
                    .frame(width: geo.size.width * CGFloat(clamped))
            }
        }
        .frame(height: height)
        .animation(reduceMotion ? nil : FDS.Spring.standard, value: clamped)
        .accessibilityElement()
        .accessibilityValue("\(Int((clamped * 100).rounded())) percent")
    }
}

// MARK: - Press feedback

/// Press feedback for primary CTAs and card-sized buttons: a 0.98 scale on
/// `FDS.Spring.snap`, and none under Reduce Motion.
struct ForgePressStyle: ButtonStyle {
    var scale: CGFloat = 0.98

    func makeBody(configuration: Configuration) -> some View {
        ForgePressBody(configuration: configuration, scale: scale)
    }
}

private struct ForgePressBody: View {
    let configuration: ButtonStyleConfiguration
    let scale: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .animation(reduceMotion ? nil : FDS.Spring.snap, value: configuration.isPressed)
    }
}
