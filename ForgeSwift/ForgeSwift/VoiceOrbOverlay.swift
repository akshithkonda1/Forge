import SwiftUI

/// Voice capture surface. Deliberately *non-modal*: it rises from the bottom
/// over a light scrim so the conversation stays visible and the user never
/// loses their place. The orb still gets a hero entrance and live amplitude —
/// premium, but no longer the whole screen.
struct VoiceOrbOverlay: View {
    @ObservedObject var speech:  SpeechManager
    let mood:         ARIAMood
    @Binding var isShowing:      Bool
    let onRecognized: (String) -> Void
    let onCancel:     () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var orbRevealed:    Bool   = false
    @State private var contentOpacity: Double = 0

    private var accent: Color { orbAccent(speech.voiceState) }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.52)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onCancel() }
                .accessibilityLabel("Dismiss voice input")
                .accessibilityAddTraits(.isButton)

            VStack(spacing: 0) {
                // Grab affordance
                Capsule()
                    .fill(Color.white.opacity(0.22))
                    .frame(width: 38, height: 4)
                    .padding(.top, 10)
                    .padding(.bottom, 18)

                ZStack {
                    if !reduceMotion {
                        RadialGradient(
                            colors: [
                                mood.accentColor.opacity(0.28),
                                Color(hex: "7B61FF").opacity(0.08),
                                .clear
                            ],
                            center: .center, startRadius: 16, endRadius: 170
                        )
                        .frame(width: 340, height: 340)
                        .blur(radius: 22)
                        .animation(.easeInOut(duration: 1.1), value: speech.voiceState.label)
                    }

                    AriaPortraitView(size: 148)
                        .scaleEffect(orbRevealed ? 1.0 : 0.7)
                        .opacity(orbRevealed ? 1 : 0)
                }
                .frame(height: 176)

                // State labels
                VStack(spacing: 6) {
                    Text(speech.voiceState.label)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(LinearGradient(
                            colors: [accent, .white.opacity(0.85)],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .shadow(color: accent.opacity(0.5), radius: 10)
                        .id(speech.voiceState.label)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 6)),
                            removal:   .opacity.combined(with: .offset(y: -6))
                        ))
                        .animation(FDS.Spring.standard, value: speech.voiceState.label)

                    Text(speech.voiceState.sublabel)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }
                .opacity(contentOpacity)
                .padding(.top, 4)

                // Live transcript
                if !speech.recognizedText.isEmpty {
                    Text("\"\(speech.recognizedText)\"")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white.opacity(0.82))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 28)
                        .padding(.top, 16)
                        .transition(.opacity.combined(with: .offset(y: 6)))
                        .animation(FDS.Spring.standard, value: speech.recognizedText)
                }

                // Actions — cancel always reachable, send-now when there's text.
                HStack(spacing: 12) {
                    Button(action: onCancel) {
                        HStack(spacing: 7) {
                            Image(systemName: "xmark").font(.system(size: 14, weight: .semibold))
                            Text("Cancel").font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundColor(.white.opacity(0.82))
                        .padding(.horizontal, 22).padding(.vertical, 13)
                        .background(Capsule().fill(Color.white.opacity(0.10)))
                        .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .accessibilityLabel("Cancel voice input")

                    if !speech.recognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button { speech.stopListening(submit: true) } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "arrow.up").font(.system(size: 14, weight: .bold))
                                Text("Send").font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 24).padding(.vertical, 13)
                            .background(Capsule().fill(
                                LinearGradient(colors: [accent, accent.opacity(0.7)],
                                               startPoint: .leading, endPoint: .trailing)
                            ))
                            .shadow(color: accent.opacity(0.35), radius: 12, y: 4)
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityLabel("Send what I said")
                    }
                }
                .opacity(contentOpacity)
                .padding(.top, 22)
                .padding(.bottom, 26)
                .animation(FDS.Spring.snap, value: speech.recognizedText.isEmpty)
            }
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    Rectangle().fill(Color.background.opacity(0.55))
                    LinearGradient(
                        colors: [mood.accentColor.opacity(0.10), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                }
            )
            .cornerRadius(28, corners: [.topLeft, .topRight])
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [accent.opacity(0.45), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(height: 1)
            }
            .shadow(color: .black.opacity(0.4), radius: 24, y: -6)
            .ignoresSafeArea(edges: .bottom)
            .offset(y: orbRevealed ? 0 : 40)
        }
        .onChange(of: speech.voiceState) { _, state in
            if case .idle = state, !speech.recognizedText.isEmpty {
                onRecognized(speech.recognizedText)
            }
        }
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : FDS.Spring.fluid) {
                orbRevealed = true
                contentOpacity = 1
            }
        }
    }

    private func orbAccent(_ state: VoiceState) -> Color {
        switch state {
        case .idle:       return Color(hex: "00D2FF")
        case .listening:  return Color.ember
        case .processing: return Color(hex: "A855F7")
        case .speaking:   return Color(hex: "22C55E")
        case .error:      return Color(hex: "EF4444")
        }
    }
}
