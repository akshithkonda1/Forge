import SwiftUI
import ForgeCore

/// Voice capture surface. Deliberately *non-modal* in feel: it rises from the
/// bottom over a light scrim so the conversation stays visible and the user
/// never loses their place. The orb animates only while ARIA listens or
/// speaks, and sits still under Reduce Motion.
struct VoiceOrbOverlay: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject var speech:  SpeechManager
    let mood:         ARIAMood
    @Binding var isShowing:      Bool
    let onRecognized: (String) -> Void
    let onCancel:     () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var orbDiameter: CGFloat = 160

    private var accent: Color { orbAccent(speech.voiceState) }

    private var orbSize: CGFloat { ForgeLayout.scaledCap(orbDiameter, base: 160) }

    /// Listening or speaking are the only live states.
    private var orbIsLive: Bool {
        switch speech.voiceState {
        case .listening, .speaking: return true
        default: return false
        }
    }

    private var hasTranscript: Bool {
        !speech.recognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var panelShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: FDS.Radius.xxl,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: FDS.Radius.xxl,
            style: .continuous
        )
    }

    // MARK: Pieces

    private var scrim: some View {
        Color.black.opacity(0.52)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { onCancel() }
            .accessibilityLabel("Dismiss voice input")
            .accessibilityAddTraits(.isButton)
    }

    private var grabber: some View {
        Capsule()
            .fill(Color.white.opacity(0.22))
            .frame(width: 38, height: 4)
            .frame(maxWidth: .infinity, minHeight: ForgeUX.minTap / 2)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 12).onEnded { value in
                    if value.translation.height > 60 { onCancel() }
                }
            )
            .accessibilityHidden(true)
    }

    private var orb: some View {
        AuroraOrbView(
            state:     speech.voiceState.orbState,
            amplitude: max(speech.amplitude, 0.35),
            mood:      mood,
            size:      orbSize,
            followPresence: true
        )
        .environment(\.forgeMinimalAnimation, reduceMotion || !orbIsLive)
        .frame(height: orbSize + FDS.Spacing.lg)
        .contentShape(Circle())
        .onTapGesture { handleOrbTap() }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(speech.voiceState.label)
        .accessibilityHint(speech.voiceState.sublabel)
    }

    private var stateLabels: some View {
        VStack(spacing: ForgeLayout.pairGap) {
            Text(speech.voiceState.label)
                .font(HomeType.cta)
                .foregroundStyle(accent)
                .multilineTextAlignment(.center)
                .forgeWrapping()
                .id(speech.voiceState.label)
                .transition(.opacity)
                .animation(reduceMotion ? nil : FDS.Spring.standard, value: speech.voiceState.label)

            Text(speech.voiceState.sublabel)
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .forgeWrapping()

            if speech.authorizationDenied {
                ForgeSecondaryButton(title: "Open Settings", icon: "gearshape", accent: .textSecondary) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .padding(.top, ForgeLayout.tileGap)
                .accessibilityLabel("Open Settings to allow microphone and speech access")
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var transcript: some View {
        if !speech.recognizedText.isEmpty {
            Text("\"\(speech.recognizedText)\"")
                .font(HomeType.body)
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .transition(.opacity)
                .animation(reduceMotion ? nil : FDS.Spring.standard, value: speech.recognizedText)
        }
    }

    /// Mute, Cancel and Send. Cancel is always reachable; Send appears once
    /// there is text. Falls back to a stack when the row cannot fit.
    @ViewBuilder
    private var actionButtons: some View {
        AriaSpokenMuteButton()

        ForgeSecondaryButton(title: "Cancel", icon: "xmark", accent: .textSecondary, action: onCancel)
            .accessibilityLabel("Cancel voice input")

        if hasTranscript {
            ForgePrimaryButton(title: "Send", icon: "arrow.up", accent: .ember) {
                speech.stopListening(submit: true)
            }
            .accessibilityLabel("Send what I said")
            .transition(.opacity)
        }
    }

    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: ForgeLayout.rowGap) { actionButtons }
            VStack(spacing: ForgeLayout.tileGap) { actionButtons }
        }
        .animation(reduceMotion ? nil : FDS.Spring.snap, value: hasTranscript)
    }

    private var panel: some View {
        VStack(spacing: ForgeLayout.blockGap) {
            grabber
            orb
            stateLabels
            transcript
            actions
        }
        .padding(.horizontal, ForgeLayout.screenInset)
        .padding(.bottom, ForgeLayout.sectionGap)
        .frame(maxWidth: .infinity)
        .background {
            panelShape
                .fill(Color.surfaceElevated)
                .ignoresSafeArea(edges: .bottom)
        }
        .overlay {
            panelShape.stroke(Color.white.opacity(0.08), lineWidth: ForgeUX.hairline)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { onCancel() }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            scrim
            panel
        }
        .onChange(of: speech.voiceState) { _, state in
            if case .idle = state, !speech.recognizedText.isEmpty {
                onRecognized(speech.recognizedText)
            }
        }
    }

    /// The orb copy promises "Tap to speak" / "Tap to interrupt" / "Try
    /// again" — this is that tap.
    private func handleOrbTap() {
        switch speech.voiceState {
        case .idle, .error:
            // Start the way ChatView's mic entry does. A live session that
            // failed or closed is still marked active, and `start` would only
            // resume it — end it first so the retry really reconnects.
            speech.conversationalMood = mood
            let session = AriaVoiceSession.shared
            if session.activeTransport?.requiresNetwork == true {
                session.stop()
            }
            session.start(store: store, speech: speech)
        case .speaking:
            AriaPresence.shared.stopSpeaking()
            AriaVoiceSession.shared.markListening()
        case .listening, .processing:
            break
        }
    }

    /// ARIA accents come from the shared tokens: neutral at rest, ember while
    /// listening or speaking, steel while thinking.
    private func orbAccent(_ state: VoiceState) -> Color {
        switch state {
        case .idle:       return .textSecondary
        case .listening:  return .ember
        case .processing: return .steel
        case .speaking:   return .ember
        case .error:      return .danger
        }
    }
}
