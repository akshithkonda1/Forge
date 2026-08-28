import SwiftUI

/// Makes the multi-specialist routing visible while it's happening, not
/// just afterward in ChatHeaderView's caption. This takes over the UI slot
/// AriaResearchProgress used to occupy between send and reply.
///
/// All workers show "thinking" for the actual duration of the wait, rather
/// than a staggered per-chip reveal: supportingBriefs() runs every
/// non-primary brief() concurrently over synchronous, near-instant local
/// computation, so real per-worker timing would flip every chip to "done"
/// within microseconds of each other. Faking a staggered reveal would be
/// less honest than showing "these specialists are being consulted" for
/// the real wait and then simply resolving to the reply.
struct AriaSpecialistActivityView: View {
    let workers: [AriaCoachWorker]
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(workers.count > 1 ? "Consulting your specialists" : "Thinking")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.aurora)
            FlowLayout(spacing: 8) {
                ForEach(workers) { worker in
                    HStack(spacing: 6) {
                        Image(systemName: worker.kind.icon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(worker.label)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(worker.kind.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(worker.kind.accent.opacity(pulse ? 0.22 : 0.1))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(worker.kind.accent.opacity(0.3), lineWidth: 1))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.aurora.opacity(0.25), lineWidth: 1))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

private struct CoachAgentChipRow: View {
    @EnvironmentObject var store: AppStore

    private var context: AriaCoachAgentRouter.Context {
        AriaCoachAgentRouter.context(pinned: store.pinnedCoachAgent, activeTab: store.activeTab)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                pinChip(nil, title: "Auto", icon: "sparkles")
                // The five modes ARIA tracks, plus Cycle -- reachable here
                // too, still consent-gated, just not one of the five
                // headline modes. Not .allCases: that would also surface a
                // redundant direct pin to .aria, which "Auto" already covers.
                ForEach(AriaCoachAgent.trackedModes + [.cycle]) { agent in
                    if AriaCoachAgentRouter.isAvailable(agent, context: context) {
                        pinChip(agent, title: agent.label, icon: agent.icon)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
        }
        .accessibilityLabel("Personal coaches")
    }

    private func pinChip(_ agent: AriaCoachAgent?, title: String, icon: String) -> some View {
        let selected = store.pinnedCoachAgent == agent
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            store.pinnedCoachAgent = agent
            if let agent { store.lastRoutedCoachAgent = agent }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(selected ? .textPrimary : .textTertiary)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(selected ? Color.white.opacity(0.10) : Color.clear)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct ChatInputAreaView: View {
    @EnvironmentObject var store: AppStore
    @Binding var inputText:        String
    @Binding var isTyping:         Bool
    @FocusState.Binding var isInputFocused: Bool
    @Binding var showQuickActions:  Bool
    let mood:         ARIAMood
    let replyTarget:  ChatMessage?
    let onSend:       (String) -> Void
    let onMicTap:     () -> Void
    @State private var charCount: Int = 0

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespaces).isEmpty && !isTyping
    }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.borderColor.opacity(0.3)).frame(height: 0.5)

            if !store.isInAriaFirstBond {
                CoachAgentChipRow()
            }

            if store.isInAriaFirstBond, !store.lastSuggestedActions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) {
                        ForEach(store.lastSuggestedActions, id: \.self) { label in
                            let yesLike = label.lowercased().hasPrefix("yes")
                            let noLike = label.lowercased().hasPrefix("no")
                            SmartChip(
                                label: label,
                                icon: yesLike ? "checkmark" : (noLike ? "xmark" : "arrow.up.right"),
                                color: yesLike ? Color(hex: "22C55E") : (noLike ? Color(hex: "F43F5E") : mood.accentColor),
                                disabled: isTyping
                            ) {
                                onSend(label)
                                choreographedHaptic(.quickChipTap)
                            }
                        }
                    }
                    .padding(.horizontal, 18).padding(.vertical, 11)
                }
            } else if showQuickActions && !isInputFocused {
                let chips = smartQuickActions(
                    mood:         mood,
                    readiness:    store.readiness.overall,
                    messageCount: store.chatMessages.count
                )
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) {
                        ForEach(Array(chips.enumerated()), id: \.offset) { i, chip in
                            SmartChip(label: chip.label, icon: chip.icon, color: chip.color, disabled: isTyping) {
                                onSend(chip.label)
                                choreographedHaptic(.quickChipTap)
                                withAnimation(.easeOut(duration: 0.22)) { showQuickActions = false }
                            }
                        }
                    }
                    .padding(.horizontal, 18).padding(.vertical, 11)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Input row
            HStack(spacing: 11) {
                // Mic
                Button(action: onMicTap) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [mood.accentColor.opacity(0.18), mood.accentColor.opacity(0.07)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                            .frame(width: 48, height: 48)
                            .overlay(Circle().stroke(mood.accentColor.opacity(0.22), lineWidth: 0.5))
                        Image(systemName: "mic.fill")
                            .font(.system(size: 19))
                            .foregroundColor(mood.accentColor)
                    }
                    .shadow(color: mood.accentColor.opacity(0.28), radius: 9, y: 3)
                }
                .disabled(isTyping)
                .opacity(isTyping ? 0.42 : 1)
                .animation(FDS.Spring.snap, value: isTyping)

                // Text field
                ZStack(alignment: .trailing) {
                    RoundedRectangle(cornerRadius: 26)
                        .fill(Color.surfaceElevated)
                        .overlay(RoundedRectangle(cornerRadius: 26).stroke(
                            isInputFocused
                                ? LinearGradient(colors: [mood.accentColor.opacity(0.65), mood.accentColor.opacity(0.32)], startPoint: .leading, endPoint: .trailing)
                                : LinearGradient(colors: [Color.borderColor.opacity(0.55), Color.borderColor.opacity(0.3)], startPoint: .leading, endPoint: .trailing),
                            lineWidth: 1.5
                        ))
                        .shadow(
                            color: isInputFocused ? mood.accentColor.opacity(0.16) : .black.opacity(0.04),
                            radius: isInputFocused ? 12 : 3, y: isInputFocused ? 3 : 1
                        )

                    TextField("Ask ARIA anything…", text: $inputText, axis: .vertical)
                        .font(.system(size: 15.5))
                        .foregroundColor(.textPrimary)
                        .tint(mood.accentColor)
                        .focused($isInputFocused)
                        .disabled(isTyping)
                        .padding(.leading, 18).padding(.trailing, 60).padding(.vertical, 14)
                        .lineLimit(1...5)
                        .onSubmit { onSend(inputText) }
                        .onChange(of: inputText) { _, text in
                            charCount = text.count
                            // Subtle typing haptic every 10 chars
                            if charCount % 10 == 0 && charCount > 0 {
                                choreographedHaptic(.typing)
                            }
                        }

                    // Send button
                    Button { onSend(inputText) } label: {
                        ZStack {
                            Circle()
                                .fill(canSend
                                    ? AnyShapeStyle(FDS.Gradient.emberDeep)
                                    : AnyShapeStyle(Color.white.opacity(0.06)))
                                .frame(width: 40, height: 40)
                                .overlay(alignment: .top) {
                                    if canSend {
                                        Circle()
                                            .fill(LinearGradient(
                                                colors: [Color.white.opacity(0.18), .clear],
                                                startPoint: .top, endPoint: .center
                                            ))
                                            .frame(width: 40, height: 20).clipped()
                                    }
                                }
                                .shadow(color: canSend ? Color.ember.opacity(0.55) : .clear, radius: 12, y: 4)

                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(canSend ? .white : .textMuted)
                        }
                        .animation(FDS.Spring.snap, value: canSend)
                    }
                    .disabled(!canSend)
                    .padding(.trailing, 7)
                    .buttonStyle(ScaleButtonStyle())
                }
                .animation(.easeInOut(duration: 0.18), value: isInputFocused)
            }
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 24)
        }
        .background(.ultraThinMaterial)
    }
}

struct SmartChip: View {
    let label:    String
    let icon:     String
    let color:    Color
    let disabled: Bool
    let onTap:    () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(color)
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textSecondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(color.opacity(0.08))
            .cornerRadius(FDS.Radius.pill)
            .overlay(Capsule().stroke(color.opacity(0.28), lineWidth: 0.5))
        }
        .disabled(disabled)
        .opacity(disabled ? 0.42 : 1)
        .buttonStyle(ScaleButtonStyle())
    }
}
