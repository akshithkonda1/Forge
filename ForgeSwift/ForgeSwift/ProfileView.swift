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

/// Pure snapshot for the You header so tests can check the glance copy
/// without mounting SwiftUI.
enum YouContextGlance {
    struct Snapshot: Equatable {
        var name: String
        var coachingStyle: String
        var personality: String
        var voice: String
        var goals: [String]
        var healthConnected: Bool
        var medicineShared: Bool
        var medicineCount: Int
        var cycleShared: Bool
        var lifeContextOn: Bool
        var units: String
    }

    static func subtitle(_ snap: Snapshot) -> String {
        "How Forge behaves toward you"
    }

    static func sharingLine(_ snap: Snapshot) -> String {
        let parts = [
            snap.healthConnected ? "Health on" : "Health off",
            snap.medicineShared
                ? (snap.medicineCount == 1 ? "1 medicine shared" : "\(snap.medicineCount) medicines shared")
                : "Medicine private",
            snap.cycleShared ? "Cycle shared" : "Cycle private",
            snap.lifeContextOn ? "Life context on" : "Life context off",
        ]
        return parts.joined(separator: " · ")
    }

    static func goalsLine(_ snap: Snapshot) -> String {
        snap.goals.isEmpty ? "No goals yet" : snap.goals.joined(separator: ", ")
    }
}

/// Context-at-a-glance header for You: identity plus how Forge should behave.
/// Workout stats and readiness live on Progress and Home.
struct ProfileHeroHeader: View {
    @EnvironmentObject var store: AppStore
    var onEdit: () -> Void
    var onShare: () -> Void

    @ObservedObject private var soul = AriaSoulStore.shared
    @ObservedObject private var voiceProfiles = AriaVoiceProfileStore.shared
    @ObservedObject private var cycleStore = MenstrualHealthStore.shared
    @ObservedObject private var messages = MessageContextStore.shared
    @ObservedObject private var reminders = RemindersManager.shared
    @ScaledMetric(relativeTo: .largeTitle) private var avatarSize: CGFloat = 92

    private var profile: UserProfile { store.userProfile }

    private var displayName: String {
        let trimmed = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "You" : trimmed
    }

    var glance: YouContextGlance.Snapshot {
        YouContextGlance.Snapshot(
            name: displayName,
            coachingStyle: profile.coachingStyle.label,
            personality: soul.config.blend.dominant.label,
            voice: voiceProfiles.selectedLabel,
            goals: profile.fitnessGoals.map(\.label),
            healthConnected: store.healthKitLive,
            medicineShared: MedicationPharmacy.shareWithAria,
            medicineCount: MedicationPharmacy.savedNames().count,
            cycleShared: cycleStore.settings.shareWithAria,
            lifeContextOn: reminders.isEnabled || messages.settings.messagesEnabled,
            units: profile.measurementSystem.label
        )
    }

    var body: some View {
        glancePlate
            .frame(maxWidth: .infinity)
    }

    private var glancePlate: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.heroGap) {
            identity
            contextChips
            sharingWell
            actions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeContentCard()
        .accessibilityElement(children: .contain)
    }

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

                Text(YouContextGlance.subtitle(glance))
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .forgeWrapping()
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
                        .font(ForgeType.micro)
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

    private var contextChips: some View {
        ForgeFlowLayout(alignment: .center) {
            ForgeChip(label: glance.coachingStyle, icon: profile.coachingStyle.icon)
            ForgeChip(label: glance.personality, icon: "face.smiling")
            ForgeChip(label: glance.voice, icon: "waveform")
            ForgeChip(label: glance.units, icon: "ruler")
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Coaching \(glance.coachingStyle), \(glance.personality), \(glance.voice), \(glance.units) units")
    }

    private var sharingWell: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
            Text("Shared with ARIA")
                .font(HomeType.micro)
                .foregroundStyle(Color.textTertiary)
            Text(YouContextGlance.sharingLine(glance))
                .font(HomeType.body)
                .foregroundStyle(Color.textPrimary)
                .forgeWrapping()
            Text(YouContextGlance.goalsLine(glance))
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeWell()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(YouContextGlance.sharingLine(glance)). Goals: \(YouContextGlance.goalsLine(glance))")
    }

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
