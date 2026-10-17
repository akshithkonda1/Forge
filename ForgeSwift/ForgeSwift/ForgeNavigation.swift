import SwiftUI
import ForgeCore

// MARK: - Primary destinations
//
// Single catalog of every user-facing surface. Used by the bottom nav,
// Settings "Explore" grid, and deep-link helpers so nothing is orphaned.

enum ForgePrimaryDestination: String, CaseIterable, Identifiable {
    case home
    case workout
    case chat
    case lifestyle
    case sleep
    case progress
    case profile
    case cycleHealth
    case hydration

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .workout: return "Train"
        case .chat: return "ARIA"
        case .lifestyle: return "Lifestyle"
        case .sleep: return "Sleep"
        case .progress: return "Progress"
        case .profile: return "Profile"
        case .cycleHealth: return "Cycle Health"
        case .hydration: return "Hydration"
        }
    }

    var subtitle: String {
        switch self {
        case .home: return "Readiness, brief, next action"
        case .workout: return "Today’s session — scaled to how you showed up"
        case .chat: return "Talk to ARIA"
        case .lifestyle: return "Nutrition, meals, wellbeing"
        case .sleep: return "Sleep, alarms, wind-down"
        case .progress: return "History, PRs, streaks"
        case .profile: return "Account & settings"
        case .cycleHealth: return "Phase, predictions, partner"
        case .hydration: return "Water, pace, Apple Health"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .workout: return "dumbbell.fill"
        case .chat: return "bubble.left"
        case .lifestyle: return "leaf.fill"
        case .sleep: return "moon.stars.fill"
        case .progress: return "chart.line.uptrend.xyaxis"
        case .profile: return "person.crop.circle.fill"
        case .cycleHealth: return "heart.circle.fill"
        case .hydration: return "drop.fill"
        }
    }

    var accent: Color {
        switch self {
        case .home: return .ember
        case .workout: return .ember
        case .chat: return .aurora
        case .lifestyle: return Color.vitality
        case .sleep: return .steel
        case .progress: return .aurora
        case .profile: return .steel
        case .cycleHealth: return Color(hex: "EC4899")
        case .hydration: return Color.steel
        }
    }

    /// Bottom-nav tabs only (Cycle opens as a cover from Home/shell).
    var tabItem: TabItem? {
        switch self {
        case .home: return .home
        case .workout: return .workout
        case .chat: return .chat
        case .lifestyle: return .lifestyle
        case .sleep: return .sleep
        case .progress: return .progress
        case .profile: return .profile
        case .cycleHealth: return nil
        case .hydration: return nil
        }
    }
}

/// Resolves My cycle vs Support so Home, Settings, and deep links open the
/// same pane the entry tile is describing — instead of always forcing `.me`.
enum CycleHealthLaunch {
    enum Pane: String, Equatable {
        case me
        case partner
    }

    static func pane(
        requested: String?,
        selfTrackingEnabled: Bool,
        hasConsentedPeople: Bool,
        defaultToSupport: Bool
    ) -> Pane {
        switch requested?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "partner", "support":
            return .partner
        case "me", "self":
            return .me
        default:
            if !selfTrackingEnabled && (defaultToSupport || hasConsentedPeople) {
                return .partner
            }
            return .me
        }
    }
}

extension AppStore {
    /// Routes to any primary surface. Cycle Health is hosted on the main shell.
    func openDestination(_ destination: ForgePrimaryDestination, lifestyleSegment: String? = nil) {
        switch destination {
        case .cycleHealth:
            openCycleHealth()
        case .hydration:
            openHydration()
        case .lifestyle:
            if let lifestyleSegment {
                pendingLifestyleSegment = lifestyleSegment
            }
            activeTab = .lifestyle
        default:
            if let tab = destination.tabItem {
                activeTab = tab
            }
        }
    }
}

// MARK: - Shared page chrome

/// Consistent top-of-page title block used across primary tabs.
struct ForgePageHeader: View {
    let title: String
    var subtitle: String? = nil
    var accent: Color = .ember
    var trailing: AnyView? = nil

    init(
        title: String,
        subtitle: String? = nil,
        accent: Color = .ember,
        @ViewBuilder trailing: () -> some View = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.accent = accent
        self.trailing = AnyView(trailing())
    }

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: FDS.Spacing.md))
            : AnyLayout(HStackLayout(alignment: .center, spacing: FDS.Spacing.md))
        layout {
            VStack(alignment: .leading, spacing: FDS.Spacing.xs) {
                Text(title)
                    .font(ForgeType.pageTitle)
                    .foregroundColor(.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(ForgeLayout.labelMinScale)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(ForgeType.body)
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.top, ForgeLayout.screenTop)
        .accessibilityElement(children: .contain)
    }
}

/// Circular icon control used in page headers (Ask ARIA, share, hydrate).
///
/// `tinted` (default) is for domain actions (hydrate, share). Pass
/// `tinted: false` for back, close and preferences: Home's neutral header
/// control (white 0.06 fill, 0.10 stroke, textSecondary glyph). No idle glow.
struct ForgeIconButton: View {
    let systemImage: String
    var accent: Color = .ember
    var accessibilityLabel: String? = nil
    var tinted: Bool = true
    var action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: ForgeUX.icon, weight: .semibold))
                .foregroundStyle(tinted ? accent : Color.textSecondary)
                .frame(width: ForgeUX.minTap, height: ForgeUX.minTap)
                .background(tinted ? accent.opacity(0.14) : Color.white.opacity(0.06))
                .clipShape(Circle())
                .overlay(
                    Circle().stroke(
                        tinted ? accent.opacity(0.28) : Color.white.opacity(0.10),
                        lineWidth: ForgeUX.stroke
                    )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel ?? systemImage)
    }
}

/// The one primary CTA per screen, built on the Home hero recipe: solid fill,
/// radius md, chevron, a light impact on touch-down and a 0.98 press. The fill is ember; `accent: .steel` gives the steel
/// fill for recovery and Sleep. Any other accent still renders ember: white
/// text on amber, vitality, aurora or a phase color fails contrast, and the
/// primary must read as one recognisable control. Domain color belongs on
/// the hero plate's energy, not the CTA. Place it at the bottom of the hero.
struct ForgePrimaryButton: View {
    let title: String
    var icon: String? = nil
    var accent: Color = .ember
    var subtitle: String? = nil
    var action: () -> Void

    private var usesSteel: Bool { accent == Color.steel }
    private var fill: LinearGradient { usesSteel ? FDS.Gradient.steel : FDS.Gradient.ember }

    var body: some View {
        Button(action: action) {
            HStack(spacing: FDS.Spacing.md) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: ForgeUX.icon, weight: .semibold))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(HomeType.cta)
                        .lineLimit(1)
                        .minimumScaleFactor(ForgeLayout.labelMinScale)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(HomeType.micro)
                            .foregroundStyle(Color.white.opacity(0.85))
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: FDS.Spacing.sm)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .accessibilityHidden(true)
            }
            .foregroundColor(.white)
            .padding(.vertical, FDS.Spacing.md)
            .padding(.horizontal, FDS.Spacing.lg)
            .frame(maxWidth: .infinity, minHeight: ForgeUX.minTap + 8, alignment: .leading)
            .background { fill }
            .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
        }
        .buttonStyle(ForgePressStyle(pressHaptic: true))
        .accessibilityLabel(title)
        .accessibilityHint(subtitle ?? "")
    }
}

/// Empty state for tabs that have no data yet: serif title, one sentence, one CTA.
struct ForgeEmptyStateCard: View {
    let icon: String
    let title: String
    let message: String
    var accent: Color = .ember
    var cta: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: ForgeLayout.blockGap) {
            ForgeIconWell(systemImage: icon, tint: accent, diameter: 36)
            ForgeMosaicStrip(
                lit: Array(repeating: false, count: ForgeMosaicTracks.count),
                energy: accent,
                size: 28
            )
            VStack(spacing: ForgeLayout.pairGap) {
                // Empty states speak in the editorial voice: a calm serif line,
                // then one plain sentence. The unlit mosaic is the same picture.
                Text(title)
                    .font(ForgeFont.serif(.title2))
                    .foregroundColor(.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .font(ForgeType.body)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let cta, let action {
                ForgePrimaryButton(title: cta, accent: accent, action: action)
                    .padding(.top, FDS.Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .forgeContentCard()
    }
}

// MARK: - Explore grid (Settings → all pages)

struct ForgeExploreDestinationsGrid: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Two columns, one at accessibility sizes. Equal-height rows.
    private var columnCount: Int { typeSize.isAccessibilitySize ? 1 : 2 }

    var body: some View {
        ForgeEqualColumnsLayout(columns: columnCount, spacing: ForgeLayout.tileGap) {
            ForEach(ForgePrimaryDestination.allCases) { dest in
                tile(for: dest)
            }
        }
    }

    private func tile(for dest: ForgePrimaryDestination) -> some View {
        Button {
            store.openDestination(dest)
        } label: {
            tileLabel(for: dest)
        }
        .buttonStyle(ForgePressStyle())
        .accessibilityLabel("Open \(dest.title)")
        .accessibilityHint(dest.subtitle)
    }

    private func tileLabel(for dest: ForgePrimaryDestination) -> some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.sm) {
            ForgeIconWell(systemImage: dest.systemImage, tint: dest.accent)
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text(dest.title)
                    .font(HomeType.status)
                    .foregroundColor(.textPrimary)
                    .forgeSingleLine(minScale: ForgeLayout.labelMinScale)
                Text(dest.subtitle)
                    .font(HomeType.body)
                    .foregroundColor(.textTertiary)
                    .multilineTextAlignment(.leading)
                    .forgeWrapping()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .forgeContentCard(tint: dest.accent, padding: ForgeLayout.tilePadding)
        .contentShape(Rectangle())
    }
}
