import SwiftUI
import ForgeCore

struct ChatHeaderView: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject private var ariaService = AriaService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let mood:              ARIAMood
    var onAvatarLongPress: (() -> Void)? = nil
    @ScaledMetric(relativeTo: .caption) private var ringSize: CGFloat = 38

    private var scoreColor: Color {
        store.readiness.hasScore ? HomeReadiness.color(store.readiness.overall) : HudChrome.miss
    }

    var body: some View {
        HStack(spacing: FDS.Spacing.md) {
            avatar

            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text("ARIA")
                    .font(ForgeType.title)
                    .foregroundColor(.textPrimary)
                    .tracking(ForgeType.tracking(.title))
                    .forgeSingleLine(minScale: ForgeLayout.labelMinScale)
                statusRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            AriaSpokenMuteButton()

            readinessRing
        }
        .padding(.horizontal, ForgeLayout.screenInset)
        .padding(.vertical, FDS.Spacing.sm)
        .forgeBarChrome(edge: .top, visible: true)
    }

    // MARK: Avatar

    /// 28 pt still-pose mark inside a 44 pt target. Long-press (or the
    /// VoiceOver action) opens the context inspector.
    private var avatar: some View {
        ARIAIdentityMark(state: .idle, mood: mood, size: 28, amplitude: 0.2)
            .environment(\.forgeMinimalAnimation, true)
            .frame(width: ForgeUX.minTap, height: ForgeUX.minTap)
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.45) {
                ForgeHaptics.play(.selection)
                onAvatarLongPress?()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("ARIA")
            .accessibilityHint("Press and hold to see what ARIA sees")
            .accessibilityAction(named: "What ARIA sees") {
                onAvatarLongPress?()
            }
    }

    // MARK: Status

    /// Coach routing text, or nil when ARIA is answering on its own.
    private var routingText: String? {
        if store.lastCoachWorkers.count > 1 {
            return store.lastCoachWorkers.map(\.kind.label).joined(separator: " + ")
        }
        if store.lastRoutedCoachAgent != .aria {
            return store.lastRoutedCoachAgent.label
        }
        return nil
    }

    /// One row under the title: a status pill, plus Skip during first bond.
    /// Wraps instead of squeezing when the row runs out of width.
    private var statusRow: some View {
        ForgeFlowLayout(spacing: ForgeLayout.chipGap, lineSpacing: ForgeLayout.chipGap) {
            statusPill
            if store.isInAriaFirstBond {
                skipButton
            }
        }
        .animation(reduceMotion ? nil : ForgeMotion.smooth, value: ariaService.isLocalFallback)
        .animation(reduceMotion ? nil : ForgeMotion.smooth, value: ariaService.lastRemoteError)
    }

    @ViewBuilder
    private var statusPill: some View {
        if ariaService.isTestReady || AriaOperatingMode.current.isDummy {
            pill(icon: "checkmark.seal", tint: .steelLight, text: "Dummy · tune without AI")
        } else if let remoteError = ariaService.lastRemoteError {
            pill(icon: "exclamationmark.triangle.fill", tint: .danger, text: remoteError, lines: 2)
        } else if ariaService.isLocalFallback {
            pill(icon: "bolt.fill", tint: .ember, text: "On this phone")
        } else if let routing = routingText {
            pill(icon: nil, tint: store.lastRoutedCoachAgent.accent, text: routing)
        } else {
            pill(icon: nil, tint: .vitality, text: headerStatusLine)
        }
    }

    /// Home's live status pill: 6 pt dot (or glyph), micro text, h9 v5,
    /// white 0.05 fill with a 0.08 edge. No shadow.
    private func pill(icon: String?, tint: Color, text: String, lines: Int = 1) -> some View {
        HStack(spacing: FDS.Spacing.xs) {
            if let icon {
                Image(systemName: icon)
                    .font(HomeType.micro)
                    .foregroundColor(tint)
                    .accessibilityHidden(true)
            } else {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(HomeType.micro)
                .foregroundColor(.textSecondary)
                .lineLimit(lines)
                .minimumScaleFactor(ForgeLayout.labelMinScale)
        }
        .padding(.horizontal, FDS.Spacing.sm)
        .padding(.vertical, FDS.Spacing.xs)
        .background(Color.white.opacity(0.05))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: ForgeUX.hairline))
        .accessibilityElement(children: .combine)
    }

    private var skipButton: some View {
        Button {
            store.skipAriaFirstBond()
        } label: {
            ForgeChip(label: AriaFirstBond.skipLabel)
                .forgeTapOutset(vertical: ForgeLayout.chipTapOutset)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Skip tutorial")
        .accessibilityHint("Ends the first conversation with ARIA. You can talk anytime.")
    }

    // MARK: Readiness ring

    private var ringDiameter: CGFloat {
        ForgeLayout.scaledCap(ringSize, base: 38)
    }

    private var ringFraction: CGFloat {
        CGFloat(min(max(store.readiness.overall, 0), 100)) / 100.0
    }

    private var readinessRing: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: ringFraction)
                .stroke(scoreColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(store.readiness.hasScore ? "\(store.readiness.overall)" : "—")
                .font(HomeType.label)
                .monospacedDigit()
                .foregroundColor(.textPrimary)
                .hudInArcText()
                .padding(FDS.Spacing.xs)
        }
        .frame(width: ringDiameter, height: ringDiameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(store.readiness.hasScore
            ? HomeReadiness.voiceOverLabel(store.readiness.overall)
            : "Readiness not measured yet")
    }

    private var headerStatusLine: String {
        let first = store.userProfile.name.components(separatedBy: " ").first ?? ""
        let score = store.readiness.overall
        // Below Fair (50) is Low. Unmeasured is not low.
        let low = store.readiness.hasScore && score < HomeReadinessTokens.Band.fair.minScore
        if first.isEmpty {
            return low ? "Easy day — I’m here" : "Ready when you are"
        }
        if low { return "\(first), let’s keep it easy" }
        if score >= 85 { return "You look ready, \(first)" }
        return "Here for you, \(first)"
    }
}
