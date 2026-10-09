import SwiftUI
import ForgeCore

struct ChatHeaderView: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject private var ariaService = AriaService.shared
    let mood:              ARIAMood
    var onAvatarLongPress: (() -> Void)? = nil
    @State private var appeared     = false

    private var scoreColor: Color {
        HomeReadiness.color(store.readiness.overall)
    }

    var body: some View {
            HStack(spacing: FDS.Spacing.md) {
            ARIAIdentityMark(state: .idle, mood: mood, size: 44, amplitude: 0.2)
            .onLongPressGesture(minimumDuration: 0.45) {
                choreographedHaptic(.reactionAdded)
                onAvatarLongPress?()
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: FDS.Spacing.sm) {
                    Text("ARIA")
                        .font(ForgeType.title)
                        .foregroundColor(.textPrimary)
                        .tracking(ForgeType.tracking(.title))
                    if store.lastCoachWorkers.count > 1 {
                        Text("· " + store.lastCoachWorkers.map(\.kind.label).joined(separator: " + "))
                            .font(FDS.TypeScale.Dynamic.caption)
                            .foregroundColor(store.lastRoutedCoachAgent.accent)
                            .lineLimit(1)
                    } else if store.lastRoutedCoachAgent != .aria {
                        Text("· \(store.lastRoutedCoachAgent.label)")
                            .font(FDS.TypeScale.Dynamic.caption)
                            .foregroundColor(store.lastRoutedCoachAgent.accent)
                    } else {
                        Text("your coaches")
                            .font(FDS.TypeScale.Dynamic.micro)
                            .foregroundColor(.textTertiary)
                    }
                }

                HStack(spacing: FDS.Spacing.xs) {
                    if ariaService.isTestReady || AriaOperatingMode.current.isDummy {
                        Image(systemName: "checkmark.seal")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(Color(hex: "A9D8FF"))
                        Text("Dummy · tune without AI")
                            .font(FDS.TypeScale.Dynamic.micro)
                            .foregroundColor(Color(hex: "A9D8FF").opacity(0.92))
                    } else if let remoteError = ariaService.lastRemoteError {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(Color.danger)
                        Text(remoteError)
                            .font(FDS.TypeScale.Dynamic.micro)
                            .foregroundColor(Color.danger.opacity(0.9))
                            .lineLimit(1)
                    } else if ariaService.isLocalFallback {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(Color.ember)
                        Text("On this phone")
                            .font(FDS.TypeScale.Dynamic.micro)
                            .foregroundColor(Color.ember.opacity(0.8))
                    } else {
                        Circle().fill(ForgePalette.amber).frame(width: 5, height: 5)
                        Text(headerStatusLine)
                            .font(FDS.TypeScale.Dynamic.micro)
                            .foregroundColor(.textSecondary)
                    }
                }
                .animation(FDS.Spring.standard, value: ariaService.isLocalFallback)
                .animation(FDS.Spring.standard, value: ariaService.lastRemoteError)
            }

            Spacer()

            if store.isInAriaFirstBond {
                Button {
                    store.skipAriaFirstBond()
                } label: {
                    Text(AriaFirstBond.skipLabel)
                        .font(FDS.TypeScale.Dynamic.caption)
                        .foregroundColor(.textTertiary)
                        .padding(.horizontal, FDS.Spacing.md)
                        .padding(.vertical, FDS.Spacing.sm)
                        .background(Color.white.opacity(0.05))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(Color(hex: "7EC8FF").opacity(0.28), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Skip tutorial")
                .accessibilityHint("Ends the first conversation with ARIA. You can talk anytime.")
            }

            AriaSpokenMuteButton()

            VStack(spacing: 2) {
                ZStack {
                    Circle()
                        .trim(from: 0, to: CGFloat(store.readiness.overall) / 100.0)
                        .stroke(
                            AngularGradient(
                                colors: [scoreColor, scoreColor.opacity(0.3)],
                                center: .center,
                                startAngle: .degrees(-90),
                                endAngle: .degrees(270)
                            ),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 38, height: 38)
                    Circle()
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                        .frame(width: 38, height: 38)
                    Text("\(store.readiness.overall)")
                        .font(FDS.TypeScale.Dynamic.body.weight(.semibold))
                        .monospacedDigit()
                        .foregroundColor(.textPrimary)
                }
                .shadow(color: scoreColor.opacity(0.42), radius: 8)
            }
        }
        .padding(.horizontal, FDS.Spacing.lg)
        .padding(.vertical, FDS.Spacing.md)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(Color.background.opacity(0.3))
                LinearGradient(
                    colors: [mood.accentColor.opacity(0.04), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        }
        .overlay(
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [mood.accentColor.opacity(0.2), Color.white.opacity(0.06), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 0.5),
            alignment: .bottom
        )
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -10)
        .onAppear { withAnimation(FDS.Spring.hero.delay(0.05)) { appeared = true } }
    }

    private var headerStatusLine: String {
        let first = store.userProfile.name.components(separatedBy: " ").first ?? ""
        let score = store.readiness.overall
        if first.isEmpty {
            return score < 55 ? "Easy day — I’m here" : "Ready when you are"
        }
        if score < 55 { return "\(first), let’s keep it easy" }
        if score >= 85 { return "You look ready, \(first)" }
        return "Here for you, \(first)"
    }
}
