import SwiftUI
import ForgeCore

/// Inline, learn-by-doing coach. Sits on the real shell — never a modal that
/// blocks. Skip is always on screen. Ghost hand is a still pose (no loop).
struct ForgeTutorialCoach: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject private var ariaService = AriaService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var appeared = false

    private var state: ForgeTutorial.State { store.mosaicTutorial }
    private var beat: ForgeTutorial.Beat { state.beat }

    var body: some View {
        if !state.isComplete {
            VStack {
                HStack(alignment: .top, spacing: FDS.Spacing.sm) {
                    ghostHand
                    VStack(alignment: .leading, spacing: FDS.Spacing.xs) {
                        Text(coachLine)
                            .font(HomeType.body)
                            .foregroundStyle(Color.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isStaticText)
                        if beat.target == .acknowledge {
                            Button("Got it") {
                                store.recordTutorial(.acknowledge)
                            }
                            .font(HomeType.label)
                            .foregroundStyle(Color.background)
                            .padding(.horizontal, FDS.Spacing.md)
                            .padding(.vertical, FDS.Spacing.sm)
                            .background(Color.paper)
                            .clipShape(Capsule())
                            .accessibilityHint(beat.voiceOverHint)
                        }
                    }
                    Spacer(minLength: 0)
                    Button(ForgeTutorialSkip.label) {
                        store.recordTutorial(.skip)
                    }
                    .font(HomeType.label)
                    .foregroundStyle(Color.textSecondary)
                    .frame(minWidth: ForgeUX.minTap, minHeight: ForgeUX.minTap)
                    .accessibilityLabel("Skip tutorial")
                    .accessibilityHint("Leaves the Health tutorial. You can replay it in Settings.")
                }
                .padding(FDS.Spacing.md)
                .background {
                    RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous)
                        .fill(Color.surfaceElevated)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous)
                        .strokeBorder(
                            state.winPulse > 0 ? Color.paper.opacity(0.45) : Color.borderHairline,
                            lineWidth: 0.5
                        )
                }
                .opacity(appeared || reduceMotion ? 1 : 0)
                Spacer()
            }
            .padding(.horizontal, HomeMetrics.inset)
            .padding(.top, FDS.Spacing.sm)
            .allowsHitTesting(true)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Health tutorial. \(beat.prompt). \(beat.voiceOverHint)")
            .onAppear {
                if reduceMotion {
                    appeared = true
                } else {
                    withAnimation(ForgeMotion.gentle) { appeared = true }
                }
                store.noteTutorialBeatAppeared()
            }
            .onChange(of: beat) { _, _ in
                appeared = reduceMotion
                if !reduceMotion {
                    withAnimation(ForgeMotion.gentle) { appeared = true }
                }
                store.noteTutorialBeatAppeared()
            }
            .onChange(of: state.winPulse) { _, _ in
                ForgeHaptics.play(beat == .done ? .success : .selection)
            }
        }
    }

    @ViewBuilder
    private var ghostHand: some View {
        if voiceOver {
            EmptyView()
        } else {
            Image(systemName: beat.target == .none ? "checkmark" : "hand.point.up.left.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.paper.opacity(0.9))
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)
        }
    }

    private var coachLine: String {
        if state.ariaPaused || ariaService.lastRemoteError == AriaPaused.line {
            return ForgeTutorial.pausedLine
        }
        if state.rehint { return rehintLine }
        return beat.prompt(opening: state.opening)
    }

    private var rehintLine: String {
        switch beat {
        case .home: return "Home is this screen. Got it when you've looked."
        case .sleep: return "Sleep is the moon tab."
        case .seeHistory: return "Progress is the tab with the chart. One tap."
        case .personalIndex: return "Any tile works. Title, then the number — that's yours."
        case .train: return "Train is the dumbbell tab."
        case .askAria: return "The Ask ARIA button sits under the tiles."
        case .hobbyFit, .lifestyle: return "Lifestyle is the leaf tab."
        case .trainingModel, .settings: return "You is the person tab — Settings lives there."
        case .watchWidgets: return "Skip if you don't use Watch or widgets."
        case .mosaicWin: return "Tap the tile itself — that's the first win."
        default: return beat.prompt(opening: state.opening)
        }
    }
}

enum ForgeTutorialSkip {
    static let label = "Skip"
}
