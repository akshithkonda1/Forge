import SwiftUI
import UIKit
import ForgeCore

struct ProfileTabView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        // Progress + Lifestyle live on bottom tabs; Profile is account + settings.
        SettingsPageView()
            .forgeScreenBackground(accent: .steel)
            .onAppear {
                // Legacy deep links: Progress / Lifestyle sub-tabs now map to root tabs.
                if let pending = store.pendingProfileSubTab {
                    switch pending.lowercased() {
                    case "progress":
                        store.activeTab = .progress
                    case "lifestyle":
                        store.activeTab = .lifestyle
                    default:
                        break
                    }
                    store.pendingProfileSubTab = nil
                }
            }
    }
}

/// The identity anchor for the Profile tab: one readiness-tinted hero plate
/// (avatar, name, coaching identity, today's readiness, lifetime stats and
/// quick actions), then the Lifetime link card.
/// Replaces the old profile card that was buried beneath the Settings title.
struct ProfileHeroHeader: View {
    @EnvironmentObject var store: AppStore
    var onEdit: () -> Void
    var onShare: () -> Void

    @ObservedObject private var lifestyle = LifestyleViewModel.shared
    @ScaledMetric(relativeTo: .title3) private var readinessRingSize: CGFloat = 72
    @ScaledMetric(relativeTo: .largeTitle) private var avatarSize: CGFloat = 92

    private var profile: UserProfile { store.userProfile }
    private var totalWorkouts: Int { store.workoutHistory.count }
    private var totalPRs: Int { store.personalRecords.count }
    private var totalVolume: Int { store.workoutHistory.reduce(0) { $0 + $1.volume } }

    private var volumeCompact: String {
        let v = Double(totalVolume)
        if v >= 1_000_000 { return String(format: "%.1fM", v / 1_000_000) }
        if v >= 1_000 { return String(format: "%.0fk", v / 1_000) }
        return String(totalVolume)
    }

    private var displayName: String {
        let trimmed = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Your Profile" : trimmed
    }

    private var hasReadiness: Bool { store.readiness.hasScore }
    private var readinessScore: Int { hasReadiness ? store.readiness.overall : 0 }
    private var heroEnergy: Color { ForgeProgressChrome.energy(for: readinessScore) }

    private var readinessWord: String {
        hasReadiness ? HomeReadiness.label(store.readiness.overall) : "Not measured yet"
    }

    private var trend: AppStore.ReadinessTrend { store.readinessTrend }

    private var trendLabel: String {
        switch trend {
        case .improving: return "Trending up"
        case .declining: return "Easing off"
        case .stable:    return "Holding"
        }
    }

    private var trendColor: Color {
        switch trend {
        case .improving: return .vitality
        case .declining: return ForgeProgressChrome.miss
        case .stable:    return .textSecondary
        }
    }

    var body: some View {
        VStack(spacing: ForgeLayout.sectionGap) {
            heroPlate
            lifetimeStrip
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Hero plate

    private var heroPlate: some View {
        VStack(spacing: ForgeLayout.heroGap) {
            identity
            readinessWell
            statGrid
            actions
        }
        .frame(maxWidth: .infinity)
        .forgeContentCard()
        .accessibilityElement(children: .contain)
    }

    // MARK: Avatar + name + identity chips

    private var identity: some View {
        VStack(spacing: ForgeLayout.rowGap) {
            avatarButton

            VStack(spacing: FDS.Spacing.sm) {
                Text(displayName)
                    .font(ForgeType.pageTitle)
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)

                ForgeFlowLayout(alignment: .center) {
                    ForgeChip(label: profile.experienceLevel.label, icon: "chart.bar.fill")
                    ForgeChip(label: profile.coachingStyle.label, icon: profile.coachingStyle.icon)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var avatarButton: some View {
        let size = ForgeLayout.scaledCap(avatarSize, base: 92, maxGrowth: 1.25)
        return Button(action: { ForgeHaptics.play(.press); onEdit() }) {
            ZStack(alignment: .bottomTrailing) {
                ProfileAvatarView(
                    fileName: profile.avatarFileName,
                    initials: profile.initials,
                    size: size
                )
                ZStack {
                    Circle().fill(Color.background).frame(width: 30, height: 30)
                    Circle().fill(Color.ember).frame(width: 26, height: 26)
                    Image(systemName: profile.avatarFileName == nil ? "camera.fill" : "pencil")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.white)
                }
                .offset(x: 3, y: 3)
            }
            .padding(FDS.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(profile.avatarFileName == nil ? "Add profile photo" : "Edit profile")
    }

    // MARK: Lifetime stats

    private func statValue(_ count: Int) -> String {
        count > 0 ? "\(count)" : "\u{2014}"
    }

    private var statGrid: some View {
        ForgeStatGrid(columns: 4) {
            ForgeStatTile(
                label: "Days trained",
                value: statValue(store.currentStreak),
                energy: .ember,
                icon: "checkmark.circle.fill"
            )
            ForgeStatTile(
                label: "Workouts",
                value: statValue(totalWorkouts),
                energy: .ember,
                icon: "figure.strengthtraining.traditional"
            )
            ForgeStatTile(
                label: "PRs",
                value: statValue(totalPRs),
                energy: .ember,
                icon: "trophy.fill"
            )
            ForgeStatTile(
                label: "Lbs lifted",
                value: totalVolume > 0 ? volumeCompact : "\u{2014}",
                energy: .ember,
                icon: "scalemass.fill"
            )
        }
    }

    // MARK: Lifetime — aging + metabolic one-liners

    private var lifetimeAging: AgingSnapshot {
        let sexFemale: Bool?
        switch profile.biologicalSex {
        case .female: sexFemale = true
        case .male: sexFemale = false
        default: sexFemale = nil
        }
        return AgingBridge.snapshot(
            age: profile.age,
            sexFemale: sexFemale,
            stats: HealthKitManager.shared.todayStats
        )
    }

    private var lifetimeMetabolic: MetabolicHealthSnapshot {
        lifestyle.metabolicSnapshot
    }

    private var lifetimeOpenAccessory: some View {
        HStack(spacing: FDS.Spacing.xs) {
            Text("Open")
                .font(HomeType.label)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(Color.vitality)
    }

    @ViewBuilder
    private var lifetimeStrip: some View {
        let heart = lifetimeAging.oneBreathLine
        let metabolic = lifetimeMetabolic.storyLine
        if heart.isEmpty && metabolic.isEmpty {
            EmptyView()
        } else {
            Button {
                store.pendingLifestyleSegment = "lifetime"
                store.activeTab = .lifestyle
            } label: {
                VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
                    ForgeCardHeader(title: "Lifetime", tint: .textTertiary) {
                        lifetimeOpenAccessory
                    }
                    VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                        if !heart.isEmpty {
                            Text(heart)
                                .font(HomeType.status)
                                .foregroundStyle(Color.textPrimary)
                                .multilineTextAlignment(.leading)
                                .forgeWrapping()
                        }
                        if !metabolic.isEmpty {
                            Text(metabolic)
                                .font(HomeType.body)
                                .foregroundStyle(Color.textSecondary)
                                .multilineTextAlignment(.leading)
                                .forgeWrapping()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .forgeContentCard(accent: .vitality)
            }
            .buttonStyle(ForgePressStyle())
            .accessibilityLabel([heart, metabolic].filter { !$0.isEmpty }.joined(separator: ". "))
            .accessibilityHint("Opens Lifestyle Lifetime")
        }
    }

    // MARK: Readiness

    private var readinessRing: some View {
        ForgeProgressRing(
            progress: readinessScore,
            energy: heroEnergy,
            size: ForgeLayout.scaledCap(readinessRingSize, base: 72),
            stroke: ForgeProgressChrome.compactStroke
        ) {
            Text(hasReadiness ? "\(store.readiness.overall)" : "\u{2014}")
                .font(HomeType.metric)
                .foregroundStyle(Color.textPrimary)
                .forgeGlanceText()
                .contentTransition(.numericText())
        }
    }

    private var readinessText: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
            Text("Readiness today")
                .font(HomeType.micro)
                .foregroundStyle(Color.textTertiary)
            Text(readinessWord)
                .font(HomeType.status)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)
            if hasReadiness {
                ForgeVibeChip(label: trendLabel, energy: trendColor)
                    .padding(.top, ForgeLayout.pairGap)
            }
        }
    }

    private var readinessWell: some View {
        ForgeAdaptiveStack(spacing: ForgeLayout.rowGap) {
            readinessRing
            readinessText
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeWell()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(hasReadiness
            ? "Readiness today \(store.readiness.overall) out of 100, \(readinessWord), \(trendLabel)"
            : "Readiness today not measured yet")
    }

    // MARK: Quick actions

    private var actions: some View {
        ForgeAdaptiveStack(spacing: ForgeLayout.tileGap) {
            ForgeSecondaryButton(title: "Edit profile", icon: "square.and.pencil", accent: .ember) {
                onEdit()
            }
            ForgeSecondaryButton(title: "Share", icon: "square.and.arrow.up", accent: .steel) {
                onShare()
            }
        }
    }
}
