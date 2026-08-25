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

/// The identity anchor for the Profile tab: avatar, name, coaching identity,
/// a signature lifetime-stat band, today's readiness, and quick actions.
/// Replaces the old profile card that was buried beneath the Settings title.
struct ProfileHeroHeader: View {
    @EnvironmentObject var store: AppStore
    var onEdit: () -> Void
    var onShare: () -> Void

    @State private var appeared = false
    @State private var glow = false

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

    private var readinessWord: String {
        switch store.readiness.overall {
        case 85...:   return "Primed"
        case 70..<85: return "Ready"
        case 55..<70: return "Steady"
        default:      return "Recover"
        }
    }

    private var trend: AppStore.ReadinessTrend { store.readinessTrend }

    private var trendSymbol: String {
        switch trend {
        case .improving: return "arrow.up.right"
        case .declining: return "arrow.down.right"
        case .stable:    return "equal"
        }
    }

    private var trendLabel: String {
        switch trend {
        case .improving: return "Trending up"
        case .declining: return "Easing off"
        case .stable:    return "Holding"
        }
    }

    private var trendColor: Color {
        switch trend {
        case .improving: return .success
        case .declining: return .danger
        case .stable:    return .textSecondary
        }
    }

    var body: some View {
        VStack(spacing: FDS.Spacing.lg) {
            identity
            statBand
            readinessStrip
            actions
        }
        .frame(maxWidth: .infinity)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 14)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { appeared = true }
            if !UIAccessibility.isReduceMotionEnabled {
                withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                    glow = true
                }
            }
        }
    }

    // MARK: Avatar + name + identity chips

    private var identity: some View {
        VStack(spacing: FDS.Spacing.md) {
            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [Color.ember.opacity(glow ? 0.34 : 0.16), .clear],
                        center: .center, startRadius: 6, endRadius: 92))
                    .frame(width: 188, height: 188)
                    .blur(radius: 14)

                Button(action: { FDS.haptic(.light); onEdit() }) {
                    ZStack(alignment: .bottomTrailing) {
                        ProfileAvatarView(
                            fileName: profile.avatarFileName,
                            initials: profile.initials,
                            size: 92
                        )
                        ZStack {
                            Circle().fill(Color.background).frame(width: 30, height: 30)
                            Circle().fill(Color.ember).frame(width: 26, height: 26)
                            Image(systemName: profile.avatarFileName == nil ? "camera.fill" : "pencil")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .offset(x: 3, y: 3)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(profile.avatarFileName == nil ? "Add profile photo" : "Edit profile")
            }
            .frame(height: 108)

            VStack(spacing: FDS.Spacing.sm) {
                Text(displayName)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                HStack(spacing: FDS.Spacing.sm) {
                    identityChip(text: profile.experienceLevel.label, icon: "chart.bar.fill", color: .ember)
                    identityChip(text: profile.coachingStyle.label, icon: profile.coachingStyle.icon, color: profile.coachingStyle.color)
                }
            }
        }
    }

    private func identityChip(text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold))
            Text(text).font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundColor(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(color.opacity(0.12)))
        .overlay(Capsule().stroke(color.opacity(0.25), lineWidth: 1))
    }

    // MARK: Signature stat band

    private var statBand: some View {
        HStack(spacing: 0) {
            heroStat(value: "\(store.currentStreak)", label: "Day streak", icon: "flame.fill", tint: .warning)
            statDivider
            heroStat(value: "\(totalWorkouts)", label: "Workouts", icon: "figure.strengthtraining.traditional", tint: .ember)
            statDivider
            heroStat(value: "\(totalPRs)", label: "PRs", icon: "trophy.fill", tint: .steel)
            statDivider
            heroStat(value: volumeCompact, label: "Lbs lifted", icon: "scalemass.fill", tint: .success)
        }
        .padding(.vertical, FDS.Spacing.lg)
        .forgeCard()
    }

    private var statDivider: some View {
        Rectangle().fill(Color.borderColor).frame(width: 1, height: 34)
    }

    private func heroStat(value: String, label: String, icon: String, tint: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundColor(tint)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }

    // MARK: Readiness strip

    private var readinessStrip: some View {
        HStack(spacing: FDS.Spacing.md) {
            ZStack {
                Circle().stroke(Color.borderColor, lineWidth: 5).frame(width: 46, height: 46)
                Circle()
                    .trim(from: 0, to: max(0.02, CGFloat(store.readiness.overall) / 100))
                    .stroke(LinearGradient.emberGradient, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 46, height: 46)
                Text("\(store.readiness.overall)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Readiness today")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.textTertiary)
                Text(readinessWord)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.textPrimary)
            }

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: trendSymbol).font(.system(size: 10, weight: .bold))
                Text(trendLabel).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            }
            .foregroundColor(trendColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(trendColor.opacity(0.12)))
        }
        .padding(FDS.Spacing.lg)
        .forgeCard(accent: .ember)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Readiness today \(store.readiness.overall) out of 100, \(readinessWord), \(trendLabel)")
    }

    // MARK: Quick actions

    private var actions: some View {
        HStack(spacing: FDS.Spacing.md) {
            Button(action: { FDS.haptic(.light); onEdit() }) {
                actionLabel(icon: "square.and.pencil", text: "Edit profile", filled: true)
            }
            .buttonStyle(.plain)

            Button(action: { FDS.haptic(.light); onShare() }) {
                actionLabel(icon: "square.and.arrow.up", text: "Share", filled: false)
            }
            .buttonStyle(.plain)
        }
    }

    private func actionLabel(icon: String, text: String, filled: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold))
            Text(text).font(.system(size: 14, weight: .semibold))
        }
        .foregroundColor(filled ? .white : .ember)
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .background {
            if filled {
                Capsule().fill(LinearGradient.emberGradient)
            } else {
                Capsule().fill(Color.ember.opacity(0.12))
                    .overlay(Capsule().stroke(Color.ember.opacity(0.3), lineWidth: 1))
            }
        }
    }
}
