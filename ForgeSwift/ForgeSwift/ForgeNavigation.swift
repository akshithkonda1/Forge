import SwiftUI

// MARK: - Primary destinations
//
// Single catalog of every user-facing surface. Used by the bottom nav,
// Settings "Explore" grid, and deep-link helpers so nothing is orphaned.

enum ForgePrimaryDestination: String, CaseIterable, Identifiable {
    case home
    case workout
    case lifestyle
    case chat
    case sleep
    case progress
    case profile
    case cycleHealth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .workout: return "Workout"
        case .chat: return "ARIA"
        case .lifestyle: return "Lifestyle"
        case .sleep: return "Sleep"
        case .progress: return "Progress"
        case .profile: return "Profile"
        case .cycleHealth: return "Cycle Health"
        }
    }

    var subtitle: String {
        switch self {
        case .home: return "Readiness, brief, next action"
        case .workout: return "Today’s session & training"
        case .chat: return "Talk to ARIA"
        case .lifestyle: return "Nutrition, meals, wellbeing"
        case .sleep: return "Sleep, alarms, wind-down"
        case .progress: return "History, PRs, streaks"
        case .profile: return "Account & settings"
        case .cycleHealth: return "Phase, predictions, partner"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .workout: return "dumbbell.fill"
        case .chat: return "sparkles"
        case .lifestyle: return "leaf.fill"
        case .sleep: return "moon.stars.fill"
        case .progress: return "chart.line.uptrend.xyaxis"
        case .profile: return "person.crop.circle.fill"
        case .cycleHealth: return "heart.circle.fill"
        }
    }

    var accent: Color {
        switch self {
        case .home: return .ember
        case .workout: return Color(hex: "F97316")
        case .chat: return Color(hex: "38BDF8")
        case .lifestyle: return Color(hex: "22C55E")
        case .sleep: return Color(hex: "A855F7")
        case .progress: return Color(hex: "3B82F6")
        case .profile: return .steel
        case .cycleHealth: return Color(hex: "EC4899")
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
        }
    }
}

extension AppStore {
    /// Routes to any primary surface. Cycle Health is hosted on the main shell.
    func openDestination(_ destination: ForgePrimaryDestination, lifestyleSegment: String? = nil) {
        switch destination {
        case .cycleHealth:
            openCycleHealth(pane: "me")
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

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.textSecondary)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.top, 12)
        .accessibilityElement(children: .combine)
    }
}

/// Premium empty state for tabs that have no data yet.
struct ForgeEmptyStateCard: View {
    let icon: String
    let title: String
    let message: String
    var accent: Color = .ember
    var cta: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.14))
                    .frame(width: 72, height: 72)
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(accent)
            }
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.textPrimary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let cta, let action {
                Button(action: action) {
                    Text(cta)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: [accent, accent.opacity(0.75)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .forgeGlassCard(accent: accent)
    }
}

// MARK: - Explore grid (Settings → all pages)

struct ForgeExploreDestinationsGrid: View {
    @EnvironmentObject var store: AppStore

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(ForgePrimaryDestination.allCases) { dest in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    store.openDestination(dest)
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(dest.accent.opacity(0.14))
                                .frame(width: 40, height: 40)
                            Image(systemName: dest.systemImage)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(dest.accent)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dest.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.textPrimary)
                                .lineLimit(1)
                            Text(dest.subtitle)
                                .font(.system(size: 11))
                                .foregroundColor(.textTertiary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(Color.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.borderColor.opacity(0.45), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(dest.title)")
                .accessibilityHint(dest.subtitle)
            }
        }
    }
}
