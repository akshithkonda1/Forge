import SwiftUI
import ForgeCore

// MARK: - Voice Coach Bar (replaces CoachBarView)

struct VoiceCoachBar: View {
    @Bindable var coach: VoiceCoachManager
    private let presence = AriaPresence.shared

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showTranscript = false
    @State private var transcriptText = ""

    /// The line currently on show, if it has any text worth expanding.
    private var expandableText: String? {
        if coach.isListening && !coach.transcribedText.isEmpty { return coach.transcribedText }
        if coach.isThinking { return nil }
        if !coach.lastCoachMessage.isEmpty { return coach.lastCoachMessage }
        return nil
    }

    private func openTranscript() {
        guard let text = expandableText else { return }
        transcriptText = text
        showTranscript = true
    }

    @ViewBuilder
    private var messageText: some View {
        if coach.isListening && !coach.transcribedText.isEmpty {
            // Live transcription
            Text(coach.transcribedText)
                .font(HomeType.body)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
        } else if coach.isThinking {
            HStack(spacing: FDS.Spacing.sm) {
                ProgressView().controlSize(.mini)
                Text("ARIA is thinking…")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if !coach.lastCoachMessage.isEmpty {
            Text(coach.lastCoachMessage)
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
                .id(coach.lastCoachMessage)
        } else if !coach.isVoiceEnabled {
            Text("Voice is muted")
                .font(HomeType.body)
                .foregroundStyle(Color.textTertiary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("Tap the mic and ask ARIA")
                .font(HomeType.body)
                .foregroundStyle(Color.textTertiary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var messageArea: some View {
        messageText
            .contentShape(Rectangle())
            .onTapGesture { openTranscript() }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(expandableText == nil ? [] : .isButton)
            .accessibilityHint(expandableText == nil ? "" : "Opens the full message")
    }

    var body: some View {
        HStack(spacing: ForgeLayout.rowGap) {
            // Forge avatar with live state indicator
            ForgeAvatarView(
                isSpeaking: presence.isSpeaking,
                isThinking: coach.isThinking,
                isListening: coach.isListening
            )

            messageArea
                .layoutPriority(1)

            AriaTrainMuteButton(coach: coach)
            MicButton(coach: coach)
        }
        .padding(.horizontal, ForgeLayout.compactCardPadding)
        .padding(.vertical, FDS.Spacing.sm)
        .frame(minHeight: 56)
        .forgeInsetTile(radius: FDS.Radius.md)
        .overlay {
            if coach.isListening {
                RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous)
                    .stroke(Color.ember.opacity(0.6), lineWidth: 1.5)
            }
        }
        .animation(reduceMotion ? nil : ForgeMotion.smooth, value: coach.isListening)
        .animation(reduceMotion ? nil : ForgeMotion.smooth, value: coach.lastCoachMessage)
        .sheet(isPresented: $showTranscript) {
            VoiceCoachTranscriptSheet(message: transcriptText)
        }
    }
}

/// The full coach line, opened from the bar. Presentation only.
private struct VoiceCoachTranscriptSheet: View {
    let message: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ForgeLayout.sectionGap) {
                ForgeSheetHeader(title: "ARIA", onClose: { dismiss() })
                Text(message)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .forgeScreenInsets(top: FDS.Spacing.lg)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.surfaceElevated)
    }
}

// MARK: - Forge Avatar

struct ForgeAvatarView: View {
    let isSpeaking: Bool
    let isThinking: Bool
    let isListening: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var ringColor: Color {
        if isListening { return .ember }
        if isSpeaking { return .steel }
        return .clear
    }

    private var isActive: Bool { isSpeaking || isListening }

    private var stateLabel: String {
        if isListening { return "ARIA is listening" }
        if isThinking { return "ARIA is thinking" }
        if isSpeaking { return "ARIA is speaking" }
        return "ARIA"
    }

    /// The pulse is an event state: it runs only while ARIA listens or
    /// speaks, and never under Reduce Motion.
    private func syncPulse() {
        if isActive && !reduceMotion {
            pulse = false
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: false)) {
                pulse = true
            }
        } else {
            withAnimation(nil) { pulse = false }
        }
    }

    var body: some View {
        ZStack {
            // Pulse ring when speaking or listening
            if isActive && !reduceMotion {
                Circle()
                    .stroke(ringColor.opacity(0.4), lineWidth: 2)
                    .frame(width: 48, height: 48)
                    .scaleEffect(pulse ? 1.3 : 1.0)
                    .opacity(pulse ? 0 : 0.8)
            }

            Circle()
                .fill(Color.ember.opacity(0.12))
                .frame(width: 36, height: 36)

            if isThinking {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.mini)
                    .tint(.ember)
            } else {
                Image(systemName: "waveform")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.ember)
                    .symbolEffect(.variableColor.iterative, isActive: isSpeaking && !reduceMotion)
            }
        }
        .frame(width: 36, height: 36)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stateLabel)
        .onAppear { syncPulse() }
        .onChange(of: isSpeaking) { _, _ in syncPulse() }
        .onChange(of: isListening) { _, _ in syncPulse() }
    }
}

// MARK: - Mic Button

struct MicButton: View {
    @Bindable var coach: VoiceCoachManager
    private let presence = AriaPresence.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: handleTap) {
            ZStack {
                Circle()
                    .fill(micBackground)
                    .frame(width: ForgeUX.minTap, height: ForgeUX.minTap)

                Image(systemName: micIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(micIconColor)
            }
            .contentShape(Circle())
        }
        .buttonStyle(ForgePressStyle())
        .disabled(!coach.isVoiceEnabled || coach.isThinking)
        .animation(reduceMotion ? nil : ForgeMotion.smooth, value: coach.isListening)
        .accessibilityLabel(coach.isListening ? "Stop listening" : "Ask ARIA")
        .accessibilityHint(coach.isListening ? "Stops voice input" : "Starts voice input")
    }

    var micBackground: Color {
        if coach.isListening { return .ember }
        if coach.isThinking { return Color.surfaceElevated }
        return Color.surface
    }

    var micIcon: String {
        if coach.isListening { return "stop.fill" }
        if presence.isSpeaking { return "speaker.wave.2.fill" }
        return "mic.fill"
    }

    var micIconColor: Color {
        if coach.isListening { return .white }
        if coach.isThinking { return Color.textTertiary }
        return Color.textSecondary
    }

    func handleTap() {
        ForgeHaptics.play(.press)

        if coach.isListening {
            coach.stopListening()
        } else {
            if presence.isSpeaking {
                coach.interruptSpeech()
            }
            coach.startListening()
        }
    }
}

/// Mute ARIA's spoken voice on every surface that talks: welcome, onboarding,
/// chat, Train. One UserDefaults flag so mute actually sticks. The glyph is
/// 36 pt; the tap target around it is 44 pt at every call site. Muted is a
/// quiet state, not an error, so it takes no red.
struct AriaSpokenMuteButton: View {
    @AppStorage(AriaSpokenMute.mutedKey) private var muted = true
    var coach: VoiceCoachManager? = nil

    var body: some View {
        Button(action: toggle) {
            Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(muted ? Color.textSecondary : Color.textPrimary)
                .frame(width: 36, height: 36)
                .forgeInsetTile(radius: FDS.Radius.sm)
                .frame(width: ForgeUX.minTap, height: ForgeUX.minTap)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(muted ? "Unmute ARIA voice" : "Mute ARIA voice")
        .accessibilityValue(muted ? "Muted" : "On")
        .accessibilityHint("Turns ARIA's spoken voice on or off")
    }

    private func toggle() {
        ForgeHaptics.play(.selection)
        muted.toggle()
        AriaSpokenMute.isMuted = muted
        if let coach {
            coach.setVoiceEnabled(!muted)
        }
        if muted {
            AriaPresence.shared.stopSpeaking()
            AriaVoiceSession.shared.mute()
        } else if AriaVoiceSession.shared.isActive {
            AriaVoiceSession.shared.unmute()
        }
    }
}

/// Train screens keep this name so existing call sites stay readable.
typealias AriaTrainMuteButton = AriaSpokenMuteButton
