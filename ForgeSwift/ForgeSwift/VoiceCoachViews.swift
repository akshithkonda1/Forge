import SwiftUI

// MARK: - Voice Coach Bar (replaces CoachBarView)

struct VoiceCoachBar: View {
    @Bindable var coach: VoiceCoachManager
    private let presence = AriaPresence.shared

    var body: some View {
        VStack(spacing: 0) {
            // Message area
            HStack(spacing: 12) {
                // Forge avatar with live state indicator
                ForgeAvatarView(
                    isSpeaking: presence.isSpeaking,
                    isThinking: coach.isThinking,
                    isListening: coach.isListening
                )
                
                // Text content
                VStack(alignment: .leading, spacing: 4) {
                    if coach.isListening && !coach.transcribedText.isEmpty {
                        // Show live transcription
                        Text(coach.transcribedText)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                            .lineSpacing(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.opacity)
                    } else if coach.isThinking {
                        ThinkingDotsView()
                    } else if !coach.lastCoachMessage.isEmpty {
                        Text(coach.lastCoachMessage)
                            .font(.system(size: 13))
                            .foregroundColor(.textSecondary)
                            .lineSpacing(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .move(edge: .top).combined(with: .opacity)
                            ))
                            .id(coach.lastCoachMessage)
                    } else if !coach.isVoiceEnabled {
                        Text("Voice is muted")
                            .font(.system(size: 13))
                            .foregroundColor(.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("Tap the mic and ask ARIA")
                            .font(.system(size: 13))
                            .foregroundColor(.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                
                AriaTrainMuteButton(coach: coach)
                MicButton(coach: coach)
            }
            .padding(16)
            .background(Color.surfaceElevated)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        coach.isListening ? Color.ember.opacity(0.6) : Color.borderColor,
                        lineWidth: coach.isListening ? 1.5 : 1
                    )
            )
            .animation(.easeInOut(duration: 0.3), value: coach.isListening)
            .animation(.easeInOut(duration: 0.4), value: coach.lastCoachMessage)
        }
    }
}

// MARK: - Forge Avatar

struct ForgeAvatarView: View {
    let isSpeaking: Bool
    let isThinking: Bool
    let isListening: Bool
    
    @State private var speakPulse = false
    @State private var listenPulse = false
    
    var ringColor: Color {
        if isListening { return .ember }
        if isSpeaking { return .steel }
        return .clear
    }
    
    var body: some View {
        ZStack {
            // Pulse ring when speaking or listening
            if isSpeaking || isListening {
                Circle()
                    .stroke(ringColor.opacity(0.4), lineWidth: 2)
                    .frame(width: 48, height: 48)
                    .scaleEffect(speakPulse ? 1.3 : 1.0)
                    .opacity(speakPulse ? 0 : 0.8)
            }
            
            Circle()
                .fill(Color.ember.opacity(0.12))
                .frame(width: 36, height: 36)
            
            if isThinking {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .ember))
                    .scaleEffect(0.7)
            } else {
                Image(systemName: "waveform")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.ember)
                    .symbolEffect(.variableColor.iterative, isActive: isSpeaking)
            }
        }
        .frame(width: 36, height: 36)
        .onChange(of: isSpeaking) { _, speaking in
            if speaking {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: false)) {
                    speakPulse = true
                }
            } else {
                speakPulse = false
            }
        }
        .onChange(of: isListening) { _, listening in
            if listening {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: false)) {
                    listenPulse = true
                }
            } else {
                listenPulse = false
            }
        }
    }
}

// MARK: - Mic Button

struct MicButton: View {
    @Bindable var coach: VoiceCoachManager
    private let presence = AriaPresence.shared
    @State private var isPressed = false
    
    var body: some View {
        Button(action: handleTap) {
            ZStack {
                Circle()
                    .fill(micBackground)
                    .frame(width: 44, height: 44)
                    .scaleEffect(isPressed ? 0.92 : 1.0)
                    .shadow(
                        color: coach.isListening ? Color.ember.opacity(0.5) : Color.clear,
                        radius: 12
                    )
                
                Image(systemName: micIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(micIconColor)
            }
        }
        .buttonStyle(.plain)
        .disabled(!coach.isVoiceEnabled || coach.isThinking)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: coach.isListening)
        .onLongPressGesture(minimumDuration: 0, pressing: { pressing in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                isPressed = pressing
            }
        }, perform: {})
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
        if coach.isThinking { return .textMuted }
        return .textSecondary
    }
    
    func handleTap() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
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

// MARK: - Thinking Dots

struct ThinkingDotsView: View {
    @State private var phase = 0
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Color.ember)
                    .frame(width: 6, height: 6)
                    .scaleEffect(phase == i ? 1.3 : 0.8)
                    .opacity(phase == i ? 1.0 : 0.4)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.4).repeatForever(autoreverses: false)) {
                // Driven by timer below
            }
            Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.3)) {
                    phase = (phase + 1) % 3
                }
            }
        }
    }
}

// MARK: - Voice Toggle Button

struct VoiceToggleButton: View {
    @Bindable var coach: VoiceCoachManager

    var body: some View {
        AriaTrainMuteButton(coach: coach)
    }
}

/// Mute ARIA's spoken voice on every surface that talks: welcome, onboarding,
/// chat, Train. One UserDefaults flag so mute actually sticks.
struct AriaSpokenMuteButton: View {
    @AppStorage(AriaSpokenMute.mutedKey) private var muted = true
    var coach: VoiceCoachManager? = nil

    var body: some View {
        Button(action: toggle) {
            Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(muted ? .danger : .textSecondary)
                .frame(width: 36, height: 36)
                .background(Color.surfaceElevated)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(muted ? Color.danger.opacity(0.4) : Color.borderColor.opacity(0.45), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(muted ? "Unmute ARIA voice" : "Mute ARIA voice")
        .accessibilityValue(muted ? "Muted" : "On")
        .accessibilityHint("Turns ARIA's spoken voice on or off")
    }

    private func toggle() {
        FDS.haptic(.light)
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
